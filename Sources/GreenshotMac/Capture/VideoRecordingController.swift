// Greenshot for Mac (Community) - an unofficial macOS port of Greenshot
// Copyright (C) 2026 Greenshot for Mac (Community) contributors
// Based on Greenshot, Copyright (C) 2007-2026 Thomas Braun, Jens Klingen, Robin Krom
// SPDX-License-Identifier: GPL-3.0-or-later

import AppKit
import GreenshotCore

/// Screen recordings: Record Screen / Window / Region… of the menu bar menu, the record hotkey and the recording
/// indicator (filled in by the VID package).
@MainActor
final class VideoRecordingController {
    init(settings: SettingsStore, saver: ImageSaver) {}
    /// The "Start or stop recording" hotkey.
    func hotkeyPressed() {}
    /// Adds the record items to the menu bar menu (`StatusItemController.menuNeedsUpdate`).
    func addMenuItems(to menu: NSMenu) {}
    /// For `applicationShouldTerminate`: `.terminateLater` while a running recording is saved first.
    func terminateReply() -> NSApplication.TerminateReply { .terminateNow }
}
