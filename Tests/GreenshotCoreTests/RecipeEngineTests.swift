// Greenshot for Mac (Community) - an unofficial macOS port of Greenshot
// Copyright (C) 2026 Greenshot for Mac (Community) contributors
// Based on Greenshot, Copyright (C) 2007-2026 Thomas Braun, Jens Klingen, Robin Krom
// SPDX-License-Identifier: GPL-3.0-or-later

import CoreGraphics
import Foundation
import Testing
@testable import GreenshotCore

/// Thread-safe list of what ran.
final class RecipeRecorder: @unchecked Sendable {
    private let lock = NSLock()
    private var entries: [String] = []

    func add(_ entry: String) { lock.withLock { entries.append(entry) } }
    var all: [String] { lock.withLock { entries } }
}

/// An executor running a closure.
struct ClosureExecutor: RecipeStepExecutor {
    let body: @Sendable (RecipeStepInvocation, RecipeFlowContext) async throws -> Void

    func execute(_ step: RecipeStepInvocation, in context: RecipeFlowContext) async throws {
        try await body(step, context)
    }
}

/// Opens once; waiters before and after continue.
final class RecipeGate: @unchecked Sendable {
    private let lock = NSLock()
    private var opened = false
    private var waiters: [CheckedContinuation<Void, Never>] = []

    func wait() async {
        await withCheckedContinuation { (continuation: CheckedContinuation<Void, Never>) in
            let resumeNow: Bool = lock.withLock {
                if opened { return true }
                waiters.append(continuation)
                return false
            }
            if resumeNow { continuation.resume() }
        }
    }

    func open() {
        let pending: [CheckedContinuation<Void, Never>] = lock.withLock {
            opened = true
            let list = waiters
            waiters = []
            return list
        }
        for waiter in pending { waiter.resume() }
    }
}

enum RecipeEngineHarness {
    /// Step types "Step", "Use" (required parameter "Text") and "Own" (evaluates its own parameters), all recording
    /// their node id, plus the core executors.
    static func registry(_ recorder: RecipeRecorder,
                         body: @escaping @Sendable (RecipeStepInvocation, RecipeFlowContext) async throws -> Void = { _, _ in }) -> RecipeStepRegistry {
        let registry = RecipeStepRegistry()
        registry.registerCoreExecutors()
        let executor = ClosureExecutor { step, context in
            recorder.add(step.node.id)
            try await body(step, context)
        }
        registry.register(contract: StepContract(stepType: "Step", displayName: "Step", acceptsUndeclaredParameters: true), executor: executor)
        registry.register(contract: StepContract(stepType: "Use", displayName: "Use", parameters: [ParameterContract("Text", required: true)]),
                          executor: executor)
        registry.register(contract: StepContract(stepType: "Own", displayName: "Own", acceptsUndeclaredParameters: true, evaluatesOwnParameters: true),
                          executor: executor)
        return registry
    }

    static func recipe(_ ids: [String], start: [String], _ transitions: [(String, String)], type: String = "Step") -> CaptureRecipe {
        var recipe = CaptureRecipe(id: "engine_test", name: "Engine Test")
        recipe.nodes = ids.map { RecipeNode(id: $0, stepType: type) }
        recipe.flow.startNodes = start
        for (from, to) in transitions { recipe.flow.addTransition(from: from, to: to) }
        return recipe
    }

    static func context(_ recipe: CaptureRecipe, payload: Bool = true) -> RecipeFlowContext {
        let context = RecipeFlowContext(recipe: recipe, environment: FixedRecipeEnvironment())
        if payload {
            context.payload = RecipePayload(image: TestImage.solid(width: 10, height: 10, .white), scale: 1, title: "Original")
        }
        return context
    }

    static func run(_ recipe: CaptureRecipe, _ registry: RecipeStepRegistry, context: RecipeFlowContext? = nil,
                    lookup: @escaping @Sendable (String) async -> CaptureRecipe? = { _ in nil }) async -> RecipeFlowContext {
        let context = context ?? Self.context(recipe)
        await RecipeFlowEngine(steps: registry, recipeLookup: lookup).execute(context)
        return context
    }
}

/// Upstream DagExecutionEngineTests and the engine checks of StepContractTests.
@Suite struct RecipeEngineTests {
    @Test func linearOrder() async {
        let recorder = RecipeRecorder()
        let recipe = RecipeEngineHarness.recipe(["a", "b", "c"], start: ["a"], [("a", "b"), ("b", "c")])
        let context = await RecipeEngineHarness.run(recipe, RecipeEngineHarness.registry(recorder))
        #expect(recorder.all == ["a", "b", "c"])
        #expect(!context.isAborted)
    }

