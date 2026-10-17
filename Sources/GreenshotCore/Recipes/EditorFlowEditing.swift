// Greenshot for Mac (Community) - an unofficial macOS port of Greenshot
// Copyright (C) 2026 Greenshot for Mac (Community) contributors
// Based on Greenshot, Copyright (C) 2007-2026 Thomas Braun, Jens Klingen, Robin Krom
// SPDX-License-Identifier: GPL-3.0-or-later

import Foundation

/// Why a step can't be renamed (upstream `HandleNodeIdChanged` refusals, as status messages).
public enum RecipeRenameError: Error, Equatable, Sendable, LocalizedError {
    case empty
    case duplicate(String)
    case reserved(String)
    case unknown(String)

    public var errorDescription: String? {
        switch self {
        case .empty: return "A step needs an ID."
        case .duplicate(let id): return "Cannot rename to '\(id)': A step with this ID already exists."
        case .reserved: return "In and Out keep their names."
        case .unknown(let id): return "There is no step '\(id)'."
        }
    }
}

/// The recipe editor's changes of the flow (upstream RecipeEditorViewModel.cs and .Insert.cs, on the recipe instead of
/// canvas connections). Every function keeps unknown members (`extra`) of the recipe, its nodes and its flow.
public enum RecipeFlowEditor {
    /// Upstream `CreateStepNode`: "<steptype>_<4 hex>", unique in the recipe (case-insensitive).
    public static func newNodeId(for stepType: String, in recipe: CaptureRecipe) -> String {
        let prefix = stepType.lowercased().filter { $0.isLetter || $0.isNumber || $0 == "_" }
        while true {
            let id = "\(prefix.isEmpty ? "step" : prefix)_\(UUID().uuidString.replacingOccurrences(of: "-", with: "").prefix(4).lowercased())"
            if recipe.node(id) == nil, !recipeEquals(id, "In"), !recipeEquals(id, "Out") { return id }
        }
    }

    static func isDecision(_ node: RecipeNode) -> Bool { RecipeOutline.isDecision(node) }

    // MARK: Inserting

    /// Adds `node` to an empty flow as its start step, else after `previous` (upstream `InsertStepAfter`): the steps that
    /// followed `previous` follow the new step; a new decision's branches all lead there until they are changed.
    public static func insert(_ node: RecipeNode, after previous: String?, in recipe: inout CaptureRecipe) {
        guard let previous, let previousNode = recipe.node(previous) else {
            append(node, in: &recipe)
            return
        }
        let next = recipe.flow.targets(from: previousNode.id)
        removeTransitions(from: previousNode.id, in: &recipe)
        place(node, after: previousNode.id, in: &recipe)
        recipe.flow.addTransition(from: previousNode.id, to: node.id)
        lead(node, to: next, in: &recipe)
    }

    /// Puts `node` on the transition `from` → `to` (upstream "Insert step here" on an arrow): `from` nil is a start
    /// step, `branch` a decision's branch.
    public static func insert(_ node: RecipeNode, between from: String?, and to: String, branch: String?, in recipe: inout CaptureRecipe) {
        if let from {
            if let branch {
                for index in recipe.flow.conditionalTransitions.indices
                where recipeEquals(recipe.flow.conditionalTransitions[index].from, from)
                    && recipeEquals(recipe.flow.conditionalTransitions[index].branch, branch)
                    && recipeEquals(recipe.flow.conditionalTransitions[index].to, to) {
                    recipe.flow.conditionalTransitions[index].to = node.id
                }
            } else {
                replaceTarget(from: from, old: to, new: node.id, in: &recipe)
            }
            place(node, after: from, in: &recipe)
        } else {
            for index in recipe.flow.startNodes.indices where recipeEquals(recipe.flow.startNodes[index], to) {
                recipe.flow.startNodes[index] = node.id
            }
            place(node, before: to, in: &recipe)
        }
        lead(node, to: [to], in: &recipe)
    }

