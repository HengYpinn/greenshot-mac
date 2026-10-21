// Greenshot for Mac (Community) - an unofficial macOS port of Greenshot
// Copyright (C) 2026 Greenshot for Mac (Community) contributors
// Based on Greenshot, Copyright (C) 2007-2026 Thomas Braun, Jens Klingen, Robin Krom
// SPDX-License-Identifier: GPL-3.0-or-later

import CoreGraphics
import Foundation

/// Errors stop a recipe from loading, warnings are shown (upstream `RecipeValidationResult`).
public struct RecipeValidationResult: Sendable, Equatable {
    public var errors: [String] = []
    public var warnings: [String] = []
    /// Every gated action of the recipe, once.
    public var gatedActions: [RecipeGatedAction] = []

    public init() {}

    public var isValid: Bool { errors.isEmpty }
    /// The kinds of gated actions, sorted (upstream `RecipeApprovalPolicy.GetGateTypes`).
    public var gateTypes: [RecipeGateType] { Array(Set(gatedActions.map(\.gateType))).sorted() }
}

/// Structural rules (header, triggers, nodes, options, flow, cycles) then, when valid, the contract warnings
/// (upstream `RecipeValidator.Validate`). The messages are upstream's; they are the editor's diagnostics too.
public struct RecipeValidator: Sendable {
    private let contracts: StepContractCatalog
    private let triggers: TriggerContractCatalog
    private let requirements: RecipeRequirementCatalog
    private let gates: GateEnvironment

    public init(contracts: StepContractCatalog = .builtIn, triggers: TriggerContractCatalog = .builtIn,
                requirements: RecipeRequirementCatalog = .builtIn, gates: GateEnvironment = .empty) {
        self.contracts = contracts
        self.triggers = triggers
        self.requirements = requirements
        self.gates = gates
    }

    /// Security review: a recipe is checked before anyone approved it, and the flow analysis grows with the square of
    /// the nodes (seconds at a thousand, minutes at twenty thousand). No real recipe comes near these limits; upstream
    /// has none.
    static let maxNodes = 200
    static let maxTriggers = 50

    public func validate(_ recipe: CaptureRecipe) -> RecipeValidationResult {
        var result = RecipeValidationResult()
        let isExtension = recipe.kind == .extension
        validateHeader(recipe, what: isExtension ? "Extension" : "Recipe", &result)
        guard recipe.nodes.count <= Self.maxNodes, recipe.triggers.count <= Self.maxTriggers else {
            let what = isExtension ? "The extension" : "The recipe"
            if recipe.nodes.count > Self.maxNodes {
                result.errors.append("\(what) has \(recipe.nodes.count) nodes; at most \(Self.maxNodes) are allowed.")
            }
            if recipe.triggers.count > Self.maxTriggers {
                result.errors.append("\(what) has \(recipe.triggers.count) triggers; at most \(Self.maxTriggers) are allowed.")
            }
            return result
        }
        if isExtension {
            validateExtensionHeader(recipe, &result)
        }
        for (index, trigger) in recipe.triggers.enumerated() {
            validateTrigger(trigger, index: index, &result)
        }
        if isExtension, !recipe.triggers.isEmpty {
            result.errors.append("An extension can't have triggers; it runs in the recipes it extends.")
        }
        guard !recipe.nodes.isEmpty else {
            result.errors.append("\(isExtension ? "Extension" : "Recipe") must contain at least one node in 'nodes'.")
            return result
        }
        var seen = Set<String>()
        let recipeVariables = RecipeGates.variablesSet(by: recipe, contracts: contracts)
        for (index, node) in recipe.nodes.enumerated() {
            validateNode(node, index: index, seen: &seen, recipeVariables: recipeVariables, &result)
            if isExtension { validateExtensionNode(node, recipe, &result) }
        }
        validateOptions(recipe, &result)
        validateFlow(recipe, ids: seen, allowOut: isExtension, &result)
        if isExtension { validateExtensionFlow(recipe, &result) }
        validateExpressions(recipe, &result)
        if result.isValid, !isExtension {
            for warning in RecipeContractAnalyzer.analyze(recipe, contracts: contracts).warnings
            where !warning.contains("has no registered contract") && !result.warnings.contains(warning) {
                result.warnings.append(warning)
            }
        }
        return result
    }

    // MARK: Header

