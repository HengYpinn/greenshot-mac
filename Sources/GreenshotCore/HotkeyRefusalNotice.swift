// Greenshot for Mac (Community) - an unofficial macOS port of Greenshot
// Copyright (C) 2026 Greenshot for Mac (Community) contributors
// SPDX-License-Identifier: GPL-3.0-or-later

/// When the user is told about the hotkeys macOS refused ("Some hotkeys could not be registered", the text of upstream's
/// `WarningHotkeys`): when the refused hotkeys are new, not again each time the same ones are registered (Settings
/// closing, a shortcut recorder ending, a recipe hotkey changing, the configuration reloaded). A registration without
/// refusals forgets them, so a hotkey refused again later is told again.
public struct HotkeyRefusalNotice: Sendable {
    /// The refused hotkeys of the registration before.
    private var previous: Set<String> = []

    public init() {}

    /// True when the hotkeys of this registration that macOS `refused` (one text for each) are told now: some were
    /// refused, and not the same ones as the last time.
    public mutating func shouldTell(_ refused: [String]) -> Bool {
        let current = Set(refused)
        defer { previous = current }
        return !current.isEmpty && current != previous
    }
}
