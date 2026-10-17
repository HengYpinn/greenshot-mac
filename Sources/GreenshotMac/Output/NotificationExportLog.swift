// Greenshot for Mac (Community) - an unofficial macOS port of Greenshot
// Copyright (C) 2026 Greenshot for Mac (Community) contributors
// Based on Greenshot, Copyright (C) 2007-2026 Thomas Braun, Jens Klingen, Robin Krom
// SPDX-License-Identifier: GPL-3.0-or-later

import GreenshotCore

/// Collects how every destination of one capture ended, for one notification after the capture (upstream
/// `ExportNotification`). Package N fills it in.
@MainActor
final class NotificationExportLog {
    init(capture: Capture, settings: SettingsStore) {}

    /// The completion for one export of the capture.
    func expect() -> ExportCompletion { { _ in } }

    /// All exports are started: the notification is shown once they all ended.
    func close() {}
}
