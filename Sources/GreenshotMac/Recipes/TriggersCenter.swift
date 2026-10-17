// Greenshot for Mac (Community) - an unofficial macOS port of Greenshot
// Copyright (C) 2026 Greenshot for Mac (Community) contributors
// Based on Greenshot, Copyright (C) 2007-2026 Thomas Braun, Jens Klingen, Robin Krom
// SPDX-License-Identifier: GPL-3.0-or-later
// Owned by RUI after the wave 4 prep.

import AppKit
import GreenshotCore

/// The recipes' place in the app: trigger sources, the approval sheet as the library's approver, the recipe switch, the
/// failure notification (RCP-060, RCP-018). Filled in by the RUI package.
@MainActor
enum RecipeAppUI {
    /// At launch, right after `app.recipes.start()` and before the menu bar icon, the hotkeys and the automation start.
    static func start(app: AppDelegate) {}
}
