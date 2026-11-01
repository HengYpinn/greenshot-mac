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

    /// What a Source step of a recipe asks for (`RecipeCaptureConsent`) when nobody selects on the capture screen.
    private func unattended(_ type: RecipeSourceValues.SourceType, named: Bool = false) -> String? {
        RecipeSourceValues.unattendedSubject(type, region: false, named: named, selectionFollows: false)
    }

    /// A recipe that replaces a built-in capture which greenshot-cli or a link started asks, like RUN_RECIPE, before it
    /// takes what the capture's own question didn't allow; the subjects are the Source step's own words.
    @Test func aReplacedCaptureOfTheCommandLineOrALinkGetsAQuestion() throws {
        let wholeScreen = try #require(unattended(.fullScreen))
        let activeWindow = try #require(unattended(.activeWindow))
        let namedWindow = try #require(unattended(.window, named: true))
        let lastRegion = try #require(unattended(.lastRegion))
        for source in [IPCSource.cli, .urlScheme] {
            let fullScreenGrant = try #require(AutomationConsent.replacedCaptureGrant(.fullScreen, source: source))
            #expect(fullScreenGrant == [wholeScreen])
            let windowGrant = try #require(AutomationConsent.replacedCaptureGrant(.window, source: source))
            #expect(Set(windowGrant) == [activeWindow, namedWindow])
            let lastRegionGrant = try #require(AutomationConsent.replacedCaptureGrant(.lastRegion, source: source))
            #expect(lastRegionGrant == [lastRegion])
        }
    }

    /// Region and text captures had no question, so their replacement asks for everything it takes without a selection;
    /// a window or the last region doesn't stand for the whole screen (a Region, Window or TextOcr Source without a
    /// selection takes it), and nothing stands for a recording.
    @Test func aReplacedCaptureIsAllowedOnlyWhatItsQuestionNamed() throws {
        for source in [IPCSource.cli, .urlScheme] {
            #expect(AutomationConsent.replacedCaptureGrant(.region, source: source) == [])
            #expect(AutomationConsent.replacedCaptureGrant(.text, source: source) == [])
            let wholeScreen = try #require(unattended(.region))
            for mode in [AutomationCaptureMode.window, .lastRegion] {
                let granted = try #require(AutomationConsent.replacedCaptureGrant(mode, source: source))
                #expect(!granted.contains(wholeScreen))
            }
            for mode in AutomationCaptureMode.allCases {
                let granted = AutomationConsent.replacedCaptureGrant(mode, source: source) ?? []
                #expect(!granted.contains("a screen recording"))
            }
        }
    }

    /// The grant as the run's `RecipeCaptureConsent`: what the capture's question named passes without asking again,
    /// anything else (here a recording) asks.
    @Test func theGrantPassesWhatTheQuestionNamedAndAsksForTheRest() async throws {
        let granted = try #require(AutomationConsent.replacedCaptureGrant(.fullScreen, source: .urlScheme))
        let wholeScreen = try #require(unattended(.fullScreen))
        let asked = AskedSubjects()
        let consent = RecipeCaptureConsent(granted: granted) { subject in
            await asked.add(subject)
            return false
        }
        let screenAllowed = await consent.allows(wholeScreen)
        #expect(screenAllowed)
        let recordingAllowed = await consent.allows("a screen recording")
        #expect(!recordingAllowed)
        let subjects = await asked.subjects
        #expect(subjects == ["a screen recording"])
    }

    private actor AskedSubjects {
        var subjects: [String] = []
        func add(_ subject: String) { subjects.append(subject) }
    }

    /// AppleScript and Shortcuts have macOS's gate; their replaced captures run as before, without a question object.
    @Test func otherSourcesGiveTheReplacedCaptureNoQuestion() {
        for source in IPCSource.allCases where source != .cli && source != .urlScheme {
            for mode in AutomationCaptureMode.allCases {
                #expect(AutomationConsent.replacedCaptureGrant(mode, source: source) == nil)
            }
        }
    }

    /// No key answers "Allow": a key event of the question's own window from just now pressed it.
    @Test func aFreshKeyOfTheQuestionPressedAllow() {
        #expect(ConsentClickGuard.pressedByKey(isKeyEvent: true, inQuestionWindow: true, age: 0.01))
    }

    /// An accessibility press (VoiceOver, Switch Control) sees whatever event came last, often the Tab of a moment ago:
    /// that one, a key of another window or a click don't count as a key press.
    @Test func anAccessibilityPressAfterAKeyIsNotAKeyPress() {
        let stale = ConsentClickGuard.pressedByKey(isKeyEvent: true, inQuestionWindow: true, age: 2)
        #expect(!stale)
        let elsewhere = ConsentClickGuard.pressedByKey(isKeyEvent: true, inQuestionWindow: false, age: 0.01)
        #expect(!elsewhere)
        let click = ConsentClickGuard.pressedByKey(isKeyEvent: false, inQuestionWindow: true, age: 0.01)
        #expect(!click)
    }

    /// A click on "Allow" counts only when the question was uncovered when the button went down and when it came up:
    /// a window over the button that goes away while the button is held doesn't make the click count.
    @Test func aClickCountsOnlyWhenUncoveredAtDownAndUp() {
        #expect(ConsentClickGuard.allowsClick(coveredAtDown: false, coveredAtUp: false))
        #expect(!ConsentClickGuard.allowsClick(coveredAtDown: true, coveredAtUp: false))
        #expect(!ConsentClickGuard.allowsClick(coveredAtDown: false, coveredAtUp: true))
        #expect(!ConsentClickGuard.allowsClick(coveredAtDown: true, coveredAtUp: true))
    }

    /// Only a mouse button going down on "Allow" itself is remembered for the press, and only until it is answered.
    @Test func theCoveredStateIsKeptOnlyForAPressOnAllow() {
        var clicks = ConsentClickState()
        clicks.mouseDown(onAllow: true, covered: true)
        let coveredAtDown = clicks.confirm(coveredNow: false)
        #expect(!coveredAtDown)
        // Answered: the next press (an accessibility press) is checked when it happens
        let pressAfterIt = clicks.confirm(coveredNow: false)
        #expect(pressAfterIt)
        clicks.mouseDown(onAllow: true, covered: false)
        let uncovered = clicks.confirm(coveredNow: false)
        #expect(uncovered)
        clicks.mouseDown(onAllow: true, covered: false)
        let coveredAtUp = clicks.confirm(coveredNow: true)
        #expect(!coveredAtUp)
    }

    /// A click on the question's text while something lay over it doesn't refuse a later press on "Allow".
    @Test func aCoveredClickElsewhereInTheQuestionIsForgotten() {
        var clicks = ConsentClickState()
        clicks.mouseDown(onAllow: false, covered: true)
        let afterTextClick = clicks.confirm(coveredNow: false)
        #expect(afterTextClick)
        clicks.mouseDown(onAllow: true, covered: true)
        clicks.mouseDown(onAllow: false, covered: false)
        let afterClickElsewhere = clicks.confirm(coveredNow: false)
        #expect(afterClickElsewhere)
        clicks.mouseDown(onAllow: true, covered: true)
        clicks.reset()
        let afterDisarming = clicks.confirm(coveredNow: false)
        #expect(afterDisarming)
    }

    /// An accessibility press (VoiceOver, Switch Control) has no mouse button going down: only the moment of the press
    /// counts.
    @Test func anAccessibilityPressIsCheckedWhenItHappens() {
        #expect(ConsentClickGuard.allowsClick(coveredAtDown: nil, coveredAtUp: false))
        #expect(!ConsentClickGuard.allowsClick(coveredAtDown: nil, coveredAtUp: true))
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
