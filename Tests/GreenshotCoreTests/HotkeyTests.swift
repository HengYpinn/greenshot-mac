// Greenshot for Mac (Community) - an unofficial macOS port of Greenshot
// Copyright (C) 2026 Greenshot for Mac (Community) contributors
// SPDX-License-Identifier: GPL-3.0-or-later

import Carbon.HIToolbox
import Foundation
import Testing
@testable import GreenshotCore

private let ctrlOptCmd = KeyCombo.control | KeyCombo.option | KeyCombo.command
private func chord(_ key: Int, _ modifiers: UInt32 = 0) -> KeyChord { KeyChord(keyCode: UInt32(key), modifiers: modifiers) }
private let ctrlOptCmdK = chord(kVK_ANSI_K, ctrlOptCmd)

struct HotkeyCodableTests {
    @Test func settingsOfOlderVersionsKeepTheirHotkey() throws {
        let legacy = #"{"keyCode":21,"modifiers":6400}"#
        let combo = try JSONDecoder().decode(KeyCombo.self, from: Data(legacy.utf8))
        #expect(combo == .defaultRegion && combo.followingChords.isEmpty)

        let settings = #"{"region":{"keyCode":21,"modifiers":6400},"window":null}"#
        let hotkeys = try JSONDecoder().decode(HotkeySettings.self, from: Data(settings.utf8))
        #expect(hotkeys.region == .defaultRegion && hotkeys.window == nil && hotkeys.text == nil)
        #expect(hotkeys.fullScreen == .defaultFullScreen)
    }

    @Test func oneStepIsWrittenAsBefore() throws {
        let json = String(decoding: try JSONEncoder().encode(KeyCombo.defaultRegion), as: UTF8.self)
        #expect(!json.contains("followingChords"))
    }

    @Test func stepsRoundTrip() throws {
        let combo = KeyCombo(keyCode: UInt32(kVK_ANSI_K), modifiers: ctrlOptCmd, followingChords: [chord(kVK_ANSI_C)])
        let decoded = try JSONDecoder().decode(KeyCombo.self, from: JSONEncoder().encode(combo))
        #expect(decoded == combo && decoded.isSequence && decoded.chords.count == 2)
    }

    @Test func aDamagedStepListKeepsTheHotkey() throws {
        let json = #"{"keyCode":21,"modifiers":6400,"followingChords":"nonsense"}"#
        #expect(try JSONDecoder().decode(KeyCombo.self, from: Data(json.utf8)) == .defaultRegion)
    }

    @Test func displayJoinsTheSteps() {
        #expect(KeyCombo.defaultRegion.displayString == "⌃⌥⌘4")
        let combo = KeyCombo(chords: [ctrlOptCmdK, chord(kVK_ANSI_C)])
        #expect(combo?.displayString == "⌃⌥⌘K, C")
        #expect(KeyCombo(chords: []) == nil)
    }
}

struct HotkeyValidationTests {
    @Test(arguments: [kVK_Escape, kVK_Return, kVK_Tab, kVK_ANSI_KeypadEnter])
    func reservedKeysAreRefusedWithAnyModifier(key: Int) {
        let combo = KeyCombo(keyCode: UInt32(key), modifiers: ctrlOptCmd)
        #expect(combo.validationProblem?.contains("is a reserved key") == true)
        #expect(!combo.isValidGlobalShortcut)
    }

    @Test func modifierRules() {
        #expect(KeyCombo(keyCode: UInt32(kVK_F13), modifiers: 0).validationProblem == nil)
        #expect(KeyCombo(keyCode: UInt32(kVK_F5), modifiers: KeyCombo.shift).validationProblem == nil)
        #expect(KeyCombo(keyCode: UInt32(kVK_ANSI_A), modifiers: 0).validationProblem == "Keys other than F1–F20 need ⌃, ⌥ or ⌘.")
        #expect(KeyCombo(keyCode: UInt32(kVK_ANSI_A), modifiers: KeyCombo.shift).validationProblem
                == "⇧ can't be the only modifier, except for F1–F20.")
        #expect(KeyCombo(keyCode: UInt32(kVK_ANSI_A), modifiers: KeyCombo.option).validationProblem == nil)
    }

    @Test func laterStepsNeedNoModifierButNoReservedKey() {
        #expect(KeyCombo(chords: [ctrlOptCmdK, chord(kVK_ANSI_C)])?.validationProblem == nil)
        #expect(KeyCombo(chords: [ctrlOptCmdK, chord(kVK_Tab)])?.validationProblem
                == "Step 2: ⇥ is a reserved key and can't be used in a hotkey.")
        #expect(KeyCombo(chords: [chord(kVK_ANSI_K), chord(kVK_ANSI_C)])?.validationProblem
                == "Step 1: Keys other than F1–F20 need ⌃, ⌥ or ⌘.")
    }

    @Test func conflictsWithOtherHotkeys() {
        let sequence = KeyCombo(chords: [ctrlOptCmdK, chord(kVK_ANSI_C)])!
        let single = KeyCombo(chords: [ctrlOptCmdK])!
        #expect(KeyCombo.conflict(of: .defaultRegion, with: [("Capture window", .defaultRegion)])
                == "“Capture window” has the same hotkey.")
        #expect(KeyCombo.conflict(of: sequence, with: [("Capture window", single)])?.contains("is the beginning of this hotkey") == true)
        // The shorter one is fine, it fires first.
        #expect(KeyCombo.conflict(of: single, with: [("Capture text", sequence)]) == nil)
        #expect(KeyCombo.conflict(of: .defaultRegion, with: [("Capture window", .defaultWindow)]) == nil)
    }
}

