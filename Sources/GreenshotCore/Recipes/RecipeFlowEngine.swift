// Greenshot for Mac (Community) - an unofficial macOS port of Greenshot
// Copyright (C) 2026 Greenshot for Mac (Community) contributors
// Based on Greenshot, Copyright (C) 2007-2026 Thomas Braun, Jens Klingen, Robin Krom
// SPDX-License-Identifier: GPL-3.0-or-later

import CoreGraphics
import Foundation

/// Executes a recipe on a context to the end (upstream `DagExecutionEngine`): start nodes; fork into merge clusters
/// (siblings that meet again run one after the other on the same context, independent ones in parallel on branch
/// copies, merged back after); join when all parents finished or were bypassed; Conditional's first true branch and
/// UserPrompt's choice with dead-path elimination; disabled nodes pass the flow on; error transitions and
/// `onErrorNodeId`/`onErrorRecipeId` with `LastError`, `LastErrorType`, `FailedNodeId`; cancellation aborts.
public struct RecipeFlowEngine: Sendable {
    let steps: RecipeStepRegistry
    let recipeLookup: @Sendable (String) async -> CaptureRecipe?
    let checkContracts: Bool
    let events: (@Sendable (RecipeFlowEvent) -> Void)?

    public init(steps: RecipeStepRegistry,
                recipeLookup: @escaping @Sendable (String) async -> CaptureRecipe? = { _ in nil },
                checkContracts: Bool = false,
                events: (@Sendable (RecipeFlowEvent) -> Void)? = nil) {
        self.steps = steps
        self.recipeLookup = recipeLookup
        self.checkContracts = checkContracts
        self.events = events
    }

    public func execute(_ context: RecipeFlowContext) async {
        let run = FlowRun(engine: self, context: context)
        await run.run()
    }
}

/// One execution of a recipe's graph (the state of upstream `DagExecutionEngine.ExecuteAsync`). Node ids are compared
/// case-insensitively: the keys here are lowercased.
private final class FlowRun: @unchecked Sendable {
    private let engine: RecipeFlowEngine
    private let root: RecipeFlowContext
    private let recipe: CaptureRecipe
    private var nodes: [String: RecipeNode] = [:]
    private var startNodes: [String] = []
    private var descendants: [String: Set<String>] = [:]

    private let lock = NSLock()
    private var pendingIncoming: [String: Int] = [:]
    private var activated = Set<String>()
    private var launched = Set<String>()
    private var bypassed = Set<String>()
    private var detached: [Task<Void, Never>] = []

    init(engine: RecipeFlowEngine, context: RecipeFlowContext) {
        self.engine = engine
        self.root = context
        self.recipe = context.recipe
        for node in recipe.nodes where !node.id.trimmingCharacters(in: .whitespaces).isEmpty {
            nodes[node.id.lowercased()] = node
        }
        var starts: [String] = []
        for start in recipe.flow.startNodes where !start.trimmingCharacters(in: .whitespaces).isEmpty {
            if !starts.contains(start.lowercased()) { starts.append(start.lowercased()) }
        }
        if starts.isEmpty, let first = recipe.nodes.first { starts.append(first.id.lowercased()) }
        startNodes = starts
        let transitions = recipe.flow.unifiedTransitions
        for key in nodes.keys { pendingIncoming[key] = 0 }
        var incoming: [String: Set<String>] = [:]
        for (from, targets) in transitions {
            for target in targets where nodes[target.lowercased()] != nil {
                incoming[target.lowercased(), default: []].insert(from)
            }
        }
        for (key, parents) in incoming { pendingIncoming[key] = parents.count }
        for start in starts {
            activated.insert(start)
            launched.insert(start)
        }
        // Everything reachable from each node, the node included (upstream `ComputeDescendantsMap`).
        for key in Set(nodes.keys).union(transitions.keys) {
            var visited: Set<String> = [key]
            var queue = [key]
            var index = 0
            while index < queue.count {
                let current = queue[index]
                index += 1
                for next in transitions[current] ?? [] where visited.insert(next.lowercased()).inserted {
                    queue.append(next.lowercased())
                }
            }
            descendants[key] = visited
        }
    }

    func run() async {
        guard !recipe.nodes.isEmpty else {
            root.log("DAG execution finished: recipe has no nodes.")
            return
        }
        root.log("DAG Execution started with \(startNodes.count) entry node(s)")
        let valid = startNodes.filter { nodes[$0] != nil }
        await launch(valid, on: root)
        // Nothing may outlive the flow: wait for the detached runs (they can start more of them while we wait).
        while true {
            let pending: [Task<Void, Never>] = lock.withLock {
                let tasks = detached
                detached = []
                return tasks
            }
            guard !pending.isEmpty else { break }
            for task in pending {
                await withTaskCancellationHandler { await task.value } onCancel: { task.cancel() }
            }
        }
    }

