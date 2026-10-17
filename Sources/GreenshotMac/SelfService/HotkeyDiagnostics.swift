// Greenshot for Mac (Community) - an unofficial macOS port of Greenshot
// Copyright (C) 2026 Greenshot for Mac (Community) contributors
// SPDX-License-Identifier: GPL-3.0-or-later

import Foundation
import GreenshotCore

/// What the last hotkey registration did, for Self-Service › Hotkeys and the setup checks (upstream
/// `HotkeySectionViewModel` reads `HotkeyManager`'s results): the hotkeys tried, with their names, and the ones macOS
/// refused. `HotkeyManager.registerAll` records every registration here.
@MainActor
enum HotkeyDiagnostics {
    struct Registration {
        var names: [String]
        var combos: [KeyCombo]
        /// Indices into `combos` that macOS refused.
        var refused: [Int]
        var date: Date
    }

    private(set) static var lastRegistration: Registration?

    static func recordRegistration(names: [String], combos: [KeyCombo], refused: [Int]) {
        lastRegistration = Registration(names: names, combos: combos, refused: refused, date: Date())
    }
}