    @Test func asymmetricDiamondRunsDepthFirst() async {
        let recorder = RecipeRecorder()
        let recipe = RecipeEngineHarness.recipe(["start", "b1", "b2", "c1", "join"], start: ["start"],
                                                [("start", "b1"), ("start", "c1"), ("b1", "b2"), ("b2", "join"), ("c1", "join")])
        _ = await RecipeEngineHarness.run(recipe, RecipeEngineHarness.registry(recorder))
        #expect(recorder.all == ["start", "b1", "b2", "c1", "join"])
    }

    @Test func nonMergingSplitIsolatesBranches() async {
        let recorder = RecipeRecorder()
        let titles = RecipeRecorder()
        let registry = RecipeEngineHarness.registry(recorder) { step, context in
            guard step.node.id.hasPrefix("branch") else { return }
            titles.add("\(step.node.id):\(context.payload?.title ?? "")")
            context.payload?.title = step.node.id
            context[variable: "branch"] = .string(step.node.id)
            context[variable: step.node.id] = .bool(true)
        }
        let recipe = RecipeEngineHarness.recipe(["start", "branch_a", "branch_b"], start: ["start"], [("start", "branch_a"), ("start", "branch_b")])
        let context = await RecipeEngineHarness.run(recipe, registry)
        #expect(Set(titles.all) == ["branch_a:Original", "branch_b:Original"])
        #expect(context.payload?.title == "Original")
        #expect(context[variable: "branch_a"] == .bool(true))
        #expect(context[variable: "branch_b"] == .bool(true))
    }

    @Test(arguments: [false, true])
    func splitPropagatesExitCode(abortInBranch: Bool) async {
        let registry = RecipeEngineHarness.registry(RecipeRecorder()) { step, context in
            guard step.node.id == "branch_b" else { return }
            context.exitCode = 3
            if abortInBranch { context.abort("branch_b failed") }
        }
        let recipe = RecipeEngineHarness.recipe(["start", "branch_a", "branch_b"], start: ["start"], [("start", "branch_a"), ("start", "branch_b")])
        let context = await RecipeEngineHarness.run(recipe, registry)
        #expect(context.exitCode == 3)
        #expect(context.isAborted == abortInBranch)
    }

    func conditionalRecipe() -> CaptureRecipe {
        var recipe = RecipeEngineHarness.recipe(["start", "action_a", "action_b", "join_node"], start: ["start"],
                                                [("start", "cond_node"), ("action_a", "join_node"), ("action_b", "join_node")])
        recipe.nodes.insert(RecipeNode(id: "cond_node", stepType: "Conditional", parameters: ["Branches": .array([
            .object(["Key": .string("BranchA"), "Expression": .string("${CustomScore > 50}")]),
            .object(["key": .string("BranchB"), "expression": .string("else")])
        ])]), at: 1)
        recipe.flow.conditionalTransitions = [ConditionalTransition(from: "cond_node", branch: "BranchA", to: "action_a"),
                                              ConditionalTransition(from: "cond_node", branch: "BranchB", to: "action_b")]
        return recipe
    }

    @Test(arguments: [(75, "action_a"), (10, "action_b")])
    func conditionalBypassesTheOtherBranch(score: Int, expected: String) async {
        let recorder = RecipeRecorder()
        let recipe = conditionalRecipe()
        let context = RecipeEngineHarness.context(recipe)
        context[variable: "CustomScore"] = .number(Double(score))
        _ = await RecipeEngineHarness.run(recipe, RecipeEngineHarness.registry(recorder), context: context)
        #expect(recorder.all == ["start", expected, "join_node"])
    }

    @Test func userPromptChoiceRoutes() async {
        let recorder = RecipeRecorder()
        let registry = RecipeEngineHarness.registry(recorder)
        registry.register(WellKnownStepType.userPrompt, executor: ClosureExecutor { step, context in
            context[variable: "UserChoice.\(step.node.id)"] = .string("no")
        })
        var recipe = RecipeEngineHarness.recipe(["yes_path", "no_path"], start: ["ask"], [])
        recipe.nodes.insert(RecipeNode(id: "ask", stepType: "UserPrompt", parameters: ["Choices": .array([])]), at: 0)
        recipe.flow.conditionalTransitions = [ConditionalTransition(from: "ask", branch: "yes", to: "yes_path"),
                                              ConditionalTransition(from: "ask", branch: "No", to: "no_path")]
        _ = await RecipeEngineHarness.run(recipe, registry)
        #expect(recorder.all == ["no_path"])
    }