    private func validateHeader(_ recipe: CaptureRecipe, what: String, _ result: inout RecipeValidationResult) {
        let version = recipe.version.trimmingCharacters(in: .whitespaces)
        if version.isEmpty {
            result.warnings.append("\(what) 'version' is missing; defaulting to '1.0'.")
        } else if version.split(separator: ".").first.map({ $0.trimmingCharacters(in: .whitespaces) }) != "1" {
            result.errors.append("Unsupported \(what.lowercased()) version '\(recipe.version)'. This version of Greenshot supports version 1.x recipes.")
        }
        if recipe.id.trimmingCharacters(in: .whitespaces).isEmpty {
            result.errors.append("\(what) 'id' is required and cannot be empty.")
        }
        if recipe.name.trimmingCharacters(in: .whitespaces).isEmpty {
            result.errors.append("\(what) 'name' is required and cannot be empty.")
        }
        for requirement in recipe.requires {
            if let problem = requirements.problem(with: requirement) { result.errors.append(problem) }
        }
    }

    // MARK: Triggers

    private func validateTrigger(_ trigger: TriggerConfig, index: Int, _ result: inout RecipeValidationResult) {
        let type = trigger.triggerType.trimmingCharacters(in: .whitespaces)
        guard !type.isEmpty else {
            result.errors.append("Trigger at index \(index) is missing required 'triggerType'.")
            return
        }
        if triggers.contract(for: type) == nil {
            result.warnings.append("Trigger at index \(index) has unrecognized triggerType '\(trigger.triggerType)'.")
        }
        let name = trigger.name ?? ""
        if trigger.isType(WellKnownTriggerType.hotkey) {
            let hotkey = trigger.hotkey?.trimmingCharacters(in: .whitespaces) ?? ""
            if hotkey.isEmpty {
                result.errors.append("Hotkey trigger '\(name)' at index \(index) is missing required 'Hotkey' parameter.")
            } else if let problem = RecipeHotkeyText.problem(with: hotkey) {
                result.errors.append("Hotkey trigger '\(name)' at index \(index) has invalid hotkey '\(hotkey)': \(problem)")
            }
        }
        if trigger.isType(WellKnownTriggerType.aiTool) {
            let toolName = trigger.toolName
            if !BuiltInTriggerContracts.isValidToolName(toolName) {
                let shown = (toolName ?? "").isEmpty ? "" : ", not '\(toolName!)'"
                result.errors.append("AI tool trigger '\(name)' at index \(index) needs a 'ToolName' of 1 to 64 letters, digits, '_' or '-'\(shown).")
            }
            if (trigger.commandDescription ?? "").trimmingCharacters(in: .whitespaces).isEmpty {
                result.warnings.append("AI tool trigger '\(name)' at index \(index) has no 'Description', the AI won't know what the tool does.")
            }
        }
        if trigger.isType(WellKnownTriggerType.openFile), let filter = trigger.fileFilter, !filter.trimmingCharacters(in: .whitespaces).isEmpty {
            for part in filter.split(separator: ";") {
                let fileExtension = part.trimmingCharacters(in: .whitespaces)
                guard !fileExtension.isEmpty else { continue }
                let rest = fileExtension.dropFirst()
                if fileExtension.count < 2 || !fileExtension.hasPrefix(".") || rest.contains(where: { ".*?,| ".contains($0) }) {
                    result.errors.append("OpenFile trigger '\(name)' at index \(index) has the invalid extension '\(fileExtension)' in its Filter; use extensions separated by ';', e.g. \".png;.jpg\".")
                }
            }
        }
    }

    // MARK: Nodes

    private static let sourceTypes = ["Region", "Window", "ActiveWindow", "FullScreen", "LastRegion", "Clipboard", "File", "TextOcr", "CurrentEditor", "Extension"]
    /// Upstream `CaptureMode`.
    private static let selectionModes = ["None", "Region", "FullScreen", "ActiveWindow", "Window", "LastRegion", "Clipboard", "File", "Import", "Text"]
    /// Upstream `RecipeValidator.BuiltInAnnotationTypes` plus the Zxing plug-in's (built in on the Mac).
    static let annotationTypes = ["Rectangle", "Ellipse", "Line", "Arrow", "Freehand", "Text", "Speechbubble", "StepLabel", "Image", "Icon",
                                  "Cursor", "Emoji", "Svg", "Blur", "Pixelize", "Highlight", "Magnify", "Crop", "QRCode", "Barcode"]

