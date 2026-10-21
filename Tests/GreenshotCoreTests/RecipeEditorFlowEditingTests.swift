// Greenshot for Mac (Community) - an unofficial macOS port of Greenshot
// Copyright (C) 2026 Greenshot for Mac (Community) contributors
// Based on Greenshot, Copyright (C) 2007-2026 Thomas Braun, Jens Klingen, Robin Krom
// SPDX-License-Identifier: GPL-3.0-or-later

import Foundation
import Testing
@testable import GreenshotCore

@Suite struct RecipeEditorFlowEditingTests {
    private func targets(_ recipe: CaptureRecipe, _ id: String) -> [String] { recipe.flow.targets(from: id) }

    @Test func insertAfterTakesOverTheNextSteps() {
        var recipe = EditorFixtures.recipe(["a:Source", "b:Clipboard"], ["a>b"])
        RecipeFlowEditor.insert(RecipeNode(id: "n", stepType: "Effect"), after: "a", in: &recipe)
        #expect(targets(recipe, "a") == ["n"])
        #expect(targets(recipe, "n") == ["b"])
        #expect(recipe.nodes.map(\.id) == ["a", "n", "b"])
    }

    @Test func insertedDecisionLeadsEveryBranchToTheNextStep() {
        var recipe = EditorFixtures.recipe(["a:Source", "b:Clipboard"], ["a>b"])
        let decision = RecipeEditorCatalog.newNode(WellKnownStepType.conditional, in: recipe)
        RecipeFlowEditor.insert(decision, after: "a", in: &recipe)
        let branches = recipe.flow.conditionalTransitions.filter { $0.from == decision.id }
        #expect(branches.map(\.branch) == ["A", "B"])
        #expect(branches.allSatisfy { $0.to == "b" })
        #expect(targets(recipe, decision.id).isEmpty)
        #expect(RecipeValidator().validate(recipe).errors.isEmpty)
    }

    @Test func insertBetweenPutsTheStepOnTheArrow() {
        var recipe = EditorFixtures.recipe(["a:Source", "b", "c:Clipboard"], ["a>b,c"])
        RecipeFlowEditor.insert(RecipeNode(id: "n", stepType: "Effect"), between: "a", and: "c", branch: nil, in: &recipe)
        #expect(targets(recipe, "a") == ["b", "n"])
        #expect(targets(recipe, "n") == ["c"])
        // Before a start step.
        RecipeFlowEditor.insert(RecipeNode(id: "s", stepType: "Effect"), between: nil, and: "a", branch: nil, in: &recipe)
        #expect(recipe.flow.startNodes == ["s"])
        #expect(targets(recipe, "s") == ["a"])
    }

    @Test func insertIntoBranch() {
        var recipe = EditorFixtures.conditional()
        RecipeFlowEditor.insert(RecipeNode(id: "n", stepType: "Effect"), intoBranch: "A", of: "decide", in: &recipe)
        let branchA = recipe.flow.conditionalTransitions.filter { $0.branch == "A" }
        #expect(branchA.map(\.to) == ["n"])
        #expect(targets(recipe, "n") == ["large"])
        // An empty branch gets its first step.
        RecipeFlowEditor.insert(RecipeNode(id: "m", stepType: "Effect"), intoBranch: "C", of: "decide", in: &recipe)
        #expect(recipe.flow.conditionalTransitions.contains(ConditionalTransition(from: "decide", branch: "C", to: "m")))
        #expect(targets(recipe, "m").isEmpty)
    }

    /// After a decision a step goes into its first branch, like Add Step: a decision with conditional transitions is
    /// left only through them, so a plain transition to the new step was never followed.
    @Test func insertAfterADecisionGoesIntoItsFirstBranch() {
        var recipe = EditorFixtures.conditional()
        RecipeFlowEditor.insert(RecipeNode(id: "n", stepType: "Effect"), after: "decide", in: &recipe)
        #expect(targets(recipe, "decide").isEmpty)
        #expect(recipe.flow.conditionalTransitions.contains(ConditionalTransition(from: "decide", branch: "A", to: "n")))
        #expect(targets(recipe, "n") == ["large"])
        #expect(!recipe.flow.conditionalTransitions.contains(ConditionalTransition(from: "decide", branch: "A", to: "large")))
        // Another lane from a decision is another step of its first branch.
        RecipeFlowEditor.addParallel(RecipeNode(id: "p", stepType: "Effect"), from: "decide", in: &recipe)
        #expect(targets(recipe, "decide").isEmpty)
        #expect(recipe.flow.conditionalTransitions.contains(ConditionalTransition(from: "decide", branch: "A", to: "p")))
        let analysis = RecipeContractAnalyzer.analyze(recipe)
        #expect(!analysis.warnings.contains { $0.contains("never followed") })
    }