    @Test func stepErrorFailsTheFlow() async {
        let recorder = RecipeRecorder()
        let registry = RecipeEngineHarness.registry(recorder) { step, _ in
            if step.node.id == "b" { throw RecipeStepError("Boom", errorType: "IOException") }
        }
        let recipe = RecipeEngineHarness.recipe(["a", "b", "c"], start: ["a"], [("a", "b"), ("b", "c")])
        let context = await RecipeEngineHarness.run(recipe, registry)
        #expect(recorder.all == ["a", "b"])
        #expect(context.state == .failed)
        #expect(context.abortReason == "Node 'b' failed: Boom")
    }

    func failingRecipe() -> CaptureRecipe {
        RecipeEngineHarness.recipe(["a", "b", "c", "handler", "other"], start: ["a"], [("a", "b"), ("b", "c")])
    }

    func failingRegistry(_ recorder: RecipeRecorder, inner: String? = nil) -> RecipeStepRegistry {
        RecipeEngineHarness.registry(recorder) { step, _ in
            if step.node.id == "b" { throw RecipeStepError("Boom", errorType: "WrapperException", innerErrorType: inner) }
        }
    }

    @Test func errorTransitionRoutesToTheHandler() async {
        let recorder = RecipeRecorder()
        var recipe = failingRecipe()
        recipe.flow.errorTransitions = [ErrorTransition(from: "b", to: "other", errorType: "OtherException"),
                                        ErrorTransition(from: "b", to: "handler")]
        let context = await RecipeEngineHarness.run(recipe, failingRegistry(recorder))
        #expect(recorder.all == ["a", "b", "handler"])
        #expect(context.state != .failed)
        #expect(context[variable: "LastError"] == .string("Boom"))
        #expect(context[variable: "LastErrorType"] == .string("WrapperException"))
        #expect(context[variable: "FailedNodeId"] == .string("b"))
    }

    @Test func nodeLevelErrorTarget() async {
        let recorder = RecipeRecorder()
        var recipe = failingRecipe()
        recipe.nodes[1].onErrorNodeId = "handler"
        _ = await RecipeEngineHarness.run(recipe, failingRegistry(recorder))
        #expect(recorder.all == ["a", "b", "handler"])
    }

    /// An error handler id that is no node (a recipe that skipped the validator, or a typo in an error transition): the
    /// failure isn't handled, the flow fails instead of ending as a success.
    @Test(arguments: [false, true])
    func missingErrorHandlerNodeFailsTheFlow(viaTransition: Bool) async {
        let recorder = RecipeRecorder()
        let failures = RecipeRecorder()
        var recipe = failingRecipe()
        if viaTransition {
            recipe.flow.errorTransitions = [ErrorTransition(from: "b", to: "typo")]
        } else {
            recipe.nodes[1].onErrorNodeId = "typo"
        }
        let context = RecipeEngineHarness.context(recipe)
        let engine = RecipeFlowEngine(steps: failingRegistry(recorder), events: { event in
            if case .nodeFailed(_, let nodeId, _, let handledBy) = event { failures.add("\(nodeId) -> \(handledBy ?? "nil")") }
        })
        await engine.execute(context)
        #expect(recorder.all == ["a", "b"])
        #expect(context.state == .failed)
        #expect(context.abortReason == "Node 'b' failed: Boom. Its error handler 'typo' is not a node of the recipe.")
        #expect(failures.all == ["b -> nil"])
    }

    @Test func innerErrorTypeAndWildcardSource() async {
        let recorder = RecipeRecorder()
        var recipe = failingRecipe()
        recipe.flow.errorTransitions = [ErrorTransition(from: "*", to: "other"),
                                        ErrorTransition(from: "*", to: "handler", errorType: "TimeoutException")]
        _ = await RecipeEngineHarness.run(recipe, failingRegistry(recorder, inner: "TimeoutException"))
        #expect(recorder.all == ["a", "b", "handler"])
    }