    /// Runs nodes that became ready together: one merge cluster on this context one after the other, several clusters
    /// in parallel on branch copies, merged back after (upstream: the fork / join of the DAG engine).
    private func launch(_ ids: [String], on context: RecipeFlowContext) async {
        guard !ids.isEmpty else { return }
        let clusters = partition(ids)
        if clusters.count == 1 {
            for id in clusters[0] { await runNode(id, context) }
            return
        }
        let branches = clusters.map { _ in context.makeBranch() }
        context.log("Branch split without merge: \(clusters.map { $0.joined(separator: ", ") }.joined(separator: " | "))")
        await withTaskGroup(of: Void.self) { group in
            for (cluster, branch) in zip(clusters, branches) {
                group.addTask {
                    for id in cluster { await self.runNode(id, branch) }
                }
            }
        }
        for branch in branches {
            context.merge(branch: branch, variables: true)
        }
    }

    /// Upstream `PartitionIntoMergeClusters`: siblings whose reachable nodes overlap (they meet again) share a cluster.
    private func partition(_ ids: [String]) -> [[String]] {
        var clusters: [[String]] = []
        for id in ids {
            let mine = descendants[id] ?? [id]
            let matching = clusters.indices.filter { index in
                clusters[index].contains { !(descendants[$0] ?? [$0]).isDisjoint(with: mine) }
            }
            if matching.isEmpty {
                clusters.append([id])
            } else {
                var merged = clusters[matching[0]]
                merged.append(id)
                for index in matching.dropFirst() { merged.append(contentsOf: clusters[index]) }
                clusters[matching[0]] = merged
                for index in matching.dropFirst().reversed() { clusters.remove(at: index) }
            }
        }
        return clusters
    }

    private func emit(_ event: RecipeFlowEvent) {
        engine.events?(event)
    }

    // MARK: A node

    private func runNode(_ id: String, _ context: RecipeFlowContext) async {
        if context.isAborted || Task.isCancelled { return }
        guard let node = nodes[id] else {
            context.log("Warning: DAG node '\(id)' not found.")
            return
        }
        if shouldRun(node, context) {
            do {
                try await execute(node, context)
            } catch {
                if error is CancellationError || Task.isCancelled {
                    context.abort("Node '\(node.id)' cancelled.")
                    return
                }
                await handleFailure(of: node, error: error, context)
                return
            }
        } else {
            let reason: String
            if case .expression(let expression) = node.enabled {
                reason = "'\(expression)' is not true"
            } else {
                reason = "disabled"
            }
            context.log("Skipping node: [\(node.id)] \(node.displayName), \(reason)")
            emit(.nodeSkipped(flowId: context.executionId, nodeId: node.id, reason: reason))
        }
        if context.isAborted || Task.isCancelled { return }
        let next = followers(of: node, context)
        await launch(next, on: context)
    }

    private func shouldRun(_ node: RecipeNode, _ context: RecipeFlowContext) -> Bool {
        switch node.enabled {
        case .value(let enabled): return enabled
        case .expression(let expression): return context.evaluator.evaluateBool(expression, in: context.scope(), default: false)
        }
    }

    private func execute(_ node: RecipeNode, _ context: RecipeFlowContext) async throws {
        let contract = engine.steps.contracts.contract(for: node.stepType)
        guard let executor = engine.steps.executor(for: node.stepType) else {
            throw RecipeStepError("Node '\(node.id)' uses step type '\(node.stepType)', which can't run in this version of Greenshot.",
                                  errorType: "NotSupportedException")
        }
        try validateBeforeStep(node, contract, context)
        // Expressions are evaluated exactly once: here, or by the step itself when its contract says so.
        let parameters: JSONObject
        if contract?.evaluatesOwnParameters == true {
            parameters = node.parameters
        } else {
            let scope = context.scope()
            parameters = JSONObject(node.parameters.members.map { member in
                if let parameter = contract?.parameter(member.key), !parameter.supportsExpressions { return member }
                return JSONMember(member.key, context.evaluator.resolve(member.value, in: scope))
            })
        }
        let before = engine.checkContracts && contract != nil ? context.variables : nil
        context.log("Executing node: [\(node.id)] \(node.displayName)")
        emit(.nodeStarted(flowId: context.executionId, nodeId: node.id, stepType: node.stepType))
        try await executor.execute(RecipeStepInvocation(node: node, parameters: parameters, contract: contract), in: context)
        emit(.nodeFinished(flowId: context.executionId, nodeId: node.id))
        if let before, let contract { checkAfterStep(node, contract, context, before: before) }
    }