    /// The first step of a decision's branch: what the branch led to follows the new step.
    public static func insert(_ node: RecipeNode, intoBranch branch: String, of decision: String, in recipe: inout CaptureRecipe) {
        let targets = recipe.flow.conditionalTransitions
            .filter { recipeEquals($0.from, decision) && recipeEquals($0.branch, branch) && !$0.to.isEmpty }.map(\.to)
        recipe.flow.conditionalTransitions.removeAll { recipeEquals($0.from, decision) && recipeEquals($0.branch, branch) }
        let decisionId = recipe.node(decision)?.id ?? decision
        recipe.flow.conditionalTransitions.append(ConditionalTransition(from: decisionId, branch: branch, to: node.id))
        place(node, after: decisionId, in: &recipe)
        lead(node, to: targets, in: &recipe)
    }

    /// One more lane of `from`'s next steps (upstream "fork by multiple outputs"): `from` nil is another start step.
    public static func addParallel(_ node: RecipeNode, from: String?, in recipe: inout CaptureRecipe) {
        if let from, let fromNode = recipe.node(from) {
            place(node, after: fromNode.id, in: &recipe)
            recipe.flow.addTransition(from: fromNode.id, to: node.id)
        } else {
            recipe.nodes.append(node)
            recipe.flow.startNodes.append(node.id)
        }
    }

    /// Upstream `AddStep` without a selection; an empty recipe's first step is its start step (upstream `CreateStepNode`).
    public static func append(_ node: RecipeNode, in recipe: inout CaptureRecipe) {
        let wasEmpty = recipe.nodes.isEmpty
        if !wasEmpty, let end = defaultAppendPoint(in: recipe) {
            insert(node, after: end, in: &recipe)
            return
        }
        recipe.nodes.append(node)
        if wasEmpty || recipe.flow.startNodes.isEmpty {
            recipe.flow.startNodes = [node.id]
        }
    }

    /// Where a new step goes without a selection: after the last step of the list that has no next step and doesn't decide.
    public static func defaultAppendPoint(in recipe: CaptureRecipe) -> String? {
        let order = RecipeOutline(recipe).stepOrder
        return order.last { id in
            guard let node = recipe.node(id), !isDecision(node) else { return false }
            return (recipe.flow.unifiedTransitions[id.lowercased()] ?? []).isEmpty
        }
    }

    // MARK: Removing

    /// Deletes a step (upstream `DeleteNode`) and joins its neighbours: what led to it leads to its next steps (a list
    /// editor's expectation; upstream only removes the connections). Start steps, error routes and "on error" pointers to it
    /// go too. False when there is no such step.
    @discardableResult
    public static func delete(_ id: String, in recipe: inout CaptureRecipe) -> Bool {
        guard let index = recipe.nodes.firstIndex(where: { recipeEquals($0.id, id) }) else { return false }
        let removed = recipe.nodes.remove(at: index)
        let next = isDecision(removed) ? [] : recipe.flow.targets(from: removed.id)
        // Start steps
        var starts: [String] = []
        for start in recipe.flow.startNodes {
            let replacement = recipeEquals(start, removed.id) ? next : [start]
            for item in replacement where !starts.contains(where: { recipeEquals($0, item) }) { starts.append(item) }
        }
        recipe.flow.startNodes = starts
        removeTransitions(from: removed.id, in: &recipe)
        recipe.flow.conditionalTransitions.removeAll { recipeEquals($0.from, removed.id) }
        // Transitions into it
        for t in recipe.flow.transitions.indices where recipe.flow.transitions[t].to.contains(where: { recipeEquals($0, removed.id) }) {
            var targets: [String] = []
            for target in recipe.flow.transitions[t].to {
                let replacement = recipeEquals(target, removed.id) ? next : [target]
                for item in replacement where !targets.contains(where: { recipeEquals($0, item) }) && !recipeEquals(item, recipe.flow.transitions[t].from) {
                    targets.append(item)
                }
            }
            recipe.flow.transitions[t].to = targets
        }
        recipe.flow.transitions.removeAll { $0.to.isEmpty }
        var conditional: [ConditionalTransition] = []
        for transition in recipe.flow.conditionalTransitions {
            guard recipeEquals(transition.to, removed.id) else {
                conditional.append(transition)
                continue
            }
            for item in next where !recipeEquals(item, transition.from) {
                conditional.append(ConditionalTransition(from: transition.from, branch: transition.branch, to: item))
            }
        }
        recipe.flow.conditionalTransitions = conditional
        recipe.flow.errorTransitions.removeAll { recipeEquals($0.from ?? "", removed.id) || recipeEquals($0.to ?? "", removed.id) }
        for n in recipe.nodes.indices where recipeEquals(recipe.nodes[n].onErrorNodeId ?? "", removed.id) {
            recipe.nodes[n].onErrorNodeId = nil
        }
        return true
    }