    @Test func errorForwardsToAnotherRecipe() async {
        let recorder = RecipeRecorder()
        let seen = RecipeRecorder()
        let registry = RecipeEngineHarness.registry(recorder) { step, context in
            if step.node.id == "b" { throw RecipeStepError("Boom") }
            if step.node.id == "recover" {
                seen.add(context[variable: "FailedNodeId"]?.asString ?? "")
                seen.add(context.payload?.title ?? "")
                seen.add(context.executionId.uuidString)
                seen.add(context.trigger?.triggerType ?? "no trigger")
                context.exitCode = 5
            }
        }
        var recipe = failingRecipe()
        recipe.nodes[1].onErrorRecipeId = "recovery"
        let recovery = RecipeEngineHarness.recipe(["recover"], start: ["recover"], [])
        let outer = RecipeFlowContext(recipe: recipe, trigger: RecipeTriggerInfo(triggerType: "AiTool"), environment: FixedRecipeEnvironment())
        outer.payload = RecipePayload(image: TestImage.solid(width: 10, height: 10, .white), scale: 1, title: "Original")
        let context = await RecipeEngineHarness.run(recipe, registry, context: outer) { id in id == "recovery" ? recovery : nil }
        #expect(recorder.all == ["a", "b", "recover"])
        // The forwarded recipe is the same flow: same execution id, same trigger (security review R-F1, SM-L5).
        #expect(seen.all == ["b", "Original", outer.executionId.uuidString, "AiTool"])
        #expect(context.exitCode == 5)
    }

    /// "a" fails and goes to its handler "h"; the join "j" below it (its other parent "b" is done) runs next to the handler
    /// on a copy of the context. What happens there reaches the flow: its failure, its own variables, without undoing what
    /// the handler set meanwhile.
    func detachedJoinRecipe() -> CaptureRecipe {
        var recipe = RecipeEngineHarness.recipe(["b", "a", "j", "h"], start: ["b", "a"], [("a", "j"), ("b", "j")])
        recipe.nodes[1].onErrorNodeId = "h"
        return recipe
    }

    @Test func failureOfTheJoinNextToAnErrorHandlerFailsTheFlow() async {
        let recorder = RecipeRecorder()
        let registry = RecipeEngineHarness.registry(recorder) { step, _ in
            if step.node.id == "a" { throw RecipeStepError("Boom") }
            if step.node.id == "j" { throw RecipeStepError("Join broke") }
        }
        let context = await RecipeEngineHarness.run(detachedJoinRecipe(), registry)
        #expect(Set(recorder.all) == ["b", "a", "j", "h"])
        #expect(context.state == .failed)
        #expect(context.abortReason == "Node 'j' failed: Join broke")
    }

    @Test func variablesOfTheJoinNextToAnErrorHandlerReachTheFlow() async {
        let joinStarted = RecipeGate()
        let handlerDone = RecipeGate()
        let registry = RecipeEngineHarness.registry(RecipeRecorder()) { step, context in
            switch step.node.id {
            case "b": context[variable: "Count"] = .number(1)
            case "a": throw RecipeStepError("Boom")
            case "h":
                await joinStarted.wait()
                context[variable: "Count"] = .number(2)
                handlerDone.open()
            case "j":
                joinStarted.open()
                await handlerDone.wait()
                context[variable: "Joined"] = .bool(true)
                context.exitCode = 3
            default: break
            }
        }
        let context = await RecipeEngineHarness.run(detachedJoinRecipe(), registry)
        #expect(context.state != .failed)
        #expect(context[variable: "Joined"] == .bool(true))
        #expect(context[variable: "Count"] == .number(2))
        #expect(context.exitCode == 3)
    }

    /// Counts the exports Notification steps showed.
    final class ShownExports: RecipeNotificationPresenting, @unchecked Sendable {
        private let lock = NSLock()
        private var shown: [String] = []
        var all: [String] { lock.withLock { shown } }

        func announce(_ exports: [RecipeExportOutcome], in context: RecipeFlowContext) async {
            lock.withLock { shown += exports.map(\.designation) }
        }
    }

    /// The core executors plus Notification; the "Step" nodes in `exporting` export their id after `body`.
    func notifyingRegistry(_ shown: ShownExports, exporting: Set<String>,
                           body: @escaping @Sendable (RecipeStepInvocation, RecipeFlowContext) async throws -> Void) -> RecipeStepRegistry {
        let registry = RecipeEngineHarness.registry(RecipeRecorder()) { step, context in
            try await body(step, context)
            if exporting.contains(step.node.id) { context.exports.add(RecipeExportOutcome(designation: step.node.id, succeeded: true)) }
        }
        registry.register(contract: RecipeNotificationExecutor.contract, executor: RecipeNotificationExecutor(presenter: shown))
        return registry
    }

