// Greenshot for Mac (Community) - an unofficial macOS port of Greenshot
// Copyright (C) 2026 Greenshot for Mac (Community) contributors
// SPDX-License-Identifier: GPL-3.0-or-later

import Testing
@testable import GreenshotCore

struct HotkeyRefusalNoticeTests {
    private let region = "Capture region: ⌃⌥⌘4"
    private let window = "Capture window: ⌃⌥⌘5"

    /// Whether each registration in turn, with these refused hotkeys, is told.
    private func told(_ registrations: [[String]]) -> [Bool] {
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

    @Test func aRefusalThatCameBackIsToldAgain() {
        // Everything registered once; later another app takes the keys again.
        #expect(told([[region], [], [region]]) == [true, false, true])
    }
}
