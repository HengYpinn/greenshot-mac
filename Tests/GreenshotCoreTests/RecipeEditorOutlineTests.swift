// Greenshot for Mac (Community) - an unofficial macOS port of Greenshot
// Copyright (C) 2026 Greenshot for Mac (Community) contributors
// Based on Greenshot, Copyright (C) 2007-2026 Thomas Braun, Jens Klingen, Robin Krom
// SPDX-License-Identifier: GPL-3.0-or-later

import Foundation
import Testing
@testable import GreenshotCore

/// Recipes for the recipe editor's tests.
enum EditorFixtures {
    /// Nodes of the given step types ("id:Type"), transitions "a>b,c", conditional "d>key>e", start nodes.
    static func recipe(_ nodes: [String], _ transitions: [String] = [], conditional: [String] = [], start: [String]? = nil,
                       kind: RecipeKind = .recipe) -> CaptureRecipe {
        var recipe = CaptureRecipe(id: "editor_test", name: "Editor Test")
        recipe.kind = kind
        recipe.nodes = nodes.map { text in
            let parts = text.split(separator: ":").map(String.init)
            return RecipeNode(id: parts[0], stepType: parts.count > 1 ? parts[1] : "Effect")
        }
        recipe.flow.startNodes = start ?? (recipe.nodes.first.map { [$0.id] } ?? [])
        for text in transitions {
            let parts = text.split(separator: ">").map(String.init)
            for target in parts[1].split(separator: ",") { recipe.flow.addTransition(from: parts[0], to: String(target)) }
        }
        for text in conditional {
            let parts = text.split(separator: ">").map(String.init)
            recipe.flow.conditionalTransitions.append(ConditionalTransition(from: parts[0], branch: parts[1], to: parts[2]))
        }
        return recipe
    }

    /// Upstream docs Example 4: a Conditional on the capture size.
    static func conditional() -> CaptureRecipe {
        var recipe = recipe(["source:Source", "decide:Conditional", "large:Editor", "small:Clipboard", "notify:Notification"],
                            ["source>decide", "large>notify", "small>notify"],
                            conditional: ["decide>A>large", "decide>B>small"])
        recipe.nodes[1].parameters["Branches"] = .array([
            .object(["key": .string("A"), "expression": .string("${payload.width > 800}")]),
            .object(["key": .string("B"), "expression": .string("else")])
        ])
        return recipe
    }

    /// A compact text of the outline: "step a@0", "parallel select@0", "lane 0@1", "branch A@1", "continues x@2", …
    static func describe(_ outline: RecipeOutline) -> [String] {
        outline.rows.map { row in
            switch row.kind {
            case .step(let id): return "step \(id)@\(row.depth)"
            case .parallel(let from): return "parallel \(from ?? "start")@\(row.depth)"
            case .lane(_, let index, _): return "lane \(index)@\(row.depth)"
            case .branch(_, let key, _, _): return "branch \(key)@\(row.depth)"
            case .continues(_, _, let to): return "continues \(to)@\(row.depth)"
            case .notReached: return "notReached@\(row.depth)"
            case .extensionIn: return "in@\(row.depth)"
            case .extensionOut(let from, _): return "out \(from)@\(row.depth)"
            }
        }
    }
}

@Suite struct RecipeEditorOutlineTests {
    @Test func aChainIsAList() {
        let recipe = EditorFixtures.recipe(["a:Source", "b:Effect", "c:Clipboard"], ["a>b", "b>c"])
        #expect(EditorFixtures.describe(RecipeOutline(recipe)) == ["step a@0", "step b@0", "step c@0"])
    }

