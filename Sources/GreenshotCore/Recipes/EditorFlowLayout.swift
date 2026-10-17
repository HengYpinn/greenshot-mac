// Greenshot for Mac (Community) - an unofficial macOS port of Greenshot
// Copyright (C) 2026 Greenshot for Mac (Community) contributors
// Based on Greenshot, Copyright (C) 2007-2026 Thomas Braun, Jens Klingen, Robin Krom
// SPDX-License-Identifier: GPL-3.0-or-later

import CoreGraphics
import Foundation

/// Where the Flow view draws each node of a `RecipeFlowGraph`: a layered layout like upstream's
/// Layout/DagAutoLayout.cs (roots first, each node one level below its lowest parent, siblings side by side), plus a
/// barycenter pass that orders each level by the positions of the parents, so branches cross less. Edges that go back
/// (a loop in an invalid recipe) are left out of the levels.
public struct RecipeFlowLayout: Sendable {
    /// Upstream `LevelYGap` and `SiblingXGap` are distances between node origins; these are the gaps between nodes.
    public static let levelGap: CGFloat = 56
    public static let siblingGap: CGFloat = 36
    public static let margin: CGFloat = 24

    /// Each node's box, by graph id.
    public private(set) var frames: [String: CGRect] = [:]
    /// Each node's level and position in it.
    public private(set) var levels: [[String]] = []
    public private(set) var size: CGSize = .zero
    /// The edges that go against the levels (loops), drawn but not laid out.
    public private(set) var backEdges: [RecipeFlowGraph.Edge] = []

    public init(_ graph: RecipeFlowGraph, size: (RecipeFlowGraph.Node) -> CGSize) {
        let ids = graph.nodes.map(\.id)
        guard !ids.isEmpty else { return }
        var children: [String: [String]] = [:]
        var parents: [String: [String]] = [:]
        for edge in graph.edges where edge.from != edge.to && ids.contains(edge.from) && ids.contains(edge.to) {
            children[edge.from, default: []].append(edge.to)
        }
        // Back edges by a depth-first walk from the roots (nodes without parents first, in graph order).
        var hasParent = Set<String>()
        for targets in children.values { hasParent.formUnion(targets) }
        let roots = ids.filter { !hasParent.contains($0) } + ids.filter { hasParent.contains($0) }
        var state: [String: Int] = [:]
        var back = Set<String>()
        func visit(_ id: String) {
            state[id] = 1
            for child in children[id] ?? [] {
                switch state[child] ?? 0 {
                case 0: visit(child)
                case 1: back.insert("\(id)>\(child)")
                default: break
                }
            }
            state[id] = 2
        }
        for root in roots where state[root] == nil { visit(root) }
        backEdges = graph.edges.filter { back.contains("\($0.from)>\($0.to)") }
        for (from, targets) in children {
            for target in targets where !back.contains("\(from)>\(target)") { parents[target, default: []].append(from) }
        }
        // Longest-path levels in a topological order.
        var level: [String: Int] = [:]
        var remaining: [String: Int] = [:]
        for id in ids { remaining[id] = Set(parents[id] ?? []).count }
        var queue = ids.filter { remaining[$0] == 0 }
        var visited = Set<String>()
        while !queue.isEmpty {
            let id = queue.removeFirst()
            guard visited.insert(id).inserted else { continue }
            let mine = (parents[id] ?? []).compactMap { level[$0] }.max().map { $0 + 1 } ?? 0
            level[id] = mine
            for child in Set(children[id] ?? []) where !back.contains("\(id)>\(child)") {
                remaining[child, default: 0] -= 1
                if remaining[child] == 0 { queue.append(child) }
            }
        }
        for id in ids where level[id] == nil { level[id] = 0 }
        let depth = (level.values.max() ?? 0) + 1
        var rows = Array(repeating: [String](), count: depth)
        for id in ids { rows[level[id] ?? 0].append(id) }
        // Barycenter ordering, top to bottom, twice.
        for _ in 0..<2 {
            for index in rows.indices.dropFirst() {
                let above = rows[index - 1]
                let position = Dictionary(uniqueKeysWithValues: above.enumerated().map { ($1, Double($0)) })
                let current = rows[index]
                let keyed = current.enumerated().map { offset, id -> (id: String, key: Double, offset: Int) in
                    let positions = (parents[id] ?? []).compactMap { position[$0] }
                    let key = positions.isEmpty ? Double(offset) : positions.reduce(0, +) / Double(positions.count)
                    return (id, key, offset)
                }
                rows[index] = keyed.sorted { ($0.key, $0.offset) < ($1.key, $1.offset) }.map(\.id)
            }
        }
        levels = rows
        // Coordinates: levels centered on the widest one.
        let nodesById = Dictionary(graph.nodes.map { ($0.id, $0) }, uniquingKeysWith: { first, _ in first })
        var sizes: [String: CGSize] = [:]
        for id in ids { if let node = nodesById[id] { sizes[id] = size(node) } }
        let widths = rows.map { row -> CGFloat in
            let total = row.reduce(CGFloat(0)) { $0 + (sizes[$1]?.width ?? 0) }
            return total + CGFloat(max(row.count - 1, 0)) * Self.siblingGap
        }
        let widest = widths.max() ?? 0
        var y = Self.margin
        for (index, row) in rows.enumerated() {
            let height = row.map { sizes[$0]?.height ?? 0 }.max() ?? 0
            var x = Self.margin + (widest - widths[index]) / 2
            for id in row {
                let box = sizes[id] ?? .zero
                frames[id] = CGRect(x: x, y: y + (height - box.height) / 2, width: box.width, height: box.height)
                x += box.width + Self.siblingGap
            }
            y += height + Self.levelGap
        }
        self.size = CGSize(width: widest + Self.margin * 2, height: y - Self.levelGap + Self.margin)
    }

    /// Where an edge is drawn: from the bottom middle of its source to the top middle of its target, or side to side
    /// for nodes on one level and for loops.
    public func path(of edge: RecipeFlowGraph.Edge) -> [CGPoint] {
        guard let from = frames[edge.from], let to = frames[edge.to] else { return [] }
        if to.minY >= from.maxY {
            let start = CGPoint(x: from.midX, y: from.maxY)
            let end = CGPoint(x: to.midX, y: to.minY)
            let middle = (start.y + end.y) / 2
            return [start, CGPoint(x: start.x, y: middle), CGPoint(x: end.x, y: middle), end]
        }
        // Same level or upwards: around the right side.
        let right = max(from.maxX, to.maxX) + Self.siblingGap / 2
        return [CGPoint(x: from.maxX, y: from.midY), CGPoint(x: right, y: from.midY), CGPoint(x: right, y: to.midY),
                CGPoint(x: to.maxX, y: to.midY)]
    }

    /// The number of crossings between consecutive levels (for tests).
    public func crossings(_ graph: RecipeFlowGraph) -> Int {
        var position: [String: (level: Int, index: Int)] = [:]
        for (levelIndex, row) in levels.enumerated() {
            for (index, id) in row.enumerated() { position[id] = (levelIndex, index) }
        }
        let spans = graph.edges.compactMap { edge -> (Int, Int, Int)? in
            guard let a = position[edge.from], let b = position[edge.to], b.level == a.level + 1 else { return nil }
            return (a.level, a.index, b.index)
        }
        var count = 0
        for i in spans.indices {
            for j in spans.indices where j > i && spans[i].0 == spans[j].0 {
                let first = spans[i]
                let second = spans[j]
                if (first.1 - second.1) * (first.2 - second.2) < 0 { count += 1 }
            }
        }
        return count
    }
}
