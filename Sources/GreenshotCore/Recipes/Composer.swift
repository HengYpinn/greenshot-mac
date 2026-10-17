// Greenshot for Mac (Community) - an unofficial macOS port of Greenshot
// Copyright (C) 2026 Greenshot for Mac (Community) contributors
// Based on Greenshot, Copyright (C) 2007-2026 Thomas Braun, Jens Klingen, Robin Krom
// SPDX-License-Identifier: GPL-3.0-or-later
// Owned by RMANAGER after the wave 4 prep.

import Foundation

/// The automatic steps a running recipe was composed with (upstream `AppliedExtensions`, `DestinationChains`): set by
/// `RecipeComposer` on the recipe as it runs, never read from or written to a file.
public struct RecipeComposition: Sendable, Equatable {
    /// The automatic steps in the recipe's slots, the BeforeDestination ones included, as loaded (their options are read
    /// as `${option.<extension id>.<key>}`).
    public var appliedExtensions: [CaptureRecipe] = []
    /// BeforeDestination: run by the export steps on a copy of the capture, per destination.
    public var destinationChains: [RecipeDestinationChain] = []

    public init() {}

    public init(appliedExtensions: [CaptureRecipe], destinationChains: [RecipeDestinationChain] = []) {
        self.appliedExtensions = appliedExtensions
        self.destinationChains = destinationChains
    }

    /// The chains that run for a destination designation ("FileNoDialog", "Clipboard"), in their order.
    public func chains(forDestination designation: String) -> [RecipeDestinationChain] {
        destinationChains.filter { $0.runs(for: designation) }
    }
}

/// Puts the switched-on automatic steps into a recipe: the recipe which runs (upstream
/// `Greenshot.Base/Recipes/RecipeComposer.cs`). Pure: the inputs are not changed.
/// - A Slot node is replaced by the chains of the automatic steps it accepts, by order, then by id: the first chain takes
///   the slot's incoming edges, each chain's ends lead to the next chain, the last chain's ends take the slot's outgoing edges.
/// - The nodes of an automatic step get prefixed ids ("ext_border/border"); their `${option.key}` becomes
///   `${option.ext_border.key}`, so they read the automatic step's options (`resolveOption`).
/// - An automatic step with "when" starts with a Conditional node which skips its chain when the expression is false.
/// - BeforeDestination slots stay where they are; their automatic steps become `RecipeComposition.destinationChains`,
///   run by the export steps.
public enum RecipeComposer {
    /// Between the extension id and the node id of a composed node.
    public static let prefixSeparator = "/"
    private static let whenRunBranch = "run"
    private static let whenSkipBranch = "skip"

    // MARK: Which recipes

    /// Whether the automatic step targets the recipe by its `extends.recipes`: an id, "*" or "*capture" (AI tool recipes
    /// only by id).
    public static func targets(_ ext: CaptureRecipe, _ recipe: CaptureRecipe) -> Bool {
        guard let targets = ext.extends?.recipes, !recipe.id.isEmpty else { return false }
        for raw in targets {
            let target = raw.trimmingCharacters(in: .whitespaces)
            if target.isEmpty { continue }
            if recipeEquals(target, recipe.id) { return true }
            if recipe.isAIToolRecipe { continue }
            if target == RecipeExtensionNames.targetAll { return true }
            if recipeEquals(target, RecipeExtensionNames.targetCaptures), recipe.hasSourceStep, recipe.hasDestinationStep { return true }
        }
        return false
    }

    /// The name of a Slot node (normalized), nil when it isn't one.
    public static func slotName(of node: RecipeNode) -> String? {
        guard recipeEquals(node.stepType, WellKnownStepType.slot) else { return nil }
        return RecipeSlots.normalize(node.parameters.string("Name"))
    }

    /// The Slot nodes of the recipe with the name, in node order.
    public static func slots(of recipe: CaptureRecipe, named slotName: String) -> [RecipeNode] {
        recipe.nodes.filter { self.slotName(of: $0).map { recipeEquals($0, slotName) } ?? false }
    }

