// Greenshot for Mac (Community) - an unofficial macOS port of Greenshot
// Copyright (C) 2026 Greenshot for Mac (Community) contributors
// Based on Greenshot, Copyright (C) 2007-2026 Thomas Braun, Jens Klingen, Robin Krom
// SPDX-License-Identifier: GPL-3.0-or-later
// Owned by RMANAGER after the wave 4 prep.

import AppKit
import GreenshotCore
import SwiftUI

/// The recipe manager window (upstream `IRecipeEditorService.OpenManager`). Callers: RUI (menus), REDITOR (toolbar,
/// ⇧⌘M), MCP (RECIPE_MANAGER).
@MainActor
enum RecipeManagerService {
    /// Opens the manager or brings it to the front, with `recipeId` selected when given.
    static func show(selecting recipeId: String? = nil) {
        guard let runtime = RecipeRuntime.shared else {
            NSSound.beep()
            return
        }
        RecipeManagerWindowController.show(library: runtime.library, runtime: runtime, selecting: recipeId)
    }
}

/// Automatic steps in the running app: sets `RecipeRuntime.composeForRun` and `destinationChains` (upstream
/// `CapturePipeline`: "the recipe runs with the switched on extensions in its slots").
@MainActor
enum RecipeAutomaticSteps {
    /// At launch, right after `app.recipes.start()`.
    static func install(on runtime: RecipeRuntime) {
        let library = runtime.library
        // Returns the recipe unchanged (==) when no automatic step applies, so stock captures stay on the direct path.
        runtime.composeForRun = { [weak library] recipe in library?.effectiveRecipe(recipe) ?? recipe }
        runtime.destinationChains = { recipe in recipe.composition?.destinationChains ?? [] }
        // An AI tool's automatic step approved with "open in the recipe editor" opens there (CONFLICTS C20).
        library.openExtensionInEditor = { id in RecipeEditorService.openExtension(id: id) }
    }
}

/// Quick Settings › "Automatic steps" (RCP-173, APP-017; upstream `TrayMenu.AddRecipeQuickSettings`): appended last to
/// the Quick Settings menu. A switch is a checked item, a choice a submenu, at most six, and "More…" opens Settings ›
/// Recipes. Left out while an administrator locks the option values.
@MainActor
enum RecipeQuickSettingsMenu {
    static func append(to menu: NSMenu, store: SettingsStore) {
        guard !store.isLocked(\.recipes.optionValues), let library = RecipeRuntime.shared?.library else { return }
        append(to: menu, library: library) {
            (NSApp.delegate as? AppDelegate)?.showSettings(pane: .recipes)
        }
    }

    /// The block for `library` (snapshots hand their own library).
    static func append(to menu: NSMenu, library: RecipeLibrary, openSettings: @escaping () -> Void) {
        let entries = library.quickSettings()
        guard !entries.isEmpty else { return }
        if !menu.items.isEmpty { menu.addItem(.separator()) }
        let header = NSMenuItem(title: String(localized: "Automatic steps"), action: nil, keyEquivalent: "")
        header.isEnabled = false
        menu.addItem(header)
        for entry in entries {
            // A built-in automatic step's texts in the language of the app; a file's as they are.
            let shown = { (text: String) in RecipeOptionTexts.shown(text, ownerId: entry.ownerId, in: library) }
            // Two options with the same label: "<owner>: <label>", each part translated on its own.
            let optionText = shown(entry.optionLabel)
            let label = entry.ownerName.map {
                String(localized: "\(shown($0)): \(optionText)",
                       comment: "A quick setting: the automatic step or recipe (first %@), then its option (second %@)")
            } ?? optionText
            if entry.option.type == .boolean {
                let on = entry.value == .bool(true)
                let item = ClosureMenuItem(title: label) {
                    library.setOption(.bool(!on), key: entry.option.key, ownerId: entry.ownerId)
                }
                item.state = on ? .on : .off
                if let description = entry.option.description, !description.isEmpty { item.toolTip = shown(description) }
                menu.addItem(item)
                continue
            }
            let choices = NSMenu(title: label)
            choices.autoenablesItems = false
            for choice in entry.option.choices ?? [] {
                let value = choice.value
                // Like a radio button: clicking the current value keeps it.
                let item = ClosureMenuItem(title: choice.label.map(shown) ?? choice.value) {
                    library.setOption(.string(value), key: entry.option.key, ownerId: entry.ownerId)
                }
                item.state = entry.value.asString.map { $0.caseInsensitiveCompare(value) == .orderedSame } == true ? .on : .off
                choices.addItem(item)
            }
            let item = NSMenuItem(title: label, action: nil, keyEquivalent: "")
            item.submenu = choices
            menu.addItem(item)
        }
        menu.addItem(ClosureMenuItem(title: String(localized: "More…"), handler: openSettings))
    }
}