    /// `Enum.TryParse`: a name of the enum (any case) or a number.
    private static func isEnumName(_ text: String, _ names: [String]) -> Bool {
        let trimmed = text.trimmingCharacters(in: .whitespaces)
        return names.contains { recipeEquals($0, trimmed) } || Int(trimmed) != nil
    }

    private func validateNode(_ node: RecipeNode, index: Int, seen: inout Set<String>, recipeVariables: Set<String>,
                              _ result: inout RecipeValidationResult) {
        let id = node.id.trimmingCharacters(in: .whitespaces)
        if id.isEmpty {
            result.errors.append("Node at index \(index) is missing required 'id'.")
        } else if seen.contains(id.lowercased()) {
            result.errors.append("Duplicate node id '\(node.id)' found in recipe.")
        } else {
            seen.insert(id.lowercased())
        }
        guard !node.stepType.trimmingCharacters(in: .whitespaces).isEmpty else {
            result.errors.append("Node '\(id.isEmpty ? String(index) : node.id)' is missing required 'stepType'.")
            return
        }
        guard let contract = contracts.contract(for: node.stepType) else {
            result.errors.append("Node '\(node.id)' uses stepType '\(node.stepType)', which is not available in this version of Greenshot.")
            return
        }
        let parameters = node.parameters
        if recipeEquals(node.stepType, WellKnownStepType.effect), recipeEquals(parameters.string("Effect") ?? "Border", "Border"),
           let width = parameters["Width"], case .number = width, let value = width.asInt, value < 1 {
            result.errors.append("Node '\(node.id)' [Border]: 'Width' must be greater than or equal to 1 (got \(value)).")
        } else if recipeEquals(node.stepType, WellKnownStepType.effect), recipeEquals(parameters.string("Effect") ?? "Border", "Border"),
                  let width = parameters["Width"]?.stringValue, let value = Int(width.trimmingCharacters(in: .whitespaces)), value < 1 {
            result.errors.append("Node '\(node.id)' [Border]: 'Width' must be greater than or equal to 1 (got \(value)).")
        }
        if recipeEquals(node.stepType, WellKnownStepType.source), let sourceType = parameters["SourceType"]?.stringValue,
           !Self.isEnumName(sourceType, Self.sourceTypes) {
            result.errors.append("Node '\(node.id)' [Source]: Unknown SourceType '\(sourceType)'.")
        }
        if recipeEquals(node.stepType, WellKnownStepType.interactiveSelection), let mode = parameters["SelectionMode"]?.stringValue,
           !Self.isEnumName(mode, Self.selectionModes) {
            result.errors.append("Node '\(node.id)' [InteractiveSelection]: Unknown SelectionMode '\(mode)'.")
        }
        if recipeEquals(node.stepType, WellKnownStepType.conditional), parameters["Branches"] == nil || parameters["Branches"] == .null {
            result.errors.append("Node '\(node.id)' [Conditional]: Missing required 'branches' configuration list.")
        }
        if recipeEquals(node.stepType, WellKnownStepType.annotation) {
            var types: [String] = []
            if let single = parameters["Type"]?.stringValue, !single.trimmingCharacters(in: .whitespaces).isEmpty { types.append(single) }
            for item in parameters["Annotations"]?.arrayValue ?? [] {
                if let type = item.objectValue?.string("Type"), !type.trimmingCharacters(in: .whitespaces).isEmpty { types.append(type) }
            }
            for type in types where !Self.annotationTypes.contains(where: { recipeEquals($0, type.trimmingCharacters(in: .whitespaces)) }) {
                result.errors.append("Node '\(node.id)' uses custom annotation type '\(type)', which is not available because the required extension is not installed or active.")
            }
        }
        if recipeEquals(node.stepType, WellKnownStepType.slot) {
            if RecipeSlots.normalize(parameters.string("Name")) == nil {
                result.errors.append("Node '\(node.id)' [Slot]: 'name' must be one of \(RecipeSlots.all.joined(separator: ", ")).")
            }
            if let accept = parameters["Accept"], !accept.isNull, accept.stringValue == nil, accept.arrayValue == nil {
                result.errors.append("Node '\(node.id)' [Slot]: 'accept' must be \"all\", \"none\" or a list of extension ids.")
            }
        }
        for action in RecipeGates.actions(of: node, contract: contract, environment: gates, recipeSets: recipeVariables)
        where !result.gatedActions.contains(action) {
            result.gatedActions.append(action)
        }
    }

    // MARK: Options