struct HotkeySequenceMatcherTests {
    private let start = Date(timeIntervalSince1970: 1000)
    private let kc = KeyCombo(chords: [ctrlOptCmdK, chord(kVK_ANSI_C)])!
    private let kr = KeyCombo(chords: [ctrlOptCmdK, chord(kVK_ANSI_R)])!

    @Test func aHotkeyOfOneStepCompletesAtOnce() {
        var matcher = HotkeySequenceMatcher(hotkeys: [.defaultRegion, kc])
        let r1 = matcher.feed(KeyCombo.defaultRegion.firstChord, at: start)
        #expect(r1 == .completed(0))
        #expect(!matcher.isPending)
        #expect(matcher.firstChords == [KeyCombo.defaultRegion.firstChord, ctrlOptCmdK])
    }

    @Test func twoStepsCompleteWithinTheTimeout() {
        var matcher = HotkeySequenceMatcher(hotkeys: [kc])
        let r2 = matcher.feed(ctrlOptCmdK, at: start)
        #expect(r2 == .pending)
        #expect(matcher.isPending)
        // The C as recorded and with any of ⌃⌥⌘ still held, then Esc.
        #expect(matcher.pendingChords.count == 9)
        #expect(matcher.pendingChords.contains(chord(kVK_ANSI_C)))
        #expect(matcher.pendingChords.contains(chord(kVK_ANSI_C, ctrlOptCmd)))
        #expect(matcher.pendingChords.last == chord(kVK_Escape))
        let r3 = matcher.feed(chord(kVK_ANSI_C, KeyCombo.command), at: start.addingTimeInterval(1))
        #expect(r3 == .completed(0))
        #expect(!matcher.isPending && matcher.pendingChords.isEmpty)
    }

    @Test func theTimeoutAndEscEndAHalfTypedHotkey() {
        var matcher = HotkeySequenceMatcher(hotkeys: [kc])
        _ = matcher.feed(ctrlOptCmdK, at: start)
        let r4 = matcher.expire(at: start.addingTimeInterval(2.4))
        #expect(!r4)
        let r5 = matcher.expire(at: start.addingTimeInterval(2.6))
        #expect(r5)
        let r6 = matcher.feed(chord(kVK_ANSI_C), at: start.addingTimeInterval(2.7))
        #expect(r6 == .ignored)

        _ = matcher.feed(ctrlOptCmdK, at: start)
        let r7 = matcher.feed(chord(kVK_Escape), at: start.addingTimeInterval(1))
        #expect(r7 == .cancelled)
        #expect(!matcher.isPending)
    }

    @Test func aLateStepStartsOver() {
        var matcher = HotkeySequenceMatcher(hotkeys: [kc])
        _ = matcher.feed(ctrlOptCmdK, at: start)
        let r8 = matcher.feed(chord(kVK_ANSI_C), at: start.addingTimeInterval(3))
        #expect(r8 == .ignored)
    }

    @Test func twoHotkeysMayShareTheFirstStep() {
        var matcher = HotkeySequenceMatcher(hotkeys: [kc, kr])
        #expect(matcher.firstChords == [ctrlOptCmdK])
        let r9 = matcher.feed(ctrlOptCmdK, at: start)
        #expect(r9 == .pending)
        #expect(Set(matcher.pendingChords.map(\.keyCode)) == [UInt32(kVK_ANSI_C), UInt32(kVK_ANSI_R), UInt32(kVK_Escape)])
        let r10 = matcher.feed(chord(kVK_ANSI_R), at: start.addingTimeInterval(0.5))
        #expect(r10 == .completed(1))
    }