    /// Whether the Slot node accepts the automatic step: "Accept" is "all" (or missing), "none" or a list of ids.
    public static func accepts(_ slot: RecipeNode, extensionId: String) -> Bool {
        guard let accept = slot.parameters["Accept"], !accept.isNull else { return true }
        switch accept {
        case .string(let text):
            let trimmed = text.trimmingCharacters(in: .whitespaces)
            if trimmed.isEmpty || recipeEquals(trimmed, RecipeSlots.acceptAll) { return true }
            if recipeEquals(trimmed, RecipeSlots.acceptNone) { return false }
            return RecipeExtensionNames.splitList(trimmed).contains { recipeEquals($0, extensionId) }
        case .array(let items):
            return items.contains { ($0.asString.map { recipeEquals($0.trimmingCharacters(in: .whitespaces), extensionId) }) ?? false }
        default:
            return true
        }
    }

    /// Whether the automatic step could change the recipe: it targets it and the recipe has a slot which accepts it.
    /// The user's settings are not looked at.
    public static func canExtend(_ ext: CaptureRecipe, _ recipe: CaptureRecipe) -> Bool {
        guard ext.kind == .extension, let slotName = ext.extensionSlotName, targets(ext, recipe) else { return false }
        return slots(of: recipe, named: slotName).contains { accepts($0, extensionId: ext.id) }
    }

    /// The automatic steps which change the recipe with these settings, by order, then by id (upstream
    /// `FindApplicableExtensions`); nil settings: all switched on, for all recipes.
    public static func applicable(to recipe: CaptureRecipe, among extensions: [CaptureRecipe],
                                  settings: ((CaptureRecipe) -> RecipeExtensionSettings)? = nil) -> [CaptureRecipe] {
        var seen = Set<String>()
        let found = extensions.filter { ext in
            guard !ext.id.isEmpty, canExtend(ext, recipe), settings?(ext).allowsRecipe(recipe.id) ?? true else { return false }
            return seen.insert(ext.id.lowercased()).inserted
        }
        return found.sorted { lhs, rhs in
            let left = lhs.extends?.order ?? 0
            let right = rhs.extends?.order ?? 0
            if left != right { return left < right }
            return lhs.id.lowercased() < rhs.id.lowercased()
        }
    }

    // MARK: Composing

    /// The recipe with the automatic steps in its slots. Returns the recipe itself (`==`) when no automatic step changes
    /// it, or when it was composed already.
    public static func compose(_ recipe: CaptureRecipe, extensions: [CaptureRecipe],
                               settings: ((CaptureRecipe) -> RecipeExtensionSettings)? = nil) -> CaptureRecipe {
        guard recipe.composition == nil else { return recipe }
        let applicable = applicable(to: recipe, among: extensions, settings: settings)
        guard !applicable.isEmpty else { return recipe }

        var composed = recipe
        var usedIds = Set(composed.nodes.map { $0.id.lowercased() })
        var insertions: [String: Int] = [:]
        var applied: [CaptureRecipe] = []
        var destinationChains: [RecipeDestinationChain] = []

        for slotNode in recipe.nodes {
            guard let slotName = slotName(of: slotNode) else { continue }
            let chains = applicable.filter { $0.extensionSlotName == slotName && accepts(slotNode, extensionId: $0.id) }
            guard !chains.isEmpty else { continue }
            if slotName == RecipeSlots.beforeDestination {
                for ext in chains where !destinationChains.contains(where: { recipeEquals($0.extensionId, ext.id) }) {
                    let only = settings?(ext).onlyDestinations ?? []
                    destinationChains.append(RecipeDestinationChain(extensionId: ext.id, extensionName: ext.name,
                                                                    flow: standalone(ext, in: recipe), onlyDestinations: only))
                    applied.append(ext)
                }
                continue
            }
            let built = chains.map { ext in buildChain(ext, prefix: nextPrefix(ext, slotNode, &insertions), usedIds: &usedIds) }
            replaceSlot(in: &composed, slotId: slotNode.id, with: built)
            applied += chains
        }
        var unique: [CaptureRecipe] = []
        for ext in applied where !unique.contains(where: { recipeEquals($0.id, ext.id) }) { unique.append(ext) }
        composed.composition = RecipeComposition(appliedExtensions: unique, destinationChains: destinationChains)
        return composed
    }

