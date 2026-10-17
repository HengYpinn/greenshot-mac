// Greenshot for Mac (Community) - an unofficial macOS port of Greenshot
// Copyright (C) 2026 Greenshot for Mac (Community) contributors
// Based on Greenshot, Copyright (C) 2007-2026 Thomas Braun, Jens Klingen, Robin Krom
// SPDX-License-Identifier: GPL-3.0-or-later

import CoreGraphics
import Foundation
import Testing
@testable import GreenshotCore

/// Upstream `UserPromptStep` + `RecipeUserPromptWindow` and `DynamicDestinationStep` + `DynamicDestinationWindow`.
@Suite struct RecipeStepsInteractionTests {
    func step(_ type: String, _ parameters: JSONObject = [:], id: String = "ask") -> RecipeStepInvocation {
        RecipeStepInvocation(node: RecipeNode(id: id, stepType: type, parameters: parameters), parameters: parameters,
                             contract: StepContractCatalog.builtIn.contract(for: type))
    }

    func choice(_ key: String, label: String? = nil, style: String? = nil, isDefault: Bool = false, isCancel: Bool = false) -> JSONValue {
        var object: JSONObject = ["Key": .string(key)]
        if let label { object["Label"] = .string(label) }
        if let style { object["style"] = .string(style) }
        if isDefault { object["IsDefault"] = .bool(true) }
        if isCancel { object["isCancel"] = .bool(true) }
        return .object(object)
    }

    // MARK: UserPrompt

    @Test func choicesAsUpstreamParsesThem() {
        let parsed = RecipePrompt.choices(.array([choice("upload", label: "Upload", isDefault: true), choice("delete", style: "Danger"),
                                                  choice("keep", style: "secondary", isCancel: true), .string("ignored"),
                                                  .object(["Label": .string("no key")])]))
        #expect(parsed.map(\.key) == ["upload", "delete", "keep"])
        #expect(parsed[0].label == "Upload")
        #expect(parsed[0].style == .primary)
        #expect(parsed[1].label == "delete")
        #expect(parsed[1].style == .danger)
        #expect(parsed[2].style == .secondary)
        #expect(parsed[0].isDefault)
        #expect(parsed[2].isCancel)
    }

    @Test func defaultsWithoutChoices() {
        let prompt = RecipePrompt(step("UserPrompt", ["Choices": .array([])]))
        #expect(prompt.choices.map(\.key) == ["Yes", "No"])
        #expect(prompt.defaultKey == "Yes")
        #expect(prompt.cancelKey == "No")
        #expect(prompt.title == "Decision Required")
        #expect(prompt.showPreview)
        #expect(prompt.timeoutSeconds == 0)
    }

    @Test func keysForEachWayOfAnswering() {
        let prompt = RecipePrompt(step("UserPrompt", ["Choices": .array([choice("a"), choice("b", isDefault: true), choice("c")])]))
        #expect(prompt.key(for: .chosen("c")) == "c")
        #expect(prompt.key(for: .enter) == "b")
        #expect(prompt.key(for: .timedOut) == "b")
        // No cancel choice and no "No": the last one.
        #expect(prompt.key(for: .escape) == "c")
        #expect(prompt.key(for: .closed) == "c")
    }

    @Test func defaultChoiceAndNoWin() {
        let prompt = RecipePrompt(step("UserPrompt", ["Choices": .array([choice("Yes"), choice("No"), choice("Later")]),
                                                      "DefaultChoice": .string("Later"), "TimeoutSeconds": .number(5)]))
        #expect(prompt.key(for: .timedOut) == "Later")
        #expect(prompt.key(for: .escape) == "No")
        #expect(prompt.timeoutSeconds == 5)
        let first = RecipePrompt(step("UserPrompt", ["Choices": .array([choice("x"), choice("y")])]))
        #expect(first.key(for: .enter) == "x")
    }

