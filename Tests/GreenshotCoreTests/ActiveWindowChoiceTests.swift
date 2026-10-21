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

    @Test func theUserAtTheCaptureGetsTheScreen() {
        // The hotkey, the menus, the editor, a test run: upstream captures the screen instead.
        for trigger in [WellKnownTriggerType.hotkey, WellKnownTriggerType.contextMenu, WellKnownTriggerType.systray,
                        WellKnownTriggerType.manual, WellKnownTriggerType.editor] {
            #expect(ActiveWindowChoice.fallback(triggerType: trigger, markedByAutomation: false, hasConsent: false) == .screen)
        }
        #expect(ActiveWindowChoice.fallback(triggerType: nil, markedByAutomation: false, hasConsent: false) == .screen)
    }

    @Test func automationNeverWidensAWindowToTheScreen() {
        // An AI tool, a command line, a link, a schedule, the browser extension: a window asked for stays a window.
        #expect(ActiveWindowChoice.fallback(triggerType: WellKnownTriggerType.aiTool, markedByAutomation: false, hasConsent: false) == .none)
        #expect(ActiveWindowChoice.fallback(triggerType: WellKnownTriggerType.aiTool, markedByAutomation: false, hasConsent: true) == .none)
        #expect(ActiveWindowChoice.fallback(triggerType: WellKnownTriggerType.commandline, markedByAutomation: false, hasConsent: false) == .none)
        #expect(ActiveWindowChoice.fallback(triggerType: WellKnownTriggerType.schedule, markedByAutomation: false, hasConsent: false) == .none)
        #expect(ActiveWindowChoice.fallback(triggerType: WellKnownTriggerType.extension, markedByAutomation: false, hasConsent: false) == .none)
        // `greenshot-cli --capture window` or a link: the built-in capture the recipe replaces carries the mark.
        #expect(ActiveWindowChoice.fallback(triggerType: WellKnownTriggerType.manual, markedByAutomation: true, hasConsent: false) == .none)
    }

    @Test func aRunThatAsksBeforeCapturingAsksForTheScreen() {
        // greenshot-cli's RUN_RECIPE allowed "the active window"; the whole screen is another question.
        #expect(ActiveWindowChoice.fallback(triggerType: WellKnownTriggerType.commandline, markedByAutomation: false, hasConsent: true) == .askForScreen)
    }
}