    /// `option.<key>` of the running recipe, else `option.<extension id>.<key>` of an automatic step it was composed with
    /// (upstream `RecipeOptionStore.TryResolve`).
    public static func resolveOption(_ key: String, in recipe: CaptureRecipe) -> (ownerId: String, option: RecipeOption)? {
        if let option = recipe.option(key) { return (ownerId: recipe.id, option: option) }
        guard let dot = key.firstIndex(of: "."), dot > key.startIndex, let applied = recipe.composition?.appliedExtensions else { return nil }
        let extensionId = String(key[..<dot])
        let optionKey = String(key[key.index(after: dot)...])
        guard let ext = applied.first(where: { recipeEquals($0.id, extensionId) }), let option = ext.option(optionKey) else { return nil }
        return (ownerId: ext.id, option: option)
    }

    /// `option.key` in the `${...}` of a text becomes `option.<extension id>.key`.
    public static func rewriteOptionReferences(_ text: String, extensionId: String) -> String {
        guard text.range(of: "option.", options: .caseInsensitive) != nil else { return text }
        let source = text as NSString
        var result = ""
        var last = 0
        for match in expressionPattern.matches(in: text, range: NSRange(location: 0, length: source.length)) {
            result += source.substring(with: NSRange(location: last, length: match.range.location - last))
            let inner = source.substring(with: match.range(at: 1))
            let template = "option." + NSRegularExpression.escapedTemplate(for: extensionId) + "."
            let rewritten = optionReference.stringByReplacingMatches(in: inner, range: NSRange(location: 0, length: (inner as NSString).length),
                                                                     withTemplate: template)
            result += "${" + rewritten + "}"
            last = match.range.location + match.range.length
        }
        result += source.substring(from: last)
        return result
    }

    /// Every text of a parameter value rewritten (texts, lists, objects).
    static func rewriteOptionReferences(_ value: JSONValue, extensionId: String) -> JSONValue {
        switch value {
        case .string(let text): return .string(rewriteOptionReferences(text, extensionId: extensionId))
        case .array(let items): return .array(items.map { rewriteOptionReferences($0, extensionId: extensionId) })
        case .object(let object):
            return .object(JSONObject(object.members.map { JSONMember($0.key, rewriteOptionReferences($0.value, extensionId: extensionId)) }))
        case .null, .bool, .number: return value
        }
    }

