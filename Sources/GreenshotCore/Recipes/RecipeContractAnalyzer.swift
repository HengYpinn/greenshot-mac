// Greenshot for Mac (Community) - an unofficial macOS port of Greenshot
// Copyright (C) 2026 Greenshot for Mac (Community) contributors
// Based on Greenshot, Copyright (C) 2007-2026 Thomas Braun, Jens Klingen, Robin Krom
// SPDX-License-Identifier: GPL-3.0-or-later

import CoreGraphics
import Foundation

/// One node in the contract report (upstream `StepSummaryContract`).
public struct RecipeStepSummary: Sendable, Equatable {
    public var nodeId: String
    public var stepType: String
    public var displayName: String
    public var requiredInputs: [String]
    public var producedOutputs: [String]
    public var reachable: Bool
    /// Variables set on every path to the node (by earlier nodes or the trigger).
    public var guaranteedVariables: [String]

    public init(nodeId: String, stepType: String, displayName: String, requiredInputs: [String] = [],
                producedOutputs: [String] = [], reachable: Bool = true, guaranteedVariables: [String] = []) {
        self.nodeId = nodeId
        self.stepType = stepType
        self.displayName = displayName
        self.requiredInputs = requiredInputs
        self.producedOutputs = producedOutputs
        self.reachable = reachable
        self.guaranteedVariables = guaranteedVariables
    }
}

/// The contract of a recipe along its graph (upstream `RecipeContract`): what it needs from the caller, what it
/// produces, and the warnings of docs section 8. `--info` (AUT) prints it.
public struct RecipeContractReport: Sendable, Equatable {
    public var recipeId: String
    public var recipeName: String
    public var description: String
    public var inputs: [VariableContract]
    public var outputs: [VariableContract]
    public var steps: [RecipeStepSummary]
    public var warnings: [String]
    public var acquiresImage: Bool
    public var mutatesPixels: Bool
    public var extractsText: Bool

    public init(recipeId: String, recipeName: String, description: String = "", inputs: [VariableContract] = [],
                outputs: [VariableContract] = [], steps: [RecipeStepSummary] = [], warnings: [String] = [],
                acquiresImage: Bool = false, mutatesPixels: Bool = false, extractsText: Bool = false) {
        self.recipeId = recipeId
        self.recipeName = recipeName
        self.description = description
        self.inputs = inputs
        self.outputs = outputs
        self.steps = steps
        self.warnings = warnings
        self.acquiresImage = acquiresImage
        self.mutatesPixels = mutatesPixels
        self.extractsText = extractsText
    }
}

public enum RecipeContractAnalyzer {
    /// The variables the triggers hand to the flow, and whether one hands the image (upstream `GetTriggerInputs`).
    public static func triggerInputs(of recipe: CaptureRecipe) -> (inputs: [VariableContract], providesPayload: Bool) {
        var inputs = OrderedVariables()
        var providesPayload = false
        for trigger in recipe.triggers where trigger.enabled {
            let isAITool = trigger.isType(WellKnownTriggerType.aiTool)
            if isAITool || trigger.isType(WellKnownTriggerType.commandline) {
                for argument in trigger.arguments where !argument.name.trimmingCharacters(in: .whitespaces).isEmpty {
                    let name = argument.effectiveVariable
                    let description = argument.description ?? (isAITool ? "AI tool argument \(argument.name)" : "Command-line argument --\(argument.name)")
                    inputs[name] = VariableContract(name, argument.type, required: argument.required, description: description,
                                                    exampleValue: argument.defaultValue,
                                                    // Only an argument with a value in every call is guaranteed
                                                    conditional: !argument.required && (argument.defaultValue ?? "").isEmpty)
                }
            } else if trigger.isType(WellKnownTriggerType.openFile) {
                inputs["Filename"] = VariableContract("Filename", .filePath, required: true, description: "The file that was opened")
            } else if trigger.isType(WellKnownTriggerType.extension) {
                providesPayload = true
                inputs["Capture"] = VariableContract("Capture", .object, required: true, description: "The capture imported from the browser (also the payload)")
                inputs["Browser"] = VariableContract("Browser", .string, description: "The browser that sent the capture", conditional: true)
            } else if trigger.isType(WellKnownTriggerType.editor) {
                inputs["EditorForm"] = VariableContract("EditorForm", .object, required: true, description: "The editor that triggered the recipe")
            }
        }
        return (inputs.values, providesPayload)
    }

