// Greenshot for Mac (Community) - an unofficial macOS port of Greenshot
// Copyright (C) 2026 Greenshot for Mac (Community) contributors
// Based on Greenshot, Copyright (C) 2007-2026 Thomas Braun, Jens Klingen, Robin Krom
// SPDX-License-Identifier: GPL-3.0-or-later

import Carbon.HIToolbox

/// Which of the two keys of a modifier a hotkey needs (upstream `Greenshot.Base/Core/ModifierLocation.cs`).
public enum ModifierSide: String, Codable, CaseIterable, Sendable {
    /// Either key, as every hotkey before.
    case any
    case left
    case right

    public init(from decoder: Decoder) throws {
        // A side this version doesn't know is either side.
        self = ModifierSide(rawValue: try decoder.singleValueContainer().decode(String.self)) ?? .any
    }
}

/// The side of each modifier of a step (upstream `KeyChord.CtrlLocation`, `AltLocation`, `ShiftLocation`,
/// `WinLocation`). Hotkeys that need a side can't go through Carbon, which doesn't tell the keys apart; they need the
/// app's keyboard event tap (Accessibility or Input Monitoring).
public struct ModifierSides: Codable, Hashable, Sendable {
    public var control: ModifierSide
    public var option: ModifierSide
    public var shift: ModifierSide
    public var command: ModifierSide

    public init(control: ModifierSide = .any, option: ModifierSide = .any, shift: ModifierSide = .any, command: ModifierSide = .any) {
        self.control = control
        self.option = option
        self.shift = shift
        self.command = command
    }

    /// Either key of every modifier.
    public static let any = ModifierSides()

    public var isAny: Bool { self == .any }

    /// The modifiers as Carbon flags, in the order the Mac shows them.
    public static let modifiers: [UInt32] = [KeyCombo.control, KeyCombo.option, KeyCombo.shift, KeyCombo.command]

    /// The side of `modifier` (a Carbon flag).
    public subscript(modifier: UInt32) -> ModifierSide {
        get {
            switch modifier {
            case KeyCombo.control: return control
            case KeyCombo.option: return option
            case KeyCombo.shift: return shift
            case KeyCombo.command: return command
            default: return .any
            }
        }
        set {
            switch modifier {
            case KeyCombo.control: control = newValue
            case KeyCombo.option: option = newValue
            case KeyCombo.shift: shift = newValue
            case KeyCombo.command: command = newValue
            default: break
            }
        }
    }

    /// Only the sides of the modifiers in `modifiers` (Carbon flags): a modifier the step doesn't use has no side.
    public func limited(to modifiers: UInt32) -> ModifierSides {
        var result = ModifierSides.any
        for modifier in Self.modifiers where modifiers & modifier != 0 { result[modifier] = self[modifier] }
        return result
    }

    /// The sides of the step typed while recording, from the device flags of the key event (`deviceFlags`): only for
    /// a modifier whose side was chosen before (`chosen`), like upstream's recorder; the others stay either side.
    public static func recorded(chosen: ModifierSides, modifiers: UInt32, deviceFlags: UInt64) -> ModifierSides {
        var result = ModifierSides.any
        for modifier in Self.modifiers where modifiers & modifier != 0 && chosen[modifier] != .any {
            let masks = DeviceModifierFlags.masks(of: modifier)
            let left = deviceFlags & masks.left != 0
            let right = deviceFlags & masks.right != 0
            result[modifier] = left && !right ? .left : (right && !left ? .right : chosen[modifier])
        }
        return result
    }

    /// "right ⌘", "left ⌃, right ⌘"; empty for either side.
    public var displayString: String {
        let symbols: [UInt32: String] = [KeyCombo.control: "⌃", KeyCombo.option: "⌥", KeyCombo.shift: "⇧", KeyCombo.command: "⌘"]
        return Self.modifiers.compactMap { modifier -> String? in
            guard let symbol = symbols[modifier] else { return nil }
            switch self[modifier] {
            case .any: return nil
            case .left: return String(localized: "left \(symbol)", comment: "Only the left key of a modifier counts, e.g. left ⌘")
            case .right: return String(localized: "right \(symbol)", comment: "Only the right key of a modifier counts, e.g. right ⌘")
            }
        }.joined(separator: ", ")
    }

