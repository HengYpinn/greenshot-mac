// Greenshot for Mac (Community) - an unofficial macOS port of Greenshot
// Copyright (C) 2026 Greenshot for Mac (Community) contributors
// SPDX-License-Identifier: GPL-3.0-or-later

import Testing
@testable import GreenshotCore

struct ActiveWindowChoiceTests {
    private let me: Int32 = 100
    /// The windows on the screen, front to back, by the process that owns them (this app's own aren't in the list).
    private let owners: [Int32] = [7, 3, 7, 5]

    @Test func theFrontWindowOfTheActiveApp() {
        #expect(ActiveWindowChoice.index(owners: owners, frontmost: 3, own: me) == 1)
        #expect(ActiveWindowChoice.index(owners: owners, frontmost: 7, own: me) == 0)
    }

    @Test func thisAppActiveTakesTheWindowBehindIt() {
        // Started from the editor or Settings: the front-most window of another app.
        #expect(ActiveWindowChoice.index(owners: owners, frontmost: me, own: me) == 0)
    }

    @Test func anActiveAppWithoutAWindowTakesNoOtherAppsWindow() {
        // The desktop clicked (Finder without windows), or an app that only has a menu bar item.
        #expect(ActiveWindowChoice.index(owners: owners, frontmost: 9, own: me) == nil)
        #expect(ActiveWindowChoice.index(owners: owners, frontmost: nil, own: me) == nil)
        #expect(ActiveWindowChoice.index(owners: [], frontmost: me, own: me) == nil)
    }
}
