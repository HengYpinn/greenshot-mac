// Greenshot for Mac (Community) - an unofficial macOS port of Greenshot
// Copyright (C) 2026 Greenshot for Mac (Community) contributors
// SPDX-License-Identifier: GPL-3.0-or-later

import Foundation
import Testing
@testable import GreenshotCore

@Suite("OverlayInputArming")
struct OverlayInputArmingTests {
    private let start = Date(timeIntervalSince1970: 1_000_000)

    @Test func startedByAutomationIgnoresKeysExceptEscape() {
        let arming = OverlayInputArming(requiresArming: true, shownAt: start)
        // Space (mode switch) and Return (capture) typed into another app within the second
        #expect(!arming.allowsKey(isEscape: false))
        #expect(!arming.allowsMouse)
        #expect(arming.allowsKey(isEscape: true))
    }

    @Test func keysStayIgnoredAfterTheDelayWithoutAClick() {
        var arming = OverlayInputArming(requiresArming: true, shownAt: start)
        #expect(!arming.allowsKey(isEscape: false))
        arming.mouseDown(at: start.addingTimeInterval(30))
        #expect(arming.allowsKey(isEscape: false))
    }

    @Test func aMouseDownBeforeTheDelayDoesNotArm() {
        var arming = OverlayInputArming(requiresArming: true, shownAt: start)
        let armed = arming.mouseDown(at: start.addingTimeInterval(0.5))
        #expect(!armed)
        #expect(!arming.allowsKey(isEscape: false))
        #expect(!arming.allowsMouse)
    }

    @Test func aMouseDownAfterTheDelayArms() {
        var arming = OverlayInputArming(requiresArming: true, shownAt: start)
        let armed = arming.mouseDown(at: start.addingTimeInterval(1.2))
        #expect(armed)
        #expect(arming.allowsKey(isEscape: false))
        #expect(arming.allowsMouse)
    }

    @Test func startedByTheUserTakesInputAtOnce() {
        var arming = OverlayInputArming(requiresArming: false, shownAt: start)
        #expect(arming.allowsKey(isEscape: false))
        #expect(arming.allowsMouse)
        let counted = arming.mouseDown(at: start)
        #expect(counted)
    }

    @Test func triggersOfAutomationAreNotTheUsers() {
        for type in [WellKnownTriggerType.commandline, WellKnownTriggerType.aiTool, WellKnownTriggerType.schedule,
                     WellKnownTriggerType.extension, WellKnownTriggerType.openFile, WellKnownTriggerType.clipboard, "Unknown"] {
            #expect(!OverlayInputArming.startedByUser(triggerType: type), "\(type)")
        }
        for type in ["Hotkey", "contextmenu", "Systray", "Manual", "Editor"] {
            #expect(OverlayInputArming.startedByUser(triggerType: type), "\(type)")
        }
        #expect(OverlayInputArming.startedByUser(triggerType: nil))
    }

    @Test func aRequestExpires() {
        #expect(OverlayInputArming.isRequestFresh(requestedAt: start, now: start.addingTimeInterval(2)))
        #expect(!OverlayInputArming.isRequestFresh(requestedAt: start, now: start.addingTimeInterval(31)))
        #expect(!OverlayInputArming.isRequestFresh(requestedAt: nil, now: start))
    }
}
