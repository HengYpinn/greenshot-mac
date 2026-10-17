// Greenshot for Mac (Community) - an unofficial macOS port of Greenshot
// Copyright (C) 2026 Greenshot for Mac (Community) contributors
// SPDX-License-Identifier: GPL-3.0-or-later

import Foundation
import Testing
@testable import GreenshotCore

/// The question before command line captures without the user (confused deputy, CWE-441).
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

    @Test func otherSourcesHaveTheirOwnGate() {
        for source in [IPCSource.urlScheme, .appleScript, .shortcuts, .services, .openWith] {
            for mode in AutomationCaptureMode.allCases {
                #expect(!AutomationConsent.captureNeedsConfirmation(mode, source: source))
            }
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
