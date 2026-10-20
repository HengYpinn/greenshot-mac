// Greenshot for Mac (Community) - an unofficial macOS port of Greenshot
// Copyright (C) 2026 Greenshot for Mac (Community) contributors
// Based on Greenshot, Copyright (C) 2007-2026 Thomas Braun, Jens Klingen, Robin Krom
// SPDX-License-Identifier: GPL-3.0-or-later

import Foundation

/// One row of the recipe editor's step list.
public struct RecipeOutlineRow: Sendable, Equatable, Identifiable {
    public enum Kind: Sendable, Equatable {
        /// A step.
        case step(nodeId: String)
        /// Several steps that run at the same time: the next steps of `from` (nil: the start steps), of its branch
        /// `branch` when `from` decides.
        case parallel(from: String?, branch: String?)
        /// One of the lanes of a `parallel` group; `target` is its first step.
        case lane(from: String?, branch: String?, index: Int, target: String)
        /// A branch of a Conditional (`expression`) or a UserPrompt (`label`); its steps follow, one level deeper.
        case branch(from: String, key: String, expression: String?, label: String?)
        /// The flow goes on at a step shown elsewhere (or one that doesn't exist): the transition `from` → `to`, of the
        /// branch `branch` when `from` decides.
        case continues(from: String?, branch: String?, to: String)
        /// The steps no start step leads to.
        case notReached
        /// Automatic steps: where the recipe's flow comes in, and where it goes on after the last step (`from`).
        case extensionIn
        case extensionOut(from: String, branch: String?)
    }

    public var kind: Kind
    public var depth: Int
    /// Stable within one outline: "step:<id>" for steps, else the kind and position.
    public var id: String

    public init(kind: Kind, depth: Int, id: String) {
        self.kind = kind
        self.depth = depth
        self.id = id
    }

    public var nodeId: String? {
        if case .step(let nodeId) = kind { return nodeId }
        return nil
    }

    /// The row id of a step.
    public static func stepId(_ nodeId: String) -> String { "step:\(nodeId.lowercased())" }
}

/// The recipe's DAG as a list (the recipe editor's left side; there is no upstream counterpart, upstream draws a node
/// graph): from the start steps in file order, a sequence goes down; the branches of a Conditional (keys and expressions)
/// or a UserPrompt (its choices) are indented under the step; several next steps are a "Parallel" group whose lanes end
/// where they all meet (upstream docs "Fork, Join & Conditional Branch Execution Semantics"), the step where they meet
/// follows the group; whatever a tree can't show is a "continues at" row. Steps no start step reaches come last.
/// Deterministic, and safe on cyclic (invalid) flows.
public struct RecipeOutline: Sendable {
    public private(set) var rows: [RecipeOutlineRow] = []

    private let recipe: CaptureRecipe
    private var nodesById: [String: RecipeNode] = [:]
    private var rank: [String: Int] = [:]
    private var postDominators: [String: Set<String>] = [:]
    private var emitted = Set<String>()
    private var counter = 0
    private let isExtension: Bool

    public init(_ recipe: CaptureRecipe) {
        self.recipe = recipe
        isExtension = recipe.kind == .extension
        for node in recipe.nodes where !node.id.isEmpty && nodesById[node.id.lowercased()] == nil {
            nodesById[node.id.lowercased()] = node
        }
        rank = RecipeOutline.topologicalRanks(recipe)
        postDominators = RecipeOutline.postDominators(recipe, ids: Set(nodesById.keys))
        build()
    }

    /// The row ids of the steps in the order they are shown.
    public var stepOrder: [String] { rows.compactMap(\.nodeId) }

    // MARK: Graph

    /// A decision step: its next steps follow its branches.
    public static func isDecision(_ node: RecipeNode) -> Bool {
        recipeEquals(node.stepType, WellKnownStepType.conditional) || recipeEquals(node.stepType, WellKnownStepType.userPrompt)
    }

    /// The branches of a decision step: declared ones (Conditional `Branches`, UserPrompt `Choices`) in their order,
    /// then keys only the conditional transitions use.
    public static func branches(of node: RecipeNode, in flow: RecipeFlow) -> [(key: String, expression: String?, label: String?)] {
        var result: [(key: String, expression: String?, label: String?)] = []
        if recipeEquals(node.stepType, WellKnownStepType.conditional) {
            for branch in ConditionalBranch.read(node) where !branch.key.isEmpty {
                if !result.contains(where: { recipeEquals($0.key, branch.key) }) { result.append((branch.key, branch.expression, nil)) }
            }
        } else if recipeEquals(node.stepType, WellKnownStepType.userPrompt) {
            for item in node.parameters["Choices"]?.arrayValue ?? [] {
                guard let object = item.objectValue, let key = object.string("Key"), !key.isEmpty else { continue }
                if !result.contains(where: { recipeEquals($0.key, key) }) { result.append((key, nil, object.string("Label"))) }
            }
        }
        for transition in flow.conditionalTransitions where recipeEquals(transition.from, node.id) && !transition.branch.isEmpty {
            if !result.contains(where: { recipeEquals($0.key, transition.branch) }) { result.append((transition.branch, nil, nil)) }
        }
        return result
    }

