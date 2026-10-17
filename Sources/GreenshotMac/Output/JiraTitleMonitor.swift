// Greenshot for Mac (Community) - an unofficial macOS port of Greenshot
// Copyright (C) 2026 Greenshot for Mac (Community) contributors
// Based on Greenshot, Copyright (C) 2007-2026 Thomas Braun, Jens Klingen, Robin Krom
// SPDX-License-Identifier: GPL-3.0-or-later
// Owned by PARTIALS-DST after the wave 5 prep.

import AppKit
import GreenshotCore

/// Watches the window titles for Jira issue keys, so the destination picker and the upload window offer the issues the
/// user looked at recently (upstream `Greenshot.Plugin.Jira/Monitoring/JiraMonitor.cs`). Filled in by the PARTIALS-DST
/// package (DST-088).
@MainActor
final class JiraTitleMonitor {
    static let shared = JiraTitleMonitor()

    /// At launch; samples only while Jira is set up (its URL and user), follows changes of `jira`.
    func start(settings: SettingsStore) {}
}