    private static let expressionPattern = try! NSRegularExpression(pattern: #"\$\{([^}]*)\}"#)
    private static let optionReference = try! NSRegularExpression(pattern: #"(?<![A-Za-z0-9_.])option\.(?=[A-Za-z])"#,
                                                                  options: .caseInsensitive)

    // MARK: Chains

    /// "ext_border/" the first time the automatic step goes into the recipe, "ext_border/<slot node id>/" for further slots.
    private static func nextPrefix(_ ext: CaptureRecipe, _ slotNode: RecipeNode, _ insertions: inout [String: Int]) -> String {
        let key = ext.id.lowercased()
        let count = insertions[key] ?? 0
        insertions[key] = count + 1
        return count == 0 ? ext.id + prefixSeparator : ext.id + prefixSeparator + slotNode.id + prefixSeparator
    }

    /// An automatic step's chain, ready to be wired between a slot's incoming and outgoing edges.
    private struct BuiltChain {
        var nodes: [RecipeNode] = []
        /// Where the recipe enters the chain: its "when" node, else its start nodes.
        var entry: [String] = []
        var starts: [String] = []
        var transitions: [RecipeTransition] = []
        var conditionalTransitions: [ConditionalTransition] = []
        var errorTransitions: [ErrorTransition] = []
        /// Nodes which lead on to the recipe: without outgoing edges, or with a transition to Out.
        var ends: [String] = []
        /// Conditional branches routed to Out.
        var branchesToOut: [(from: String, branch: String)] = []
        var whenNodeId: String?
    }

    private static func buildChain(_ ext: CaptureRecipe, prefix: String, usedIds: inout Set<String>) -> BuiltChain {
        var chain = BuiltChain()
        var idMap: [String: String] = [:]
        for node in ext.nodes where !node.id.isEmpty {
            idMap[node.id.lowercased()] = uniqueId(prefix + node.id, &usedIds)
        }
        func map(_ id: String?) -> String? { id.flatMap { idMap[$0.lowercased()] } }
        func isOut(_ id: String) -> Bool { recipeEquals(id.trimmingCharacters(in: .whitespaces), RecipeExtensionNames.outNode) }

        for node in ext.nodes where !node.id.isEmpty {
            var clone = node
            clone.id = map(node.id) ?? node.id
            clone.parameters = JSONObject(node.parameters.members.map {
                JSONMember($0.key, rewriteOptionReferences($0.value, extensionId: ext.id))
            })
            if case .expression(let expression) = node.enabled {
                clone.enabled = .expression(rewriteOptionReferences(expression, extensionId: ext.id))
            }
            clone.onErrorNodeId = map(node.onErrorNodeId)
            chain.nodes.append(clone)
        }

        var toOut = Set<String>()
        var outgoing = Set<String>()
        for transition in ext.flow.transitions {
            guard let from = map(transition.from) else { continue }
            for target in transition.to {
                if isOut(target) {
                    toOut.insert(from.lowercased())
                } else if let to = map(target) {
                    add(from: from, to: to, &chain.transitions)
                    outgoing.insert(from.lowercased())
                }
            }
        }
        for conditional in ext.flow.conditionalTransitions {
            guard let from = map(conditional.from) else { continue }
            outgoing.insert(from.lowercased())
            if isOut(conditional.to) {
                chain.branchesToOut.append((from, conditional.branch))
            } else if let to = map(conditional.to) {
                chain.conditionalTransitions.append(ConditionalTransition(from: from, branch: conditional.branch, to: to))
            }
        }
        for error in ext.flow.errorTransitions {
            // An automatic step's error transitions only apply to its own nodes.
            guard let from = map(error.from) else { continue }
            chain.errorTransitions.append(ErrorTransition(from: from, to: map(error.to), targetRecipeId: error.targetRecipeId,
                                                          errorType: error.errorType))
        }

        var starts: [String] = []
        for start in ext.flow.startNodes {
            if let mapped = map(start), !starts.contains(where: { recipeEquals($0, mapped) }) { starts.append(mapped) }
        }
        if starts.isEmpty, let first = chain.nodes.first { starts.append(first.id) }
        chain.starts = starts
        for node in chain.nodes where !outgoing.contains(node.id.lowercased()) || toOut.contains(node.id.lowercased()) {
            chain.ends.append(node.id)
        }

        if let when = ext.when?.trimmingCharacters(in: .whitespaces), !when.isEmpty {
            let whenId = uniqueId(prefix + "when", &usedIds)
            let branches: [JSONValue] = [
                .object(["Key": .string(whenRunBranch), "Expression": .string(rewriteOptionReferences(when, extensionId: ext.id))]),
                .object(["Key": .string(whenSkipBranch), "Expression": .string("else")])
            ]
            let whenNode = RecipeNode(id: whenId, stepType: WellKnownStepType.conditional, name: "\(ext.name.isEmpty ? ext.id : ext.name): when",
                                      parameters: ["Branches": .array(branches)])
            chain.nodes.insert(whenNode, at: 0)
            for start in chain.starts {
                chain.conditionalTransitions.append(ConditionalTransition(from: whenId, branch: whenRunBranch, to: start))
            }
            chain.whenNodeId = whenId
            chain.entry = [whenId]
        } else {
            chain.entry = chain.starts
        }
        return chain
    }

    /// Adds the chain to the flow, its ends leading to the exits.
    private static func connect(_ chain: BuiltChain, to exits: [String], in flow: inout RecipeFlow) {
        for transition in chain.transitions {
            for target in transition.to { flow.addTransition(from: transition.from, to: target) }
        }
        for conditional in chain.conditionalTransitions {
            addConditional(conditional.from, conditional.branch, conditional.to, &flow)
        }
        flow.errorTransitions += chain.errorTransitions
        for end in chain.ends {
            for exit in exits { flow.addTransition(from: end, to: exit) }
        }
        for branch in chain.branchesToOut {
            for exit in exits { addConditional(branch.from, branch.branch, exit, &flow) }
        }
        if let whenId = chain.whenNodeId {
            for exit in exits { addConditional(whenId, whenSkipBranch, exit, &flow) }
        }
    }

    private static func replaceSlot(in composed: inout CaptureRecipe, slotId: String, with chains: [BuiltChain]) {
        var flow = composed.flow
        var exits: [String] = []
        for transition in flow.transitions where recipeEquals(transition.from, slotId) {
            for target in transition.to where !exits.contains(where: { recipeEquals($0, target) }) { exits.append(target) }
        }
        flow.transitions.removeAll { recipeEquals($0.from, slotId) }
        flow.conditionalTransitions.removeAll { recipeEquals($0.from, slotId) }
        flow.errorTransitions.removeAll { $0.from.map { recipeEquals($0, slotId) } ?? false }

        // Wired from the last chain to the first: each chain leads to the entry of the next one.
        var next = exits
        for chain in chains.reversed() {
            connect(chain, to: next, in: &flow)
            next = chain.entry
        }
        let entry = next

        // The slot's incoming edges go to the first chain.
        for index in flow.transitions.indices {
            flow.transitions[index].to = replaceTarget(flow.transitions[index].to, slotId, with: entry)
        }
        let intoSlot = flow.conditionalTransitions.filter { recipeEquals($0.to, slotId) }
        flow.conditionalTransitions.removeAll { recipeEquals($0.to, slotId) }
        for conditional in intoSlot {
            for target in entry { addConditional(conditional.from, conditional.branch, target, &flow) }
        }
        flow.startNodes = replaceTarget(flow.startNodes, slotId, with: entry)
        let firstEntry = entry.first
        for index in flow.errorTransitions.indices where flow.errorTransitions[index].to.map({ recipeEquals($0, slotId) }) ?? false {
            flow.errorTransitions[index].to = firstEntry
        }
        for index in composed.nodes.indices where composed.nodes[index].onErrorNodeId.map({ recipeEquals($0, slotId) }) ?? false {
            composed.nodes[index].onErrorNodeId = firstEntry
        }
        composed.flow = flow

        // The chains' nodes take the place of the slot node.
        let chainNodes = chains.flatMap(\.nodes)
        if let index = composed.nodes.firstIndex(where: { recipeEquals($0.id, slotId) }) {
            composed.nodes.remove(at: index)
            composed.nodes.insert(contentsOf: chainNodes, at: index)
        } else {
            composed.nodes += chainNodes
        }
    }

    /// An automatic step's chain as a flow of its own (BeforeDestination): starts at its entry, its ends end the flow.
    /// It carries the running recipe's id and name (so `${recipe.*}` reads the recipe, as upstream's branch context
    /// does) and the composition that resolves the automatic step's options.
    private static func standalone(_ ext: CaptureRecipe, in recipe: CaptureRecipe) -> CaptureRecipe {
        var usedIds = Set<String>()
        let chain = buildChain(ext, prefix: ext.id + prefixSeparator, usedIds: &usedIds)
        var flow = RecipeFlow(startNodes: chain.entry)
        connect(chain, to: [], in: &flow)
        var standalone = CaptureRecipe(id: recipe.id, name: recipe.name, description: ext.description)
        standalone.nodes = chain.nodes
        standalone.flow = flow
        standalone.composition = RecipeComposition(appliedExtensions: [ext])
        return standalone
    }

    private static func replaceTarget(_ targets: [String], _ oldTarget: String, with newTargets: [String]) -> [String] {
        guard targets.contains(where: { recipeEquals($0, oldTarget) }) else { return targets }
        var result: [String] = []
        for target in targets {
            let replacement = recipeEquals(target, oldTarget) ? newTargets : [target]
            for id in replacement where !result.contains(where: { recipeEquals($0, id) }) { result.append(id) }
        }
        return result
    }

    private static func add(from: String, to: String, _ transitions: inout [RecipeTransition]) {
        if let index = transitions.firstIndex(where: { recipeEquals($0.from, from) }) {
            if !transitions[index].to.contains(where: { recipeEquals($0, to) }) { transitions[index].to.append(to) }
        } else {
            transitions.append(RecipeTransition(from: from, to: [to]))
        }
    }

    /// Upstream `AddConditionalTransition`: once per from, branch and target.
    private static func addConditional(_ from: String, _ branch: String, _ to: String, _ flow: inout RecipeFlow) {
        guard !from.isEmpty, !branch.isEmpty, !to.isEmpty else { return }
        let exists = flow.conditionalTransitions.contains {
            recipeEquals($0.from, from) && recipeEquals($0.branch, branch) && recipeEquals($0.to, to)
        }
        if !exists { flow.conditionalTransitions.append(ConditionalTransition(from: from, branch: branch, to: to)) }
    }

    private static func uniqueId(_ id: String, _ usedIds: inout Set<String>) -> String {
        var unique = id
        var counter = 2
        while usedIds.contains(unique.lowercased()) {
            unique = "\(id)_\(counter)"
            counter += 1
        }
        usedIds.insert(unique.lowercased())
        return unique
    }
}
