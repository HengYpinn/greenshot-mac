// Greenshot for Mac (Community) - an unofficial macOS port of Greenshot
// Copyright (C) 2026 Greenshot for Mac (Community) contributors
// Based on Greenshot, Copyright (C) 2007-2026 Thomas Braun, Jens Klingen, Robin Krom
// SPDX-License-Identifier: GPL-3.0-or-later

/// Which window "Capture active window" takes (upstream `WindowHelper.GetActiveWindow` in
/// `ActiveWindowCaptureSource`).
public enum ActiveWindowChoice {
    /// The index in `owners` (the process of each window on the screen, front to back, without this app's own) of the
    /// window to capture: the front window of the active app `frontmost`. When this app (`own`) is active, e.g. a
    /// capture from the editor, the front-most window of another app. Nil when the active app has no window on the
    /// screen (the desktop clicked, an app with only a menu bar item) or no app is active: then upstream captures the
    /// screen, never another app's window.
    public static func index(owners: [Int32], frontmost: Int32?, own: Int32) -> Int? {
        guard let frontmost else { return nil }
        if frontmost == own { return owners.isEmpty ? nil : 0 }
        return owners.firstIndex(of: frontmost)
    }

    /// What "the active window" becomes when the active app has no window on the screen.
    public enum Fallback: Equatable, Sendable {
        /// The whole screen, like upstream (`ActiveWindowCaptureSource` falls back to `CaptureScreenAsync`).
        case screen
        /// The whole screen once the run's own question allows it (greenshot-cli's RUN_RECIPE, `RecipeCaptureConsent`).
        case askForScreen
        /// Nothing: "The window is no longer on the screen".
        case none
    }

    /// The fallback for a capture or recording of the active window. Only a capture the user started at the computer
    /// (`OverlayInputArming.startedByUser`: the hotkey, the menus, the editor) widens to the whole screen. A capture
    /// another program started (a command line, a link, an AI tool, a schedule, the browser extension) was allowed one
    /// window, and a program can arrange that the active app has none: it asks again when its run has a question of its
    /// own (`hasConsent`), else it fails. An AI tool never gets the screen in place of a window.
    public static func fallback(triggerType: String?, markedByAutomation: Bool, hasConsent: Bool) -> Fallback {
        if let triggerType, recipeEquals(triggerType, WellKnownTriggerType.aiTool) { return .none }
        if hasConsent { return .askForScreen }
        return OverlayInputArming.startedByUser(triggerType: triggerType, markedByAutomation: markedByAutomation) ? .screen : .none
    }
}
