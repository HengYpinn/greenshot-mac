// Greenshot for Mac (Community) - an unofficial macOS port of Greenshot
// Copyright (C) 2026 Greenshot for Mac (Community) contributors
// Based on Greenshot, Copyright (C) 2007-2026 Thomas Braun, Jens Klingen, Robin Krom
// SPDX-License-Identifier: GPL-3.0-or-later
// Owned by RUI after the wave 4 prep.

import AppKit
import GreenshotCore

/// The Recipes submenu of the menu bar icon (RCP-062/063, APP-011) and the editor's Recipes menu (RCP-064). Filled in by
/// the RUI package.
@MainActor
enum RecipeMenus {
    /// The menu bar icon's "Recipes" item with its submenu; nil when recipes are off.
    static func statusMenuItem(app: AppDelegate) -> NSMenuItem? { nil }
    /// The main menu's "Recipes" menu between Image and View (rebuilt when it opens).
    static func addEditorMenu(to main: NSMenu) {}
}
