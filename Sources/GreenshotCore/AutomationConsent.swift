// Greenshot for Mac (Community) - an unofficial macOS port of Greenshot
// Copyright (C) 2026 Greenshot for Mac (Community) contributors
// SPDX-License-Identifier: GPL-3.0-or-later

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

    /// What the question names: "the whole screen", ...
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
        case let (process?, app?) where process.caseInsensitiveCompare(app) != .orderedSame: return "\(process) in \(app)"
        case let (_, app?): return app
        case let (process?, nil): return process
        default: return "A program"
        }
    }
}