    /// The handler and the join next to it both notify, the join first: the flow's count is both, not the join's copy
    /// (the failure message would list the handler's export again).
    @Test func notificationsNextToAnErrorHandlerCountTogether() async {
        let shown = ShownExports()
        let joinNotified = RecipeGate()
        let registry = notifyingRegistry(shown, exporting: ["j", "h"]) { step, _ in
            if step.node.id == "a" { throw RecipeStepError("Boom") }
            if step.node.id == "h" { await joinNotified.wait() }
            if step.node.id == "jdone" { joinNotified.open() }
        }
        var recipe = RecipeEngineHarness.recipe(["b", "a", "j", "jn", "jdone", "h", "hn"], start: ["b", "a"],
                                                [("a", "j"), ("b", "j"), ("j", "jn"), ("jn", "jdone"), ("h", "hn")])
        recipe.nodes[3].stepType = WellKnownStepType.notification
        recipe.nodes[6].stepType = WellKnownStepType.notification
        recipe.nodes[1].onErrorNodeId = "h"
        let context = await RecipeEngineHarness.run(recipe, registry)
        #expect(shown.all == ["j", "h"])
        #expect(context[variable: RecipeNotificationExecutor.announcedExportsVariable] == .number(2))
    }

    /// Two parallel branches both notify, the second one first: merged in branch order, the count is still both.
    @Test func notificationsOfParallelBranchesCountTogether() async {
        let shown = ShownExports()
        let secondNotified = RecipeGate()
        let registry = notifyingRegistry(shown, exporting: ["x", "y"]) { step, _ in
            if step.node.id == "x" { await secondNotified.wait() }
            if step.node.id == "ydone" { secondNotified.open() }
        }
        var recipe = RecipeEngineHarness.recipe(["x", "xn", "y", "yn", "ydone"], start: ["x", "y"],
                                                [("x", "xn"), ("y", "yn"), ("yn", "ydone")])
        recipe.nodes[1].stepType = WellKnownStepType.notification
        recipe.nodes[3].stepType = WellKnownStepType.notification
        let context = await RecipeEngineHarness.run(recipe, registry)
        #expect(shown.all == ["y", "x"])
        #expect(context[variable: RecipeNotificationExecutor.announcedExportsVariable] == .number(2))
    }

    /// The recipe a failure is forwarded to is the same flow: its exports and variables are the flow's.
    @Test func exportsAndVariablesOfTheForwardedRecipeReachTheFlow() async {
        let registry = RecipeEngineHarness.registry(RecipeRecorder()) { step, context in
            if step.node.id == "a" { context.exports.add(RecipeExportOutcome(designation: "Clipboard", succeeded: true)) }
            if step.node.id == "b" { throw RecipeStepError("Boom") }
            if step.node.id == "recover" {
                context.exports.add(RecipeExportOutcome(designation: "FileNoDialog", succeeded: false, errorMessage: "Disk full"))
                context[variable: "Recovered"] = .bool(true)
            }
        }
        var recipe = failingRecipe()
        recipe.nodes[1].onErrorRecipeId = "recovery"
        let recovery = RecipeEngineHarness.recipe(["recover"], start: ["recover"], [])
        let context = await RecipeEngineHarness.run(recipe, registry) { id in id == "recovery" ? recovery : nil }
        #expect(context.exports.all.map(\.designation) == ["Clipboard", "FileNoDialog"])
        #expect(context[variable: "Recovered"] == .bool(true))
        #expect(context[variable: "FailedNodeId"] == .string("b"))
    }

    @Test func missingErrorRecipeFails() async {
        var recipe = failingRecipe()
        recipe.nodes[1].onErrorRecipeId = "nowhere"
        let context = await RecipeEngineHarness.run(recipe, failingRegistry(RecipeRecorder()))
        #expect(context.state == .failed)
        #expect(context.abortReason == "Target error recipe 'nowhere' not found.")
    }

    @Test func disabledNodesPassTheFlowOn() async {
        let recorder = RecipeRecorder()
        var recipe = RecipeEngineHarness.recipe(["a", "b", "c", "d"], start: ["a"], [("a", "b"), ("b", "c"), ("c", "d")])
        recipe.nodes[1].enabled = .value(false)
        recipe.nodes[2].enabled = .expression("${1 > 2}")
        _ = await RecipeEngineHarness.run(recipe, RecipeEngineHarness.registry(recorder))
        #expect(recorder.all == ["a", "d"])
    }

