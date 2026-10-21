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
}
