// Greenshot for Mac (Community) - an unofficial macOS port of Greenshot
// Copyright (C) 2026 Greenshot for Mac (Community) contributors
// Based on Greenshot, Copyright (C) 2007-2026 Thomas Braun, Jens Klingen, Robin Krom
// SPDX-License-Identifier: GPL-3.0-or-later
// Owned by RMANAGER after the wave 4 prep.

import Foundation

/// The automatic steps (recipe extensions) the library knows, built in and from files. Filled in by the RMANAGER package.
struct RecipeExtensionStore: Sendable {
    init() {}
}

/// Automatic steps in recipe files (upstream `Greenshot/Recipes/RecipeManager.ExtensionFiles.cs`, a partial class of the
/// recipe manager like this extension of `RecipeLibrary`). Filled in by the RMANAGER package; until then an extension
/// file is refused as before and the public members answer "none".
extension RecipeLibrary {
    // MARK: Hooks of RecipeLibrary.swift

    /// `loadFile` for a file whose recipes are automatic steps (`"kind": "extension"`).
    func loadExtensionFile(_ fileURL: URL, content: String, hash: String, definitions: [CaptureRecipe], interactive: Bool,
                           forcePrompt: Bool) async -> RecipeLoadResult {
        var result = RecipeLoadResult()
        let message = "This file is an automatic step (\"kind\": \"extension\"), not a recipe. Automatic steps aren't available in this version yet."
        result.errors.append(message)
        if interactive { await approver?.showValidationError(validationErrorRequest(fileURL, content, hash, recipe: nil, message: message)) }
        return result
    }

    /// `reload()`: the automatic steps of files are loaded again with their files.
    func forgetFileExtensions() {}

    /// `fileDidChange`: whether the file is one of the loaded automatic steps.
    func isExtensionFile(_ path: String) -> Bool { false }

    /// `fileDidChange`: the automatic steps of a changed file are not used until the change is approved (upstream
    /// `CheckChangedFile`).
    func dropExtensions(ofFile path: String) {}

    // MARK: For the other packages (names and signatures frozen by the prep)

    /// The automatic steps, built in and from files, by order then id; `recipe.kind == .extension`, `isEnabled` is the
    /// automatic step's `enabled` option (REDITOR's editor, MCP's catalog).
    public var extensions: [LoadedRecipe] { [] }

    /// Saves an automatic step from the recipe editor, with the approval rules of `save(_:to:)` (REDITOR).
    public func saveExtension(_ ext: CaptureRecipe, to url: URL) async -> RecipeLoadResult {
        var result = RecipeLoadResult()
        result.errors.append("Automatic steps aren't available in this version yet.")
        return result
    }

    /// Why saving `ext` to `url` asks for approval; empty when it doesn't (like `saveDecisionReasons(for:at:)`; REDITOR).
    public func extensionSaveDecisionReasons(for ext: CaptureRecipe, at url: URL?) -> [String] { [] }

    /// The automatic steps that plug into `slot` of `recipe` (upstream `GetSlotExtensions`), by order then id; `isOn`:
    /// switched on for this recipe (REDITOR's slot inspector).
    public func extensionsPlugging(into slot: RecipeNode, of recipe: CaptureRecipe) -> [(loaded: LoadedRecipe, isOn: Bool)] { [] }

    /// An AI tool's proposed automatic step; the frozen `propose(content:...)` refuses extensions (MCP).
    public func proposeExtension(content: String, proposedBy: String, aiRequest: String?, aiExplanation: String?,
                                 saveTo url: URL) async -> RecipeLoadResult {
        var result = RecipeLoadResult()
        result.errors.append("Automatic steps can't be proposed in this version yet.")
        return result
    }

    /// The "Changes other recipes" lines of an automatic step (upstream `ExtensionReach`; MCP's `changes_other_recipes`).
    public func describeExtensionReach(_ ext: CaptureRecipe) -> [String] { [] }
}
