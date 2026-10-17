// Greenshot for Mac (Community) - an unofficial macOS port of Greenshot
// Copyright (C) 2026 Greenshot for Mac (Community) contributors
// Based on Greenshot, Copyright (C) 2007-2026 Thomas Braun, Jens Klingen, Robin Krom
// SPDX-License-Identifier: GPL-3.0-or-later
// Owned by REDITOR after the wave 4 prep.

import AppKit
import GreenshotCore

/// Opens the recipe editor window (upstream `IRecipeEditorService`). One window; calls reuse it. Callers: RUI (menus,
/// approval sheet), RMANAGER (manager rows and toolbar), MCP (RECIPE_EDITOR, approved proposals).
@MainActor
enum RecipeEditorService {
    /// The editor with this recipe (nil: the last one / the first recipe).
    static func openEditor(recipeId: String? = nil) {
        let controller = RecipeEditorWindowController.show()
        let model = controller.model
        guard let recipeId else {
            if model.recipe == nil { openFirst(in: model) }
            return
        }
        if model.recipe?.id.caseInsensitiveCompare(recipeId) == .orderedSame { return }
        Task {
            guard await model.confirmDiscardChanges() else { return }
            if !model.open(recipeId: recipeId) {
                model.status = String(localized: "There is no recipe '\(recipeId)'.")
                if model.recipe == nil { openFirst(in: model) }
            }
        }
    }

    /// The editor with the recipe file at `url` (manager "Edit" of a file, approval "Open in the recipe editor after
    /// saving", validation-error "Edit Recipe File").
    static func openFile(_ url: URL) {
        let model = RecipeEditorWindowController.show().model
        Task {
            guard await model.confirmDiscardChanges() else { return }
            // An approved file is loaded already: open its copy; otherwise load it (the library asks for approval).
            let path = RecipeEditorFiles.standardized(url).path
            if let library = model.library,
               let loaded = (library.recipes + library.extensions).first(where: { $0.sourceFile.map { RecipeEditorFiles.standardized($0).path } == path }) {
                model.open(loaded.recipe, fileURL: loaded.sourceFile, saved: true)
                return
            }
            await model.openFile(url)
        }
    }

    /// The editor with a new recipe (manager "New Recipe").
    static func newRecipe() {
        let model = RecipeEditorWindowController.show().model
        Task { await model.newRecipeAsking() }
    }

    /// The editor with this automatic step (manager "Edit" of an automatic step, RCP-259/RCP-300).
    static func openExtension(id: String) {
        openEditor(recipeId: id)
    }

    /// Before the app quits (RSTEPS calls it from `applicationShouldTerminate`; true = may quit): unsaved changes in the
    /// recipe editor are asked about, like closing its window. "Save" cancels this quit and quits again once saved (saving
    /// may ask for an approval first); "Don't Save" drops them.
    static func reviewUnsavedBeforeQuit() -> Bool {
        guard let controller = RecipeEditorWindowController.shared else { return true }
        let model = controller.model
        guard model.isDirty || model.jsonDraft != nil, let recipe = model.recipe else { return true }
        controller.window?.makeKeyAndOrderFront(nil)
        let alert = NSAlert()
        let name = recipe.name
        alert.messageText = String(localized: "Unsaved Changes")
        alert.informativeText = String(localized: "\"\(name)\" has unsaved changes in the recipe editor. Do you want to save them before quitting?")
        alert.addButton(withTitle: String(localized: "Save"))
        alert.addButton(withTitle: String(localized: "Don't Save"))
        alert.addButton(withTitle: String(localized: "Cancel"))
        alert.buttons[2].keyEquivalent = "\u{1b}"
        switch alert.runModal() {
        case .alertFirstButtonReturn:
            Task { @MainActor in
                if await model.save() { NSApp.terminate(nil) }
            }
            return false
        case .alertSecondButtonReturn:
            model.discardChanges()
            return true
        default:
            return false
        }
    }

    private static func openFirst(in model: RecipeEditorModel) {
        if let first = model.library?.recipes.first {
            model.open(first.recipe, fileURL: first.sourceFile, saved: true)
        } else {
            model.newRecipe()
        }
    }
}
