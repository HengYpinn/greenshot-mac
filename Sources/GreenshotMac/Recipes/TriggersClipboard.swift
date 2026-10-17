// Greenshot for Mac (Community) - an unofficial macOS port of Greenshot
// Copyright (C) 2026 Greenshot for Mac (Community) contributors
// Based on Greenshot, Copyright (C) 2007-2026 Thomas Braun, Jens Klingen, Robin Krom
// SPDX-License-Identifier: GPL-3.0-or-later
// Owned by RUI after the wave 4 prep.

import AppKit
import GreenshotCore

/// The app's own writes to the clipboard, which the Clipboard trigger (RCP-065) must not take for a copy in another app.
/// Every place that writes `NSPasteboard.general` calls `recordWrite` after the write (Clipboard.copy, RSTEPS's
/// Clipboard step and clipboard writer).
@MainActor
enum OwnPasteboardWrites {
    private(set) static var lastChangeCount: Int?

    static func recordWrite(_ pasteboard: NSPasteboard) {
        lastChangeCount = pasteboard.changeCount
    }
}