    private func validateOptions(_ recipe: CaptureRecipe, _ result: inout RecipeValidationResult) {
        var declared: [String: RecipeOption] = [:]
        let reserved = ["applyTo", "onlyRecipes", "exceptRecipes", "onlyDestinations"]
        let supported: [ContractDataType] = [.boolean, .integer, .decimal, .string, .enumeration, .color]
        for option in recipe.options ?? [] {
            let key = option.key
            guard Self.isOptionKey(key) else {
                result.errors.append("Option key '\(key)' is invalid: use letters, digits and underscores, starting with a letter.")
                continue
            }
            guard declared[key.lowercased()] == nil else {
                result.errors.append("Duplicate option key '\(key)'.")
                continue
            }
            if recipe.kind == .extension, reserved.contains(where: { recipeEquals($0, key) }) {
                result.errors.append("Option key '\(key)' is reserved for the settings every extension has (which recipes, which destinations).")
                continue
            }
            declared[key.lowercased()] = option
            guard supported.contains(option.type) else {
                result.errors.append("Option '\(key)' has type '\(option.type.rawValue)', options can be Boolean, Integer, Decimal, String, Enum, Color.")
                continue
            }
            if option.type == .enumeration {
                let values = (option.choices ?? []).map(\.value)
                if values.isEmpty || values.contains(where: { $0.trimmingCharacters(in: .whitespaces).isEmpty }) {
                    result.errors.append("Option '\(key)' is an Enum and needs 'choices', each with a 'value'.")
                } else if Set(values.map { $0.lowercased() }).count != values.count {
                    result.errors.append("Option '\(key)' has duplicate choices.")
                }
            } else if !(option.choices ?? []).isEmpty {
                result.warnings.append("Option '\(key)': 'choices' are only used for Enum options.")
            }
            let isNumber = option.type == .integer || option.type == .decimal
            if !isNumber, option.min != nil || option.max != nil {
                result.warnings.append("Option '\(key)': 'min' and 'max' are only used for Integer and Decimal options.")
            }
            if let min = option.min, let max = option.max, min > max {
                result.errors.append("Option '\(key)': 'min' (\(JSONValue.format(min))) is larger than 'max' (\(JSONValue.format(max))).")
            }
            if let defaultValue = option.defaultValue, option.convert(defaultValue) == nil {
                result.errors.append("Option '\(key)': the default '\(defaultValue.interpolationText)' is not a valid \(option.type.rawValue).")
            }
            if option.quickSettings, option.type != .boolean, option.type != .enumeration {
                result.errors.append("Option '\(key)' can't be shown in the quick settings, only Boolean and Enum options can.")
            }
        }
        for option in declared.values.sorted(by: { $0.key < $1.key }) {
            guard let switchKey = option.enabledWhen?.trimmingCharacters(in: .whitespaces), !switchKey.isEmpty else { continue }
            if recipeEquals(switchKey, option.key) || declared[switchKey.lowercased()]?.type != .boolean {
                result.errors.append("Option '\(option.key)': 'enabledWhen' must be the key of another Boolean option of the recipe.")
            }
        }
        let recipeVariables = RecipeGates.variablesSet(by: recipe, contracts: contracts)
        for node in recipe.nodes {
            if case .expression(let expression) = node.enabled, !expression.contains("${") {
                result.errors.append("Node '\(node.id)': 'enabled' must be true, false or an expression like \"${option.key}\".")
            }
            let parameterText = node.parameters.isEmpty ? "" : JSONValue.object(node.parameters).serialized(indented: false)
            var enabledText = ""
            if case .expression(let expression) = node.enabled { enabledText = expression }
            let parameterReferences = ExpressionEvaluator.optionReferences(in: parameterText)
            let references = parameterReferences.union(ExpressionEvaluator.optionReferences(in: enabledText))
            for key in references.sorted() where declared[key.lowercased()] == nil {
                result.errors.append("Node '\(node.id)' uses the option '\(key)', which the recipe doesn't declare in 'options'.")
            }
            // A text the user types must not end up in a command line, an upload address or a file path.
            let textOptions = parameterReferences.sorted().filter { declared[$0.lowercased()]?.type == .string }
            if !textOptions.isEmpty, let contract = contracts.contract(for: node.stepType),
               !RecipeGates.actions(of: node, contract: contract, environment: gates, recipeSets: recipeVariables).isEmpty {
                let list = textOptions.map { "'\($0)'" }.joined(separator: ", ")
                result.errors.append("Node '\(node.id)' needs an approval and can't use the text option(s) \(list).")
            }
        }
        if recipe.kind == .extension, let when = recipe.when {
            for key in ExpressionEvaluator.optionReferences(in: when).sorted() where declared[key.lowercased()] == nil {
                result.errors.append("Extension 'when' uses the option '\(key)', which the extension doesn't declare in 'options'.")
            }
        }
    }

