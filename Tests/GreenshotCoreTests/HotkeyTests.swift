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