    public static func analyze(_ recipe: CaptureRecipe, contracts: StepContractCatalog = .builtIn) -> RecipeContractReport {
        var analyzer = ContractAnalysis(recipe: recipe, contracts: contracts)
        return analyzer.run()
    }
}

/// Variables by name (case-insensitive), in the order they were first added.
struct OrderedVariables {
    private(set) var values: [VariableContract] = []
    private var positions: [String: Int] = [:]

    subscript(name: String) -> VariableContract? {
        get { positions[name.lowercased()].map { values[$0] } }
        set {
            guard let newValue else { return }
            if let position = positions[name.lowercased()] {
                values[position] = newValue
            } else {
                positions[name.lowercased()] = values.count
                values.append(newValue)
            }
        }
    }

    var names: [String] { values.map(\.name) }
}

/// Upstream `RecipeContract.Analyzer`: follows the flow as the engine runs it. A node runs after all its predecessors
/// finished or were bypassed; a Conditional or UserPrompt node follows only the transitions of the chosen branch; a node
/// with an error transition continues there when it fails. Every combination of branch choices and error outcomes is a
/// scenario; a variable is guaranteed for a node when, in every scenario that runs the node, a node that ran before it
/// (an ancestor) set it, or the trigger provided it.
struct ContractAnalysis {
    static let errorVariables = ["LastError", "LastErrorType", "FailedNodeId"]
    static let maxScenarios = 4096

    private enum EdgeKind { case standard, conditional, error }

    private struct Edge {
        var from: String
        var to: String
        var kind: EdgeKind
        var branch: String?
    }

    let recipe: CaptureRecipe
    let contracts: StepContractCatalog
    private var warnings: [String] = []
    /// By lowercased id, the first node with the id.
    private var nodes: [String: RecipeNode] = [:]
    private var nodeOrder: [String] = []
    private var nodeContracts: [String: StepContract] = [:]
    private var outgoing: [String: [Edge]] = [:]
    private var incoming: [String: [Edge]] = [:]
    private var branchKeys: [String: [String]] = [:]
    private var hasErrorEdge = Set<String>()
    private var ancestors: [String: Set<String>] = [:]

    init(recipe: CaptureRecipe, contracts: StepContractCatalog) {
        self.recipe = recipe
        self.contracts = contracts
    }

    private mutating func warn(_ message: String) {
        if !warnings.contains(message) { warnings.append(message) }
    }

