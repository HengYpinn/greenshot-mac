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
            case .parallel(let from, let branch): return "parallel \(from ?? "start")\(branch.map { "/" + $0 } ?? "")@\(row.depth)"
            case .lane(_, _, let index, _): return "lane \(index)@\(row.depth)"
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
    /// A crafted file with thousands of next steps of one step and thousands of branches of a decision opens in the
    /// editor: every branch and lane is a row.
    @Test func thousandsOfNextStepsAndBranches() async {
        var recipe = EditorFixtures.recipe(["a:Source", "decide:Conditional", "end:Clipboard"], ["a>decide"])
        recipe.flow.transitions.append(RecipeTransition(from: "end", to: (0..<20_000).map { "x\($0)" }))
        recipe.flow.conditionalTransitions = (0..<20_000).map { ConditionalTransition(from: "decide", branch: "b\($0)", to: "end") }
        let crafted = recipe
        let rows = await Task.detached { RecipeOutline(crafted).rows }.value
        var branches = 0
        var lanes = 0
        for row in rows {
            if case .branch = row.kind { branches += 1 }
            if case .lane = row.kind { lanes += 1 }
        }
        #expect(branches == 20_000)
        #expect(lanes == 20_000)
        #expect(rows.compactMap(\.nodeId) == ["a", "decide", "end"])
    }

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

    /// The step after a decision is where every path meets, not merely a step every branch can reach.
    @Test func nestedDecisionsMeetWhereEveryPathMeets() {
        let recipe = EditorFixtures.recipe(["source:Source", "decide:Conditional", "confirm:UserPrompt", "large:Editor", "small:Clipboard",
                                            "notify:Notification"], ["source>decide", "large>notify", "small>notify"],
                                           conditional: ["decide>A>confirm", "decide>B>small", "confirm>Yes>large", "confirm>No>small"])
        #expect(EditorFixtures.describe(RecipeOutline(recipe))
                == ["step source@0", "step decide@0", "branch A@1", "step confirm@2", "branch Yes@3", "step large@4", "branch No@3",
                    "step small@4", "branch B@1", "continues small@2", "step notify@0"])
    }

    @Test func aBranchThatEndsMeansNoMeetingPoint() {
        let recipe = EditorFixtures.recipe(["d:Conditional", "x:Editor", "y:Clipboard", "z:Notification"], ["x>z", "y>z"],
                                           conditional: ["d>A>x", "d>B>y", "d>C>x"])
        var withEmpty = recipe
        withEmpty.nodes[0].parameters["Branches"] = .array([.object(["key": .string("A")]), .object(["key": .string("B")]),
                                                            .object(["key": .string("C")]), .object(["key": .string("D")])])
        let rows = EditorFixtures.describe(RecipeOutline(withEmpty))
        #expect(rows.last == "branch D@1")
        #expect(rows.contains("step z@2"))
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

    /// A parallel group inside a decision's branch knows the branch, so its Add Lane, Insert and Delete Connection act on
    /// the branch's transitions (they wrote or removed plain transitions from the decision, which the engine never
    /// follows, and an inserted step was not reached).
    @Test func lanesOfABranchKnowTheirBranch() {
        var recipe = EditorFixtures.recipe(["source:Source", "decide:Conditional", "large:Editor", "extra:Effect", "small:Clipboard",
                                            "notify:Notification"], ["source>decide", "large>notify", "extra>notify", "small>notify"],
                                           conditional: ["decide>A>large", "decide>A>extra", "decide>B>small"])
        let outline = RecipeOutline(recipe)
        #expect(EditorFixtures.describe(outline).contains("parallel decide/A@2"))
        let lane = outline.rows.first { if case .lane(_, _, 1, _) = $0.kind { return true } else { return false } }
        #expect(lane?.kind == .lane(from: "decide", branch: "A", index: 1, target: "extra"))
        // The lane's Insert and the group's Add Lane.
        RecipeFlowEditor.insert(RecipeNode(id: "n", stepType: "Effect"), between: "decide", and: "extra", branch: "A", in: &recipe)
        RecipeFlowEditor.addParallel(RecipeNode(id: "p", stepType: "Effect"), from: "decide", branch: "A", in: &recipe)
        #expect(recipe.flow.targets(from: "decide").isEmpty)
        let branchA: [String] = recipe.flow.conditionalTransitions.filter { $0.branch == "A" }.map(\.to)
        #expect(branchA == ["large", "n", "p"])
        #expect(!EditorFixtures.describe(RecipeOutline(recipe)).contains("notReached@0"))
        // A lane that is where the others meet.
        let meeting = EditorFixtures.recipe(["decide:Conditional", "large:Editor", "notify:Notification"], ["large>notify"],
                                            conditional: ["decide>A>large", "decide>A>notify"])
        let continues = RecipeOutline(meeting).rows.first { if case .continues = $0.kind { return true } else { return false } }
        #expect(continues?.kind == .continues(from: "decide", branch: "A", to: "notify"))
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

    /// A recipe of one step needs no start steps (RecipeValidator): the step is where it starts, not "Not reached".
    @Test func theOnlyStepIsTheStart() {
        let single = EditorFixtures.recipe(["a:Source"], start: [])
        #expect(RecipeValidator().validate(single).errors.isEmpty)
        #expect(EditorFixtures.describe(RecipeOutline(single)) == ["step a@0"])
        #expect(RecipeOutline.startSteps(of: single) == ["a"])
        // With more steps the start steps must be named.
        let two = EditorFixtures.recipe(["a:Source", "b"], ["a>b"], start: [])
        #expect(RecipeOutline.startSteps(of: two).isEmpty)
        #expect(EditorFixtures.describe(RecipeOutline(two)).first == "notReached@0")
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

    /// A row other than a step is named by what it shows, so a selection kept over an edit or an undo is the same
    /// connection or none (a running number named it: after an undo it could be another connection, and Delete removed
    /// that one).
    @Test func rowIdsFollowWhatTheRowShows() throws {
        let before = RecipeOutline(EditorFixtures.recipe(["a:Source"], ["a>g1,g2,g3"]))
        let after = RecipeOutline(EditorFixtures.recipe(["a:Source"], ["a>g2,g3"]))
        let selected = try #require(before.rows.first { $0.kind == .continues(from: "a", branch: nil, to: "g2") })
        let kept = try #require(after.rows.first { $0.id == selected.id })
        #expect(kept.kind == selected.kind)
        let removed = try #require(before.rows.first { $0.kind == .continues(from: "a", branch: nil, to: "g1") })
        #expect(!after.rows.contains { $0.id == removed.id })
        for name in RecipeFixtures.exampleNames {
            let rows = RecipeOutline(try RecipeFixtures.recipe(name)).rows
            #expect(Set(rows.map(\.id)).count == rows.count, "\(name)")
        }
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