    /// Removes one transition (upstream "Delete Connection"); `from` nil removes a start step.
    public static func disconnect(from: String?, to: String, branch: String?, in recipe: inout CaptureRecipe) {
        guard let from else {
            recipe.flow.startNodes.removeAll { recipeEquals($0, to) }
            return
        }
        if let branch {
            recipe.flow.conditionalTransitions.removeAll {
                recipeEquals($0.from, from) && recipeEquals($0.branch, branch) && recipeEquals($0.to, to)
            }
            return
        }
        for t in recipe.flow.transitions.indices where recipeEquals(recipe.flow.transitions[t].from, from) {
            recipe.flow.transitions[t].to.removeAll { recipeEquals($0, to) }
        }
        recipe.flow.transitions.removeAll { $0.to.isEmpty }
    }

    // MARK: Connecting

    /// Whether `from` may lead to `to` without a loop (upstream `ValidateGraphCycles` refuses those connections); `to` may
    /// be "Out" in an automatic step.
    public static func canConnect(from: String, to: String, in recipe: CaptureRecipe) -> Bool {
        if recipe.kind == .extension, recipeEquals(to, "Out") { return recipe.node(from) != nil }
        guard recipe.node(from) != nil, recipe.node(to) != nil, !recipeEquals(from, to) else { return false }
        // A loop when `from` is reachable from `to`.
        let transitions = recipe.flow.unifiedTransitions
        var seen = Set<String>()
        var stack = [to.lowercased()]
        while let id = stack.popLast() {
            if id == from.lowercased() { return false }
            guard seen.insert(id).inserted else { continue }
            stack += (transitions[id] ?? []).map { $0.lowercased() }
        }
        return true
    }

    /// The targets the "continues at" picker offers after `from`: steps that don't make a loop, in file order.
    public static func connectableTargets(from: String, in recipe: CaptureRecipe) -> [String] {
        var result = recipe.nodes.map(\.id).filter { canConnect(from: from, to: $0, in: recipe) }
        if recipe.kind == .extension { result.append("Out") }
        return result
    }

    /// Adds `from` → `to` (or the branch's transition); false when it would make a loop.
    @discardableResult
    public static func connect(from: String, to: String, branch: String?, in recipe: inout CaptureRecipe) -> Bool {
        guard canConnect(from: from, to: to, in: recipe) else { return false }
        let fromId = recipe.node(from)?.id ?? from
        let toId = recipe.node(to)?.id ?? to
        if let branch {
            if !recipe.flow.conditionalTransitions.contains(where: {
                recipeEquals($0.from, fromId) && recipeEquals($0.branch, branch) && recipeEquals($0.to, toId)
            }) {
                recipe.flow.conditionalTransitions.append(ConditionalTransition(from: fromId, branch: branch, to: toId))
            }
        } else {
            recipe.flow.addTransition(from: fromId, to: toId)
        }
        return true
    }

