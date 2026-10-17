// Greenshot for Mac (Community) - an unofficial macOS port of Greenshot
// Copyright (C) 2026 Greenshot for Mac (Community) contributors
// Based on Greenshot, Copyright (C) 2007-2026 Thomas Braun, Jens Klingen, Robin Krom
// SPDX-License-Identifier: GPL-3.0-or-later

import AppKit

/// The macOS notifications after a capture (upstream `TrayNotificationService`). Package N fills it in.
@MainActor
final class NotificationService {
    /// Sets up the notification centre's delegate; called while the app finishes launching, so a click on a
    /// notification that launched the app is not lost.
    static func install(app: AppDelegate) {}
}
