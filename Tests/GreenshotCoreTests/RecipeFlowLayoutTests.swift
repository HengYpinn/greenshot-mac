// Greenshot for Mac (Community) - an unofficial macOS port of Greenshot
// Copyright (C) 2026 Greenshot for Mac (Community) contributors
// Based on Greenshot, Copyright (C) 2007-2026 Thomas Braun, Jens Klingen, Robin Krom
// SPDX-License-Identifier: GPL-3.0-or-later

import CoreGraphics
import Foundation
import Testing
@testable import GreenshotCore

@Suite struct RecipeFlowLayoutTests {
    private let box = CGSize(width: 120, height: 40)

    @Test func edgesGoDownAndNodesDontOverlap() throws {
        var recipe = try RecipeFixtures.recipe("dag_watermark_branching.gsrecipe.json")
        recipe.flow.errorTransitions = [ErrorTransition(from: "*", to: "export_join")]
        let graph = RecipeFlowGraph(recipe)
        let layout = RecipeFlowLayout(graph) { _ in box }
        #expect(layout.frames.count == graph.nodes.count)
        for edge in graph.edges {
            let from = try #require(layout.frames[edge.from])
            let to = try #require(layout.frames[edge.to])
            #expect(to.minY > from.minY, "\(edge.from) -> \(edge.to)")
        }
        let frames = Array(layout.frames.values)
        for i in frames.indices {
            for j in frames.indices where j > i {
                #expect(!frames[i].intersects(frames[j]))
            }
        }
        #expect(layout.size.width >= frames.map(\.maxX).max() ?? 0)
    }

    @Test func startAndTriggersAreAtTheTop() throws {
        let recipe = try RecipeFixtures.recipe("dag_watermark_branching.gsrecipe.json")
        let layout = RecipeFlowLayout(RecipeFlowGraph(recipe)) { _ in box }
        #expect(layout.levels.first == recipe.triggers.indices.map { "trigger_\($0)" })
        #expect(layout.levels[1] == ["capture_node"])
        let feedback = try #require(layout.frames["feedback_branch"])
        let setVars = try #require(layout.frames["set_vars_node"])
        #expect(feedback.minY == setVars.minY)
    }

    @Test func barycenterUncrossesLanes() {
        // a -> (b, c); c -> d; b -> e: with c listed first under b's child, the order follows the parents.
        let recipe = EditorFixtures.recipe(["a:Source", "b", "c", "e", "d"], ["a>b,c", "c>d", "b>e"])
        let graph = RecipeFlowGraph(recipe)
        let layout = RecipeFlowLayout(graph) { _ in box }
        #expect(layout.crossings(graph) == 0)
        #expect(layout.levels[2] == ["e", "d"])
    }

    @Test func loopsAreLeftOut() {
        let recipe = EditorFixtures.recipe(["a:Source", "b", "c"], ["a>b", "b>c", "c>a"])
        let layout = RecipeFlowLayout(RecipeFlowGraph(recipe)) { _ in box }
        #expect(layout.backEdges.count == 1)
        #expect(layout.levels.map(\.count) == [1, 1, 1])
        let path = layout.path(of: RecipeFlowGraph.Edge(from: "c", to: "a", label: nil, style: .normal))
        #expect(path.count == 4)
    }

    @Test func deterministicAndEmpty() throws {
        let recipe = try RecipeFixtures.recipe("dag_watermark_branching.gsrecipe.json")
        let first = RecipeFlowLayout(RecipeFlowGraph(recipe)) { _ in box }
        let second = RecipeFlowLayout(RecipeFlowGraph(recipe)) { _ in box }
        #expect(first.frames == second.frames)
        let empty = RecipeFlowLayout(RecipeFlowGraph(CaptureRecipe(id: "e", name: "E"))) { _ in box }
        #expect(empty.frames.isEmpty)
        #expect(empty.size == .zero)
    }
}