    /// Upstream `RecipeOption.KeyPattern`: letters, digits and underscores, starting with a letter.
    static func isOptionKey(_ key: String) -> Bool {
        guard let first = key.unicodeScalars.first, first.isASCII, CharacterSet.letters.contains(first) else { return false }
        return key.unicodeScalars.allSatisfy { $0.isASCII && (CharacterSet.alphanumerics.contains($0) || $0 == "_") }
    }

    // MARK: Flow

    private func validateFlow(_ recipe: CaptureRecipe, ids: Set<String>, allowOut: Bool, _ result: inout RecipeValidationResult) {
        let flow = recipe.flow
        var starts = flow.startNodes.filter { !$0.trimmingCharacters(in: .whitespaces).isEmpty }
        if starts.isEmpty {
            if recipe.nodes.count == 1 {
                starts = [recipe.nodes[0].id]
            } else {
                result.errors.append("Flow definition must specify at least one entry node in 'startNodes'.")
            }
        }
        func exists(_ id: String) -> Bool { ids.contains(id.lowercased()) }
        func isOut(_ id: String) -> Bool { allowOut && recipeEquals(id, "Out") }
        for start in starts where !exists(start) {
            result.errors.append("Flow start node '\(start)' does not match any defined node id.")
        }
        for transition in flow.conditionalTransitions {
            guard !transition.from.trimmingCharacters(in: .whitespaces).isEmpty else {
                result.errors.append("Conditional transition is missing source 'from' node ID.")
                continue
            }
            if transition.branch.trimmingCharacters(in: .whitespaces).isEmpty {
                result.errors.append("Conditional transition from '\(transition.from)' is missing 'branch' key.")
            }
            guard !transition.to.trimmingCharacters(in: .whitespaces).isEmpty else {
                result.errors.append("Conditional transition from '\(transition.from)' is missing target 'to' node ID.")
                continue
            }
            if !exists(transition.from) {
                result.errors.append("Conditional transition source node '\(transition.from)' does not exist in 'nodes'.")
            } else if let from = recipe.node(transition.from), !recipeEquals(from.stepType, WellKnownStepType.conditional),
                      !recipeEquals(from.stepType, WellKnownStepType.userPrompt) {
                result.warnings.append("Conditional transition source node '\(transition.from)' has stepType '\(from.stepType)' rather than 'Conditional'.")
            }
            if !exists(transition.to), !isOut(transition.to) {
                result.errors.append("Conditional transition target node '\(transition.to)' (from '\(transition.from)', branch '\(transition.branch)') does not exist in 'nodes'.")
            }
        }
        for transition in flow.transitions {
            if !exists(transition.from) {
                result.errors.append("Flow transition source node '\(transition.from)' does not exist in 'nodes'.")
            }
            for target in transition.to where !exists(target) && !isOut(target) {
                result.errors.append("Flow transition target node '\(target)' (from '\(transition.from)') does not exist in 'nodes'.")
            }
        }
        // An error handler that isn't a node would let the failed node end the flow as a success (a Mac addition: upstream
        // checks error targets only in extensions). Only targets the engine would run as a node are checked.
        var reported = Set<String>()
        for handler in Self.errorHandlerTargets(recipe) where !exists(handler.target) {
            let message: String
            if let transition = handler.transition, RecipeFlowEngine.nonEmpty(transition.to) != nil {
                // Extensions say it in their own words (`validateExtensionFlow`).
                if allowOut { continue }
                let from = transition.from.flatMap { $0.isEmpty ? nil : $0 } ?? "*"
                message = "Error transition target node '\(handler.target)' (from '\(from)') does not exist in 'nodes'."
            } else {
                message = "Error handler node '\(handler.target)' of node '\(handler.node.id)' does not exist in 'nodes'."
            }
            if reported.insert(message).inserted { result.errors.append(message) }
        }
        if let cycle = Self.findCycle(recipe, starts: starts, ids: ids) {
            result.errors.append("Cycle/loop detected in recipe flow: \(cycle.joined(separator: " -> ")). Loops are strictly disallowed in DAG flows.")
        }
    }

