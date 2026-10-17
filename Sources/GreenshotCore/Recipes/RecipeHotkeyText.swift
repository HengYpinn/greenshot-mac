// Greenshot for Mac (Community) - an unofficial macOS port of Greenshot
// Copyright (C) 2026 Greenshot for Mac (Community) contributors
// Based on Greenshot, Copyright (C) 2007-2026 Thomas Braun, Jens Klingen, Robin Krom
// SPDX-License-Identifier: GPL-3.0-or-later

import Carbon.HIToolbox
import Foundation

/// Upstream hotkey text ("Ctrl + Shift + B", "Ctrl + K, C", "PrintScreen") to a Mac hotkey and back
/// (upstream `HotkeySequence.Parse`, `KeyChord.Parse`). Mapping: Ctrl/Control -> ⌘, Alt -> ⌥, Shift -> ⇧, Win -> ⌃;
/// the Mac names Cmd/Command/⌘, Option/Opt/⌥ and ⌃ are read too, so the same file works on both systems.
public enum RecipeHotkeyText {
    public static func parse(_ text: String) -> KeyCombo? {
        guard case .success(let combo) = read(text) else { return nil }
        return combo
    }

    /// Why the text is not a usable hotkey (syntax, or `KeyCombo.validationProblem`), nil when it is.
    public static func problem(with text: String) -> String? {
        switch read(text) {
        case .failure(let problem): return problem.message
        case .success(let combo): return combo.validationProblem
        }
    }

    public static func format(_ combo: KeyCombo) -> String {
        combo.chords.map { chord in
            var parts: [String] = []
            if chord.modifiers & KeyCombo.command != 0 { parts.append(modifierName("Ctrl", chord.sides.command)) }
            if chord.modifiers & KeyCombo.option != 0 { parts.append(modifierName("Alt", chord.sides.option)) }
            if chord.modifiers & KeyCombo.shift != 0 { parts.append(modifierName("Shift", chord.sides.shift)) }
            if chord.modifiers & KeyCombo.control != 0 { parts.append(modifierName("Win", chord.sides.control)) }
            parts.append(keyName(chord.keyCode))
            return parts.joined(separator: " + ")
        }.joined(separator: ", ")
    }

    // MARK: - Reading

    struct Problem: Error {
        let message: String
    }

    static func read(_ text: String) -> Result<KeyCombo, Problem> {
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty, !recipeEquals(trimmed, "None") else { return .failure(Problem(message: "No hotkey set.")) }
        let normalized = trimmed.replacingOccurrences(of: " then ", with: ",", options: .caseInsensitive)
        var chords: [KeyChord] = []
        for part in normalized.split(whereSeparator: { $0 == "," || $0 == ";" }) {
            let chordText = part.trimmingCharacters(in: .whitespaces)
            guard !chordText.isEmpty else { continue }
            switch chord(chordText) {
            case .success(let chord): chords.append(chord)
            case .failure(let problem): return .failure(problem)
            }
        }
        guard let combo = KeyCombo(chords: chords) else { return .failure(Problem(message: "No hotkey set.")) }
        return .success(combo)
    }

    private static func chord(_ text: String) -> Result<KeyChord, Problem> {
        var modifiers: UInt32 = 0
        var sides = ModifierSides()
        var key: UInt32?
        for raw in text.split(separator: "+") {
            let part = raw.trimmingCharacters(in: .whitespaces)
            guard !part.isEmpty else { continue }
            let lower = part.lowercased()
            if let modifier = modifier(lower) {
                modifiers |= modifier
                sides[modifier] = side(lower)
                continue
            }
            guard key == nil else { return .failure(Problem(message: "'\(text)' has more than one key.")) }
            guard let code = keyCode(part) else { return .failure(Problem(message: "'\(part)' is not a key Greenshot knows.")) }
            key = code
        }
        guard let key else { return .failure(Problem(message: "'\(text)' has no key, only modifiers.")) }
        return .success(KeyChord(keyCode: key, modifiers: modifiers, sides: sides))
    }

    /// Upstream `KeyChord.Parse`: the prefix decides; Ctrl is ⌘ and Win is ⌃ on the Mac.
    private static func modifier(_ lower: String) -> UInt32? {
        if lower.hasPrefix("ctrl") || lower.hasPrefix("control") || lower.hasPrefix("cmd") || lower.hasPrefix("command") || lower.hasPrefix("⌘") {
            return KeyCombo.command
        }
        if lower.hasPrefix("alt") || lower.hasPrefix("opt") || lower.hasPrefix("⌥") { return KeyCombo.option }
        if lower.hasPrefix("shift") || lower.hasPrefix("⇧") { return KeyCombo.shift }
        if lower.hasPrefix("win") || lower.hasPrefix("⌃") { return KeyCombo.control }
        return nil
    }

