// Greenshot for Mac (Community) - an unofficial macOS port of Greenshot
// Copyright (C) 2026 Greenshot for Mac (Community) contributors
// Based on Greenshot, Copyright (C) 2007-2026 Thomas Braun, Jens Klingen, Robin Krom
// SPDX-License-Identifier: GPL-3.0-or-later

import Foundation
import Testing
@testable import GreenshotCore

@Suite struct RecipeEditorDefaultsTests {
    @Test func everyToolboxStepHasAContract() {
        for item in RecipeEditorCatalog.toolbox.flatMap(\.items) {
            #expect(StepContractCatalog.builtIn.contains(item.stepType), "\(item.stepType)")
        }
        // ...and every step type is in the toolbox.
        let offered = Set(RecipeEditorCatalog.toolbox.flatMap(\.items).map { $0.stepType.lowercased() })
        for contract in StepContractCatalog.builtIn.all {
            #expect(offered.contains(contract.stepType.lowercased()), "\(contract.stepType)")
        }
    }

    @Test func newRecipeIsValidAndHasTheStandardSlots() {
        let recipe = RecipeEditorCatalog.newRecipe()
        let result = RecipeValidator().validate(recipe)
        #expect(result.errors.isEmpty, "\(result.errors)")
        #expect(recipe.id.hasPrefix("recipe_"))
        let slots = recipe.nodes.filter { $0.stepType == WellKnownStepType.slot }.compactMap { $0.parameters.string("Name") }
        #expect(Set(slots) == Set([RecipeSlots.afterCapture, RecipeSlots.beforeExport, RecipeSlots.beforeDestination, RecipeSlots.afterExport]))
    }

    @Test func everyStepWithItsDefaultsValidates() {
        for item in RecipeEditorCatalog.toolbox.flatMap(\.items) {
            var recipe = RecipeEditorCatalog.newRecipe()
            let node = RecipeEditorCatalog.newNode(item.stepType, in: recipe, previous: "acquire")
            RecipeFlowEditor.insert(node, after: "acquire", in: &recipe)
            let result = RecipeValidator().validate(recipe)
            #expect(result.errors.isEmpty, "\(item.stepType): \(result.errors)")
        }
    }

    @Test func slotNameIsGuessed() {
        let recipe = RecipeEditorCatalog.newRecipe()
        let afterExport = RecipeEditorCatalog.newNode("Slot", in: recipe, previous: "export")
        #expect(afterExport.parameters.string("Name") == RecipeSlots.afterExport)
        let beforeExport = RecipeEditorCatalog.newNode("Slot", in: recipe, previous: "acquire", next: "export")
        #expect(beforeExport.parameters.string("Name") == RecipeSlots.beforeExport)
        let afterCapture = RecipeEditorCatalog.newNode("Slot", in: recipe, previous: "acquire", next: "feedback")
        #expect(afterCapture.parameters.string("Name") == RecipeSlots.afterCapture)
    }

    @Test func newExtensionIsValid() {
        let ext = RecipeEditorCatalog.newExtension()
        #expect(ext.kind == .extension)
        let result = RecipeValidator().validate(ext)
        #expect(result.errors.isEmpty, "\(result.errors)")
    }

    @Test func everyTriggerTypeValidates() {
        let base = RecipeEditorCatalog.newRecipe()
        for entry in RecipeEditorCatalog.triggerTypes {
            var recipe = base
            recipe.triggers = [RecipeEditorCatalog.newTrigger(entry.type, for: recipe)]
            let result = RecipeValidator().validate(recipe)
            #expect(result.errors.isEmpty, "\(entry.type): \(result.errors)")
        }
    }

    @Test func aiToolNameIsSanitised() {
        #expect(RecipeEditorCatalog.toolName(from: "recipe.my tool!") == "recipe_my_tool_")
        #expect(RecipeEditorCatalog.toolName(from: String(repeating: "a", count: 80)).count == 64)
        #expect(RecipeEditorCatalog.toolName(from: "") == "my_tool")
    }

    @Test func errorRouteAndOptionDefaults() {
        var recipe = EditorFixtures.recipe(["a:Source", "e:Editor", "d:DynamicDestination"], ["a>e"])
        #expect(RecipeEditorCatalog.newErrorTransition(for: recipe) == ErrorTransition(from: "*", to: "d"))
        recipe.nodes.removeLast()
        #expect(RecipeEditorCatalog.newErrorTransition(for: recipe).to == "e")
        let first = RecipeEditorCatalog.newOption(for: recipe)
        #expect(first.key == "option")
        recipe.options = [first]
        #expect(RecipeEditorCatalog.newOption(for: recipe).key == "option2")
    }

    @Test func symbols() {
        #expect(RecipeEditorCatalog.symbol(for: "conditional") == "arrow.triangle.branch")
        #expect(RecipeEditorCatalog.symbol(for: "Unknown") == "square.dashed")
    }
}
