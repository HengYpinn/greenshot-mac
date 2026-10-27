// Greenshot for Mac (Community) - an unofficial macOS port of Greenshot
// Copyright (C) 2026 Greenshot for Mac (Community) contributors
// SPDX-License-Identifier: GPL-3.0-or-later

import Foundation
import Testing
@testable import GreenshotCore

/// The question before command line and link captures without the user (confused deputy, CWE-441).
struct AutomationConsentTests {
    @Test func commandLineCapturesWithoutTheUserAsk() {
        #expect(AutomationConsent.captureNeedsConfirmation(.fullScreen, source: .cli))
        #expect(AutomationConsent.captureNeedsConfirmation(.window, source: .cli))
        #expect(AutomationConsent.captureNeedsConfirmation(.lastRegion, source: .cli))
    }

    @Test func capturesTheUserDrivesDontAsk() {
        #expect(!AutomationConsent.captureNeedsConfirmation(.region, source: .cli))
        #expect(!AutomationConsent.captureNeedsConfirmation(.text, source: .cli))
    }

    /// Any program can open a link (`open greenshotmac://…`) and turn the capture-link setting on in the preferences,
    /// so the setting alone can't stand for the user's consent.
    @Test func linkCapturesWithoutTheUserAsk() {
        #expect(AutomationConsent.captureNeedsConfirmation(.fullScreen, source: .urlScheme))
        #expect(AutomationConsent.captureNeedsConfirmation(.window, source: .urlScheme))
        #expect(AutomationConsent.captureNeedsConfirmation(.lastRegion, source: .urlScheme))
    }

    @Test func linkCapturesTheUserDrivesDontAsk() {
        #expect(!AutomationConsent.captureNeedsConfirmation(.region, source: .urlScheme))
        #expect(!AutomationConsent.captureNeedsConfirmation(.text, source: .urlScheme))
    }

    @Test func otherSourcesHaveTheirOwnGate() {
        for source in IPCSource.allCases where source != .cli && source != .urlScheme {
            for mode in AutomationCaptureMode.allCases {
                #expect(!AutomationConsent.captureNeedsConfirmation(mode, source: source))
            }
        }
    }

    /// The question comes only when the capture can start after it: while a capture runs or a capture screen is open
    /// the user would answer for nothing, under that screen.
    @Test func aCaptureThatCantStartIsRefusedBeforeTheQuestion() {
        for source in [IPCSource.cli, .urlScheme] {
            for mode in [AutomationCaptureMode.fullScreen, .window, .lastRegion] {
                let busy = AutomationConsent.captureStart(mode, source: source, captureCanStart: false)
                #expect(busy == .refusedAsBusy)
                let free = AutomationConsent.captureStart(mode, source: source, captureCanStart: true)
                #expect(free == .afterAsking)
            }
        }
    }

    /// Without a question nothing changes: the capture itself beeps when it can't start.
    @Test func capturesWithoutAQuestionStartAsBefore() {
        for mode in [AutomationCaptureMode.region, .text] {
            let link = AutomationConsent.captureStart(mode, source: .urlScheme, captureCanStart: false)
            #expect(link == .now)
        }
        for source in [IPCSource.appleScript, .shortcuts] {
            let busy = AutomationConsent.captureStart(.fullScreen, source: source, captureCanStart: false)
            #expect(busy == .now)
        }
    }

    @Test func callerIsNamedByItsProcessAndApp() {
        #expect(AutomationConsent.callerName(processNames: ["zsh", "login"], appName: "Terminal") == "zsh in Terminal")
        #expect(AutomationConsent.callerName(processNames: ["Raycast"], appName: "Raycast") == "Raycast")
        #expect(AutomationConsent.callerName(processNames: ["python3", nil], appName: nil) == "python3")
        #expect(AutomationConsent.callerName(processNames: [nil], appName: "iTerm2") == "iTerm2")
        #expect(AutomationConsent.callerName(processNames: [], appName: nil) == "A program")
        #expect(AutomationConsent.callerName(processNames: [""], appName: nil) == "A program")
    }

    @Test func questionNamesWhatIsCaptured() {
        #expect(AutomationConsent.subject(of: .fullScreen) == "the whole screen")
        #expect(AutomationConsent.subject(of: .window) == "a window")
        #expect(AutomationConsent.subject(of: .lastRegion) == "the last captured region")
    }

    @Test func helpSaysThatCapturesAsk() {
        #expect(IPCCommandLine.cliUsage(installedPath: nil).contains("ask you to allow them first"))
    }
}