    @Test func countdownTexts() {
        #expect(RecipePrompt.countdownText(3) == "Auto-selecting default choice in 3s...")
        #expect(RecipePrompt.countdownText(0) == "")
        #expect(RecipeFlyout.countdownText(9) == "Auto-closing in 9s...")
    }

    final class Answering: RecipePromptPresenting, @unchecked Sendable {
        let answer: RecipePrompt.Answer
        private let lock = NSLock()
        private var asked: [RecipePrompt] = []
        var prompts: [RecipePrompt] { lock.withLock { asked } }

        init(_ answer: RecipePrompt.Answer) {
            self.answer = answer
        }

        func ask(_ prompt: RecipePrompt, preview: CGImage?, in context: RecipeFlowContext) async throws -> RecipePrompt.Answer {
            lock.withLock { asked.append(prompt) }
            return answer
        }
    }

    @Test func theChosenKeyLeadsTheFlow() async {
        let recorder = RecipeRecorder()
        let registry = RecipeEngineHarness.registry(recorder)
        registry.register(WellKnownStepType.userPrompt, executor: RecipeUserPromptExecutor(presenter: Answering(.chosen("upload"))))
        var recipe = RecipeEngineHarness.recipe(["upload", "keep"], start: ["ask"], [])
        recipe.nodes.insert(RecipeNode(id: "ask", stepType: WellKnownStepType.userPrompt,
                                       parameters: ["Choices": .array([choice("upload"), choice("keep")])]), at: 0)
        recipe.flow.conditionalTransitions = [ConditionalTransition(from: "ask", branch: "upload", to: "upload"),
                                              ConditionalTransition(from: "ask", branch: "keep", to: "keep")]
        let context = await RecipeEngineHarness.run(recipe, registry)
        #expect(context[variable: "UserChoice.ask"] == .string("upload"))
        #expect(recorder.all == ["upload"])
    }

    @Test func escapeTakesTheCancelChoice() async throws {
        let presenter = Answering(.escape)
        let context = RecipeEngineHarness.context(RecipeEngineHarness.recipe(["a"], start: ["a"], []))
        let invocation = step("UserPrompt", ["Choices": .array([choice("go", isDefault: true), choice("stop", isCancel: true)]),
                                             "ShowPreview": .bool(false), "Title": .string("Upload?")])
        try await RecipeUserPromptExecutor(presenter: presenter).execute(invocation, in: context)
        #expect(context[variable: "UserChoice.ask"] == .string("stop"))
        #expect(presenter.prompts.first?.title == "Upload?")
    }

    // MARK: DynamicDestination

    let available: [(designation: String, name: String)] = [
        ("FileNoDialog", "Save"), ("Picker", "Ask"), ("Clipboard", "Copy"), ("Jira", "Upload to Jira"), ("Windows10OCR", "Copy Text"),
        ("External Paint", "Paint"), ("Printer", "Print")
    ]

    @Test func tilesCoreFirstInUpstreamsOrder() {
        let flyout = RecipeFlyout(step("DynamicDestination"), lastError: nil, available: available, recipes: [], runningRecipeId: "me")
        #expect(flyout.title == "Export Capture")
        #expect(flyout.showPreview)
        let core = flyout.tiles.filter(\.isCore).map(\.designation)
        #expect(core == ["Editor", "Clipboard", "FileNoDialog", "Printer", "Windows10OCR"])
        let others = flyout.tiles.filter { !$0.isCore }.map(\.designation)
        #expect(others == ["Jira", "External Paint"])
        #expect(!flyout.tiles.contains { $0.designation == "Picker" })
        #expect(flyout.tiles.allSatisfy { $0.badge == nil })
        #expect(flyout.tiles.first { $0.designation == "External Paint" }?.title == "Paint")
    }

