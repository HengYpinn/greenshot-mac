// Greenshot for Mac (Community) - an unofficial macOS port of Greenshot
// Copyright (C) 2026 Greenshot for Mac (Community) contributors
// SPDX-License-Identifier: GPL-3.0-or-later

import Testing
@testable import GreenshotCore

struct HotkeyRefusalNoticeTests {
    private let region = (name: "Capture region", combo: KeyCombo.defaultRegion)
    private let window = (name: "Capture window", combo: KeyCombo.defaultWindow)

    /// Whether each registration in turn, with these refused hotkeys, is told.
    private func told(_ registrations: [[(name: String, combo: KeyCombo)]]) -> [Bool] {
        var notice = HotkeyRefusalNotice()
        return registrations.map { notice.shouldTell($0) }
    }

    @Test func theSameRefusalIsToldOnce() {
        // Then Settings closes, a shortcut recorder ends, a recipe hotkey changes: the same hotkeys register again.
        #expect(told([[], [region], [region], [region]]) == [false, true, false, false])
    }

    @Test func anotherRefusalIsTold() {
        #expect(told([[region], [region, window]]) == [true, true])
        // The order of the hotkeys doesn't matter.
        #expect(told([[region, window], [window, region]]) == [true, false])
    }

    @Test func otherKeysForTheSameHotkeyAreAnotherRefusal() {
        // The user picked another taken combination, or the right ⌘ instead of either.
        let rightCommand = KeyCombo(keyCode: KeyCombo.defaultRegion.keyCode, modifiers: KeyCombo.defaultRegion.modifiers,
                                    sides: ModifierSides(command: .right))
        #expect(told([[region], [(name: region.name, combo: .defaultFullScreen)]]) == [true, true])
        #expect(told([[region], [(name: region.name, combo: rightCommand)]]) == [true, true])
    }

    @Test func aRefusalThatCameBackIsToldAgain() {
        // Everything registered once; later another app takes the keys again.
        #expect(told([[region], [], [region]]) == [true, false, true])
    }
}
