// Greenshot for Mac (Community) - an unofficial macOS port of Greenshot
// Copyright (C) 2026 Greenshot for Mac (Community) contributors
// Based on Greenshot, Copyright (C) 2007-2026 Thomas Braun, Jens Klingen, Robin Krom
// SPDX-License-Identifier: GPL-3.0-or-later

import CoreGraphics
import Foundation

/// Upstream hotkey text ("Ctrl + Shift + B", "Ctrl + K, C", "PrintScreen") to a Mac hotkey and back
/// (upstream `HotkeySequence.Parse`, `KeyChord.Parse`). Mapping: Ctrl/Control -> ⌘, Alt -> ⌥, Shift -> ⇧, Win -> ⌃;
/// the Mac names Cmd/Command/⌘, Option/Opt/⌥ and ⌃ are read too, so the same file works on both systems.
public enum RecipeHotkeyText {
    public static func parse(_ text: String) -> KeyCombo? { rcoreStub() }
    /// Why the text is not a usable hotkey (syntax, or `KeyCombo.validationProblem`), nil when it is.
    public static func problem(with text: String) -> String? { rcoreStub() }
    public static func format(_ combo: KeyCombo) -> String { rcoreStub() }
}