    /// Changes where a transition leads (the "continues at" picker); false when the new target would make a loop.
    @discardableResult
    public static func retarget(from: String?, branch: String?, old: String, new: String, in recipe: inout CaptureRecipe) -> Bool {
        guard let from else {
            guard recipe.node(new) != nil else { return false }
            for index in recipe.flow.startNodes.indices where recipeEquals(recipe.flow.startNodes[index], old) {
                recipe.flow.startNodes[index] = recipe.node(new)?.id ?? new
            }
            return true
        }
        var copy = recipe
        disconnect(from: from, to: old, branch: branch, in: &copy)
        guard connect(from: from, to: new, branch: branch, in: &copy) else { return false }
        recipe = copy
        return true
    }

    /// Upstream `ToggleStartNode`: a start step stops being one, another step becomes one (several run in parallel).
    public static func toggleStart(_ id: String, in recipe: inout CaptureRecipe) {
        guard let node = recipe.node(id) else { return }
        if recipe.flow.startNodes.contains(where: { recipeEquals($0, node.id) }) {
            recipe.flow.startNodes.removeAll { recipeEquals($0, node.id) }
        } else {
            recipe.flow.startNodes.append(node.id)
        }
    }

    public static func isStart(_ id: String, in recipe: CaptureRecipe) -> Bool {
        recipe.flow.startNodes.contains { recipeEquals($0, id) }
    }

    // MARK: Renaming and moving

    /// Upstream `HandleNodeIdChanged`: the new id everywhere the old one is used (start steps, transitions, conditional
    /// and error transitions, every step's "on error").
    public static func rename(_ old: String, to new: String, in recipe: inout CaptureRecipe) throws {
        let newId = new.trimmingCharacters(in: .whitespaces)
        guard let index = recipe.nodes.firstIndex(where: { recipeEquals($0.id, old) }) else { throw RecipeRenameError.unknown(old) }
        let oldId = recipe.nodes[index].id
        guard !newId.isEmpty else { throw RecipeRenameError.empty }
        if oldId == newId { return }
        if recipe.kind == .extension, recipeEquals(newId, "In") || recipeEquals(newId, "Out") || recipeEquals(oldId, "In") || recipeEquals(oldId, "Out") {
            throw RecipeRenameError.reserved(newId)
        }
        if recipe.nodes.indices.contains(where: { $0 != index && recipeEquals(recipe.nodes[$0].id, newId) }) {
            throw RecipeRenameError.duplicate(newId)
        }
        func swap(_ text: String) -> String { recipeEquals(text, oldId) ? newId : text }
        recipe.nodes[index].id = newId
        recipe.flow.startNodes = recipe.flow.startNodes.map(swap)
        for t in recipe.flow.transitions.indices {
            recipe.flow.transitions[t].from = swap(recipe.flow.transitions[t].from)
            recipe.flow.transitions[t].to = recipe.flow.transitions[t].to.map(swap)
        }
        for c in recipe.flow.conditionalTransitions.indices {
            recipe.flow.conditionalTransitions[c].from = swap(recipe.flow.conditionalTransitions[c].from)
            recipe.flow.conditionalTransitions[c].to = swap(recipe.flow.conditionalTransitions[c].to)
        }
        for e in recipe.flow.errorTransitions.indices {
            recipe.flow.errorTransitions[e].from = recipe.flow.errorTransitions[e].from.map(swap)
            recipe.flow.errorTransitions[e].to = recipe.flow.errorTransitions[e].to.map(swap)
        }
        for n in recipe.nodes.indices {
            recipe.nodes[n].onErrorNodeId = recipe.nodes[n].onErrorNodeId.map(swap)
        }
    }

    /// The step before `id` in a plain sequence: its only predecessor, which leads only to `id`; neither decides.
    public static func sequencePredecessor(of id: String, in recipe: CaptureRecipe) -> String? {
        guard let node = recipe.node(id), !isDecision(node) else { return nil }
        let into = recipe.flow.transitions.filter { $0.to.contains { recipeEquals($0, node.id) } }
        guard into.count == 1, into[0].to.count == 1,
              !recipe.flow.conditionalTransitions.contains(where: { recipeEquals($0.to, node.id) }),
              !isStart(node.id, in: recipe),
              let previous = recipe.node(into[0].from), !isDecision(previous) else { return nil }
        return previous.id
    }