    // Tolerant, and only the sides that aren't "either" are written.
    enum CodingKeys: String, CodingKey { case control, option, shift, command }

    public init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        func side(_ key: CodingKeys) -> ModifierSide { (try? c.decodeIfPresent(ModifierSide.self, forKey: key)) ?? .any }
        self.init(control: side(.control), option: side(.option), shift: side(.shift), command: side(.command))
    }

    public func encode(to encoder: Encoder) throws {
        var c = encoder.container(keyedBy: CodingKeys.self)
        if control != .any { try c.encode(control, forKey: .control) }
        if option != .any { try c.encode(option, forKey: .option) }
        if shift != .any { try c.encode(shift, forKey: .shift) }
        if command != .any { try c.encode(command, forKey: .command) }
    }
}

/// The device-dependent modifier bits of a key event (`CGEventFlags`, `NSEvent.ModifierFlags` raw values), which tell the
/// left key from the right one (IOKit `IOLLEvent.h` `NX_DEVICE*KEYMASK`).
public enum DeviceModifierFlags {
    public static let leftControl: UInt64 = 0x0000_0001
    public static let leftShift: UInt64 = 0x0000_0002
    public static let rightShift: UInt64 = 0x0000_0004
    public static let leftCommand: UInt64 = 0x0000_0008
    public static let rightCommand: UInt64 = 0x0000_0010
    public static let leftOption: UInt64 = 0x0000_0020
    public static let rightOption: UInt64 = 0x0000_0040
    public static let rightControl: UInt64 = 0x0000_2000

    /// The left and right bit of `modifier` (a Carbon flag).
    public static func masks(of modifier: UInt32) -> (left: UInt64, right: UInt64) {
        switch modifier {
        case KeyCombo.control: return (leftControl, rightControl)
        case KeyCombo.option: return (leftOption, rightOption)
        case KeyCombo.shift: return (leftShift, rightShift)
        case KeyCombo.command: return (leftCommand, rightCommand)
        default: return (0, 0)
        }
    }
}

/// One key with its modifiers: a step of a hotkey (upstream `Greenshot.Base/Core/KeyChord.cs`). The modifiers are
/// Carbon flags, as `RegisterEventHotKey` takes them; `sides` says when only the left or the right key of a modifier
/// counts (upstream `ModifierLocation`).
public struct KeyChord: Codable, Hashable, Sendable {
    public var keyCode: UInt32
    public var modifiers: UInt32
    /// Only for modifiers in `modifiers`.
    public var sides: ModifierSides {
        didSet { sides = sides.limited(to: modifiers) }
    }

    public init(keyCode: UInt32, modifiers: UInt32, sides: ModifierSides = .any) {
        self.keyCode = keyCode
        self.modifiers = modifiers
        self.sides = sides.limited(to: modifiers)
    }

    /// "⌃⌥⌘K", with sides "⌃⌥⌘K (right ⌘)".
    public var displayString: String { displayString(layoutNames: KeyCombo.layoutNames) }

    /// `displayString` with the key named by `layoutNames` (`KeyCombo.displayKeyName(for:layoutNames:)`).
    public func displayString(layoutNames: [UInt32: String]) -> String {
        var result = ""
        if modifiers & KeyCombo.control != 0 { result += "⌃" }
        if modifiers & KeyCombo.option != 0 { result += "⌥" }
        if modifiers & KeyCombo.shift != 0 { result += "⇧" }
        if modifiers & KeyCombo.command != 0 { result += "⌘" }
        result += KeyCombo.displayKeyName(for: keyCode, layoutNames: layoutNames)
        return sides.isAny ? result : "\(result) (\(sides.displayString))"
    }

    public var isFunctionKey: Bool { KeyCombo.functionKeys.contains(Int(keyCode)) }

    /// The keys pressed, as `deviceFlags` of the key event tell them, are on the sides this step needs. Both keys held
    /// count for either side, like upstream `MatchChord`.
    public func sidesMatch(deviceFlags: UInt64) -> Bool {
        ModifierSides.modifiers.allSatisfy { modifier in
            let masks = DeviceModifierFlags.masks(of: modifier)
            switch sides[modifier] {
            case .any: return true
            case .left: return deviceFlags & masks.left != 0
            case .right: return deviceFlags & masks.right != 0
            }
        }
    }

