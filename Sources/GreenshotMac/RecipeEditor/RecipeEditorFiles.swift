// Greenshot for Mac (Community) - an unofficial macOS port of Greenshot
// Copyright (C) 2026 Greenshot for Mac (Community) contributors
// Based on Greenshot, Copyright (C) 2007-2026 Thomas Braun, Jens Klingen, Robin Krom
// SPDX-License-Identifier: GPL-3.0-or-later

import AppKit
import GreenshotCore
import UniformTypeIdentifiers

private let log = Log("RecipeEditor")

/// New, Open, Save, Save As, the "unsaved changes" question, unload and the approval review (upstream
/// RecipeEditorViewModel.cs :1713-1973, :311, :1767). Saving goes through the library, which renews the approval of the
/// saved content and asks (RUI's approval sheet) only when the change needs a decision.
extension RecipeEditorModel {
    // MARK: Alerts

    /// An alert as a sheet on the editor window (modal without one); the index of the clicked button.
    func ask(_ message: String, detail: String, buttons: [String], style: NSAlert.Style = .warning) async -> Int {
        let alert = NSAlert()
        alert.messageText = message
        alert.informativeText = detail
        alert.alertStyle = style
        for title in buttons { alert.addButton(withTitle: title) }
        if buttons.count > 2 { alert.buttons.last?.keyEquivalent = "\u{1b}" }
        guard let window, window.isVisible else {
            return alert.runModal().rawValue - NSApplication.ModalResponse.alertFirstButtonReturn.rawValue
        }
        return await withCheckedContinuation { continuation in
            alert.beginSheetModal(for: window) { response in
                continuation.resume(returning: response.rawValue - NSApplication.ModalResponse.alertFirstButtonReturn.rawValue)
            }
        }
    }

    func tell(_ message: String, detail: String, style: NSAlert.Style = .warning) async {
        _ = await ask(message, detail: detail, buttons: ["OK"], style: style)
    }

    /// Upstream `ConfirmDiscardChanges`: Save, Don't Save or Cancel; true when the editor may go on.
    func confirmDiscardChanges() async -> Bool {
        guard isDirty, let recipe else { return true }
        let answer = await ask("Unsaved Changes", detail: "\"\(recipe.name)\" has unsaved changes. Do you want to save them?",
                               buttons: ["Save", "Don't Save", "Cancel"])
        switch answer {
        case 0: return await save()
        case 1:
            discardChanges()
            return true
        default: return false
        }
    }

    // MARK: Commands

    func newRecipeAsking() async {
        guard await confirmDiscardChanges() else { return }
        newRecipe()
    }

    func newExtensionAsking() async {
        guard await confirmDiscardChanges() else { return }
        newExtension()
    }

    /// Switches to another recipe of the library (the recipe picker).
    func switchTo(recipeId: String) async {
        guard recipe?.id.caseInsensitiveCompare(recipeId) != .orderedSame || isDirty else { return }
        guard await confirmDiscardChanges() else {
            objectWillChange.send()
            return
        }
        _ = open(recipeId: recipeId)
    }

    /// Upstream `OpenRecipeDialog`: a recipe file is loaded (and approved) by the library, then opened as a copy.
    func openFileAsking() async {
        let panel = NSOpenPanel()
        panel.title = "Open Greenshot Recipe"
        panel.allowedContentTypes = [.json]
        panel.allowsMultipleSelection = false
        if let folder = environment.runtime()?.recipesFolder, FileManager.default.fileExists(atPath: folder.path) {
            panel.directoryURL = folder
        }
        guard await present(panel) == .OK, let url = panel.url else { return }
        guard await confirmDiscardChanges() else { return }
        await openFile(url)
    }

    /// Opens a recipe file: through the library (approval) when recipes run, else read and checked only.
    func openFile(_ url: URL) async {
        let name = url.lastPathComponent
        guard let library else {
            guard let data = try? Data(contentsOf: url), let text = RecipeSerializer.text(of: data),
                  let read = try? RecipeSerializer.decode(text: text), let first = read.first else {
                await tell("Error Loading Recipe", detail: "The file \(name) is not a recipe.")
                return
            }
            open(first, fileURL: url, saved: true)
            status = "Loaded: \(name)"
            return
        }
        let standardized = RecipeEditorFiles.standardized(url)
        let result = await library.loadFile(standardized)
        if !result.isValid {
            await tell("Validation Error", detail: "Recipe failed validation:\n" + result.errors.joined(separator: "\n"))
            status = "Recipe failed validation: \(name)"
            return
        }
        let loaded = library.recipes.first { $0.sourceFile?.path == standardized.path }
            ?? library.extensions.first { $0.sourceFile?.path == standardized.path }
        guard let loaded else { return }
        open(loaded.recipe, fileURL: loaded.sourceFile, saved: true)
        status = "Loaded and registered: \(name)"
    }

    /// Upstream `TrySaveRecipe`: to its file, or Save As when it has none (a new or built-in recipe). False when it wasn't saved.
    @discardableResult
    func save() async -> Bool {
        guard recipe != nil else { return false }
        guard let fileURL else { return await saveAs() }
        return await save(to: fileURL, askBeforeReplacing: true)
    }