    /// Upstream `KeyChord.ParseLocation`: "(L)", "left", "(R)", "right".
    private static func side(_ lower: String) -> ModifierSide {
        if lower.contains("(l)") || lower.contains("left") { return .left }
        if lower.contains("(r)") || lower.contains("right") { return .right }
        return .any
    }

    private static func modifierName(_ name: String, _ side: ModifierSide) -> String {
        switch side {
        case .any: return name
        case .left: return "\(name) (L)"
        case .right: return "\(name) (R)"
        }
    }

    // MARK: - Key names

    /// Upstream `KeyChord.ParseVirtualKeyCode` aliases and .NET `Keys` names, onto the Mac's key codes. PC keys a Mac
    /// keyboard doesn't have are the keys in their place on Apple's extended keyboard: Print Screen F13, Scroll Lock
    /// F14, Pause F15, Insert Help.
    private static let keyCodes: [String: Int] = {
        var codes: [String: Int] = [
            "printscreen": kVK_F13, "prnt": kVK_F13, "print": kVK_F13, "prtscr": kVK_F13, "snapshot": kVK_F13,
            "scroll": kVK_F14, "scrolllock": kVK_F14, "pause": kVK_F15, "break": kVK_F15,
            "esc": kVK_Escape, "escape": kVK_Escape, "enter": kVK_Return, "return": kVK_Return, "tab": kVK_Tab,
            "space": kVK_Space, "spacebar": kVK_Space, "back": kVK_Delete, "backspace": kVK_Delete,
            "del": kVK_ForwardDelete, "delete": kVK_ForwardDelete, "ins": kVK_Help, "insert": kVK_Help, "help": kVK_Help,
            "caps": kVK_CapsLock, "capslock": kVK_CapsLock, "capital": kVK_CapsLock,
            "home": kVK_Home, "end": kVK_End, "pageup": kVK_PageUp, "pgup": kVK_PageUp, "prior": kVK_PageUp,
            "pagedown": kVK_PageDown, "pgdn": kVK_PageDown, "next": kVK_PageDown,
            "left": kVK_LeftArrow, "right": kVK_RightArrow, "up": kVK_UpArrow, "down": kVK_DownArrow,
            "leftarrow": kVK_LeftArrow, "rightarrow": kVK_RightArrow, "uparrow": kVK_UpArrow, "downarrow": kVK_DownArrow,
            "multiply": kVK_ANSI_KeypadMultiply, "add": kVK_ANSI_KeypadPlus, "subtract": kVK_ANSI_KeypadMinus,
            "decimal": kVK_ANSI_KeypadDecimal, "divide": kVK_ANSI_KeypadDivide,
            "oemminus": kVK_ANSI_Minus, "minus": kVK_ANSI_Minus, "-": kVK_ANSI_Minus,
            "oemplus": kVK_ANSI_Equal, "plus": kVK_ANSI_Equal, "=": kVK_ANSI_Equal,
            "oemcomma": kVK_ANSI_Comma, "comma": kVK_ANSI_Comma, "oemperiod": kVK_ANSI_Period, "period": kVK_ANSI_Period, ".": kVK_ANSI_Period,
            "oemquestion": kVK_ANSI_Slash, "oem2": kVK_ANSI_Slash, "/": kVK_ANSI_Slash,
            "oemsemicolon": kVK_ANSI_Semicolon, "oem1": kVK_ANSI_Semicolon,
            "oemquotes": kVK_ANSI_Quote, "oem7": kVK_ANSI_Quote, "'": kVK_ANSI_Quote,
            "oemopenbrackets": kVK_ANSI_LeftBracket, "oem4": kVK_ANSI_LeftBracket, "[": kVK_ANSI_LeftBracket,
            "oemclosebrackets": kVK_ANSI_RightBracket, "oem6": kVK_ANSI_RightBracket, "]": kVK_ANSI_RightBracket,
            "oempipe": kVK_ANSI_Backslash, "oem5": kVK_ANSI_Backslash, "\\": kVK_ANSI_Backslash,
            "oemtilde": kVK_ANSI_Grave, "oem3": kVK_ANSI_Grave, "`": kVK_ANSI_Grave
        ]
        let letters: [Int] = [kVK_ANSI_A, kVK_ANSI_B, kVK_ANSI_C, kVK_ANSI_D, kVK_ANSI_E, kVK_ANSI_F, kVK_ANSI_G, kVK_ANSI_H,
                              kVK_ANSI_I, kVK_ANSI_J, kVK_ANSI_K, kVK_ANSI_L, kVK_ANSI_M, kVK_ANSI_N, kVK_ANSI_O, kVK_ANSI_P,
                              kVK_ANSI_Q, kVK_ANSI_R, kVK_ANSI_S, kVK_ANSI_T, kVK_ANSI_U, kVK_ANSI_V, kVK_ANSI_W, kVK_ANSI_X,
                              kVK_ANSI_Y, kVK_ANSI_Z]
        for (offset, code) in letters.enumerated() {
            let letter = String(UnicodeScalar(UInt8(97 + offset)))
            codes[letter] = code
        }
        let digits: [Int] = [kVK_ANSI_0, kVK_ANSI_1, kVK_ANSI_2, kVK_ANSI_3, kVK_ANSI_4, kVK_ANSI_5, kVK_ANSI_6, kVK_ANSI_7, kVK_ANSI_8, kVK_ANSI_9]
        let keypad: [Int] = [kVK_ANSI_Keypad0, kVK_ANSI_Keypad1, kVK_ANSI_Keypad2, kVK_ANSI_Keypad3, kVK_ANSI_Keypad4,
                             kVK_ANSI_Keypad5, kVK_ANSI_Keypad6, kVK_ANSI_Keypad7, kVK_ANSI_Keypad8, kVK_ANSI_Keypad9]
        for digit in 0..<10 {
            codes["\(digit)"] = digits[digit]
            codes["d\(digit)"] = digits[digit]
            codes["numpad\(digit)"] = keypad[digit]
        }
        let functions: [Int] = [kVK_F1, kVK_F2, kVK_F3, kVK_F4, kVK_F5, kVK_F6, kVK_F7, kVK_F8, kVK_F9, kVK_F10,
                                kVK_F11, kVK_F12, kVK_F13, kVK_F14, kVK_F15, kVK_F16, kVK_F17, kVK_F18, kVK_F19, kVK_F20]
        for (offset, code) in functions.enumerated() {
            codes["f\(offset + 1)"] = code
        }
        return codes
    }()

