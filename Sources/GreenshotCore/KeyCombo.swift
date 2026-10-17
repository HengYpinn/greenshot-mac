// Greenshot for Mac (Community) - an unofficial macOS port of Greenshot
// Copyright (C) 2026 Greenshot for Mac (Community) contributors
// Based on Greenshot, Copyright (C) 2007-2026 Thomas Braun, Jens Klingen, Robin Krom
// SPDX-License-Identifier: GPL-3.0-or-later

import Carbon.HIToolbox

/// One key with its modifiers: a step of a hotkey (upstream `Greenshot.Base/Core/KeyChord.cs`). The modifiers are
/// Carbon flags, as `RegisterEventHotKey` takes them.
public struct KeyChord: Codable, Hashable, Sendable {
    public var keyCode: UInt32
    public var modifiers: UInt32

    public init(keyCode: UInt32, modifiers: UInt32) {
        self.keyCode = keyCode
        self.modifiers = modifiers
    }

    /// "⌃⌥⌘K"
    public var displayString: String {
        var result = ""
        if modifiers & KeyCombo.control != 0 { result += "⌃" }
        if modifiers & KeyCombo.option != 0 { result += "⌥" }
        if modifiers & KeyCombo.shift != 0 { result += "⇧" }
        if modifiers & KeyCombo.command != 0 { result += "⌘" }
        return result + KeyCombo.keyName(for: keyCode)
    }

    public var isFunctionKey: Bool { KeyCombo.functionKeys.contains(Int(keyCode)) }
}

/// A global keyboard shortcut: a key code and Carbon modifier flags, as `RegisterEventHotKey` takes them, optionally
/// followed by more keys (upstream `HotkeySequence`, e.g. "Ctrl + K, C"). A hotkey of one step is stored as before,
/// `{"keyCode": …, "modifiers": …}`, so older settings keep loading and stay the same.
public struct KeyCombo: Codable, Hashable, Sendable {
    public var keyCode: UInt32
    public var modifiers: UInt32
    /// The keys pressed after this one, each within `HotkeySequenceMatcher.chordTimeout` of the one before. Empty for a
    /// hotkey of one step.
    public var followingChords: [KeyChord]

    public init(keyCode: UInt32, modifiers: UInt32, followingChords: [KeyChord] = []) {
        self.keyCode = keyCode
        self.modifiers = modifiers
        self.followingChords = followingChords
    }

    /// The hotkey of these steps; nil without any.
    public init?(chords: [KeyChord]) {
        guard let first = chords.first else { return nil }
        self.init(keyCode: first.keyCode, modifiers: first.modifiers, followingChords: Array(chords.dropFirst()))
    }

    public var firstChord: KeyChord { KeyChord(keyCode: keyCode, modifiers: modifiers) }
    /// Every step, the first one first.
    public var chords: [KeyChord] { [firstChord] + followingChords }
    /// More than one step.
    public var isSequence: Bool { !followingChords.isEmpty }

    /// The most steps a hotkey can have in the settings.
    public static let maximumSteps = 4

    public static let control = UInt32(controlKey)
    public static let option = UInt32(optionKey)
    public static let shift = UInt32(shiftKey)
    public static let command = UInt32(cmdKey)

    /// Macs have no Print Screen key and ⇧⌘3/4/5 belong to macOS, so the defaults are ⌃⌥⌘ with the same digits:
    /// 4 region, 5 window, 3 full screen, 6 last region.
    public static let defaultRegion = KeyCombo(keyCode: UInt32(kVK_ANSI_4), modifiers: control | option | command)
    public static let defaultWindow = KeyCombo(keyCode: UInt32(kVK_ANSI_5), modifiers: control | option | command)
    public static let defaultFullScreen = KeyCombo(keyCode: UInt32(kVK_ANSI_3), modifiers: control | option | command)
    public static let defaultLastRegion = KeyCombo(keyCode: UInt32(kVK_ANSI_6), modifiers: control | option | command)

    /// "⌃⌥⌘4", or "⌃⌥⌘K, C" for a hotkey of two steps (upstream joins the chords with ", " too).
    public var displayString: String {
        chords.map(\.displayString).joined(separator: ", ")
    }

    // MARK: Codable

    enum CodingKeys: String, CodingKey { case keyCode, modifiers, followingChords }

