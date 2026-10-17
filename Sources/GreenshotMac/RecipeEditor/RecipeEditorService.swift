// Greenshot for Mac (Community) - an unofficial macOS port of Greenshot
// Copyright (C) 2026 Greenshot for Mac (Community) contributors
// Based on Greenshot, Copyright (C) 2007-2026 Thomas Braun, Jens Klingen, Robin Krom
// SPDX-License-Identifier: GPL-3.0-or-later
// Owned by REDITOR after the wave 4 prep.

import AppKit
import GreenshotCore

/// Opens the recipe editor window (upstream `IRecipeEditorService`). One window; calls reuse it. Filled in by the REDITOR
/// package. Callers: RUI (menus, approval sheet), RMANAGER (manager rows and toolbar), MCP (RECIPE_EDITOR, approved proposals).
@MainActor
enum RecipeEditorService {
    /// The editor with this recipe (nil: the last one / the first recipe).
    static func openEditor(recipeId: String? = nil) {}
    /// The editor with the recipe file at `url` (manager "Edit" of a file, approval "Open in the recipe editor after
    /// saving", validation-error "Edit Recipe File").
    static func openFile(_ url: URL) {}
    /// The editor with a new recipe (manager "New Recipe").
    static func newRecipe() {}
    /// The editor with this automatic step (manager "Edit" of an automatic step, RCP-259/RCP-300).
    static func openExtension(id: String) {}
}
