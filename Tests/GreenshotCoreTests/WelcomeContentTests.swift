// Greenshot for Mac (Community) - an unofficial macOS port of Greenshot
// Copyright (C) 2026 Greenshot for Mac (Community) contributors
// SPDX-License-Identifier: GPL-3.0-or-later

import Foundation
import Testing
@testable import GreenshotCore

struct WelcomeContentTests {
    @Test func basicsAreTheFourCaptureHotkeysInUpstreamsOrder() {
        let basics = WelcomeContent.basics(HotkeySettings())
        #expect(basics.map(\.keys) == ["⌃⌥⌘4", "⌃⌥⌘5", "⌃⌥⌘3", "⌃⌥⌘6"])
        #expect(basics.first?.text == "Select a region or a window")
    }

    @Test func unsetHotkeysAreLeftOut() {
        var hotkeys = HotkeySettings()
        hotkeys.window = nil
        hotkeys.lastRegion = nil
        hotkeys.text = .defaultRegion
        let basics = WelcomeContent.basics(hotkeys)
        #expect(basics.map(\.text) == ["Select a region or a window", "Capture the whole screen"])
        var none = HotkeySettings()
        none.region = nil
        none.window = nil
        none.fullScreen = nil
        none.lastRegion = nil
        #expect(WelcomeContent.basics(none).isEmpty)
    }

    @Test func tenTipsAndTheNotificationTipOnlyWhereItApplies() {
        let tips = WelcomeContent.tips(appName: "Greenshot for Mac", showsCaptures: false)
        #expect(tips.count == 10)
        let noNotificationTip = !tips.contains { $0.contains("Notification Center") }
        #expect(noNotificationTip)
        let more = WelcomeContent.tips(appName: "Greenshot for Mac", showsCaptures: true)
        #expect(more.count == 11)
        #expect(more.last?.contains("Notification Center") == true)
        #expect(tips[9].hasPrefix("Greenshot for Mac is free and open source"))
    }

    @Test func anotherTipGoesAround() {
        let tips = ["a", "b", "c"]
        #expect(WelcomeContent.tip(tips, at: 0) == "a")
        #expect(WelcomeContent.tip(tips, at: 3) == "a")
        #expect(WelcomeContent.tip(tips, at: 5) == "c")
        #expect(WelcomeContent.tip(tips, at: -1) == "c")
        #expect(WelcomeContent.tip([], at: 2).isEmpty)
    }
}