    private static func keyCode(_ name: String) -> UInt32? {
        keyCodes[name.lowercased()].map { UInt32($0) }
    }

    /// The name upstream writes for a key: letters and digits as they are, PC names for the rest.
    private static func keyName(_ code: UInt32) -> String {
        let preferred: [Int: String] = [
            kVK_F13: "PrintScreen", kVK_F14: "Scroll", kVK_F15: "Pause", kVK_Escape: "Escape", kVK_Return: "Enter", kVK_Tab: "Tab",
            kVK_Space: "Space", kVK_Delete: "Back", kVK_ForwardDelete: "Delete", kVK_Help: "Insert", kVK_CapsLock: "CapsLock",
            kVK_Home: "Home", kVK_End: "End", kVK_PageUp: "PageUp", kVK_PageDown: "PageDown",
            kVK_LeftArrow: "Left", kVK_RightArrow: "Right", kVK_UpArrow: "Up", kVK_DownArrow: "Down",
            kVK_ANSI_KeypadMultiply: "Multiply", kVK_ANSI_KeypadPlus: "Add", kVK_ANSI_KeypadMinus: "Subtract",
            kVK_ANSI_KeypadDecimal: "Decimal", kVK_ANSI_KeypadDivide: "Divide",
            kVK_ANSI_Minus: "OemMinus", kVK_ANSI_Equal: "OemPlus", kVK_ANSI_Comma: "OemComma", kVK_ANSI_Period: "OemPeriod",
            kVK_ANSI_Slash: "OemQuestion", kVK_ANSI_Semicolon: "OemSemicolon", kVK_ANSI_Quote: "OemQuotes",
            kVK_ANSI_LeftBracket: "OemOpenBrackets", kVK_ANSI_RightBracket: "OemCloseBrackets", kVK_ANSI_Backslash: "OemPipe",
            kVK_ANSI_Grave: "OemTilde"
        ]
        if let name = preferred[Int(code)] { return name }
        let keypad: [Int] = [kVK_ANSI_Keypad0, kVK_ANSI_Keypad1, kVK_ANSI_Keypad2, kVK_ANSI_Keypad3, kVK_ANSI_Keypad4,
                             kVK_ANSI_Keypad5, kVK_ANSI_Keypad6, kVK_ANSI_Keypad7, kVK_ANSI_Keypad8, kVK_ANSI_Keypad9]
        if let digit = keypad.firstIndex(of: Int(code)) { return "NumPad\(digit)" }
        return KeyCombo.keyName(for: code)
    }
}