    /// Upstream `ValidateBeforeStep`: a missing required parameter or input fails the node with a clear message.
    private func validateBeforeStep(_ node: RecipeNode, _ contract: StepContract?, _ context: RecipeFlowContext) throws {
        guard let contract else { return }
        for parameter in contract.parameters where parameter.required && parameter.defaultValue == nil {
            let value = node.parameters.first { parameter.matches($0.key) }?.value
            var isSet = value != nil && value != .null
            if let text = value?.stringValue, text.trimmingCharacters(in: .whitespaces).isEmpty { isSet = false }
            if !isSet {
                throw RecipeStepError("Node '\(node.id)' (\(node.stepType)) is missing required parameter '\(parameter.name)'.",
                                      errorType: "InvalidOperationException")
            }
        }
        for input in contract.inputVariables where input.required {
            for name in input.resolveNames(for: node) where context[variable: name] == nil {
                throw RecipeStepError("Node '\(node.id)' (\(node.stepType)) needs variable '\(name)', which is not set.",
                                      errorType: "InvalidOperationException")
            }
        }
    }

    /// Upstream `CheckAfterStep` (debug builds): what the step did against its contract.
    private func checkAfterStep(_ node: RecipeNode, _ contract: StepContract, _ context: RecipeFlowContext, before: RecipeVariables) {
        guard !context.isAborted else { return }
        var declared = Set<String>()
        for output in contract.outputVariables {
            for name in output.resolveNames(for: node) {
                declared.insert(name.lowercased())
                if output.isGuaranteed(for: node), context[variable: name] == nil {
                    emit(.contractViolation(flowId: context.executionId, message: "Node '\(node.id)' (\(node.stepType)) did not set its declared output '\(name)'."))
                }
            }
        }
        for member in context.variables where before[member.key] != member.value && !declared.contains(member.key.lowercased()) {
            emit(.contractViolation(flowId: context.executionId,
                                    message: "Node '\(node.id)' (\(node.stepType)) set variable '\(member.key)', which its contract does not declare."))
        }
        if contract.payload.rawCapture == .created, context.payload == nil {
            emit(.contractViolation(flowId: context.executionId, message: "Node '\(node.id)' (\(node.stepType)) should have created the image, but there is none."))
        }
    }

    // MARK: Errors

    private func handleFailure(of node: RecipeNode, error: Error, _ context: RecipeFlowContext) async {
        let stepError = error as? RecipeStepError
        let message = stepError?.message ?? error.localizedDescription
        let errorType = stepError?.errorType ?? String(describing: type(of: error))
        log.warn("Node '\(node.id)' of recipe '\(recipe.id)' failed: \(message)")
        let transition = recipe.flow.errorTransition(from: node.id, errorType: errorType, innerErrorType: stepError?.innerErrorType)
        let targetNode = Self.nonEmpty(transition?.to) ?? Self.nonEmpty(node.onErrorNodeId)
        let targetRecipe = Self.nonEmpty(transition?.targetRecipeId) ?? Self.nonEmpty(node.onErrorRecipeId)
        guard targetNode != nil || targetRecipe != nil else {
            context.fail("Node '\(node.id)' failed: \(message)", error: error)
            emit(.nodeFailed(flowId: context.executionId, nodeId: node.id, message: message, handledBy: nil))
            return
        }
        context[variable: "LastError"] = .string(message)
        context[variable: "LastErrorType"] = .string(errorType)
        context[variable: "FailedNodeId"] = .string(node.id)
        context.log("Node '\(node.id)' failed: \(message). Routing to error handler: '\(targetRecipe ?? targetNode ?? "")'")
        emit(.nodeFailed(flowId: context.executionId, nodeId: node.id, message: message, handledBy: targetRecipe ?? targetNode))
        // The normal successors of the failed node are bypassed; a join below them runs next to the error handler.
        var toLaunch: [String] = []
        lock.withLock { bypass(node.id.lowercased(), &toLaunch) }
        for next in toLaunch {
            let branch = context.makeBranch()
            let task = Task { await self.runNode(next, branch) }
            lock.withLock { detached.append(task) }
        }
        if let targetRecipe {
            guard let target = await engine.recipeLookup(targetRecipe) else {
                context.fail("Target error recipe '\(targetRecipe)' not found.", error: error)
                return
            }
            let forwarded = RecipeFlowContext(recipe: target, trigger: nil, environment: context.environment,
                                              optionValues: context.optionValues, output: context.output)
            forwarded.payload = context.payload
            for member in context.variables { forwarded[variable: member.key] = member.value }
            for (key, object) in context.objects { forwarded.setObject(object, forKey: key) }
            context.log("Forwarding to recipe '\(target.id)'")
            await engine.execute(forwarded)
            context.merge(branch: forwarded, variables: false)
            return
        }
        if let targetNode {
            lock.withLock {
                activated.insert(targetNode.lowercased())
                launched.insert(targetNode.lowercased())
            }
            await runNode(targetNode.lowercased(), context)
        }
    }