    public init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        keyCode = try c.decode(UInt32.self, forKey: .keyCode)
        modifiers = try c.decode(UInt32.self, forKey: .modifiers)
        // Missing in settings of older versions; a damaged list doesn't cost the user the hotkey.
        followingChords = (try? c.decodeIfPresent([KeyChord].self, forKey: .followingChords)) ?? []
    }

    public func encode(to encoder: Encoder) throws {
        var c = encoder.container(keyedBy: CodingKeys.self)
        try c.encode(keyCode, forKey: .keyCode)
        try c.encode(modifiers, forKey: .modifiers)
        if !followingChords.isEmpty { try c.encode(followingChords, forKey: .followingChords) }
    }

    // MARK: Validation

    /// Keys a hotkey can't use (upstream `HotkeySequence.Validate`: Escape, Return, Tab and Caps Lock).
    static let reservedKeys: Set<Int> = [kVK_Escape, kVK_Return, kVK_ANSI_KeypadEnter, kVK_Tab, kVK_CapsLock]

    /// What is wrong with this hotkey, nil when it can be used (upstream `HotkeySequence.Validate`, with the Mac's
    /// modifiers). Every step: Esc, Return, Tab and Caps Lock are reserved. The first step: F1–F20 work alone, any other
    /// key needs ⌃, ⌥ or ⌘, so typing isn't swallowed; ⇧ alone isn't enough (upstream: not for letters and digits). Later
    /// steps need no modifier, like the C of "⌃⌥⌘K, C".
    public var validationProblem: String? {
        let steps = chords
        for (index, chord) in steps.enumerated() {
            let prefix = steps.count > 1 ? "Step \(index + 1): " : ""
            if Self.reservedKeys.contains(Int(chord.keyCode)) {
                return "\(prefix)\(Self.keyName(for: chord.keyCode)) is a reserved key and can't be used in a hotkey."
            }
            guard index == 0, !chord.isFunctionKey, chord.modifiers & (Self.control | Self.option | Self.command) == 0 else { continue }
            if chord.modifiers & Self.shift != 0 {
                return "\(prefix)⇧ can't be the only modifier, except for F1–F20."
            }
            return "\(prefix)Keys other than F1–F20 need ⌃, ⌥ or ⌘."
        }
        return nil
    }

    /// Function keys work without modifiers; any other key needs ⌃, ⌥ or ⌘ so typing isn't swallowed. Reserved keys
    /// never work (see `validationProblem`).
    public var isValidGlobalShortcut: Bool { validationProblem == nil }

    /// The problem of `combo` (named `name`) with the other hotkeys: the same hotkey twice, or another hotkey that is the
    /// beginning of this one. Upstream checks the hotkeys of one step first and finishes a sequence as soon as one is
    /// complete (`HotkeyManager.MatchHotkey`), so the longer hotkey would never fire. Nil when there is none.
    public static func conflict(of combo: KeyCombo, with others: [(name: String, combo: KeyCombo)]) -> String? {
        let steps = combo.chords
        for other in others {
            let otherSteps = other.combo.chords
            if otherSteps == steps { return "“\(other.name)” has the same hotkey." }
            if otherSteps.count < steps.count, Array(steps.prefix(otherSteps.count)) == otherSteps {
                return "“\(other.name)” (\(other.combo.displayString)) is the beginning of this hotkey, so this one never fires."
            }
        }
        return nil
    }

    // MARK: Key names

    static let functionKeys: Set<Int> = [kVK_F1, kVK_F2, kVK_F3, kVK_F4, kVK_F5, kVK_F6, kVK_F7, kVK_F8, kVK_F9, kVK_F10,
                                         kVK_F11, kVK_F12, kVK_F13, kVK_F14, kVK_F15, kVK_F16, kVK_F17, kVK_F18, kVK_F19, kVK_F20]

    public static func keyName(for keyCode: UInt32) -> String {
        names[Int(keyCode)] ?? "Key \(keyCode)"
    }

    private static let names: [Int: String] = [
        kVK_ANSI_A: "A", kVK_ANSI_B: "B", kVK_ANSI_C: "C", kVK_ANSI_D: "D", kVK_ANSI_E: "E", kVK_ANSI_F: "F",
        kVK_ANSI_G: "G", kVK_ANSI_H: "H", kVK_ANSI_I: "I", kVK_ANSI_J: "J", kVK_ANSI_K: "K", kVK_ANSI_L: "L",
        kVK_ANSI_M: "M", kVK_ANSI_N: "N", kVK_ANSI_O: "O", kVK_ANSI_P: "P", kVK_ANSI_Q: "Q", kVK_ANSI_R: "R",
        kVK_ANSI_S: "S", kVK_ANSI_T: "T", kVK_ANSI_U: "U", kVK_ANSI_V: "V", kVK_ANSI_W: "W", kVK_ANSI_X: "X",
        kVK_ANSI_Y: "Y", kVK_ANSI_Z: "Z",
        kVK_ANSI_0: "0", kVK_ANSI_1: "1", kVK_ANSI_2: "2", kVK_ANSI_3: "3", kVK_ANSI_4: "4",
        kVK_ANSI_5: "5", kVK_ANSI_6: "6", kVK_ANSI_7: "7", kVK_ANSI_8: "8", kVK_ANSI_9: "9",
        kVK_ANSI_Minus: "-", kVK_ANSI_Equal: "=", kVK_ANSI_LeftBracket: "[", kVK_ANSI_RightBracket: "]",
        kVK_ANSI_Semicolon: ";", kVK_ANSI_Quote: "'", kVK_ANSI_Comma: ",", kVK_ANSI_Period: ".",
        kVK_ANSI_Slash: "/", kVK_ANSI_Backslash: "\\", kVK_ANSI_Grave: "`",
        kVK_F1: "F1", kVK_F2: "F2", kVK_F3: "F3", kVK_F4: "F4", kVK_F5: "F5", kVK_F6: "F6", kVK_F7: "F7",
        kVK_F8: "F8", kVK_F9: "F9", kVK_F10: "F10", kVK_F11: "F11", kVK_F12: "F12", kVK_F13: "F13",
        kVK_F14: "F14", kVK_F15: "F15", kVK_F16: "F16", kVK_F17: "F17", kVK_F18: "F18", kVK_F19: "F19", kVK_F20: "F20",
        kVK_Space: "Space", kVK_Return: "↩", kVK_Tab: "⇥", kVK_Delete: "⌫", kVK_ForwardDelete: "⌦", kVK_Escape: "⎋",
        kVK_CapsLock: "⇪", kVK_ANSI_KeypadEnter: "⌤",
        kVK_LeftArrow: "←", kVK_RightArrow: "→", kVK_UpArrow: "↑", kVK_DownArrow: "↓",
        kVK_Home: "↖", kVK_End: "↘", kVK_PageUp: "⇞", kVK_PageDown: "⇟",
    ]
}
