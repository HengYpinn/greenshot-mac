// Greenshot for Mac (Community) - an unofficial macOS port of Greenshot
// Copyright (C) 2026 Greenshot for Mac (Community) contributors
// Based on Greenshot, Copyright (C) 2007-2026 Thomas Braun, Jens Klingen, Robin Krom
// SPDX-License-Identifier: GPL-3.0-or-later

import AppKit
import GreenshotCore

/// The Office and Notes destinations by AppleScript (upstream `Greenshot.Plugin.Office`). Package O fills it in.
@MainActor
enum OfficeMenus {
    /// The File menu's entries for the installed Office apps and Notes (`MainMenu.destinationItem`s).
    static func fileMenuItems() -> [NSMenuItem] { [] }
}