    /// Swaps a step with the one before it in a sequence (Move Up); false when it isn't in a plain sequence.
    @discardableResult
    public static func moveUp(_ id: String, in recipe: inout CaptureRecipe) -> Bool {
        guard let previous = sequencePredecessor(of: id, in: recipe), let node = recipe.node(id) else { return false }
        let after = recipe.flow.targets(from: node.id)
        // What led to `previous` leads to `node`.
        for index in recipe.flow.startNodes.indices where recipeEquals(recipe.flow.startNodes[index], previous) {
            recipe.flow.startNodes[index] = node.id
        }
        for t in recipe.flow.transitions.indices where !recipeEquals(recipe.flow.transitions[t].from, previous) {
            recipe.flow.transitions[t].to = recipe.flow.transitions[t].to.map { recipeEquals($0, previous) ? node.id : $0 }
        }
        for c in recipe.flow.conditionalTransitions.indices where recipeEquals(recipe.flow.conditionalTransitions[c].to, previous) {
            recipe.flow.conditionalTransitions[c].to = node.id
        }
        removeTransitions(from: previous, in: &recipe)
        removeTransitions(from: node.id, in: &recipe)
        recipe.flow.addTransition(from: node.id, to: previous)
        for target in after { recipe.flow.addTransition(from: previous, to: target) }
        if let a = recipe.nodes.firstIndex(where: { recipeEquals($0.id, previous) }),
           let b = recipe.nodes.firstIndex(where: { recipeEquals($0.id, node.id) }), b > a {
            let moved = recipe.nodes.remove(at: b)
            recipe.nodes.insert(moved, at: a)
        }
        return true
    }

    /// Swaps a step with the one after it in a sequence (Move Down).
    @discardableResult
    public static func moveDown(_ id: String, in recipe: inout CaptureRecipe) -> Bool {
        let next = recipe.flow.targets(from: id)
        guard next.count == 1, sequencePredecessor(of: next[0], in: recipe) != nil else { return false }
        return moveUp(next[0], in: &recipe)
    }

    // MARK: Helpers

    private static func removeTransitions(from id: String, in recipe: inout CaptureRecipe) {
        recipe.flow.transitions.removeAll { recipeEquals($0.from, id) }
    }

    private static func replaceTarget(from: String, old: String, new: String, in recipe: inout CaptureRecipe) {
        for t in recipe.flow.transitions.indices where recipeEquals(recipe.flow.transitions[t].from, from) {
            recipe.flow.transitions[t].to = recipe.flow.transitions[t].to.map { recipeEquals($0, old) ? new : $0 }
        }
    }

    /// The new step leads to `targets`: a decision through each of its branches, others directly.
    private static func lead(_ node: RecipeNode, to targets: [String], in recipe: inout CaptureRecipe) {
        guard !targets.isEmpty else { return }
        if isDecision(node) {
            let keys = RecipeOutline.branches(of: node, in: recipe.flow).map(\.key)
            if !keys.isEmpty {
                for key in keys {
                    for target in targets { recipe.flow.conditionalTransitions.append(ConditionalTransition(from: node.id, branch: key, to: target)) }
                }
                return
            }
        }
        for target in targets { recipe.flow.addTransition(from: node.id, to: target) }
    }

    private static func place(_ node: RecipeNode, after id: String, in recipe: inout CaptureRecipe) {
        if let index = recipe.nodes.firstIndex(where: { recipeEquals($0.id, id) }) {
            recipe.nodes.insert(node, at: index + 1)
        } else {
            recipe.nodes.append(node)
        }
    }

    private static func place(_ node: RecipeNode, before id: String, in recipe: inout CaptureRecipe) {
        if let index = recipe.nodes.firstIndex(where: { recipeEquals($0.id, id) }) {
            recipe.nodes.insert(node, at: index)
        } else {
            recipe.nodes.append(node)
        }
    }
}
