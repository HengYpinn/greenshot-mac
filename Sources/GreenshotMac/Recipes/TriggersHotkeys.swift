// Greenshot for Mac (Community) - an unofficial macOS port of Greenshot
// Copyright (C) 2026 Greenshot for Mac (Community) contributors
// Based on Greenshot, Copyright (C) 2007-2026 Thomas Braun, Jens Klingen, Robin Krom
// SPDX-License-Identifier: GPL-3.0-or-later
// Owned by RUI after the wave 4 prep.

import AppKit
import GreenshotCore

/// The Hotkey triggers of the recipes, registered with the app's hotkeys (`HotkeyManager.registerAll`, RCP-061/322).
/// Filled in by the RUI package.
@MainActor
enum RecipeHotkeyBindings {
    /// The recipe hotkeys to bind besides `taken` (the app's own, which win a clash); `name` reads "Recipe “Name”".
    static func current(excluding taken: [KeyCombo]) -> [(combo: KeyCombo, name: String, action: () -> Void)] { [] }
}