    /// The node targets failures can go to, as the engine picks them: for each node, the error transition each error type
    /// finds (`RecipeFlow.errorTransition`: the node's own by type, its own for any type, a wildcard one by type, a
    /// wildcard one for any type) or none, then `RecipeFlowEngine.errorTargets`, where a target recipe wins. An error with
    /// an inner type finds one of the transitions of its two types, so one type at a time is enough. A wildcard
    /// transition's own target is the same for every node and is listed once, with the first node that reaches it: the
    /// work stays linear in the transitions (a file with thousands of them is validated before it is approved).
    static func errorHandlerTargets(_ recipe: CaptureRecipe) -> [(node: RecipeNode, transition: ErrorTransition?, target: String)] {
        func isWildcard(_ text: String?) -> Bool { (text ?? "").isEmpty || text == "*" }
        /// The first transition of each error type, and the first for any type, in file order.
        func firsts(_ list: [ErrorTransition]) -> (byType: [(type: String, transition: ErrorTransition)], any: ErrorTransition?) {
            var seen = Set<String>()
            var byType: [(type: String, transition: ErrorTransition)] = []
            var any: ErrorTransition?
            for transition in list {
                if isWildcard(transition.errorType) {
                    if any == nil { any = transition }
                } else if seen.insert(transition.errorType.lowercased()).inserted {
                    byType.append((transition.errorType.lowercased(), transition))
                }
            }
            return (byType, any)
        }
        /// What a transition leads to by itself (a node without handlers of its own): nil, nil sends the error on to the
        /// node's own handler.
        func ownTargets(_ transition: ErrorTransition?) -> (node: String?, recipe: String?) {
            RecipeFlowEngine.errorTargets(of: RecipeNode(id: "", stepType: ""), transition: transition)
        }
        var fromNode: [String: [ErrorTransition]] = [:]
        var fromAny: [ErrorTransition] = []
        for transition in recipe.flow.errorTransitions {
            if isWildcard(transition.from) {
                fromAny.append(transition)
            } else if let from = transition.from {
                fromNode[from.lowercased(), default: []].append(transition)
            }
        }
        let wildcard = firsts(fromAny)
        var wildcardIndex: [String: Int] = [:]
        for (index, entry) in wildcard.byType.enumerated() { wildcardIndex[entry.type] = index }
        // Wildcard transitions by type with a node target not listed yet; those which send the error on to the node's own
        // handler; whether the one for any other type (or none) does.
        var pending = Set(wildcard.byType.indices.filter {
            let leads = ownTargets(wildcard.byType[$0].transition)
            return leads.recipe == nil && leads.node != nil
        })
        let passing = Set(wildcard.byType.indices.filter {
            let leads = ownTargets(wildcard.byType[$0].transition)
            return leads.recipe == nil && leads.node == nil
        })
        let anyLeads = ownTargets(wildcard.any)
        var anyListed = false
        var targets: [(node: RecipeNode, transition: ErrorTransition?, target: String)] = []
        // A node that forwards its errors to a recipe runs no handler node.
        for node in recipe.nodes where !node.id.trimmingCharacters(in: .whitespaces).isEmpty
            && RecipeFlowEngine.nonEmpty(node.onErrorRecipeId) == nil {
            let own = firsts(fromNode[node.id.lowercased()] ?? [])
            var found: [ErrorTransition?] = own.byType.map(\.transition)
            if let any = own.any {
                found.append(any)
            } else {
                // The wildcard transitions of the types the node has none of its own for, and the one for any other type.
                let hidden = Set(own.byType.compactMap { wildcardIndex[$0.type] })
                for index in pending.subtracting(hidden).sorted() {
                    let transition = wildcard.byType[index].transition
                    if let target = ownTargets(transition).node { targets.append((node, transition, target)) }
                    pending.remove(index)
                }
                if !passing.subtracting(hidden).isEmpty { found.append(nil) }
                if anyLeads.recipe == nil {
                    if let target = anyLeads.node {
                        if !anyListed { targets.append((node, wildcard.any, target)) }
                        anyListed = true
                    } else {
                        found.append(nil)
                    }
                }
            }
            var ownHandlerListed = false
            for transition in found {
                let handler = RecipeFlowEngine.errorTargets(of: node, transition: transition)
                guard handler.recipe == nil, let target = handler.node else { continue }
                let isOwnHandler = RecipeFlowEngine.nonEmpty(transition?.to) == nil
                if isOwnHandler, ownHandlerListed { continue }
                ownHandlerListed = ownHandlerListed || isOwnHandler
                targets.append((node, transition, target))
            }
        }
        return targets
    }