    private func node(_ id: String) -> RecipeNode? { nodesById[id.lowercased()] }

    private func unconditionalTargets(_ id: String) -> [String] { recipe.flow.targets(from: id) }

    private func branchTargets(_ id: String, _ key: String) -> [String] {
        var result: [String] = []
        for transition in recipe.flow.conditionalTransitions
        where recipeEquals(transition.from, id) && recipeEquals(transition.branch, key) && !transition.to.isEmpty {
            if !result.contains(where: { recipeEquals($0, transition.to) }) { result.append(transition.to) }
        }
        return result
    }

    /// Every next step of a node (unconditional and conditional), for reachability.
    private func allTargets(_ id: String) -> [String] {
        recipe.flow.unifiedTransitions[id.lowercased()] ?? []
    }

    /// Kahn's order over all transitions, ties in file order; nodes on a cycle come last in file order.
    static func topologicalRanks(_ recipe: CaptureRecipe) -> [String: Int] {
        let ids = recipe.nodes.map { $0.id.lowercased() }.filter { !$0.isEmpty }
        let known = Set(ids)
        let transitions = recipe.flow.unifiedTransitions
        var inDegree: [String: Int] = [:]
        for id in ids { inDegree[id] = 0 }
        for (from, targets) in transitions where known.contains(from) {
            for target in targets where known.contains(target.lowercased()) { inDegree[target.lowercased(), default: 0] += 1 }
        }
        var ranks: [String: Int] = [:]
        var ready = ids.filter { inDegree[$0] == 0 }
        var next = 0
        while !ready.isEmpty {
            let id = ready.removeFirst()
            guard ranks[id] == nil else { continue }
            ranks[id] = next
            next += 1
            for target in transitions[id] ?? [] where known.contains(target.lowercased()) {
                let key = target.lowercased()
                inDegree[key, default: 0] -= 1
                if inDegree[key] == 0 {
                    // Keep file order among the ready ones.
                    let position = ready.firstIndex { (ids.firstIndex(of: $0) ?? 0) > (ids.firstIndex(of: key) ?? 0) } ?? ready.count
                    ready.insert(key, at: position)
                }
            }
        }
        for id in ids where ranks[id] == nil {
            ranks[id] = next
            next += 1
        }
        return ranks
    }

    /// For each node the nodes every path from it to an end passes through (itself included): post-dominators over all
    /// transitions, by iteration to a fixed point (loops of an invalid recipe converge too).
    static func postDominators(_ recipe: CaptureRecipe, ids: Set<String>) -> [String: Set<String>] {
        let transitions = recipe.flow.unifiedTransitions
        func successors(_ id: String) -> [String] { (transitions[id] ?? []).map { $0.lowercased() }.filter { ids.contains($0) } }
        var result: [String: Set<String>] = [:]
        for id in ids { result[id] = successors(id).isEmpty ? [id] : ids }
        var changed = true
        while changed {
            changed = false
            for id in ids.sorted() {
                let next = successors(id)
                guard !next.isEmpty else { continue }
                var common = result[next[0]] ?? []
                for item in next.dropFirst() { common.formIntersection(result[item] ?? []) }
                common.insert(id)
                if common != result[id] {
                    result[id] = common
                    changed = true
                }
            }
        }
        return result
    }

    /// Where lanes starting at `targets` all meet: the earliest node (by rank) every path from every lane passes through;
    /// nil when they never meet.
    private func meetingPoint(of targets: [String]) -> String? {
        guard targets.count > 1 else { return nil }
        var common: Set<String>?
        for target in targets {
            let must = postDominators[target.lowercased()] ?? []
            common = common.map { $0.intersection(must) } ?? must
        }
        guard let common, !common.isEmpty else { return nil }
        return common.min { (rank[$0] ?? .max, $0) < (rank[$1] ?? .max, $1) }.flatMap { node($0)?.id }
    }

    // MARK: Rows

    private mutating func add(_ kind: RecipeOutlineRow.Kind, depth: Int) {
        let id: String
        if case .step(let nodeId) = kind {
            id = RecipeOutlineRow.stepId(nodeId)
        } else {
            counter += 1
            id = "row:\(counter)"
        }
        rows.append(RecipeOutlineRow(kind: kind, depth: depth, id: id))
    }

    private mutating func build() {
        if isExtension { add(.extensionIn, depth: 0) }
        let starts = recipe.flow.startNodes.filter { node($0) != nil }.reduce(into: [String]()) { list, id in
            if !list.contains(where: { recipeEquals($0, id) }) { list.append(node(id)?.id ?? id) }
        }
        if starts.count == 1 {
            lane(starts[0], from: nil, branch: nil, depth: 0, join: nil, stop: [])
        } else if starts.count > 1 {
            if let met = fork(from: nil, branch: nil, targets: starts, depth: 0, join: nil, stop: []) {
                lane(met, from: nil, branch: nil, depth: 0, join: nil, stop: [])
            }
        }
        let unreached = recipe.nodes.filter { !$0.id.isEmpty && !emitted.contains($0.id.lowercased()) }
        if !unreached.isEmpty {
            add(.notReached, depth: 0)
            for item in unreached where !emitted.contains(item.id.lowercased()) {
                lane(item.id, from: nil, branch: nil, depth: 1, join: nil, stop: [])
            }
        }
    }

