// Greenshot for Mac (Community) - an unofficial macOS port of Greenshot
// Copyright (C) 2026 Greenshot for Mac (Community) contributors
// Based on Greenshot, Copyright (C) 2007-2026 Thomas Braun, Jens Klingen, Robin Krom
// SPDX-License-Identifier: GPL-3.0-or-later

import Foundation
import Testing
@testable import GreenshotCore

/// The recipe manager's rows, filters and counters (upstream RecipeManagerViewModel).
@MainActor
@Suite struct RecipeManagerListTests {
    @Test func rowsOfBuiltInFileAndAutomaticSteps() async throws {
        let builtIn = ComposerFixture.recipe("cap", slots: ["BeforeDestination"])
        let fixture = LibraryFixture(builtIns: [builtIn])
        defer { fixture.cleanUp() }
        // A file recipe whose hotkey trigger the user switched off in the approval.
        let fileRecipe = libraryRecipe()
        let decline = StubApprover { request in
            RecipeApprovalDecision(approval: RecipeApproval(recipeId: request.recipe?.id ?? "", approvedTriggers: ["1:Clipboard"],
                                                            allowedGates: request.gates))
        }
        fixture.approver.answer = decline.answer
        _ = await fixture.library.loadFile(try fixture.write(fileRecipe))
        fixture.library.setEnabled(false, recipeId: "cap")

        let items = fixture.library.managerItems()
        #expect(items.recipes.map(\.id) == ["cap", "lib_recipe"])
        let cap = items.recipes[0]
        #expect(cap.typeBadge == "BUILT-IN")
        #expect(cap.statusBadge == "DEACTIVATED")
        #expect(!cap.canUnload)
        #expect(cap.triggersSummary == "Recipes menu (default)")
        #expect(cap.stepCount == 3)
        let file = items.recipes[1]
        #expect(file.typeBadge == "CUSTOM")
        #expect(file.canUnload)
        #expect(file.unloadTitle == "Unload")
        #expect(file.hasUnapprovedTriggers)
        #expect(file.triggersSummary.hasPrefix("Hotkey "))
        #expect(file.triggersSummary.contains("(off, not approved)"))
        #expect(file.triggersSummary.hasSuffix("Clipboard monitor"))
        #expect(file.filePath?.hasSuffix("test.gsrecipe.json") == true)

        #expect(items.extensions.map(\.id) == ["ext_caption", "ext_border", "ext_dropshadow"])
        let border = items.extensions[1]
        #expect(border.isExtension)
        #expect(!border.isEnabled)
        #expect(border.canToggle)
        #expect(!border.canUnload)
        #expect(border.triggersSummary == "Automatic step at BeforeDestination, fits 1 recipe(s)")

        let counts = RecipeManagerList.counts(items.recipes)
        #expect(counts.total == 2)
        #expect(counts.active == 1)
        #expect(counts.deactivated == 1)
    }

    @Test func filtersAndSearch() {
        let items = [
            RecipeManagerItem(id: "recipe_region", name: "Region", isBuiltIn: true, triggersSummary: "Hotkey ⇧⌘R"),
            RecipeManagerItem(id: "mine", name: "Mine", description: "uploads", isEnabled: false, filePath: "/Users/me/mine.gsrecipe.json"),
            RecipeManagerItem(id: "recipe_window", name: "Window", isBuiltIn: true, isOverridden: true, filePath: "/tmp/w.gsrecipe.json"),
            RecipeManagerItem(id: "ai", name: "AI one", proposedBy: "Claude", filePath: "/tmp/ai.gsrecipe.json")
        ]
        func ids(_ filter: RecipeManagerFilter, _ query: String = "") -> [String] {
            RecipeManagerList.filter(items, by: filter, query: query).map(\.id)
        }
        #expect(ids(.all) == ["recipe_region", "mine", "recipe_window", "ai"])
        #expect(ids(.active) == ["recipe_region", "recipe_window", "ai"])
        #expect(ids(.deactivated) == ["mine"])
        #expect(ids(.builtIn) == ["recipe_region"])
        #expect(ids(.custom) == ["mine", "recipe_window", "ai"])
        #expect(ids(.ai) == ["ai"])
        #expect(ids(.all, "UPLOAD") == ["mine"])
        #expect(ids(.all, "⇧⌘R") == ["recipe_region"])
        #expect(ids(.custom, "gsrecipe") == ["mine", "recipe_window", "ai"])
        #expect(ids(.builtIn, "mine").isEmpty)
        #expect(items[2].unloadTitle == "Reset Default")
        #expect(items[2].typeBadge == "OVERRIDDEN")
        #expect(items[3].isAICreated)
    }
}