    /// The same keys, either side of each modifier.
    public var ignoringSides: KeyChord { KeyChord(keyCode: keyCode, modifiers: modifiers) }

    /// Pressing one of them can be the other: the same keys, and no modifier on opposite sides.
    public func overlaps(_ other: KeyChord) -> Bool {
        guard keyCode == other.keyCode, modifiers == other.modifiers else { return false }
        return ModifierSides.modifiers.allSatisfy { modifier in
            let mine = sides[modifier]
            let theirs = other.sides[modifier]
            return mine == theirs || mine == .any || theirs == .any
        }
    }

    enum CodingKeys: String, CodingKey { case keyCode, modifiers, sides }

    public init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        let keyCode = try c.decode(UInt32.self, forKey: .keyCode)
        let modifiers = try c.decode(UInt32.self, forKey: .modifiers)
        let sides = (try? c.decodeIfPresent(ModifierSides.self, forKey: .sides)) ?? .any
        self.init(keyCode: keyCode, modifiers: modifiers, sides: sides)
    }

    public func encode(to encoder: Encoder) throws {
        var c = encoder.container(keyedBy: CodingKeys.self)
        try c.encode(keyCode, forKey: .keyCode)
        try c.encode(modifiers, forKey: .modifiers)
        if !sides.isAny { try c.encode(sides, forKey: .sides) }
    }
}

/// A global keyboard shortcut: a key code and Carbon modifier flags, as `RegisterEventHotKey` takes them, optionally
/// followed by more keys (upstream `HotkeySequence`, e.g. "Ctrl + K, C"). A hotkey of one step is stored as before,
/// `{"keyCode": …, "modifiers": …}`, so older settings keep loading and stay the same.
public struct KeyCombo: Codable, Hashable, Sendable {
    public var keyCode: UInt32
    public var modifiers: UInt32
    /// The sides of the first step's modifiers (upstream `ModifierLocation`); written only when one isn't "either".
    public var sides: ModifierSides {
        didSet { sides = sides.limited(to: modifiers) }
    }
    /// The keys pressed after this one, each within `HotkeySequenceMatcher.chordTimeout` of the one before. Empty for a
    /// hotkey of one step.
    public var followingChords: [KeyChord]

    public init(keyCode: UInt32, modifiers: UInt32, sides: ModifierSides = .any, followingChords: [KeyChord] = []) {
        self.keyCode = keyCode
        self.modifiers = modifiers
        self.sides = sides.limited(to: modifiers)
        self.followingChords = followingChords
    }

    /// The hotkey of these steps; nil without any.
    public init?(chords: [KeyChord]) {
        guard let first = chords.first else { return nil }
        self.init(keyCode: first.keyCode, modifiers: first.modifiers, sides: first.sides, followingChords: Array(chords.dropFirst()))
    }

    public var firstChord: KeyChord { KeyChord(keyCode: keyCode, modifiers: modifiers, sides: sides) }
    /// Every step, the first one first.
    public var chords: [KeyChord] { [firstChord] + followingChords }
    /// More than one step.
    public var isSequence: Bool { !followingChords.isEmpty }

    /// A step needs the left or the right key of a modifier: the hotkey goes through the keyboard event tap.
    public var usesSides: Bool { chords.contains { !$0.sides.isAny } }

    /// The same keys, either side of every modifier: how such a hotkey works without the event tap's permission.
    public var ignoringSides: KeyCombo { KeyCombo(chords: chords.map(\.ignoringSides)) ?? self }

    /// The step at `index` replaced by `chord` (sides chosen in the settings).
    public func replacing(step index: Int, with chord: KeyChord) -> KeyCombo {
        var steps = chords
        guard steps.indices.contains(index) else { return self }
        steps[index] = chord
        return KeyCombo(chords: steps) ?? self
    }

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
    public var displayString: String { displayString(layoutNames: Self.layoutNames) }

    /// `displayString` with the keys named by `layoutNames` (`displayKeyName(for:layoutNames:)`).
    public func displayString(layoutNames: [UInt32: String]) -> String {
        chords.map { $0.displayString(layoutNames: layoutNames) }.joined(separator: ", ")
    }

    // MARK: Codable

    enum CodingKeys: String, CodingKey { case keyCode, modifiers, sides, followingChords }