    /// A sequence from `start` until it ends, reaches `join` (shown by the caller after the group), another stop of an
    /// outer group or a step shown before ("continues at").
    private mutating func lane(_ start: String, from: String?, branch: String?, depth: Int, join: String?, stop: Set<String>) {
        var current = start
        var previous = from
        var previousBranch = branch
        while true {
            if isExtension, recipeEquals(current, "Out"), node(current) == nil {
                if let previous { add(.extensionOut(from: previous, branch: previousBranch), depth: depth) }
                return
            }
            let key = current.lowercased()
            if let join, recipeEquals(join, current) { return }
            guard let item = node(current), !emitted.contains(key), !stop.contains(key) else {
                add(.continues(from: previous, branch: previousBranch, to: node(current)?.id ?? current), depth: depth)
                return
            }
            emitted.insert(key)
            add(.step(nodeId: item.id), depth: depth)
            var targets = unconditionalTargets(item.id)
            if RecipeOutline.isDecision(item) {
                let after = decision(item, depth: depth, join: join, stop: stop)
                if recipe.flow.conditionalTransitions.contains(where: { recipeEquals($0.from, item.id) }) {
                    // With conditional transitions the normal ones are never followed (the analyzer warns): shown, not walked.
                    for target in targets { add(.continues(from: item.id, branch: nil, to: target), depth: depth + 1) }
                    // The branches meet again: the step where they meet goes on at this level.
                    targets = after.map { [$0] } ?? []
                }
            }
            switch targets.count {
            case 0:
                return
            case 1:
                previous = item.id
                previousBranch = nil
                current = targets[0]
            default:
                guard let met = fork(from: item.id, branch: nil, targets: targets, depth: depth, join: join, stop: stop) else { return }
                previous = nil
                previousBranch = nil
                current = met
            }
        }
    }

    /// The parallel group of `targets` (of `from`'s branch `branch` when it decides); returns the step where its lanes
    /// meet (still to be shown), nil when they don't. `join`: where the enclosing lane ends (the caller shows it); lanes
    /// meeting there need no "continues at" row.
    @discardableResult
    private mutating func fork(from: String?, branch: String?, targets: [String], depth: Int, join: String?, stop: Set<String>) -> String? {
        let met = meetingPoint(of: targets)
        add(.parallel(from: from, branch: branch), depth: depth)
        var inner = stop
        if let met { inner.insert(met.lowercased()) }
        for (index, target) in targets.enumerated() {
            add(.lane(from: from, branch: branch, index: index, target: target), depth: depth + 1)
            if let met, recipeEquals(met, target) {
                add(.continues(from: from, branch: branch, to: met), depth: depth + 2)
                continue
            }
            lane(target, from: from, branch: branch, depth: depth + 2, join: met, stop: inner)
        }
        guard let met, !emitted.contains(met.lowercased()), !stop.contains(met.lowercased()) else {
            if let met, !recipeEquals(met, join ?? "") { add(.continues(from: nil, branch: nil, to: met), depth: depth) }
            return nil
        }
        return met
    }

    /// The branches of a decision step; returns the step where all branches meet (still to be shown), if any.
    private mutating func decision(_ item: RecipeNode, depth: Int, join outer: String?, stop: Set<String>) -> String? {
        let branches = RecipeOutline.branches(of: item, in: recipe.flow)
        let all = branches.flatMap { branchTargets(item.id, $0.key) }
        // A branch that leads nowhere ends the flow there: the branches don't all meet.
        let everyBranchGoesOn = branches.allSatisfy { !branchTargets(item.id, $0.key).isEmpty }
        let met = branches.count > 1 && everyBranchGoesOn ? meetingPoint(of: all) : nil
        var inner = stop
        if let met { inner.insert(met.lowercased()) }
        for branch in branches {
            add(.branch(from: item.id, key: branch.key, expression: branch.expression, label: branch.label), depth: depth + 1)
            let targets = branchTargets(item.id, branch.key)
            if targets.count > 1 {
                let inside = fork(from: item.id, branch: branch.key, targets: targets, depth: depth + 2, join: met ?? outer, stop: inner)
                if let inside, !recipeEquals(inside, met ?? "") {
                    lane(inside, from: nil, branch: nil, depth: depth + 2, join: met, stop: inner)
                }
            } else if let target = targets.first {
                if let met, recipeEquals(met, target) {
                    add(.continues(from: item.id, branch: branch.key, to: met), depth: depth + 2)
                } else {
                    lane(target, from: item.id, branch: branch.key, depth: depth + 2, join: met, stop: inner)
                }
            }
        }
        guard let met, !emitted.contains(met.lowercased()), !stop.contains(met.lowercased()) else {
            if let met, !recipeEquals(met, outer ?? "") { add(.continues(from: nil, branch: nil, to: met), depth: depth) }
            return nil
        }
        return met
    }
}