    mutating func run() -> RecipeContractReport {
        var report = RecipeContractReport(recipeId: recipe.id, recipeName: recipe.name, description: recipe.description ?? "")
        let trigger = RecipeContractAnalyzer.triggerInputs(of: recipe)
        // A recipe without a source node gets a trigger-specific one when a trigger runs it (TriggerRecipePreparer).
        let triggerProvidesPayload = trigger.providesPayload || (!recipe.hasSourceStep && recipe.triggers.contains { $0.enabled })
        var inputs = OrderedVariables()
        for input in trigger.inputs { inputs[input.name] = input }
        var outputs = OrderedVariables()

        for node in recipe.nodes {
            let key = node.id.lowercased()
            guard !node.id.trimmingCharacters(in: .whitespaces).isEmpty, nodes[key] == nil else { continue }
            nodes[key] = node
            nodeOrder.append(key)
            if let contract = node.stepType.isEmpty ? nil : contracts.contract(for: node.stepType) {
                nodeContracts[key] = contract
            } else {
                warn("Node '\(node.id)' uses step type '\(node.stepType)', which has no registered contract.")
            }
        }
        var summaries: [String: RecipeStepSummary] = [:]
        for key in nodeOrder {
            let node = nodes[key]!
            let contract = nodeContracts[key]
            var summary = RecipeStepSummary(nodeId: node.id, stepType: node.stepType, displayName: contract?.displayName ?? node.stepType)
            if let contract {
                report.acquiresImage = report.acquiresImage || contract.payload.rawCapture == .created
                report.mutatesPixels = report.mutatesPixels || contract.payload.visualMutation == .mutatesPixels
                report.extractsText = report.extractsText || contract.payload.extractedText == .created
                summary.requiredInputs = contract.inputVariables.filter(\.required).flatMap { $0.resolveNames(for: node) }
                var produced: [String] = []
                for output in contract.outputVariables {
                    for name in output.resolveNames(for: node) {
                        produced.append(name)
                        let existing = outputs[name]
                        if existing == nil || existing!.conditional {
                            outputs[name] = VariableContract(name, output.dataType, description: output.description, exampleValue: output.exampleValue,
                                                             conditional: !output.isGuaranteed(for: node) && (existing?.conditional ?? true))
                        }
                    }
                }
                summary.producedOutputs = produced
                checkParameters(node, contract)
            }
            summaries[key] = summary
        }

        buildEdges()
        let order = topologicalOrder()
        computeAncestors(order)
        let starts = startNodes()
        let scenarios = runScenarios(order: order, starts: starts, triggerInputs: trigger.inputs, triggerProvidesPayload: triggerProvidesPayload)

        var producible = Set(outputs.names.map { $0.lowercased() })
        producible.formUnion(inputs.names.map { $0.lowercased() })
        producible.formUnion(Self.errorVariables.map { $0.lowercased() })

        if let scenarios {
            let orderSet = Set(order)
            for key in nodeOrder where orderSet.contains(key) {
                let node = nodes[key]!
                guard scenarios.reachable.contains(key) else {
                    summaries[key]?.reachable = false
                    warn("Node '\(node.id)' (\(node.stepType)) is never executed: no path from a start node leads to it.")
                    continue
                }
                let guaranteedHere = scenarios.guaranteed[key] ?? OrderedNames()
                summaries[key]?.guaranteedVariables = guaranteedHere.names.sorted { $0.lowercased() < $1.lowercased() }
                if let contract = nodeContracts[key] {
                    if contract.payload.rawCapture == .required, scenarios.image[key] != true {
                        warn("Node '\(node.id)' (\(node.stepType)) needs an image, but on some path to it no preceding node acquires one.")
                    }
                    for input in contract.inputVariables where input.required {
                        for name in input.resolveNames(for: node) where !guaranteedHere.contains(name) {
                            if scenarios.possible[key]?.contains(name.lowercased()) == true {
                                warn("Node '\(node.id)' (\(node.stepType)) needs variable '\(name)', which is not set on every path to it.")
                            } else if inputs[name] == nil {
                                // Not produced before this node: the caller has to provide it
                                inputs[name] = input
                            }
                        }
                    }
                }
                var seen = Set<String>()
                for reference in Self.referencedVariables(node) where seen.insert(reference.lowercased()).inserted {
                    guard let produced = Self.findProducible(reference, producible),
                          scenarios.covered[key]?.contains(produced.lowercased()) != true else { continue }
                    if scenarios.possible[key]?.contains(produced.lowercased()) == true {
                        warn("Node '\(node.id)' (\(node.stepType)) uses ${\(produced)}, which is not set on every path to it (it is only set in some branches).")
                    } else {
                        warn("Node '\(node.id)' (\(node.stepType)) uses ${\(produced)}, which is only set by nodes that do not run before it.")
                    }
                }
            }
        }
        if report.acquiresImage || triggerProvidesPayload {
            outputs["Payload.Width"] = VariableContract("Payload.Width", .integer, description: "Image width in points")
            outputs["Payload.Height"] = VariableContract("Payload.Height", .integer, description: "Image height in points")
        }
        if report.extractsText {
            outputs["Payload.ExtractedText"] = VariableContract("Payload.ExtractedText", .string, description: "Text extracted via OCR or barcode recognition",
                                                                conditional: true)
        }
        report.inputs = inputs.values
        report.outputs = outputs.values
        report.steps = nodeOrder.compactMap { summaries[$0] }
        report.warnings = warnings
        return report
    }