    public init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        let keyCode = try c.decode(UInt32.self, forKey: .keyCode)
        let modifiers = try c.decode(UInt32.self, forKey: .modifiers)
        // Missing in settings of older versions; damaged sides or steps don't cost the user the hotkey.
        let sides = (try? c.decodeIfPresent(ModifierSides.self, forKey: .sides)) ?? .any
        let following = (try? c.decodeIfPresent([KeyChord].self, forKey: .followingChords)) ?? []
        self.init(keyCode: keyCode, modifiers: modifiers, sides: sides, followingChords: following)
    }

    public func encode(to encoder: Encoder) throws {
        var c = encoder.container(keyedBy: CodingKeys.self)
        try c.encode(keyCode, forKey: .keyCode)
        try c.encode(modifiers, forKey: .modifiers)
        if !sides.isAny { try c.encode(sides, forKey: .sides) }
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
            // A hotkey of several steps names the step: one whole sentence for each case, so it can be translated.
            let step = steps.count > 1 ? index + 1 : nil
            if Self.reservedKeys.contains(Int(chord.keyCode)) {
                let key = Self.displayKeyName(for: chord.keyCode)
                guard let step else { return String(localized: "\(key) is a reserved key and can't be used in a hotkey.") }
                return String(localized: "Step \(step): \(key) is a reserved key and can't be used in a hotkey.")
            }
            guard index == 0, !chord.isFunctionKey, chord.modifiers & (Self.control | Self.option | Self.command) == 0 else { continue }
            if chord.modifiers & Self.shift != 0 {
                guard let step else { return String(localized: "⇧ can't be the only modifier, except for F1–F20.") }
                return String(localized: "Step \(step): ⇧ can't be the only modifier, except for F1–F20.")
            }
            guard let step else { return String(localized: "Keys other than F1–F20 need ⌃, ⌥ or ⌘.") }
            return String(localized: "Step \(step): Keys other than F1–F20 need ⌃, ⌥ or ⌘.")
        }
        return nil
    }

    /// Function keys work without modifiers; any other key needs ⌃, ⌥ or ⌘ so typing isn't swallowed. Reserved keys
    /// never work (see `validationProblem`).
    public var isValidGlobalShortcut: Bool { validationProblem == nil }

    /// The problem of `combo` (named `name`) with the other hotkeys: the same hotkey twice, or another hotkey that is the
    /// beginning of this one. Upstream checks the hotkeys of one step first and finishes a sequence as soon as one is
    /// complete (`HotkeyManager.MatchHotkey`), so the longer hotkey would never fire. Without `tellsSides` (no permission
    /// for the keyboard event tap) every hotkey works with either key of its modifiers, so a left and a right key clash
    /// too: only the first of them fires. Nil when there is none.
    public static func conflict(of combo: KeyCombo, with others: [(name: String, combo: KeyCombo)],
                                tellsSides: Bool = true) -> String? {
        let steps = combo.chords
        for other in others {
            let otherSteps = other.combo.chords
            if otherSteps == steps { return String(localized: "“\(other.name)” has the same hotkey.") }
            if otherSteps.count == steps.count, overlap(steps, otherSteps, tellsSides: tellsSides) {
                guard tellsSides else {
                    return String(localized: "“\(other.name)” (\(other.combo.displayString)) has the same keys while left and right keys can't be told apart, so only one of them fires.")
                }
                return String(localized: "“\(other.name)” (\(other.combo.displayString)) has the same keys with either side, so both would fire.")
            }
            if otherSteps.count < steps.count, overlap(Array(steps.prefix(otherSteps.count)), otherSteps, tellsSides: tellsSides) {
                return String(localized: "“\(other.name)” (\(other.combo.displayString)) is the beginning of this hotkey, so this one never fires.")
            }
        }
        return nil
    }

    /// Each step of `a` can be the step of `b`: left/right sides taken into account when they can be told apart.
    private static func overlap(_ a: [KeyChord], _ b: [KeyChord], tellsSides: Bool = true) -> Bool {
        a.count == b.count && zip(a, b).allSatisfy { tellsSides ? $0.overlaps($1) : $0.ignoringSides == $1.ignoringSides }
    }

    // MARK: Key names

    static let functionKeys: Set<Int> = [kVK_F1, kVK_F2, kVK_F3, kVK_F4, kVK_F5, kVK_F6, kVK_F7, kVK_F8, kVK_F9, kVK_F10,
                                         kVK_F11, kVK_F12, kVK_F13, kVK_F14, kVK_F15, kVK_F16, kVK_F17, kVK_F18, kVK_F19, kVK_F20]

    /// The name of a key as data: English (recipe hotkey texts fall back to it, see `RecipeHotkeyText`).
    public static func keyName(for keyCode: UInt32) -> String {
        names[Int(keyCode)] ?? "Key \(keyCode)"
    }

    /// The name of a key as the user sees it (hotkeys in Settings, menus and messages): `keyName(for:)` with its words
    /// translated, a letter or punctuation key as the keyboard layout names it (`layoutNames`).
    public static func displayKeyName(for keyCode: UInt32) -> String {
        displayKeyName(for: keyCode, layoutNames: layoutNames)
    }

    /// `displayKeyName(for:)` with the names of a given keyboard layout: what a letter or punctuation key types there,
    /// a letter in upper case as on the keycap. The digits keep their names (a French keyboard types them with ⇧; the
    /// key is still the 4, like upstream's virtual keys), and a key the layout gives nothing visible keeps the US name.
    public static func displayKeyName(for keyCode: UInt32, layoutNames: [UInt32: String]) -> String {
        if layoutKeyCodes.contains(keyCode), let typed = layoutNames[keyCode], let name = keycapName(typed) { return name }
        if Int(keyCode) == kVK_Space { return String(localized: "Space", comment: "The space bar, in a hotkey such as ⌃⌥Space") }
        guard let name = names[Int(keyCode)] else {
            return String(localized: "Key \(keyCode)", comment: "A key without a name in a hotkey, by its key code")
        }
        return name
    }

    // MARK: Keyboard layout

    /// The keys a keyboard layout names: the letters and the punctuation keys, which other layouts move or label
    /// differently (the key code of the US Y is the Z of a German keyboard, the US Q the A of a French one).
    public static let layoutKeyCodes: [UInt32] = [
        kVK_ANSI_A, kVK_ANSI_B, kVK_ANSI_C, kVK_ANSI_D, kVK_ANSI_E, kVK_ANSI_F, kVK_ANSI_G, kVK_ANSI_H, kVK_ANSI_I,
        kVK_ANSI_J, kVK_ANSI_K, kVK_ANSI_L, kVK_ANSI_M, kVK_ANSI_N, kVK_ANSI_O, kVK_ANSI_P, kVK_ANSI_Q, kVK_ANSI_R,
        kVK_ANSI_S, kVK_ANSI_T, kVK_ANSI_U, kVK_ANSI_V, kVK_ANSI_W, kVK_ANSI_X, kVK_ANSI_Y, kVK_ANSI_Z,
        kVK_ANSI_Minus, kVK_ANSI_Equal, kVK_ANSI_LeftBracket, kVK_ANSI_RightBracket, kVK_ANSI_Semicolon, kVK_ANSI_Quote,
        kVK_ANSI_Comma, kVK_ANSI_Period, kVK_ANSI_Slash, kVK_ANSI_Backslash, kVK_ANSI_Grave, kVK_ISO_Section,
    ].map { UInt32($0) }

    /// One visible character as on a keycap: a letter in upper case, unless that is two letters (ß); nil otherwise.
    private static func keycapName(_ typed: String) -> String? {
        guard typed.count == 1, let character = typed.first, !character.isWhitespace,
              character.unicodeScalars.allSatisfy({ $0.properties.generalCategory != .control })
        else { return nil }
        let upper = typed.uppercased()
        return upper.count == 1 ? upper : typed
    }

    private static let layoutLock = NSLock()
    private static var currentLayoutNames: [UInt32: String] = [:]

    /// What each key of `layoutKeyCodes` types on the user's keyboard layout, for the names of hotkeys. Set by the app
    /// (`KeyboardLayoutNames`), from any thread readable; empty (the tests, the command line tools): the US names.
    public static var layoutNames: [UInt32: String] {
        get {
            layoutLock.lock()
            defer { layoutLock.unlock() }
            return currentLayoutNames
        }
        set {
            layoutLock.lock()
            defer { layoutLock.unlock() }
            currentLayoutNames = newValue
        }
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