    @Test func missingRequiredParameterFailsTheNode() async {
        var recipe = RecipeEngineHarness.recipe(["a"], start: ["a"], [], type: "Use")
        recipe.nodes[0].onErrorNodeId = "handler"
        recipe.nodes.append(RecipeNode(id: "handler", stepType: "Step"))
        let context = await RecipeEngineHarness.run(recipe, RecipeEngineHarness.registry(RecipeRecorder()))
        #expect(context[variable: "LastError"] == .string("Node 'a' (Use) is missing required parameter 'Text'."))
    }

    @Test func stepWithoutExecutorFails() async {
        let recipe = RecipeEngineHarness.recipe(["video"], start: ["video"], [], type: "RecordVideo")
        let context = await RecipeEngineHarness.run(recipe, RecipeEngineHarness.registry(RecipeRecorder()))
        #expect(context.state == .failed)
        #expect(context.abortReason?.contains("can't run in this version of Greenshot") == true)
    }

    @Test func parametersAreEvaluatedOnceUnlessTheStepDoesIt() async {
        let received = RecipeRecorder()
        let registry = RecipeEngineHarness.registry(RecipeRecorder()) { step, _ in
            received.add("\(step.node.id)=\(step.parameters.string("Text") ?? "")")
        }
        var recipe = RecipeEngineHarness.recipe(["plain", "own"], start: ["plain"], [("plain", "own")])
        recipe.nodes[0].parameters = ["Text": .string("${1 + 1}/${Data}")]
        recipe.nodes[1].stepType = "Own"
        recipe.nodes[1].parameters = ["Text": .string("${1 + 1}")]
        let context = RecipeEngineHarness.context(recipe)
        context[variable: "Data"] = .string("${user.username}")
        _ = await RecipeEngineHarness.run(recipe, registry, context: context)
        #expect(received.all == ["plain=2/${user.username}", "own=${1 + 1}"])
    }

    @Test func coreStepsRun() async throws {
        let output = TestOutput()
        var recipe = CaptureRecipe(id: "core", name: "Core")
        recipe.nodes = [
            RecipeNode(id: "set", stepType: "SetVariable", parameters: ["variable": .string("Greeting"), "value": .string("Hello ${user.username}"),
                                                                       "variables": .object(["Count": .string("${2 * 3}")])]),
            RecipeNode(id: "print", stepType: "Stdout", parameters: ["text": .string("${Greeting} x${Count}")]),
            RecipeNode(id: "fail", stepType: "Stderr", parameters: ["text": .string("bad"), "exitCode": .number(4)]),
            RecipeNode(id: "never", stepType: "Stdout")
        ]
        recipe.flow.startNodes = ["set"]
        recipe.flow.addTransition(from: "set", to: "print")
        recipe.flow.addTransition(from: "print", to: "fail")
        recipe.flow.addTransition(from: "fail", to: "never")
        let context = RecipeFlowContext(recipe: recipe, environment: FixedRecipeEnvironment(), output: output)
        let registry = RecipeStepRegistry()
        registry.registerCoreExecutors()
        await RecipeFlowEngine(steps: registry).execute(context)
        #expect(context[variable: "Count"] == .number(6))
        #expect(output.stdout.all == ["Hello jane x6"])
        #expect(output.stderr.all == ["bad"])
        #expect(context.exitCode == 4)
        #expect(context.state == .cancelled)
        #expect(context[variable: "StdoutEmitted"] == .bool(true))
    }

    @Test func contractViolationsAreReported() async {
        let violations = RecipeRecorder()
        let registry = RecipeStepRegistry()
        registry.register(contract: StepContract(stepType: "Sloppy", displayName: "Sloppy",
                                                 outputVariables: [VariableContract("Promised")], payload: PayloadContract(rawCapture: .created)),
                          executor: ClosureExecutor { _, context in context[variable: "Surprise"] = .bool(true) })
        let recipe = RecipeEngineHarness.recipe(["s"], start: ["s"], [], type: "Sloppy")
        let context = RecipeEngineHarness.context(recipe, payload: false)
        await RecipeFlowEngine(steps: registry, checkContracts: true) { event in
            if case .contractViolation(_, let message) = event { violations.add(message) }
        }.execute(context)
        #expect(violations.all.count == 3)
    }
}

/// Collects what the Stdout and Stderr steps write.
final class TestOutput: RecipeOutputSink, @unchecked Sendable {
    let stdout = RecipeRecorder()
    let stderr = RecipeRecorder()

    func writeStdout(_ text: String) async { stdout.add(text) }
    func writeStderr(_ text: String) async { stderr.add(text) }
}