    /// The only step of a recipe without start steps is its start; a step added to it writes that down, since two steps
    /// need named start steps (the recipe became invalid and both steps "Not reached").
    @Test func addingToTheOnlyStepKeepsItTheStart() {
        var after = EditorFixtures.recipe(["a:Source"], start: [])
        RecipeFlowEditor.insert(RecipeNode(id: "n", stepType: "Effect"), after: "a", in: &after)
        #expect(after.flow.startNodes == ["a"])
        #expect(RecipeValidator().validate(after).errors.isEmpty)
        var appended = EditorFixtures.recipe(["a:Source"], start: [])
        RecipeFlowEditor.append(RecipeNode(id: "n", stepType: "Effect"), in: &appended)
        #expect(appended.flow.startNodes == ["a"])
        var parallel = EditorFixtures.recipe(["a:Source"], start: [])
        RecipeFlowEditor.addParallel(RecipeNode(id: "p", stepType: "Source"), from: nil, in: &parallel)
        #expect(parallel.flow.startNodes == ["a", "p"])
        var before = EditorFixtures.recipe(["a:Source"], start: [])
        RecipeFlowEditor.insert(RecipeNode(id: "s", stepType: "Source"), between: nil, and: "a", branch: nil, in: &before)
        #expect(before.flow.startNodes == ["s"])
        #expect(RecipeValidator().validate(before).errors.isEmpty)
    }

    @Test func appendGoesAfterTheLastStepAndStartsAnEmptyRecipe() {
        var empty = CaptureRecipe(id: "e", name: "E")
        RecipeFlowEditor.append(RecipeNode(id: "first", stepType: "Source"), in: &empty)
        #expect(empty.flow.startNodes == ["first"])
        var recipe = EditorFixtures.recipe(["a:Source", "b:Clipboard"], ["a>b"])
        RecipeFlowEditor.append(RecipeNode(id: "n", stepType: "Notification"), in: &recipe)
        #expect(targets(recipe, "b") == ["n"])
    }

    @Test func addParallelLane() {
        var recipe = EditorFixtures.recipe(["a:Source", "b:Clipboard"], ["a>b"])
        RecipeFlowEditor.addParallel(RecipeNode(id: "p", stepType: "Editor"), from: "a", in: &recipe)
        #expect(targets(recipe, "a") == ["b", "p"])
        RecipeFlowEditor.addParallel(RecipeNode(id: "q", stepType: "Source"), from: nil, in: &recipe)
        #expect(recipe.flow.startNodes == ["a", "q"])
    }

    @Test func deleteJoinsTheNeighbours() {
        var recipe = EditorFixtures.recipe(["a:Source", "b", "c:Clipboard"], ["a>b", "b>c"])
        recipe.nodes[2].onErrorNodeId = "b"
        recipe.flow.errorTransitions = [ErrorTransition(from: "b", to: "c"), ErrorTransition(from: "*", to: "b"), ErrorTransition(from: "*", to: "c")]
        #expect(RecipeFlowEditor.delete("b", in: &recipe))
        #expect(targets(recipe, "a") == ["c"])
        #expect(recipe.nodes.map(\.id) == ["a", "c"])
        #expect(recipe.nodes[1].onErrorNodeId == nil)
        #expect(recipe.flow.errorTransitions == [ErrorTransition(from: "*", to: "c")])
        // A start step's place goes to its next steps.
        #expect(RecipeFlowEditor.delete("a", in: &recipe))
        #expect(recipe.flow.startNodes == ["c"])
        #expect(!RecipeFlowEditor.delete("ghost", in: &recipe))
    }

    @Test func deleteInsideABranch() {
        var recipe = EditorFixtures.conditional()
        #expect(RecipeFlowEditor.delete("large", in: &recipe))
        #expect(recipe.flow.conditionalTransitions.contains(ConditionalTransition(from: "decide", branch: "A", to: "notify")))
        // Deleting the decision drops its branches.
        #expect(RecipeFlowEditor.delete("decide", in: &recipe))
        #expect(recipe.flow.conditionalTransitions.isEmpty)
        #expect(targets(recipe, "source").isEmpty)
    }

    @Test func renameUpdatesEveryReference() throws {
        var recipe = EditorFixtures.conditional()
        recipe.nodes[2].onErrorNodeId = "decide"
        recipe.flow.errorTransitions = [ErrorTransition(from: "decide", to: "small")]
        try RecipeFlowEditor.rename("decide", to: "choose", in: &recipe)
        #expect(recipe.node("choose") != nil)
        #expect(targets(recipe, "source") == ["choose"])
        #expect(recipe.flow.conditionalTransitions.allSatisfy { $0.from == "choose" })
        #expect(recipe.flow.errorTransitions[0].from == "choose")
        #expect(recipe.nodes[2].onErrorNodeId == "choose")
        try RecipeFlowEditor.rename("source", to: "capture", in: &recipe)
        #expect(recipe.flow.startNodes == ["capture"])
    }