    /// Upstream `TrySaveAsRecipe`.
    @discardableResult
    func saveAs() async -> Bool {
        guard let recipe else { return false }
        let panel = NSSavePanel()
        panel.title = recipe.kind == .extension ? "Save Automatic Step As…" : "Save Greenshot Recipe As…"
        panel.nameFieldStringValue = fileURL?.lastPathComponent ?? "\(recipe.id)\(RecipeSerializer.fileExtension)"
        panel.allowedContentTypes = [.json]
        panel.isExtensionHidden = false
        if let folder = fileURL?.deletingLastPathComponent() ?? environment.runtime()?.recipesFolder {
            try? FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
            panel.directoryURL = folder
        }
        guard await present(panel) == .OK, var url = panel.url else { return false }
        if !url.lastPathComponent.lowercased().hasSuffix(RecipeSerializer.fileExtension) {
            url = url.deletingPathExtension().appendingPathExtension("gsrecipe.json")
        }
        return await save(to: url, askBeforeReplacing: false)
    }

    /// Saves through the library: `save(_:to:)` for a recipe, `saveExtension(_:to:)` for an automatic step.
    private func save(to url: URL, askBeforeReplacing: Bool) async -> Bool {
        guard let recipe else { return false }
        guard let library else {
            await tell("Recipe Not Saved", detail: "Recipes aren't running in Greenshot right now, so the recipe can't be saved.")
            return false
        }
        // A file with several recipes: the library writes one recipe per file.
        if askBeforeReplacing, let data = try? Data(contentsOf: url), let text = RecipeSerializer.text(of: data),
           let inFile = try? RecipeSerializer.decode(text: text), inFile.count > 1 {
            let others = inFile.filter { $0.id.caseInsensitiveCompare(recipe.id) != .orderedSame }.map { "\"\($0.name)\"" }
            let answer = await ask("This File Has \(inFile.count) Recipes",
                                   detail: "Saving writes only \"\(recipe.name)\" to \(url.lastPathComponent); \(others.joined(separator: ", ")) would be removed from the file.",
                                   buttons: ["Save As…", "Replace File", "Cancel"])
            switch answer {
            case 0: return await saveAs()
            case 1: break
            default: return false
            }
        }
        let result = recipe.kind == .extension ? await library.saveExtension(recipe, to: url) : await library.save(recipe, to: url)
        guard result.isValid else {
            await tell("Recipe Not Saved", detail: result.errors.joined(separator: "\n"))
            status = "The recipe was not saved."
            return false
        }
        // The library may have changed the path to its standard form.
        let saved = library.recipe(id: recipe.id)?.sourceFile ?? RecipeEditorFiles.standardized(url)
        markSaved(at: recipe.kind == .extension ? RecipeEditorFiles.standardized(url) : saved)
        status = "Saved recipe to \(url.lastPathComponent)"
        log.info("Saved recipe '\(recipe.id)' from the recipe editor.")
        return true
    }

    /// Upstream `ReviewApproval`: the approval of the saved file again, to switch triggers and permissions.
    func reviewApproval() async {
        guard let library, let recipe else { return }
        guard await confirmDiscardChanges() else { return }
        let result = await library.reviewApproval(recipeId: recipe.id)
        if !result.isValid, !result.errors.isEmpty {
            await tell("Recipe Permissions", detail: result.errors.joined(separator: "\n"))
        }
        if let loaded = library.recipe(id: recipe.id) { open(loaded.recipe, fileURL: loaded.sourceFile, saved: true) }
        refreshNotice()
    }

    /// Upstream `UnloadActiveRecipe`: a file recipe is unloaded, a file that replaces a built-in gives the built-in back.
    func unloadAsking() async {
        guard let library, let recipe, let loaded = library.recipe(id: recipe.id), !loaded.isBuiltIn else { return }
        let reset = loaded.replacesBuiltIn
        var detail = reset ? "Revert '\(recipe.name)' to default built-in definition?" : "Unload '\(recipe.name)' from Greenshot?"
        if isDirty { detail += "\n\nYour unsaved changes are discarded." }
        guard await ask(reset ? "Reset Recipe to Default" : "Unload Recipe", detail: detail, buttons: ["Yes", "No"], style: .informational) == 0 else {
            return
        }
        discardChanges()
        if reset {
            _ = library.resetToDefault(recipeId: recipe.id)
        } else {
            library.unload(recipeId: recipe.id)
        }
        if let back = library.recipe(id: recipe.id) {
            open(back.recipe, fileURL: back.sourceFile, saved: true)
        } else if let first = library.recipes.first {
            open(first.recipe, fileURL: first.sourceFile, saved: true)
        } else {
            newRecipe()
        }
        status = "Unloaded recipe '\(recipe.id)'."
    }

    /// The header's "(Deactivated)" switch (upstream `ToggleActiveRecipeEnabledCommand`).
    func toggleActive() {
        guard let library, let recipe, let loaded = library.recipe(id: recipe.id) else { return }
        library.setEnabled(!loaded.isEnabled, recipeId: recipe.id)
        status = loaded.isEnabled ? "Deactivated '\(recipe.name)'." : "Activated '\(recipe.name)'."
    }

    private func present(_ panel: NSSavePanel) async -> NSApplication.ModalResponse {
        guard let window, window.isVisible else { return panel.runModal() }
        return await withCheckedContinuation { continuation in
            panel.beginSheetModal(for: window) { continuation.resume(returning: $0) }
        }
    }

    /// Copies the Mermaid text (upstream `CopyMermaidToClipboard`).
    func copyMermaid() {
        let text = RecipeMermaid.text(of: recipe)
        let pasteboard = NSPasteboard.general
        pasteboard.clearContents()
        pasteboard.setString(text, forType: .string)
        status = "Copied Mermaid DSL to clipboard."
    }

    /// Upstream `CopyRecipeIdCommand`.
    func copyRecipeId() {
        guard let id = recipe?.id else { return }
        let pasteboard = NSPasteboard.general
        pasteboard.clearContents()
        pasteboard.setString(id, forType: .string)
        status = "Copied recipe ID '\(id)' to the clipboard."
    }
}