    // MARK: Parameters

    private mutating func checkParameters(_ node: RecipeNode, _ contract: StepContract) {
        for parameter in contract.parameters {
            let supplied = node.parameters.first { parameter.matches($0.key) }?.value
            var isSet = supplied != nil && supplied != .null
            if let text = supplied?.stringValue, text.trimmingCharacters(in: .whitespaces).isEmpty { isSet = false }
            if parameter.required, !isSet, parameter.defaultValue == nil {
                warn("Node '\(node.id)' (\(node.stepType)) is missing required parameter '\(parameter.name)'.")
            }
            let allowed = parameter.effectiveAllowedValues
            if isSet, !allowed.isEmpty, let literal = supplied?.stringValue, !literal.contains("${"),
               !allowed.contains(where: { recipeEquals($0, literal) }) {
                warn("Node '\(node.id)' (\(node.stepType)): parameter '\(parameter.name)' has value '\(literal)'; allowed are \(allowed.joined(separator: ", ")).")
            }
        }
        guard !contract.acceptsUndeclaredParameters else { return }
        for key in node.parameters.keys where contract.parameter(key) == nil {
            warn("Node '\(node.id)' (\(node.stepType)) has parameter '\(key)', which the step does not read.")
        }
    }

    // MARK: Graph

    private func startNodes() -> [String] {
        var starts: [String] = []
        for start in recipe.flow.startNodes where nodes[start.lowercased()] != nil && !starts.contains(start.lowercased()) {
            starts.append(start.lowercased())
        }
        if starts.isEmpty, let first = nodeOrder.first { starts.append(first) }
        return starts
    }

    private mutating func addEdge(_ from: String, _ to: String, _ kind: EdgeKind, branch: String? = nil) {
        guard !from.trimmingCharacters(in: .whitespaces).isEmpty, !to.trimmingCharacters(in: .whitespaces).isEmpty else { return }
        let fromKey = from.lowercased()
        let toKey = to.lowercased()
        guard nodes[fromKey] != nil, nodes[toKey] != nil else {
            warn("Transition from '\(from)' to '\(to)' refers to a node that does not exist.")
            return
        }
        let edge = Edge(from: fromKey, to: toKey, kind: kind, branch: branch)
        outgoing[fromKey, default: []].append(edge)
        incoming[toKey, default: []].append(edge)
    }

    private mutating func buildEdges() {
        let flow = recipe.flow
        let conditionalSources = Set(flow.conditionalTransitions
            .filter { !$0.from.trimmingCharacters(in: .whitespaces).isEmpty && !$0.to.trimmingCharacters(in: .whitespaces).isEmpty }
            .map { $0.from.lowercased() })
        for transition in flow.transitions {
            if conditionalSources.contains(transition.from.lowercased()) {
                // The engine follows only the conditional transitions of a node that has them
                if !transition.to.isEmpty {
                    warn("Node '\(transition.from)' has conditional transitions, so its normal transitions (\(transition.to.joined(separator: ", "))) are never followed.")
                }
                continue
            }
            for target in transition.to { addEdge(transition.from, target, .standard) }
        }
        for transition in flow.conditionalTransitions
        where !transition.from.trimmingCharacters(in: .whitespaces).isEmpty && !transition.to.trimmingCharacters(in: .whitespaces).isEmpty {
            addEdge(transition.from, transition.to, .conditional, branch: transition.branch)
            var keys = branchKeys[transition.from.lowercased()] ?? []
            if !keys.contains(where: { recipeEquals($0, transition.branch) }) { keys.append(transition.branch) }
            branchKeys[transition.from.lowercased()] = keys
        }
        for transition in flow.errorTransitions {
            // A wildcard source ("*") is any node: it adds no edge of its own.
            guard let from = transition.from, from != "*", let to = transition.to else { continue }
            guard !from.trimmingCharacters(in: .whitespaces).isEmpty, !to.trimmingCharacters(in: .whitespaces).isEmpty else { continue }
            addEdge(from, to, .error)
            hasErrorEdge.insert(from.lowercased())
        }
        for key in nodeOrder {
            let node = nodes[key]!
            if let target = node.onErrorNodeId, !target.trimmingCharacters(in: .whitespaces).isEmpty, !hasErrorEdge.contains(key) {
                addEdge(node.id, target, .error)
                hasErrorEdge.insert(key)
            }
        }
    }