    /// The normal transitions plus the error edges (a node's `onErrorNodeId` and the error transitions): a failing error
    /// handler routes to its own handler, so an error edge that leads back is a loop as much as a normal one. Wildcard
    /// error transitions are left out (see below).
    static func edgesIncludingErrorHandlers(_ recipe: CaptureRecipe) -> [String: [String]] {
        var map = recipe.flow.unifiedTransitions
        func add(_ from: String, _ to: String?) {
            guard let to, !to.trimmingCharacters(in: .whitespaces).isEmpty,
                  !from.trimmingCharacters(in: .whitespaces).isEmpty else { return }
            var list = map[from.lowercased()] ?? []
            if !list.contains(where: { recipeEquals($0, to) }) { list.append(to) }
            map[from.lowercased()] = list
        }
        for node in recipe.nodes { add(node.id, node.onErrorNodeId) }
        for transition in recipe.flow.errorTransitions {
            guard let to = transition.to else { continue }
            let source = transition.from ?? ""
            // A wildcard source isn't an edge of the flow: with the handler's own successors it would make a loop of every
            // valid recipe. The run-time cap on error handlers ends a loop through a wildcard handler.
            if source.isEmpty || source == "*" { continue }
            add(source, to)
        }
        return map
    }

    /// Depth-first search with three colours from the start nodes, then from the rest (upstream `DetectCycleDfs`).
    static func findCycle(_ recipe: CaptureRecipe, starts: [String], ids: Set<String>) -> [String]? {
        let transitions = Self.edgesIncludingErrorHandlers(recipe)
        var state: [String: Int] = [:]
        var names: [String: String] = [:]
        for node in recipe.nodes where ids.contains(node.id.lowercased()) {
            state[node.id.lowercased()] = 0
            if names[node.id.lowercased()] == nil { names[node.id.lowercased()] = node.id }
        }
        // An explicit stack instead of recursion: a long chain of nodes must not overflow the thread's stack.
        var stack: [(id: String, next: Int)] = []
        let order = starts.map { $0.lowercased() } + recipe.nodes.map { $0.id.lowercased() }
        for root in order where state[root] == 0 {
            state[root] = 1
            stack.append((root, 0))
            while let top = stack.last {
                let targets = transitions[top.id] ?? []
                guard top.next < targets.count else {
                    state[top.id] = 2
                    stack.removeLast()
                    continue
                }
                stack[stack.count - 1].next += 1
                let key = targets[top.next].lowercased()
                guard let nextState = state[key] else { continue }
                if nextState == 1 {
                    let path = stack.map(\.id)
                    let start = path.firstIndex(of: key) ?? 0
                    return (path[start...] + [key]).map { names[$0] ?? $0 }
                }
                if nextState == 0 {
                    state[key] = 1
                    stack.append((key, 0))
                }
            }
        }
        return nil
    }

    // MARK: Expressions (a Mac addition: the editor shows where a `${...}` doesn't parse)

    private func validateExpressions(_ recipe: CaptureRecipe, _ result: inout RecipeValidationResult) {
        for node in recipe.nodes {
            let contract = contracts.contract(for: node.stepType)
            for member in node.parameters {
                if let parameter = contract?.parameter(member.key), !parameter.supportsExpressions { continue }
                for text in Self.strings(in: member.value) {
                    if let problem = ExpressionEvaluator.syntaxProblem(in: text) {
                        result.warnings.append("Node '\(node.id)' parameter '\(member.key)': the expression \(problem).")
                        break
                    }
                }
            }
        }
    }

    static func strings(in value: JSONValue) -> [String] {
        switch value {
        case .string(let text): return [text]
        case .array(let items): return items.flatMap(strings(in:))
        case .object(let object): return object.members.flatMap { strings(in: $0.value) }
        case .null, .bool, .number: return []
        }
    }

    // MARK: Extensions (upstream `Validate(RecipeExtension)`), so extension files get their messages

