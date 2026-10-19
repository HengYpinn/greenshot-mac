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
        _ = await ask(message, detail: detail, buttons: [String(localized: "OK")], style: style)
    }

    /// Upstream `ConfirmDiscardChanges`: Save, Don't Save or Cancel; true when the editor may go on.
    func confirmDiscardChanges() async -> Bool {
        guard isDirty || jsonDraft != nil, let recipe else { return true }
        let answer = await ask(String(localized: "Unsaved Changes"),
                               detail: String(localized: "\"\(recipe.name)\" has unsaved changes. Do you want to save them?"),
                               buttons: [String(localized: "Save"), String(localized: "Don't Save"), String(localized: "Cancel")])
        switch answer {
        case 0: return await save()
        case 1:
            discardChanges()
            return true
        default: return false
        }
    }

    /// Unapplied text in the JSON tab when saving: apply it, discard it, or don't save.
    func applyJSONDraftBeforeSaving() async -> Bool {
        guard let draft = jsonDraft else { return true }
        let answer = await ask(String(localized: "Apply the JSON Changes?"),
                               detail: String(localized: "The JSON tab has changes that aren't applied to the recipe yet."),
                               buttons: [String(localized: "Apply"), String(localized: "Discard"), String(localized: "Cancel")])
        switch answer {
        case 0:
            if let problem = applyJSON(draft) {
                tab = .json
                await tell(String(localized: "JSON Error"), detail: problem)
                return false
            }
            return true
        case 1:
            discardJSONDraft()
            return true
        default:
            return false
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
        panel.title = String(localized: "Open Greenshot Recipe")
        panel.allowedContentTypes = [.json]
        panel.allowsMultipleSelection = false
        if let folder = environment.runtime()?.recipesFolder, FileManager.default.fileExists(atPath: folder.path) {
            panel.directoryURL = folder
        }
        guard await present(panel) == .OK, let url = panel.url else { return }
        guard await confirmDiscardChanges() else { return }
        await openFile(url)
    }

    /// Opens a recipe file. A valid file is loaded by the library first (it asks for approval), so it runs in Greenshot;
    /// a file with problems is opened as it is, to fix them (loading it would only show the validation-error sheet,
    /// whose "Edit Recipe File" comes back here). The editor always shows what the file holds.
    func openFile(_ url: URL) async {
        let name = url.lastPathComponent
        let fileURL = RecipeEditorFiles.standardized(url)
        let read: [CaptureRecipe]
        var loadedHash: String?
        do {
            guard let data = RecipeLibrary.readRecipeFile(fileURL), let text = RecipeSerializer.text(of: data) else {
                await tell(String(localized: "Error Loading Recipe"), detail: String(localized: "The file \(name) could not be read."))
                return
            }
            loadedHash = RecipeHash.sha256Hex(data)
            read = try RecipeSerializer.decode(text: text)
        } catch {
            let problem = (error as? RecipeFormatError)?.message ?? error.localizedDescription
            await tell(String(localized: "Error Loading Recipe"), detail: String(localized: "\(name) is not a recipe:\n\(problem)"))
            return
        }
        guard let first = read.first else {
            await tell(String(localized: "Error Loading Recipe"), detail: String(localized: "\(name) holds no recipe."))
            return
        }
        let validation = RecipeValidator(contracts: contracts, gates: environment.gates()).validate(first)
        guard let library, validation.isValid else {
            openUnapproved(first, fileURL: fileURL)
            loadedSha256 = loadedHash
            let problems = validation.errors.count
            status = validation.isValid ? String(localized: "Loaded: \(name)")
                : String(localized: "\(name) has problems: \(problems) to fix before it can run.")
            return
        }
        let result = await library.loadFile(fileURL)
        let loaded = library.recipes.first { $0.sourceFile?.path == fileURL.path && $0.recipe.id.caseInsensitiveCompare(first.id) == .orderedSame }
            ?? library.extensions.first { $0.sourceFile?.path == fileURL.path }
        if let loaded {
            open(loaded.recipe, fileURL: loaded.sourceFile, saved: true)
            loadedSha256 = loadedHash
            status = String(localized: "Loaded and registered: \(name)")
        } else {
            openUnapproved(first, fileURL: fileURL)
            loadedSha256 = loadedHash
            status = String(localized: "Opened \(name); it isn't loaded in Greenshot.")
            if !result.errors.isEmpty {
                await tell(String(localized: "Recipe Not Loaded"), detail: result.errors.joined(separator: "\n"), style: .informational)
            }
        }
    }

    /// Upstream `TrySaveRecipe`: to its file, or Save As when it has none (a new or built-in recipe). False when it wasn't saved.
    @discardableResult
    func save() async -> Bool {
        guard recipe != nil else { return false }
        if jsonDraft != nil, !(await applyJSONDraftBeforeSaving()) { return false }
        guard let fileURL else { return await saveAs() }
        return await save(to: fileURL)
    }

    /// Upstream `TrySaveAsRecipe`. `freshName`: suggest a file name that isn't taken (the "Save As…" of the warning about
    /// a file with other recipes) instead of the current file's.
    @discardableResult
    func saveAs(freshName: Bool = false) async -> Bool {
        if jsonDraft != nil, !(await applyJSONDraftBeforeSaving()) { return false }
        guard let recipe else { return false }
        let fileManager = FileManager.default
        let panel = NSSavePanel()
        panel.title = recipe.kind == .extension ? String(localized: "Save Automatic Step As…") : String(localized: "Save Greenshot Recipe As…")
        panel.allowedContentTypes = [.json]
        panel.isExtensionHidden = false
        let folder = fileURL?.deletingLastPathComponent() ?? environment.runtime()?.recipesFolder
        if let folder {
            try? fileManager.createDirectory(at: folder, withIntermediateDirectories: true)
            panel.directoryURL = folder
        }
        if let fileURL, !freshName {
            panel.nameFieldStringValue = fileURL.lastPathComponent
        } else {
            let free = folder.map { RecipeEditorFiles.freeFileURL(for: recipe.id, in: $0) { fileManager.fileExists(atPath: $0.path) } }
            panel.nameFieldStringValue = free?.lastPathComponent ?? "\(recipe.id)\(RecipeSerializer.fileExtension)"
        }
        guard await present(panel) == .OK, let chosen = panel.url else { return false }
        let url = RecipeEditorFiles.recipeFileURL(for: chosen)
        // The panel asked about the name it saw; a different final name that exists is asked about here.
        if url.path != chosen.path, fileManager.fileExists(atPath: url.path) {
            let fileName = url.lastPathComponent
            let fileExtension = RecipeSerializer.fileExtension
            let answer = await ask(String(localized: "“\(fileName)” already exists. Do you want to replace it?"),
                                   detail: String(localized: "Recipe files end in \(fileExtension), so the recipe is saved as \(fileName)."),
                                   buttons: [String(localized: "Replace"), String(localized: "Cancel")])
            guard answer == 0 else { return false }
        }
        return await save(to: url)
    }

    /// Saves through the library: `save(_:to:)` for a recipe, `saveExtension(_:to:)` for an automatic step.
    private func save(to url: URL) async -> Bool {
        guard let recipe else { return false }
        guard let library else {
            await tell(String(localized: "Recipe Not Saved"),
                       detail: String(localized: "Recipes aren't running in Greenshot right now, so the recipe can't be saved."))
            return false
        }
        let target = RecipeEditorFiles.standardized(url)
        // The library writes one recipe per file: ask before other recipes of the file are removed (Save and Save As).
        let isOwnFile = fileURL.map { RecipeEditorFiles.standardized($0).path == target.path } ?? false
        switch RecipeEditorFiles.overwrite(saving: recipe, existing: try? Data(contentsOf: target),
                                           ownIds: isOwnFile ? savedRecipeIds : []) {
        case .none:
            break
        case .removes(let names):
            let list = names.map { "\"\($0)\"" }.joined(separator: ", ")
            let file = target.lastPathComponent
            let name = recipe.name
            let detail = names.count == 1
                ? String(localized: "\(file) also holds \(list). Saving writes only \"\(name)\" to it, so it is removed from the file and from Greenshot.")
                : String(localized: "\(file) also holds \(list). Saving writes only \"\(name)\" to it, so they are removed from the file and from Greenshot.")
            let answer = await ask(String(localized: "Saving Replaces Other Recipes"), detail: detail,
                                   buttons: [String(localized: "Save As…"), String(localized: "Replace File"), String(localized: "Cancel")])
            switch answer {
            case 0: return await saveAs(freshName: true)
            case 1: break
            default: return false
            }
        case .notARecipe:
            let file = target.lastPathComponent
            let answer = await ask(String(localized: "Replace a File That Isn't a Recipe?"),
                                   detail: String(localized: "\(file) is not a recipe file. Saving replaces its content with the recipe."),
                                   buttons: [String(localized: "Replace"), String(localized: "Cancel")])
            guard answer == 0 else { return false }
        }
        // What the file held before: no longer in it after the save, so no longer loaded.
        let previous = (library.recipes + library.extensions).filter { loaded in
            loaded.sourceFile.map { RecipeEditorFiles.standardized($0).path == target.path } == true
                && (loaded.recipe.id.caseInsensitiveCompare(recipe.id) != .orderedSame || loaded.recipe.kind != recipe.kind)
        }
        // A file that was never approved (rejected, or opened to fix it) gets the approval window at its first save, also
        // when the library would renew the approval of harmless triggers without asking.
        let reasons = recipe.kind == .extension ? library.extensionSaveDecisionReasons(for: recipe, at: target)
            : library.saveDecisionReasons(for: recipe, at: target, loadedSha256: target == fileURL ? loadedSha256 : nil)
        let reviewAfterSaving = openedUnapproved && reasons.isEmpty
        // The bytes the library writes; edits made while its approval window is open stay unsaved.
        let written = RecipeSerializer.encode(recipe)
        let result = recipe.kind == .extension ? await library.saveExtension(recipe, to: target) : await library.save(recipe, to: target, loadedSha256: target == fileURL ? loadedSha256 : nil)
        guard result.isValid else {
            await tell(String(localized: "Recipe Not Saved"), detail: result.errors.joined(separator: "\n"))
            status = String(localized: "The recipe was not saved.")
            return false
        }
        for loaded in previous {
            if loaded.recipe.kind == .extension {
                library.unloadExtension(id: loaded.recipe.id)
            } else {
                library.unload(recipeId: loaded.recipe.id)
            }
            log.info("Recipe '\(loaded.recipe.id)' is no longer in its file after the recipe editor saved over it; unloaded.")
        }
        markSaved(at: target, savedText: written)
        let file = target.lastPathComponent
        status = String(localized: "Saved recipe to \(file)")
        log.info("Saved recipe '\(recipe.id)' from the recipe editor.")
        if reviewAfterSaving {
            let review = recipe.kind == .extension ? await library.reviewExtensionApproval(id: recipe.id)
                : await library.reviewApproval(recipeId: recipe.id)
            if !review.isValid, !review.errors.isEmpty {
                await tell(String(localized: "Recipe Permissions"), detail: review.errors.joined(separator: "\n"), style: .informational)
            }
            refreshNotice()
        }
        return true
    }

    /// Upstream `ReviewApproval`: the approval of the saved file again, to switch triggers and permissions.
    func reviewApproval() async {
        guard let library, let recipe else { return }
        guard await confirmDiscardChanges() else { return }
        let result = await library.reviewApproval(recipeId: recipe.id)
        if !result.isValid, !result.errors.isEmpty {
            await tell(String(localized: "Recipe Permissions"), detail: result.errors.joined(separator: "\n"))
        }
        if let loaded = library.recipe(id: recipe.id) { open(loaded.recipe, fileURL: loaded.sourceFile, saved: true) }
        refreshNotice()
    }

    /// Upstream `UnloadActiveRecipe`: a file recipe is unloaded, a file that replaces a built-in gives the built-in back.
    func unloadAsking() async {
        guard let library, let recipe, let loaded = library.recipe(id: recipe.id), !loaded.isBuiltIn else { return }
        let reset = loaded.replacesBuiltIn
        let name = recipe.name
        var detail = reset ? String(localized: "Revert '\(name)' to default built-in definition?")
            : String(localized: "Unload '\(name)' from Greenshot?")
        if isDirty { detail += "\n\n" + String(localized: "Your unsaved changes are discarded.") }
        let title = reset ? String(localized: "Reset Recipe to Default") : String(localized: "Unload Recipe")
        guard await ask(title, detail: detail, buttons: [String(localized: "Yes"), String(localized: "No")], style: .informational) == 0 else {
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
        let id = recipe.id
        status = String(localized: "Unloaded recipe '\(id)'.")
    }

    /// The header's "(Deactivated)" switch (upstream `ToggleActiveRecipeEnabledCommand`).
    func toggleActive() {
        guard let library, let recipe, let loaded = library.recipe(id: recipe.id) else { return }
        library.setEnabled(!loaded.isEnabled, recipeId: recipe.id)
        let name = recipe.name
        status = loaded.isEnabled ? String(localized: "Deactivated '\(name)'.") : String(localized: "Activated '\(name)'.")
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
        OwnPasteboardWrites.recordWrite(pasteboard)
        status = String(localized: "Copied Mermaid DSL to clipboard.")
    }

    /// Upstream `CopyRecipeIdCommand`.
    func copyRecipeId() {
        guard let id = recipe?.id else { return }
        let pasteboard = NSPasteboard.general
        pasteboard.clearContents()
        pasteboard.setString(id, forType: .string)
        OwnPasteboardWrites.recordWrite(pasteboard)
        status = String(localized: "Copied recipe ID '\(id)' to the clipboard.")
    }
}