    @Test func aHotkeyOfOneStepWinsOverTheStartOfALongerOne() {
        let single = KeyCombo(chords: [ctrlOptCmdK])!
        var matcher = HotkeySequenceMatcher(hotkeys: [kc, single])
        let r11 = matcher.feed(ctrlOptCmdK, at: start)
        #expect(r11 == .completed(1))
    }

    @Test func aWrongStepEndsTheHotkeyAndMayStartAnother() {
        var matcher = HotkeySequenceMatcher(hotkeys: [kc, .defaultRegion])
        _ = matcher.feed(ctrlOptCmdK, at: start)
        let r12 = matcher.feed(KeyCombo.defaultRegion.firstChord, at: start.addingTimeInterval(0.5))
        #expect(r12 == .completed(1))
        #expect(!matcher.isPending)
    }

    @Test func modifiersNotOfEitherStepDontMatch() {
        var matcher = HotkeySequenceMatcher(hotkeys: [kc])
        _ = matcher.feed(ctrlOptCmdK, at: start)
        let r13 = matcher.feed(chord(kVK_ANSI_C, KeyCombo.shift), at: start.addingTimeInterval(0.5))
        #expect(r13 == .ignored)
    }
}

/// Left and right modifier keys (CAP-034, upstream `ModifierLocation`).
struct HotkeySidesTests {
    private let rightCommand = ModifierSides(command: .right)