    private mutating func topologicalOrder() -> [String] {
        var inDegree: [String: Int] = [:]
        for key in nodeOrder { inDegree[key] = 0 }
        for edges in outgoing.values {
            for edge in edges { inDegree[edge.to, default: 0] += 1 }
        }
        var queue = nodeOrder.filter { inDegree[$0] == 0 }
        var order: [String] = []
        var index = 0
        while index < queue.count {
            let key = queue[index]
            index += 1
            order.append(key)
            for edge in outgoing[key] ?? [] {
                inDegree[edge.to, default: 0] -= 1
                if inDegree[edge.to] == 0 { queue.append(edge.to) }
            }
        }
        let ordered = Set(order)
        let cyclic = nodeOrder.filter { !ordered.contains($0) }.map { nodes[$0]!.id }
        if !cyclic.isEmpty {
            warn("The flow contains a cycle through node(s) \(cyclic.joined(separator: ", ")); these nodes are not analyzed.")
        }
        return order
    }

    private mutating func computeAncestors(_ order: [String]) {
        for key in order {
            var set = Set<String>()
            for edge in incoming[key] ?? [] {
                set.insert(edge.from)
                set.formUnion(ancestors[edge.from] ?? [])
            }
            ancestors[key] = set
        }
    }

    private struct Scenarios {
        var guaranteed: [String: OrderedNames] = [:]
        var covered: [String: Set<String>] = [:]
        var possible: [String: Set<String>] = [:]
        var reachable = Set<String>()
        var image: [String: Bool] = [:]
    }

    /// Names keeping the spelling, compared case-insensitively.
    struct OrderedNames {
        private(set) var names: [String] = []
        private var keys = Set<String>()

        init(_ names: [String] = []) {
            for name in names { insert(name) }
        }

        mutating func insert(_ name: String) {
            if keys.insert(name.lowercased()).inserted { names.append(name) }
        }

        func contains(_ name: String) -> Bool { keys.contains(name.lowercased()) }

        mutating func formIntersection(_ other: OrderedNames) {
            names = names.filter { other.contains($0) }
            keys = Set(names.map { $0.lowercased() })
        }
    }