    private func validateExtensionHeader(_ recipe: CaptureRecipe, _ result: inout RecipeValidationResult) {
        if !recipe.id.isEmpty, !Self.isOptionKey(recipe.id) {
            result.errors.append("Extension id '\(recipe.id)' is invalid: use letters, digits and underscores, starting with a letter.")
        }
        if let extends = recipe.extends {
            if RecipeSlots.normalize(extends.slot) == nil {
                result.errors.append("Extension slot '\(extends.slot ?? "")' is unknown, use \(RecipeSlots.all.joined(separator: ", ")).")
            }
            if extends.recipes.isEmpty || extends.recipes.contains(where: { $0.trimmingCharacters(in: .whitespaces).isEmpty }) {
                result.errors.append("Extension 'extends.recipes' needs recipe ids, \"*\" or \"*capture\".")
            } else if extends.recipes.contains(where: { recipeEquals($0.trimmingCharacters(in: .whitespaces), recipe.id) }) {
                result.errors.append("An extension can't extend itself.")
            }
        } else {
            result.errors.append("Extension 'extends' is required: which recipes, at which slot.")
        }
        if let when = recipe.when, !when.trimmingCharacters(in: .whitespaces).isEmpty, !when.contains("${") {
            result.errors.append("Extension 'when' must be an expression like \"${payload.width > 800}\".")
        }
    }

    private func validateExtensionNode(_ node: RecipeNode, _ recipe: CaptureRecipe, _ result: inout RecipeValidationResult) {
        if recipeEquals(node.id, "In") || recipeEquals(node.id, "Out") {
            result.errors.append("Node id '\(node.id)' is reserved in extensions (In and Out are where the extension starts and ends).")
        }
        if recipeEquals(node.stepType, WellKnownStepType.source) || recipeEquals(node.stepType, WellKnownStepType.recordVideo) {
            result.errors.append("Node '\(node.id)': an extension can't capture, it works on the capture of the recipe it extends.")
        }
        if recipeEquals(node.stepType, WellKnownStepType.slot) {
            result.errors.append("Node '\(node.id)': an extension can't have slots, an extension can't extend another extension.")
        }
        if WellKnownStepType.isDestination(node.stepType), let slot = RecipeSlots.normalize(recipe.extends?.slot), slot != RecipeSlots.afterExport {
            result.errors.append("Node '\(node.id)' exports the capture (\(node.stepType)); an extension can only use destinations at the \(RecipeSlots.afterExport) slot.")
        }
    }

    private func validateExtensionFlow(_ recipe: CaptureRecipe, _ result: inout RecipeValidationResult) {
        let flow = recipe.flow
        if flow.startNodes.contains(where: { recipeEquals($0, "Out") }) {
            result.errors.append("An extension can't start at Out.")
        }
        for node in recipe.nodes where recipeEquals(node.stepType, WellKnownStepType.conditional) {
            let branches = ConditionalBranch.read(node)
            if !branches.contains(where: { recipeEquals($0.expression.trimmingCharacters(in: .whitespaces), "else") }) {
                result.errors.append("Node '\(node.id)' [Conditional]: in an extension a decision needs an \"else\" branch, so the recipe always goes on.")
            }
            for branch in branches where !branch.key.isEmpty {
                let routed = flow.conditionalTransitions.contains {
                    recipeEquals($0.from, node.id) && recipeEquals($0.branch, branch.key) && !$0.to.trimmingCharacters(in: .whitespaces).isEmpty
                }
                if !routed {
                    result.errors.append("Node '\(node.id)' [Conditional]: branch '\(branch.key)' leads nowhere; route it to a node or to \"Out\".")
                }
            }
        }
        for transition in flow.errorTransitions {
            if recipe.node(transition.from ?? "") == nil {
                result.errors.append("Error transition from '\(transition.from ?? "")': in an extension error transitions must start at one of its nodes.")
            }
            if let to = transition.to, !to.trimmingCharacters(in: .whitespaces).isEmpty, recipe.node(to) == nil {
                result.errors.append("Error transition to '\(to)' doesn't lead to a node of the extension.")
            }
        }
    }
}

/// A branch of a Conditional node's `Branches` (keys case-insensitive, like upstream's `GetBranchProperty`).
struct ConditionalBranch: Equatable {
    var key: String
    var expression: String

    static func read(_ node: RecipeNode) -> [ConditionalBranch] {
        (node.parameters["Branches"]?.arrayValue ?? []).compactMap { item in
            guard let object = item.objectValue else { return nil }
            return ConditionalBranch(key: object.string("Key") ?? "", expression: object.string("Expression") ?? "")
        }
    }
}