    @Test func todaysSettingsLoadWithEitherSide() throws {
        let combo = try JSONDecoder().decode(KeyCombo.self, from: Data(#"{"keyCode":21,"modifiers":6400}"#.utf8))
        #expect(combo.sides.isAny)
        #expect(!combo.usesSides)
        let object = try JSONSerialization.jsonObject(with: JSONEncoder().encode(combo)) as? [String: Any]
        #expect(object?["sides"] == nil)
    }

    @Test func sidesRoundTrip() throws {
        let second = KeyChord(keyCode: UInt32(kVK_ANSI_C), modifiers: KeyCombo.shift, sides: ModifierSides(shift: .left))
        let combo = KeyCombo(keyCode: UInt32(kVK_ANSI_K), modifiers: ctrlOptCmd, sides: rightCommand, followingChords: [second])
        let decoded = try JSONDecoder().decode(KeyCombo.self, from: JSONEncoder().encode(combo))
        #expect(decoded == combo)
        #expect(decoded.sides.command == .right)
        #expect(decoded.followingChords.first?.sides.shift == .left)
        #expect(decoded.usesSides)
    }

    @Test func damagedOrUnknownSidesAreEitherSide() throws {
        let unknown = #"{"keyCode":21,"modifiers":6400,"sides":{"command":"middle","control":"left"}}"#
        let combo = try JSONDecoder().decode(KeyCombo.self, from: Data(unknown.utf8))
        #expect(combo.sides == ModifierSides(control: .left))
        let damaged = #"{"keyCode":21,"modifiers":6400,"sides":"nonsense"}"#
        #expect(try JSONDecoder().decode(KeyCombo.self, from: Data(damaged.utf8)) == .defaultRegion)
    }

    @Test func aModifierTheStepDoesntUseHasNoSide() {
        let combo = KeyCombo(keyCode: UInt32(kVK_ANSI_4), modifiers: KeyCombo.control | KeyCombo.option,
                             sides: ModifierSides(option: .left, command: .right))
        #expect(combo.sides == ModifierSides(option: .left))
    }

    @Test func theSidesAreShownInWords() {
        let combo = KeyCombo(keyCode: UInt32(kVK_ANSI_4), modifiers: ctrlOptCmd, sides: ModifierSides(control: .left, command: .right))
        #expect(combo.displayString == "⌃⌥⌘4 (left ⌃, right ⌘)")
        #expect(combo.ignoringSides == .defaultRegion)
        #expect(KeyCombo.defaultRegion.displayString == "⌃⌥⌘4")
    }

    @Test func eitherSideAndOneSideClash() {
        let right = KeyCombo(keyCode: UInt32(kVK_ANSI_4), modifiers: ctrlOptCmd, sides: rightCommand)
        let left = KeyCombo(keyCode: UInt32(kVK_ANSI_4), modifiers: ctrlOptCmd, sides: ModifierSides(command: .left))
        let clash = KeyCombo.conflict(of: right, with: [("Capture region", .defaultRegion)])
        #expect(clash?.contains("same keys with either side") == true)
        #expect(KeyCombo.conflict(of: right, with: [("Capture window", left)]) == nil)
        #expect(KeyCombo.conflict(of: right, with: [("Capture window", right)]) == "“Capture window” has the same hotkey.")
    }

    @Test func leftAndRightClashWhenTheSidesCantBeToldApart() {
        // Without Accessibility and Input Monitoring both go to Carbon with either key, and only the first one fires.
        let right = KeyCombo(keyCode: UInt32(kVK_ANSI_4), modifiers: ctrlOptCmd, sides: rightCommand)
        let left = KeyCombo(keyCode: UInt32(kVK_ANSI_4), modifiers: ctrlOptCmd, sides: ModifierSides(command: .left))
        #expect(KeyCombo.conflict(of: right, with: [("Capture window", left)], tellsSides: true) == nil)
        let clash = KeyCombo.conflict(of: right, with: [("Capture window", left)], tellsSides: false)
        #expect(clash?.contains("only one of them fires") == true)
        let withEither = KeyCombo.conflict(of: right, with: [("Capture region", .defaultRegion)], tellsSides: false)
        #expect(withEither?.contains("only one of them fires") == true)
        // Also as the beginning of a longer hotkey.
        let sequence = KeyCombo(keyCode: UInt32(kVK_ANSI_4), modifiers: ctrlOptCmd, sides: rightCommand,
                                followingChords: [chord(kVK_ANSI_C)])
        #expect(KeyCombo.conflict(of: sequence, with: [("Capture region", left)], tellsSides: true) == nil)
        let beginning = KeyCombo.conflict(of: sequence, with: [("Capture region", left)], tellsSides: false)
        #expect(beginning?.contains("is the beginning of this hotkey") == true)
        // Other keys still don't clash.
        #expect(KeyCombo.conflict(of: right, with: [("Capture window", .defaultWindow)], tellsSides: false) == nil)
        #expect(KeyCombo.conflict(of: .defaultRegion, with: [("Capture window", .defaultRegion)], tellsSides: false)
                == "“Capture window” has the same hotkey.")
    }

    @Test func theDeviceFlagsTellTheSides() {
        let chord = KeyChord(keyCode: UInt32(kVK_ANSI_4), modifiers: ctrlOptCmd, sides: ModifierSides(control: .right, command: .left))
        let rightControlLeftCommand = DeviceModifierFlags.rightControl | DeviceModifierFlags.leftCommand
        let leftControlLeftCommand = DeviceModifierFlags.leftControl | DeviceModifierFlags.leftCommand
        let both = rightControlLeftCommand | DeviceModifierFlags.leftControl
        #expect(chord.sidesMatch(deviceFlags: rightControlLeftCommand))
        #expect(!chord.sidesMatch(deviceFlags: leftControlLeftCommand))
        #expect(chord.sidesMatch(deviceFlags: both))
        #expect(!chord.sidesMatch(deviceFlags: 0))
        #expect(KeyCombo.defaultRegion.firstChord.sidesMatch(deviceFlags: 0))
    }

    @Test func recordingKeepsTheSideOnlyWhereOneWasChosen() {
        let pressed = DeviceModifierFlags.rightCommand | DeviceModifierFlags.leftOption | DeviceModifierFlags.leftControl
        let chosen = ModifierSides(control: .any, command: .left)
        let sides = ModifierSides.recorded(chosen: chosen, modifiers: ctrlOptCmd, deviceFlags: pressed)
        #expect(sides == ModifierSides(command: .right))
        // Both keys held: the side chosen before stays.
        let bothCommands = pressed | DeviceModifierFlags.leftCommand
        #expect(ModifierSides.recorded(chosen: chosen, modifiers: ctrlOptCmd, deviceFlags: bothCommands) == ModifierSides(command: .left))
    }

    @Test func theMatcherChecksTheSidesOfTappedKeys() {
        let right = KeyCombo(keyCode: UInt32(kVK_ANSI_4), modifiers: ctrlOptCmd, sides: rightCommand)
        var matcher = HotkeySequenceMatcher(hotkeys: [right])
        let pressed = chord(kVK_ANSI_4, ctrlOptCmd)
        let now = Date()
        #expect(matcher.feed(pressed, deviceFlags: DeviceModifierFlags.leftCommand, at: now) == .ignored)
        #expect(matcher.feed(pressed, deviceFlags: DeviceModifierFlags.rightCommand, at: now) == .completed(0))
        // Carbon doesn't know the sides.
        #expect(matcher.feed(pressed, at: now) == .completed(0))
    }

    @Test func aSidedSequenceCompletes() {
        let second = KeyChord(keyCode: UInt32(kVK_ANSI_C), modifiers: KeyCombo.shift, sides: ModifierSides(shift: .right))
        let combo = KeyCombo(keyCode: UInt32(kVK_ANSI_K), modifiers: ctrlOptCmd, followingChords: [second])
        var matcher = HotkeySequenceMatcher(hotkeys: [combo])
        let now = Date()
        #expect(matcher.feed(ctrlOptCmdK, deviceFlags: DeviceModifierFlags.leftCommand, at: now) == .pending)
        #expect(matcher.feed(chord(kVK_ANSI_C, KeyCombo.shift), deviceFlags: DeviceModifierFlags.rightShift, at: now) == .completed(0))
    }
}

/// Hotkeys are named by the keyboard layout: the key the user presses, not the US key at its place (SHL-3). The layout
/// is given, never this Mac's.
struct HotkeyKeyNameTests {
    /// German: Y and Z swapped, ß and Ö where the US layout has - and ;.
    private let german: [UInt32: String] = [UInt32(kVK_ANSI_Y): "z", UInt32(kVK_ANSI_Z): "y", UInt32(kVK_ANSI_Minus): "ß",
                                            UInt32(kVK_ANSI_Semicolon): "ö", UInt32(kVK_ANSI_4): "4"]
    /// French: A where the US layout has Q, an apostrophe on the digit row.
    private let french: [UInt32: String] = [UInt32(kVK_ANSI_Q): "a", UInt32(kVK_ANSI_4): "'"]

