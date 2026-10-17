// Greenshot for Mac (Community) - an unofficial macOS port of Greenshot
// Copyright (C) 2026 Greenshot for Mac (Community) contributors
// SPDX-License-Identifier: GPL-3.0-or-later

import CoreGraphics
import Foundation

/// Which automation captures the user confirms first (Mac only). Any program of the user can run greenshot-cli, also
/// one without the screen recording permission: without a question, `greenshot-cli --capture fullscreen` would let it
/// take screenshots through the app's permission (a confused deputy, CWE-441), and the destinations it could rewrite
/// in the user's preferences would hand them over. A setting can't prevent that (the same program can change it), a
/// question on the screen can: another program can only answer it with the Accessibility permission.
///
/// - `cli` (greenshot-cli, a second start's command, the command the app was started with): a capture without the
///   user on the capture screen (full screen, window, last region) asks every time. Region and text captures need the
///   user to select the area anyway.
/// - Links are gated by the capture-link setting (`IPCWhitelist.captureLinkCommands`); AppleScript and Shortcuts by
///   macOS's own Automation and Shortcuts consent. The Services menu and Finder can't capture.
///
/// Wave 4: a recipe run from the command line or a link (RUN_RECIPE) that captures without the user must ask the same way.
public enum AutomationConsent {
    public static func captureNeedsConfirmation(_ mode: AutomationCaptureMode, source: IPCSource) -> Bool {
        guard source == .cli else { return false }
        switch mode {
        case .fullScreen, .window, .lastRegion: return true
        case .region, .text: return false
        }
    }

    /// RUN_RECIPE (Mac only): what a recipe started by greenshot-cli takes from the screen without the user on the
    /// capture screen, for the question ("a screenshot of the whole screen"); nil when it captures nothing, or only what
    /// the user selects. `recipe` is the recipe as it runs (`RecipeTriggerPreparer` added the trigger's Source);
    /// `variables` are the bound arguments (a pre-supplied region needs no selection).
    public static func recipeCaptureSubject(_ recipe: CaptureRecipe, variables: [String: JSONValue], source: IPCSource) -> String? {
        guard source == .cli else { return nil }
        if recipe.firstNode(ofType: WellKnownStepType.recordVideo) != nil { return "a screen recording" }
        let hasRegion = variables.keys.contains { $0.caseInsensitiveCompare("PreSuppliedRegion") == .orderedSame }
        for node in recipe.nodes where node.stepType.caseInsensitiveCompare(WellKnownStepType.source) == .orderedSame {
            let type = (node.parameters.string("SourceType") ?? "Region").trimmingCharacters(in: .whitespaces).lowercased()
            switch type {
            case "fullscreen": return "a screenshot of the whole screen"
            case "activewindow": return "a screenshot of the active window"
            case "lastregion": return "a screenshot of the last captured region"
            case "window":
                let named = ["WindowHandle", "WindowTitle", "WindowTitlePattern", "ProcessName", "TargetWindow"]
                    .contains { node.parameters.string($0)?.isEmpty == false }
                if named { return "a screenshot of a window" }
            case "region":
                if hasRegion || node.parameters.string("PreSuppliedRegion")?.isEmpty == false { return "a screenshot of a region" }
            default:
                continue
            }
        }
        return nil
    }

    /// What the question names: "the whole screen", ... English: the log, and the alert words its sentences by `mode`
    /// (`AutomationCaptureConsent`). The subjects of `recipeCaptureSubject` are compared as they are (`RecipeCaptureConsent`).
    public static func subject(of mode: AutomationCaptureMode) -> String {
        switch mode {
        case .region: return "a region"
        case .window: return "a window"
        case .fullScreen: return "the whole screen"
        case .lastRegion: return "the last captured region"
        case .text: return "the text in a region"
        }
    }

    /// The program that asked, from the names of the processes above the requesting one (nearest first; nil where a
    /// name is unknown) and the first of them that is an app: "zsh in Terminal", "Raycast", or "A program".
    public static func callerName(processNames: [String?], appName: String?) -> String {
        let first = processNames.first.flatMap { $0 }.flatMap { $0.isEmpty ? nil : $0 }
        switch (first, appName) {
        case let (process?, app?) where process.caseInsensitiveCompare(app) != .orderedSame:
            return String(localized: "\(process) in \(app)", comment: "The program that asks for a capture and the app it runs in, e.g. zsh in Terminal")
        case let (_, app?): return app
        case let (process?, nil): return process
        default: return String(localized: "A program", comment: "Starts the sentence of a capture question when the program that asks is unknown")
        }
    }
}

/// Clickjacking (security review SM-M2): a click on "Allow" of a consent question counts only when no window of another
/// program lies over the question; otherwise another program could put a window with a hole over it and let the user
/// click "Allow" without seeing the question.
public enum ConsentClickGuard {
    /// A window on the screen above the question: its owner, its frame (Quartz global points) and its opacity.
    public struct WindowAbove: Equatable, Sendable {
        public var ownerPID: Int32
        public var frame: CGRect
        public var alpha: Double

        public init(ownerPID: Int32, frame: CGRect, alpha: Double) {
            self.ownerPID = ownerPID
            self.frame = frame
            self.alpha = alpha
        }
    }

    /// True when a visible window of another process overlaps `frame`. The app's own windows don't count.
    public static func isCovered(_ frame: CGRect, by windowsAbove: [WindowAbove], ownPID: Int32) -> Bool {
        windowsAbove.contains { window in
            guard window.ownerPID != ownPID, window.alpha > 0 else { return false }
            let overlap = window.frame.intersection(frame)
            return !overlap.isNull && overlap.width > 0 && overlap.height > 0
        }
    }
}