    @Test func renameRefusals() {
        var recipe = EditorFixtures.recipe(["a:Source", "b:Clipboard"], ["a>b"])
        #expect(throws: RecipeRenameError.duplicate("B")) { try RecipeFlowEditor.rename("a", to: "B", in: &recipe) }
        #expect(throws: RecipeRenameError.empty) { try RecipeFlowEditor.rename("a", to: "  ", in: &recipe) }
        var ext = RecipeEditorCatalog.newExtension()
        #expect(throws: RecipeRenameError.reserved("Out")) { try RecipeFlowEditor.rename("border", to: "Out", in: &ext) }
    }

    @Test func toggleStart() {
        var recipe = EditorFixtures.recipe(["a:Source", "b:Source"], [])
        RecipeFlowEditor.toggleStart("b", in: &recipe)
        #expect(recipe.flow.startNodes == ["a", "b"])
        RecipeFlowEditor.toggleStart("a", in: &recipe)
        #expect(recipe.flow.startNodes == ["b"])
    }

    @Test func connectRefusesLoops() {
        var recipe = EditorFixtures.recipe(["a:Source", "b", "c"], ["a>b", "b>c"])
        #expect(!RecipeFlowEditor.canConnect(from: "c", to: "a", in: recipe))
        #expect(!RecipeFlowEditor.canConnect(from: "b", to: "b", in: recipe))
        #expect(RecipeFlowEditor.canConnect(from: "a", to: "c", in: recipe))
        #expect(RecipeFlowEditor.connectableTargets(from: "b", in: recipe) == ["c"])
        #expect(!RecipeFlowEditor.connect(from: "c", to: "a", branch: nil, in: &recipe))
        #expect(RecipeFlowEditor.retarget(from: "a", branch: nil, old: "b", new: "c", in: &recipe))
        #expect(targets(recipe, "a") == ["c"])
        // A loop is refused and changes nothing.
        #expect(!RecipeFlowEditor.retarget(from: "a", branch: nil, old: "c", new: "a", in: &recipe))
        #expect(targets(recipe, "a") == ["c"])
        RecipeFlowEditor.disconnect(from: "b", to: "c", branch: nil, in: &recipe)
        #expect(targets(recipe, "b").isEmpty)
    }

    @Test func moveUpAndDownInASequence() {
        var recipe = EditorFixtures.recipe(["a:Source", "b", "c", "d:Clipboard"], ["a>b", "b>c", "c>d"])
        #expect(RecipeFlowEditor.moveUp("c", in: &recipe))
        #expect(RecipeOutline(recipe).stepOrder == ["a", "c", "b", "d"])
        #expect(RecipeFlowEditor.moveDown("c", in: &recipe))
        #expect(RecipeOutline(recipe).stepOrder == ["a", "b", "c", "d"])
        // The start step can't move up; the step after it can, and becomes the start step.
        #expect(!RecipeFlowEditor.moveUp("a", in: &recipe))
        #expect(RecipeFlowEditor.moveUp("b", in: &recipe))
        #expect(RecipeOutline(recipe).stepOrder == ["b", "a", "c", "d"])
        #expect(recipe.flow.startNodes == ["b"])
        // A step after a fork can't move.
        var fork = EditorFixtures.recipe(["a:Source", "b", "c"], ["a>b,c"])
        #expect(!RecipeFlowEditor.moveUp("b", in: &fork))
    }

    @Test func newIdsAreUniqueAndReadable() {
        var recipe = CaptureRecipe(id: "r", name: "R")
        for _ in 0..<20 {
            let id = RecipeFlowEditor.newNodeId(for: "Effect", in: recipe)
            #expect(id.hasPrefix("effect_"))
            #expect(id.count == 11)
            recipe.nodes.append(RecipeNode(id: id, stepType: "Effect"))
        }
        #expect(Set(recipe.nodes.map(\.id)).count == 20)
    }

    @Test func unknownMembersSurviveEditsAndSaving() throws {
        var recipe = try RecipeFixtures.recipe("dag_watermark_branching.gsrecipe.json")
        recipe.extra["x-editor"] = .string("kept")
        recipe.nodes[0].extra["x-node"] = .number(1)
        recipe.flow.extra["x-flow"] = .bool(true)
        RecipeFlowEditor.insert(RecipeNode(id: "n", stepType: "Effect"), after: "capture_node", in: &recipe)
        try RecipeFlowEditor.rename("n", to: "border", in: &recipe)
        let decoded = try #require(try RecipeSerializer.decode(text: RecipeSerializer.encode(recipe)).first)
        #expect(decoded.extra["x-editor"] == .string("kept"))
        #expect(decoded.nodes[0].extra["x-node"] == .number(1))
        #expect(decoded.flow.extra["x-flow"] == .bool(true))
    }
}