    @Test func lettersAndPunctuationAreNamedByTheLayout() {
        #expect(KeyCombo.displayKeyName(for: UInt32(kVK_ANSI_Y), layoutNames: german) == "Z")
        #expect(KeyCombo.displayKeyName(for: UInt32(kVK_ANSI_Z), layoutNames: german) == "Y")
        #expect(KeyCombo.displayKeyName(for: UInt32(kVK_ANSI_Semicolon), layoutNames: german) == "Ö")
        // An upper case of two letters keeps the key's own letter.
        #expect(KeyCombo.displayKeyName(for: UInt32(kVK_ANSI_Minus), layoutNames: german) == "ß")
        #expect(KeyCombo.displayKeyName(for: UInt32(kVK_ANSI_Q), layoutNames: french) == "A")
        let combo = KeyCombo(keyCode: UInt32(kVK_ANSI_Y), modifiers: ctrlOptCmd, followingChords: [chord(kVK_ANSI_Q)])
        #expect(combo.displayString(layoutNames: german) == "⌃⌥⌘Z, Q")
        #expect(combo.displayString(layoutNames: french) == "⌃⌥⌘Y, A")
    }

    @Test func digitsAndOtherKeysKeepTheirNames() {
        // The digit row of a French keyboard types ' without ⇧; the key is still the 4.
        #expect(KeyCombo.displayKeyName(for: UInt32(kVK_ANSI_4), layoutNames: french) == "4")
        #expect(KeyCombo.defaultRegion.displayString(layoutNames: french) == "⌃⌥⌘4")
        let odd: [UInt32: String] = [UInt32(kVK_F5): "x", UInt32(kVK_ANSI_A): "", UInt32(kVK_ANSI_B): "\u{10}",
                                     UInt32(kVK_ANSI_C): " ", UInt32(kVK_ANSI_D): "ab"]
        #expect(KeyCombo.displayKeyName(for: UInt32(kVK_F5), layoutNames: odd) == "F5")
        // Nothing, a control character, a space or several characters: the US name.
        #expect(KeyCombo.displayKeyName(for: UInt32(kVK_ANSI_A), layoutNames: odd) == "A")
        #expect(KeyCombo.displayKeyName(for: UInt32(kVK_ANSI_B), layoutNames: odd) == "B")
        #expect(KeyCombo.displayKeyName(for: UInt32(kVK_ANSI_C), layoutNames: odd) == "C")
        #expect(KeyCombo.displayKeyName(for: UInt32(kVK_ANSI_D), layoutNames: odd) == "D")
        // Without a layout, the US names.
        #expect(KeyCombo.displayKeyName(for: UInt32(kVK_ANSI_Y), layoutNames: [:]) == "Y")
    }

    @Test func dataStaysEnglish() {
        // Recipe hotkey texts are read back with these names.
        #expect(KeyCombo.keyName(for: UInt32(kVK_ANSI_Y)) == "Y")
    }
}