    private static func nonEmpty(_ text: String?) -> String? {
        guard let text, !text.trimmingCharacters(in: .whitespaces).isEmpty else { return nil }
        return text
    }

    // MARK: Routing

    /// The next nodes that are ready after `node` (upstream: branch selection, activation, join counters, dead paths).
    private func followers(of node: RecipeNode, _ context: RecipeFlowContext) -> [String] {
        var matchedBranch: String?
        if recipeEquals(node.stepType, WellKnownStepType.conditional) {
            let scope = context.scope()
            for branch in ConditionalBranch.read(node) where !branch.key.isEmpty {
                let expression = branch.expression.trimmingCharacters(in: .whitespacesAndNewlines)
                if expression.isEmpty { continue }
                if recipeEquals(expression, "else") || context.evaluator.evaluateBool(expression, in: scope, default: false) {
                    matchedBranch = branch.key
                    break
                }
            }
            context.log("Conditional node [\(node.id)] evaluated branch -> '\(matchedBranch ?? "None")'")
            emit(.branchChosen(flowId: context.executionId, nodeId: node.id, branch: matchedBranch))
        } else if recipeEquals(node.stepType, WellKnownStepType.userPrompt) {
            matchedBranch = context[variable: "UserChoice.\(node.id)"]?.asString
            context.log("UserPrompt node [\(node.id)] selected branch -> '\(matchedBranch ?? "None")'")
            emit(.branchChosen(flowId: context.executionId, nodeId: node.id, branch: matchedBranch))
        }
        var active: [String] = []
        var bypassedNext: [String] = []
        let conditional = recipe.flow.conditionalTransitions.filter {
            recipeEquals($0.from, node.id) && !$0.to.trimmingCharacters(in: .whitespaces).isEmpty
        }
        if !conditional.isEmpty {
            for transition in conditional {
                let target = transition.to.lowercased()
                if let matchedBranch, recipeEquals(transition.branch, matchedBranch) {
                    if !active.contains(target) { active.append(target) }
                } else if !bypassedNext.contains(target) {
                    bypassedNext.append(target)
                }
            }
        } else {
            for target in recipe.flow.targets(from: node.id) where !active.contains(target.lowercased()) {
                active.append(target.lowercased())
            }
        }
        return lock.withLock {
            var toLaunch: [String] = []
            for target in active { activated.insert(target) }
            for target in bypassedNext where !active.contains(target) {
                decrement(target, &toLaunch)
            }
            for target in active {
                decrement(target, &toLaunch)
            }
            return toLaunch
        }
    }

    /// One parent of `target` is done: when it was the last one, the node runs (activated) or is bypassed. Locked.
    private func decrement(_ target: String, _ toLaunch: inout [String]) {
        guard let remaining = pendingIncoming[target] else { return }
        pendingIncoming[target] = remaining - 1
        guard remaining - 1 <= 0 else { return }
        if activated.contains(target) {
            if launched.insert(target).inserted { toLaunch.append(target) }
        } else {
            bypass(target, &toLaunch)
        }
    }

    /// Upstream `BypassNodeLocked`: a node on a dead path passes the bypass on to everything after it. Locked.
    private func bypass(_ id: String, _ toLaunch: inout [String]) {
        guard bypassed.insert(id).inserted else { return }
        var outgoing: [String] = []
        for target in recipe.flow.targets(from: id) where !outgoing.contains(target.lowercased()) {
            outgoing.append(target.lowercased())
        }
        for transition in recipe.flow.conditionalTransitions where recipeEquals(transition.from, id) && !transition.to.isEmpty {
            if !outgoing.contains(transition.to.lowercased()) { outgoing.append(transition.to.lowercased()) }
        }
        for target in outgoing {
            decrement(target, &toLaunch)
        }
    }
}

private let log = Log("Recipes")
