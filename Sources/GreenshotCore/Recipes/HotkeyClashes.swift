// Greenshot for Mac (Community) - an unofficial macOS port of Greenshot
// Copyright (C) 2026 Greenshot for Mac (Community) contributors
// Based on Greenshot, Copyright (C) 2007-2026 Thomas Braun, Jens Klingen, Robin Krom
// SPDX-License-Identifier: GPL-3.0-or-later

import Foundation

/// A hotkey with the name shown when it clashes ("Capture region", "Recipe “Upload to Jira”").
public struct NamedHotkey: Sendable, Equatable {
    public var name: String
    public var combo: KeyCombo

    public init(name: String, combo: KeyCombo) {
        self.name = name
        self.combo = combo
    }
}

/// A recipe hotkey that isn't registered, and why.
public struct RecipeHotkeyClash: Sendable, Equatable {
    public var name: String
    public var combo: KeyCombo
    public var problem: String

    public init(name: String, combo: KeyCombo, problem: String) {
        self.name = name
        self.combo = combo
        self.problem = problem
    }

    /// For the log and Settings › Recipes.
    public var text: String { "\(name) (\(combo.displayString)): \(problem)" }
}

/// Which recipe hotkeys can be registered next to the app's own (RCP-061). The hotkeys share one matcher
/// (`HotkeySequenceMatcher`), which completes a hotkey of one step before a longer one with the same beginning; so a
/// recipe hotkey equal to another hotkey, or the beginning of one, or starting with one, would take another's keys or
/// never fire. The app's hotkeys win, then the earlier recipe hotkey. Without `tellsSides` (no permission for the
/// keyboard event tap) every hotkey works with either key of its modifiers, so a left and a right key clash too.
public enum RecipeHotkeyClashes {
    public static func resolve(_ candidates: [NamedHotkey], taken: [NamedHotkey],
                               tellsSides: Bool = true) -> (kept: [Int], clashes: [RecipeHotkeyClash]) {
        var kept: [Int] = []
        var clashes: [RecipeHotkeyClash] = []
        var others = taken.map { (name: $0.name, combo: $0.combo) }
        for (index, candidate) in candidates.enumerated() {
            if let problem = problem(of: candidate, with: others, tellsSides: tellsSides) {
                clashes.append(RecipeHotkeyClash(name: candidate.name, combo: candidate.combo, problem: problem))
                continue
            }
            kept.append(index)
            others.append((name: candidate.name, combo: candidate.combo))
        }
        return (kept, clashes)
    }

    static func problem(of candidate: NamedHotkey, with others: [(name: String, combo: KeyCombo)],
                        tellsSides: Bool = true) -> String? {
        if let problem = candidate.combo.validationProblem { return problem }
        if let problem = KeyCombo.conflict(of: candidate.combo, with: others, tellsSides: tellsSides) { return problem }
        // The other way round: this hotkey is the beginning of a longer one, which would then never fire.
        let mine = [(name: candidate.name, combo: candidate.combo)]
        for other in others where KeyCombo.conflict(of: other.combo, with: mine, tellsSides: tellsSides) != nil {
            return String(localized: "It is the beginning of “\(other.name)” (\(other.combo.displayString)), which would then never fire.")
        }
        return nil
    }
}
