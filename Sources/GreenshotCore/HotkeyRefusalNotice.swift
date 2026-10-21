// Greenshot for Mac (Community) - an unofficial macOS port of Greenshot
// Copyright (C) 2026 Greenshot for Mac (Community) contributors
// SPDX-License-Identifier: GPL-3.0-or-later

/// When the user is told about the hotkeys macOS refused ("Some hotkeys could not be registered", the text of upstream's
/// `WarningHotkeys`): when the refused hotkeys are new, not again each time the same ones are registered (Settings
/// closing, a shortcut recorder ending, a recipe hotkey changing, the configuration reloaded). A registration without
/// refusals forgets them, so a hotkey refused again later is told again.
/// The hotkeys are compared by their keys (key codes, modifiers, sides), not by how they are shown, which follows the
/// keyboard layout.
public struct HotkeyRefusalNotice: Sendable {
    private struct Refused: Hashable, Sendable {
        var name: String
        var combo: KeyCombo
    }

    /// The refused hotkeys of the registration before.
    private var previous: Set<Refused> = []

    public init() {}

    /// True when the hotkeys of this registration that macOS `refused` are told now: some were refused, and not the
    /// same ones as the last time.
    public mutating func shouldTell(_ refused: [(name: String, combo: KeyCombo)]) -> Bool {
        let current = Set(refused.map { Refused(name: $0.name, combo: $0.combo) })
        defer { previous = current }
        return !current.isEmpty && current != previous
    }
}