    /// Upstream docs Example 2 (fork at select_node, join at export_join).
    @Test func forkAndJoinOfTheWatermarkExample() throws {
        let recipe = try RecipeFixtures.recipe("dag_watermark_branching.gsrecipe.json")
        let rows = EditorFixtures.describe(RecipeOutline(recipe))
        #expect(rows == ["step capture_node@0", "step select_node@0", "parallel select_node@0", "lane 0@1", "step feedback_branch@2",
                         "lane 1@1", "step set_vars_node@2", "step watermark_node@2", "step export_join@0"])
    }

    @Test func branchesOfAConditionalAndWhereTheyMeet() {
        let rows = EditorFixtures.describe(RecipeOutline(EditorFixtures.conditional()))
        #expect(rows == ["step source@0", "step decide@0", "branch A@1", "step large@2", "branch B@1", "step small@2", "step notify@0"])
    }

    @Test func branchCarriesItsExpression() throws {
        let outline = RecipeOutline(EditorFixtures.conditional())
        let branch = try #require(outline.rows.first { if case .branch = $0.kind { return true } else { return false } })
        #expect(branch.kind == .branch(from: "decide", key: "A", expression: "${payload.width > 800}", label: nil))
    }

    @Test func userPromptChoicesAreBranches() {
        var recipe = EditorFixtures.recipe(["a:Source", "ask:UserPrompt", "yes:Editor"], ["a>ask"], conditional: ["ask>Yes>yes"])
        recipe.nodes[1].parameters["Choices"] = .array([.object(["Key": .string("Yes"), "Label": .string("Yes, Proceed")]),
                                                        .object(["Key": .string("No"), "Label": .string("No")])])
        let outline = RecipeOutline(recipe)
        #expect(EditorFixtures.describe(outline) == ["step a@0", "step ask@0", "branch Yes@1", "step yes@2", "branch No@1"])
        let labels = outline.rows.compactMap { row -> String? in
            if case .branch(_, _, _, let label) = row.kind { return label }
            return nil
        }
        #expect(labels == ["Yes, Proceed", "No"])
    }

    @Test func undeclaredBranchKeyIsShown() {
        let recipe = EditorFixtures.recipe(["d:Conditional", "x:Editor"], conditional: ["d>Z>x"])
        #expect(EditorFixtures.describe(RecipeOutline(recipe)) == ["step d@0", "branch Z@1", "step x@2"])
    }

    @Test func crossEdgeContinuesAtTheStepShownBefore() {
        // a forks to b and c; b goes to d, c to e; e also goes to d, so the lanes meet at d (both reach it).
        let recipe = EditorFixtures.recipe(["a:Source", "b", "c", "d:Clipboard", "e"], ["a>b,c", "b>d", "c>e", "e>d"])
        #expect(EditorFixtures.describe(RecipeOutline(recipe))
                == ["step a@0", "parallel a@0", "lane 0@1", "step b@2", "lane 1@1", "step c@2", "step e@2", "step d@0"])
        // Lanes that never meet: the second one points back at a shown step.
        let split = EditorFixtures.recipe(["a:Source", "b", "c", "x:Clipboard"], ["a>b,c", "b>x"])
        #expect(EditorFixtures.describe(RecipeOutline(split))
                == ["step a@0", "parallel a@0", "lane 0@1", "step b@2", "step x@2", "lane 1@1", "step c@2"])
        let cross = EditorFixtures.recipe(["a:Source", "b", "c", "x:Clipboard", "y"], ["a>b,c", "b>x", "c>y", "y>b"])
        let rows = EditorFixtures.describe(RecipeOutline(cross))
        #expect(rows.contains("continues b@0") || rows.contains("continues b@2"))
    }

    @Test func severalStartStepsAreAParallelStart() {
        let recipe = EditorFixtures.recipe(["a:Source", "b:Source", "c:Clipboard"], ["a>c", "b>c"], start: ["a", "b"])
        #expect(EditorFixtures.describe(RecipeOutline(recipe))
                == ["parallel start@0", "lane 0@1", "step a@2", "lane 1@1", "step b@2", "step c@0"])
    }

    @Test func unreachedStepsComeLast() {
        let recipe = EditorFixtures.recipe(["a:Source", "b:Clipboard", "lost", "lost2"], ["a>b", "lost>lost2"])
        #expect(EditorFixtures.describe(RecipeOutline(recipe))
                == ["step a@0", "step b@0", "notReached@0", "step lost@1", "step lost2@1"])
    }

    @Test func missingTargetContinues() {
        let recipe = EditorFixtures.recipe(["a:Source"], ["a>ghost"])
        #expect(EditorFixtures.describe(RecipeOutline(recipe)) == ["step a@0", "continues ghost@0"])
    }

    @Test func aLoopEnds() {
        let recipe = EditorFixtures.recipe(["a:Source", "b", "c"], ["a>b", "b>c", "c>a"])
        let outline = RecipeOutline(recipe)
        #expect(EditorFixtures.describe(outline) == ["step a@0", "step b@0", "step c@0", "continues a@0"])
    }

    @Test func automaticStepBetweenInAndOut() {
        let ext = RecipeEditorCatalog.newExtension()
        #expect(EditorFixtures.describe(RecipeOutline(ext)) == ["in@0", "step border@0", "out border@0"])
    }

    @Test func outlineIsDeterministicAndRowIdsAreUnique() throws {
        let recipe = try RecipeFixtures.recipe("dag_watermark_branching.gsrecipe.json")
        let first = RecipeOutline(recipe).rows
        let second = RecipeOutline(recipe).rows
        #expect(first == second)
        #expect(Set(first.map(\.id)).count == first.count)
    }

    @Test func everyExampleShowsEveryStepOnce() throws {
        for name in RecipeFixtures.exampleNames {
            let recipe = try RecipeFixtures.recipe(name)
            let order = RecipeOutline(recipe).stepOrder
            #expect(order.count == recipe.nodes.count, "\(name)")
            #expect(Set(order.map { $0.lowercased() }).count == order.count, "\(name)")
        }
    }
}
