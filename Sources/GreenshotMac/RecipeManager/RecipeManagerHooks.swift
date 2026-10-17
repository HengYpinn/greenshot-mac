// Greenshot for Mac (Community) - an unofficial macOS port of Greenshot
// Copyright (C) 2026 Greenshot for Mac (Community) contributors
// Based on Greenshot, Copyright (C) 2007-2026 Thomas Braun, Jens Klingen, Robin Krom
// SPDX-License-Identifier: GPL-3.0-or-later
// Owned by RMANAGER after the wave 4 prep.

import AppKit
import GreenshotCore
import SwiftUI

/// The recipe manager window (upstream `IRecipeEditorService.OpenManager`). Filled in by the RMANAGER package. Callers:
/// RUI (menus), REDITOR (toolbar, ⇧⌘M), MCP (RECIPE_MANAGER).
@MainActor
enum RecipeManagerService {
    /// Opens the manager or brings it to the front, with `recipeId` selected when given.
    static func show(selecting recipeId: String? = nil) {}
}

/// Automatic steps in the running app: sets `RecipeRuntime.composeForRun` and `destinationChains`. Filled in by the
/// RMANAGER package.
@MainActor
enum RecipeAutomaticSteps {
    /// At launch, right after `app.recipes.start()`.
    static func install(on runtime: RecipeRuntime) {}
}

/// Quick Settings › "Automatic steps" (RCP-173, APP-017): appended last to the Quick Settings menu. Filled in by the
/// RMANAGER package.
@MainActor
enum RecipeQuickSettingsMenu {
    static func append(to menu: NSMenu, store: SettingsStore) {}
}

/// The automatic steps' and recipes' option sections at the bottom of Settings › Recipes (RCP-175, RCP-230, RCP-231).
/// Filled in by the RMANAGER package.
struct RecipeOptionsSections: View {
    @ObservedObject var store: SettingsStore

    var body: some View { EmptyView() }
}