    private mutating func runScenarios(order: [String], starts: [String], triggerInputs: [VariableContract],
                                       triggerProvidesPayload: Bool) -> Scenarios? {
        let startSet = Set(starts)
        var dimensions: [(node: String, outcomes: [String])] = []
        for key in order {
            if let keys = branchKeys[key] { dimensions.append((key, keys.map { "branch:" + $0 })) }
            if hasErrorEdge.contains(key) { dimensions.append((key, ["ok", "error"])) }
        }
        var count = 1
        for dimension in dimensions {
            count = min(count * max(1, dimension.outcomes.count), Self.maxScenarios + 1)
        }
        if count > Self.maxScenarios {
            warn("The flow has too many branch combinations (\(count)+) to check which variables are set on every path; variable checks are skipped.")
            return nil
        }
        let guaranteedInputs = triggerInputs.filter { !$0.conditional }.map(\.name)
        let possibleInputs = triggerInputs.map { $0.name.lowercased() }
        var scenarios = Scenarios()
        var choice = [Int](repeating: 0, count: dimensions.count)
        for scenario in 0..<count {
            var rest = scenario
            for index in dimensions.indices {
                let outcomes = max(1, dimensions[index].outcomes.count)
                choice[index] = rest % outcomes
                rest /= outcomes
            }
            func branchOf(_ key: String) -> String? {
                for index in dimensions.indices where dimensions[index].node == key && dimensions[index].outcomes[choice[index]].hasPrefix("branch:") {
                    return String(dimensions[index].outcomes[choice[index]].dropFirst("branch:".count))
                }
                return nil
            }
            func fails(_ key: String) -> Bool {
                dimensions.indices.contains { dimensions[$0].node == key && dimensions[$0].outcomes[choice[$0]] == "error" }
            }
            var executed = Set<String>()
            for key in order {
                let runs = startSet.contains(key) || (incoming[key] ?? []).contains { edge in
                    guard executed.contains(edge.from) else { return false }
                    switch edge.kind {
                    case .standard: return !fails(edge.from)
                    case .conditional: return !fails(edge.from) && (branchOf(edge.from).map { recipeEquals($0, edge.branch ?? "") } ?? false)
                    case .error: return fails(edge.from)
                    }
                }
                guard runs else { continue }
                executed.insert(key)
                scenarios.reachable.insert(key)
                var sure = OrderedNames(guaranteedInputs)
                var maybe = Set(possibleInputs)
                var produced = Set(possibleInputs)
                var hasImage = triggerProvidesPayload
                for ancestor in ancestors[key] ?? [] where executed.contains(ancestor) {
                    if fails(ancestor) {
                        for name in Self.errorVariables {
                            sure.insert(name)
                            maybe.insert(name.lowercased())
                            produced.insert(name.lowercased())
                        }
                        continue
                    }
                    guard let node = nodes[ancestor], node.enabled != .value(false), let contract = nodeContracts[ancestor] else { continue }
                    hasImage = hasImage || contract.payload.rawCapture == .created
                    for output in contract.outputVariables {
                        for name in output.resolveNames(for: node) {
                            maybe.insert(name.lowercased())
                            produced.insert(name.lowercased())
                            if output.isGuaranteed(for: node) { sure.insert(name) }
                        }
                    }
                }
                if var existing = scenarios.guaranteed[key] {
                    existing.formIntersection(sure)
                    scenarios.guaranteed[key] = existing
                    scenarios.covered[key] = scenarios.covered[key]?.intersection(produced)
                    scenarios.possible[key] = scenarios.possible[key]?.union(maybe)
                    scenarios.image[key] = (scenarios.image[key] ?? true) && hasImage
                } else {
                    scenarios.guaranteed[key] = sure
                    scenarios.covered[key] = produced
                    scenarios.possible[key] = maybe
                    scenarios.image[key] = hasImage
                }
            }
        }
        return scenarios
    }

    // MARK: References

    /// The variables `${...}` in the node's parameters start with (upstream `GetReferencedVariables`).
    static func referencedVariables(_ node: RecipeNode) -> [String] {
        node.parameters.members.flatMap { RecipeValidator.strings(in: $0.value) }.flatMap(ExpressionEvaluator.variableReferences(in:))
    }

    /// The producible variable a reference is about: the reference itself, or its longest producible prefix
    /// (`${UserChoice.ask.Length}` is about "UserChoice.ask"). Lowercased, nil when none.
    static func findProducible(_ reference: String, _ producible: Set<String>) -> String? {
        var candidate = reference
        while !candidate.isEmpty {
            if producible.contains(candidate.lowercased()) { return candidate }
            guard let dot = candidate.lastIndex(of: ".") else { return nil }
            candidate = String(candidate[..<dot])
        }
        return nil
    }
}
