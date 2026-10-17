// Greenshot for Mac (Community) - an unofficial macOS port of Greenshot
// Copyright (C) 2026 Greenshot for Mac (Community) contributors
// Based on Greenshot, Copyright (C) 2007-2026 Thomas Braun, Jens Klingen, Robin Krom
// SPDX-License-Identifier: GPL-3.0-or-later

import Foundation
@testable import GreenshotCore
import Testing

/// The Recipes menus' entries (upstream `TriggerManager.SyncRecipeTriggers`, `TrayMenu.CreateRecipesItem`).
struct RecipeTriggersMenuTests {
    static func trigger(_ type: String, _ parameters: JSONObject = [:], enabled: Bool = true) -> TriggerConfig {
        var trigger = TriggerConfig(triggerType: type, parameters: parameters)
        trigger.enabled = enabled
        return trigger
    }

    static func recipe(_ id: String, _ triggers: [TriggerConfig], showInMenu: Bool = true) -> CaptureRecipe {
        var recipe = CaptureRecipe(id: id, name: id.capitalized)
        recipe.triggers = triggers
        recipe.showInContextMenu = showInMenu
        return recipe
    }

    /// A file recipe with every trigger approved.
    static func loaded(_ recipe: CaptureRecipe, enabled: Bool = true, builtIn: Bool = false) -> LoadedRecipe {
        let keys = recipe.triggers.enumerated().map { RecipeApprovalPolicy.triggerKey(index: $0.offset, trigger: $0.element) }
        return LoadedRecipe(recipe: recipe, source: builtIn ? .builtIn : .file(URL(fileURLWithPath: "/tmp/\(recipe.id).gsrecipe.json")),
                            isEnabled: enabled, approval: builtIn ? nil : RecipeApproval(recipeId: recipe.id, approvedTriggers: keys))
    }

    /// What `RecipeLibrary.activeTriggers` answers for these recipes.
    static func active(_ recipes: [LoadedRecipe]) -> [ActiveRecipeTrigger] {
        var result: [ActiveRecipeTrigger] = []
        for loaded in recipes where loaded.isEnabled {
            for (index, trigger) in loaded.recipe.triggers.enumerated() where loaded.isTriggerActive(at: index) {
                let hotkey = trigger.isType(WellKnownTriggerType.hotkey) ? trigger.hotkey.flatMap(RecipeHotkeyText.parse) : nil
                result.append(ActiveRecipeTrigger(recipeId: loaded.recipe.id, recipeName: loaded.recipe.name, index: index,
                                                  trigger: trigger, hotkey: hotkey))
            }
        }
        return result
    }

    @Test func menuTriggersSortedByOrderStable() {
        let recipes = [
            Self.loaded(Self.recipe("b", [Self.trigger(WellKnownTriggerType.contextMenu, ["Order": .number(2)])])),
            Self.loaded(Self.recipe("a", [Self.trigger(WellKnownTriggerType.systray, ["MenuItemText": .string("Alpha")])])),
            Self.loaded(Self.recipe("c", [Self.trigger(WellKnownTriggerType.contextMenu)]))
        ]
        let entries = RecipeMenuEntries.statusMenu(recipes: recipes, active: Self.active(recipes))
        #expect(entries.map(\.recipeId) == ["a", "c", "b"])
        #expect(entries.first?.title == "Alpha")
        #expect(entries.last?.title == "B")
    }

    @Test func switchedOffAndHiddenRecipesAreLeftOut() {
        let recipes = [
            Self.loaded(Self.recipe("off", [Self.trigger(WellKnownTriggerType.contextMenu)]), enabled: false),
            Self.loaded(Self.recipe("hidden", [Self.trigger(WellKnownTriggerType.contextMenu)], showInMenu: false)),
            Self.loaded(Self.recipe("shown", [Self.trigger(WellKnownTriggerType.contextMenu)]))
        ]
        let entries = RecipeMenuEntries.statusMenu(recipes: recipes, active: Self.active(recipes))
        #expect(entries.map(\.recipeId) == ["shown"])
    }

    @Test func fileRecipeWithoutMenuTriggerGetsDefaultEntry() throws {
        let recipes = [
            Self.loaded(Self.recipe("hotkey_only", [Self.trigger(WellKnownTriggerType.hotkey, ["Hotkey": .string("Ctrl + Shift + H")])])),
            Self.loaded(Self.recipe("builtin", []), builtIn: true)
        ]
        let entries = RecipeMenuEntries.statusMenu(recipes: recipes, active: Self.active(recipes))
        #expect(entries.count == 1)
        let entry = try #require(entries.first)
        #expect(entry.recipeId == "hotkey_only")
        #expect(entry.trigger == nil)
        let hotkey = try #require(entry.hotkey)
        #expect(hotkey.displayString == "⇧⌘H")
    }

    @Test func unapprovedMenuTriggerFallsBackToDefaultEntry() throws {
        let recipe = Self.recipe("pending", [Self.trigger(WellKnownTriggerType.contextMenu)])
        let loaded = LoadedRecipe(recipe: recipe, source: .file(URL(fileURLWithPath: "/tmp/p.json")),
                                  approval: RecipeApproval(recipeId: "pending"))
        let entries = RecipeMenuEntries.statusMenu(recipes: [loaded], active: Self.active([loaded]))
        let entry = try #require(entries.first)
        #expect(entry.trigger == nil)
    }

    @Test func groupsBecomeSubmenus() {
        let recipes = [
            Self.loaded(Self.recipe("a", [Self.trigger(WellKnownTriggerType.contextMenu, ["Group": .string("Tools")])])),
            Self.loaded(Self.recipe("b", [Self.trigger(WellKnownTriggerType.contextMenu, ["Group": .string("Recipes")])])),
            Self.loaded(Self.recipe("c", [Self.trigger(WellKnownTriggerType.contextMenu, ["Group": .string("tools")])]))
        ]
        let layout = RecipeMenuEntries.layout(RecipeMenuEntries.statusMenu(recipes: recipes, active: Self.active(recipes)))
        #expect(layout.count == 2)
        guard case .group(let name, let members) = layout.first else {
            Issue.record("The first item should be the Tools submenu")
            return
        }
        #expect(name == "Tools")
        #expect(members.map(\.recipeId) == ["a", "c"])
        guard case .entry(let entry) = layout.last else {
            Issue.record("The default group goes straight into the menu")
            return
        }
        #expect(entry.recipeId == "b")
    }

    @Test func editorMenuHasOnlyEditorTriggers() {
        let recipes = [
            Self.loaded(Self.recipe("edit", [Self.trigger(WellKnownTriggerType.editor, ["MenuItemText": .string("Blur faces")]),
                                             Self.trigger(WellKnownTriggerType.contextMenu)], showInMenu: false)),
            Self.loaded(Self.recipe("menu", [Self.trigger(WellKnownTriggerType.contextMenu)]))
        ]
        let entries = RecipeMenuEntries.editorMenu(recipes: recipes, active: Self.active(recipes))
        #expect(entries.map(\.title) == ["Blur faces"])
    }

    @Test func disabledTriggerIsNoEntry() {
        let recipes = [Self.loaded(Self.recipe("x", [Self.trigger(WellKnownTriggerType.contextMenu, enabled: false),
                                                     Self.trigger(WellKnownTriggerType.contextMenu, ["MenuItemText": .string("On")])]))]
        let entries = RecipeMenuEntries.statusMenu(recipes: recipes, active: Self.active(recipes))
        #expect(entries.map(\.title) == ["On"])
    }
}
