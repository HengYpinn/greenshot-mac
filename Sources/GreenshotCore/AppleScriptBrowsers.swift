// Greenshot for Mac (Community) - an unofficial macOS port of Greenshot
// Copyright (C) 2026 Greenshot for Mac (Community) contributors
// Based on Greenshot, Copyright (C) 2007-2026 Thomas Braun, Jens Klingen, Robin Krom
// SPDX-License-Identifier: GPL-3.0-or-later

import Foundation

/// A browser whose tabs Greenshot can read by AppleScript, to find the Confluence pages open in it (upstream
/// `ConfluenceUtils.GetBrowserUrls` reads Firefox's address bar by UI Automation; Firefox for Mac has no AppleScript).
public struct ScriptableBrowser: Equatable, Sendable {
    public var bundleID: String
    public var name: String

    public init(bundleID: String, name: String) {
        self.bundleID = bundleID
        self.name = name
    }

    /// Safari and the Chromium browsers, which share Chrome's dictionary (windows, tabs, URL).
    public static let all = [
        ScriptableBrowser(bundleID: "com.apple.Safari", name: "Safari"),
        ScriptableBrowser(bundleID: "com.google.Chrome", name: "Google Chrome"),
        ScriptableBrowser(bundleID: "com.microsoft.edgemac", name: "Microsoft Edge"),
        ScriptableBrowser(bundleID: "com.brave.Browser", name: "Brave"),
        ScriptableBrowser(bundleID: "company.thebrowser.Browser", name: "Arc"),
        ScriptableBrowser(bundleID: "com.vivaldi.Vivaldi", name: "Vivaldi"),
        ScriptableBrowser(bundleID: "org.chromium.Chromium", name: "Chromium"),
    ]

    /// The addresses of all tabs of all windows, one per line.
    public var tabURLsScript: AppleScriptCall {
        AppleScriptCall(source: """
        on run argv
            set answer to {}
            tell application id "\(bundleID)"
                repeat with aWindow in windows
                    try
                        repeat with aTab in tabs of aWindow
                            try
                                set end of answer to (URL of aTab) as text
                            end try
                        end repeat
                    end try
                end repeat
            end tell
            set AppleScript's text item delimiters to linefeed
            return answer as text
        end run
        """, bundleID: bundleID)
    }
}
