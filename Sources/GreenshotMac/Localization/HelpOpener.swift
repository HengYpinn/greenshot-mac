// Greenshot for Mac (Community) - an unofficial macOS port of Greenshot
// Copyright (C) 2026 Greenshot for Mac (Community) contributors
// Based on Greenshot, Copyright (C) 2007-2026 Thomas Braun, Jens Klingen, Robin Krom
// SPDX-License-Identifier: GPL-3.0-or-later
// Owned by L10N-INFRA after the wave 5 prep.

import AppKit
import GreenshotCore

/// Help › Greenshot Help and the menu bar's Help (upstream `Greenshot.Base/Help/HelpFileLoader.cs`): the online help in
/// the UI language, else the bundled page. Filled in by the L10N-INFRA package; until then the website, as before.
@MainActor
enum HelpOpener {
    static func open() {
        NSWorkspace.shared.open(AppInfo.helpURL)
    }
}