    @Test func destinationsParameterNarrowsTheTiles() {
        let invocation = step("DynamicDestination", ["Destinations": .array([.string("clipboard"), .string("jira")]), "Title": .string("Send")])
        let flyout = RecipeFlyout(invocation, lastError: nil, available: available, recipes: [], runningRecipeId: "me")
        #expect(flyout.tiles.map(\.designation) == ["Editor", "Clipboard", "Jira"])
        #expect(flyout.title == "Send")
    }

    @Test func aFailedExportShowsItsMessageAndRetry() {
        let flyout = RecipeFlyout(step("DynamicDestination"), lastError: "Export to Jira failed: 401", available: available, recipes: [],
                                  runningRecipeId: "me")
        #expect(flyout.errorMessage == "Export to Jira failed: 401")
        #expect(flyout.tiles.first { $0.designation == "Clipboard" }?.badge == "Retry")
    }

    @Test func forwardingWithoutTheRunningRecipe() {
        let recipes = [RecipeFlyout.RecipeForwardChoice(id: "me", name: "This"), RecipeFlyout.RecipeForwardChoice(id: "other", name: "Other")]
        let flyout = RecipeFlyout(step("DynamicDestination"), lastError: nil, available: [], recipes: recipes, runningRecipeId: "ME")
        #expect(flyout.recipes.map(\.id) == ["other"])
        let off = RecipeFlyout(step("DynamicDestination", ["AllowRecipeForwarding": .bool(false)]), lastError: nil, available: [],
                               recipes: recipes, runningRecipeId: "me")
        #expect(off.recipes.isEmpty)
    }

    @Test func searchFiltersTheOtherTiles() {
        let flyout = RecipeFlyout(step("DynamicDestination"), lastError: nil, available: available, recipes: [], runningRecipeId: "me")
        #expect(flyout.otherTiles(matching: "jira").map(\.designation) == ["Jira"])
        #expect(flyout.otherTiles(matching: "command").map(\.designation) == ["External Paint"])
        #expect(flyout.otherTiles(matching: " ").count == 2)
    }

    final class Choosing: RecipeFlyoutPresenting, @unchecked Sendable {
        let choice: RecipeFlyout.Choice
        private let lock = NSLock()
        private var log: [String] = []
        var actions: [String] { lock.withLock { log } }

        init(_ choice: RecipeFlyout.Choice) {
            self.choice = choice
        }

        func availableDestinations(in context: RecipeFlowContext) async -> [(designation: String, name: String)] { [("Clipboard", "Copy")] }
        func forwardableRecipes() async -> [RecipeFlyout.RecipeForwardChoice] { [] }
        func choose(_ flyout: RecipeFlyout, preview: CGImage?, in context: RecipeFlowContext) async throws -> RecipeFlyout.Choice {
            lock.withLock { log.append("shown \(flyout.tiles.count) preview \(preview != nil)") }
            return choice
        }
        func export(_ designation: String, step: RecipeStepInvocation, in context: RecipeFlowContext) async throws {
            lock.withLock { log.append("export \(designation)") }
        }
        func forward(to recipeId: String, in context: RecipeFlowContext) async {
            lock.withLock { log.append("forward \(recipeId)") }
        }
    }

    @Test func theChoiceIsCarriedOut() async throws {
        let context = RecipeEngineHarness.context(RecipeEngineHarness.recipe(["a"], start: ["a"], []))
        for (choice, expected) in [(RecipeFlyout.Choice.editor, "export Editor"), (.destination("Clipboard"), "export Clipboard"),
                                   (.forward("other"), "forward other")] {
            let presenter = Choosing(choice)
            try await RecipeDynamicDestinationExecutor(presenter: presenter).execute(step("DynamicDestination", id: "export"), in: context)
            #expect(presenter.actions == ["shown 2 preview true", expected])
        }
        let dismissed = Choosing(.dismissed)
        try await RecipeDynamicDestinationExecutor(presenter: dismissed)
            .execute(step("DynamicDestination", ["ShowPreview": .bool(false)], id: "export"), in: context)
        #expect(dismissed.actions == ["shown 2 preview false"])
    }
}
