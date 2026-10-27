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
        arming.mouseDown(at: start.addingTimeInterval(30), clickCount: 1)
        #expect(arming.allowsKey(isEscape: false))
    }

    @Test func aMouseDownBeforeTheDelayDoesNotArm() {
        var arming = OverlayInputArming(requiresArming: true, shownAt: start)
        let armed = arming.mouseDown(at: start.addingTimeInterval(0.5), clickCount: 1)
        #expect(!armed)
        #expect(!arming.allowsKey(isEscape: false))
        #expect(!arming.allowsMouse)
    }

    @Test func aMouseDownAfterTheDelayArms() {
        var arming = OverlayInputArming(requiresArming: true, shownAt: start)
        let armed = arming.mouseDown(at: start.addingTimeInterval(1.2), clickCount: 1)
        #expect(armed)
        #expect(arming.allowsKey(isEscape: false))
        #expect(arming.allowsMouse)
    }

    /// The press that arms shows that the user is at the screen, not what to take: the text mode doesn't copy a line
    /// with that click alone.
    @Test func thePressThatArmsIsMarked() {
        var arming = OverlayInputArming(requiresArming: true, shownAt: start)
        arming.mouseDown(at: start.addingTimeInterval(0.5), clickCount: 1)
        #expect(!arming.armedByLastMouseDown)
        arming.mouseDown(at: start.addingTimeInterval(1.5), clickCount: 1)
        #expect(arming.armedByLastMouseDown)
        arming.mouseDown(at: start.addingTimeInterval(2), clickCount: 1)
        #expect(!arming.armedByLastMouseDown)
    }

    /// The second (and third) press of a double click that started with the arming press is still that gesture: a
    /// double click copies no line either.
    @Test func aDoubleClickThatStartsWithTheArmingPressStillOnlyArms() {
        var arming = OverlayInputArming(requiresArming: true, shownAt: start)
        arming.mouseDown(at: start.addingTimeInterval(1.5), clickCount: 1)
        arming.mouseDown(at: start.addingTimeInterval(1.7), clickCount: 2)
        #expect(arming.armedByLastMouseDown)
        arming.mouseDown(at: start.addingTimeInterval(1.9), clickCount: 3)
        #expect(arming.armedByLastMouseDown)
        // A new click after it counts
        arming.mouseDown(at: start.addingTimeInterval(3), clickCount: 1)
        #expect(!arming.armedByLastMouseDown)
        // and so does a later double click
        arming.mouseDown(at: start.addingTimeInterval(3.2), clickCount: 2)
        #expect(!arming.armedByLastMouseDown)
    }

    /// A double click whose first press came too early: its second press arms, and only arms.
    @Test func aDoubleClickWhoseSecondPressArmsOnlyArms() {
        var arming = OverlayInputArming(requiresArming: true, shownAt: start)
        arming.mouseDown(at: start.addingTimeInterval(0.9), clickCount: 1)
        let armed = arming.mouseDown(at: start.addingTimeInterval(1.1), clickCount: 2)
        #expect(armed)
        #expect(arming.armedByLastMouseDown)
    }

    @Test func aScreenTheUserStartedHasNoArmingPress() {
        var arming = OverlayInputArming(requiresArming: false, shownAt: start)
        arming.mouseDown(at: start.addingTimeInterval(1.5), clickCount: 1)
        #expect(!arming.armedByLastMouseDown)
    }

    @Test func startedByTheUserTakesInputAtOnce() {
        var arming = OverlayInputArming(requiresArming: false, shownAt: start)
        #expect(arming.allowsKey(isEscape: false))
        #expect(arming.allowsMouse)
        let counted = arming.mouseDown(at: start, clickCount: 1)
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

    @Test func aMarkedFlowIsNeverTheUsers() {
        // A built-in capture that automation started runs as a recipe with the menu's Manual trigger
        #expect(OverlayInputArming.startedByUser(triggerType: "Manual"))
        #expect(!OverlayInputArming.startedByUser(triggerType: "Manual", markedByAutomation: true))
        #expect(!OverlayInputArming.startedByUser(triggerType: nil, markedByAutomation: true))
        #expect(!OverlayInputArming.startedByUser(triggerType: "Hotkey", markedByAutomation: true))
    }
}

@Suite("Capture delay bounds")
struct CaptureDelayBoundsTests {
    @Test func theDelayIsClamped() {
        #expect(AppSettings.clampedCaptureDelay(35_000) == 10_000)
        #expect(AppSettings.clampedCaptureDelay(-5) == 0)
        #expect(AppSettings.clampedCaptureDelay(250) == 250)
    }

    @Test func aDelayInThePreferencesFileIsClampedWhenDecoded() throws {
        let long = try JSONDecoder().decode(AppSettings.self, from: Data(#"{"captureDelayMilliseconds": 35000}"#.utf8))
        #expect(long.captureDelayMilliseconds == 10_000)
        let negative = try JSONDecoder().decode(AppSettings.self, from: Data(#"{"captureDelayMilliseconds": -1}"#.utf8))
        #expect(negative.captureDelayMilliseconds == 0)
    }
}
