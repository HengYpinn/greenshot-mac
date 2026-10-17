// Greenshot for Mac (Community) - an unofficial macOS port of Greenshot
// Copyright (C) 2026 Greenshot for Mac (Community) contributors
// Based on Greenshot, Copyright (C) 2007-2026 Thomas Braun, Jens Klingen, Robin Krom
// SPDX-License-Identifier: GPL-3.0-or-later

import Foundation

/// The texts of the welcome window: upstream's `[Welcome]` section of `Languages/greenshot.en-US.ini`
/// (docs/welcome-window.md), for the Mac: the menu bar instead of the notification area, ⌘ and ⌃ for Ctrl.
public enum WelcomeContent {
    /// A hotkey of the user and what it does (upstream `WelcomeHotkeyViewModel`).
    public struct Basic: Equatable, Sendable {
        public var keys: String
        public var text: String
    }

    /// The four capture hotkeys of upstream's "The basics", in its order; a hotkey that isn't set is left out.
    public static func basics(_ hotkeys: HotkeySettings) -> [Basic] {
        let rows: [(KeyCombo?, String)] = [
            (hotkeys.region, "Select a region or a window"),
            (hotkeys.window, "Capture the active window"),
            (hotkeys.fullScreen, "Capture the whole screen"),
            (hotkeys.lastRegion, "Capture the same region again"),
        ]
        return rows.compactMap { combo, text in combo.map { Basic(keys: $0.displayString, text: text) } }
    }

    /// The tips (upstream `tip1` ... `tip10`), and `tip_notification` only where a notification offers its capture
    /// again (`showsCaptures`). Empty tips are left out.
    public static func tips(appName: String, showsCaptures: Bool) -> [String] {
        var tips = [
            "While capturing, press Space to switch between selecting a region and capturing a window.",
            "While capturing, the arrow keys move the pointer one pixel at a time, with ⌃ or ⌘ ten pixels.",
            "Press Z while capturing to show or hide the zoomer, for selections to the pixel.",
            "Press M while capturing to show or hide the mouse pointer in the screenshot.",
            "Press F1 or H while capturing to see all the keys you can use.",
            "Changed your mind? Esc cancels a capture.",
            "The Obfuscate tool of the editor pixelates or blurs the parts of a screenshot nobody else should see.",
            "Number the steps of a how-to with the Counter tool of the editor.",
            "In Settings › Output you choose the folder and the file name pattern of saved screenshots.",
            "\(appName) is free and open source, made by volunteers. If it helps you, tell your friends about it.",
        ]
        if showsCaptures {
            tips.append("Clicked away a notification of \(appName)? It waits in Notification Center: a click on it lets you choose again where the capture goes, even after \(appName) was closed.")
        }
        return tips.filter { !$0.trimmingCharacters(in: .whitespaces).isEmpty }
    }

    /// The tip at `index`, counted around (upstream `ShowTip`); "" when there are none.
    public static func tip(_ tips: [String], at index: Int) -> String {
        guard !tips.isEmpty else { return "" }
        return tips[((index % tips.count) + tips.count) % tips.count]
    }

    public static func title(_ app: String) -> String { "Welcome to \(app)" }

    public static func thanks(_ app: String) -> String {
        "Thank you for installing \(app)! It's running now and waits for you in the menu bar, at the top right of the screen."
    }

    public static func intro(_ app: String) -> String {
        "In a few steps you'll see how capturing works, and \(app) checks that everything is set up well."
    }

    public static let basicsTitle = "Capturing takes one key"

    public static func basicsMenu(_ app: String) -> String {
        "Everything is also in the menu of the \(app) icon in the menu bar."
    }

    public static let basicsAfter = "What happens with a capture is up to you: open it in the editor, save it, copy it to the clipboard, print it and more. You choose in Settings."
    public static let noHotkeys = "You have no capture hotkeys at the moment. Choose them in Settings › General."
    public static let setupTitle = "Your setup"

    public static func setupSubtitle(_ app: String) -> String {
        "What \(app) needs to work as expected, with a fix where something is off."
    }

    public static let doneTitle = "You're all set"

    public static func done(_ app: String) -> String {
        "That's all you need to start. \(app) waits in the menu bar, and everything else can be changed in Settings whenever you like."
    }

    public static let tipTitle = "Did you know?"
}
