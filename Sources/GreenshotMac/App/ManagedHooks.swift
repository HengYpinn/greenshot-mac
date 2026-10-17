// Greenshot for Mac (Community) - an unofficial macOS port of Greenshot
// Copyright (C) 2026 Greenshot for Mac (Community) contributors
// Based on Greenshot, Copyright (C) 2007-2026 Thomas Braun, Jens Klingen, Robin Krom
// SPDX-License-Identifier: GPL-3.0-or-later

import AppKit
import GreenshotCore

/// The admin policy's hooks in files other packages own (package ADMIN fills them in).
@MainActor
enum ManagedHooks {
    /// From `AppDelegate.validateMenuItem`: nil leaves the item to the usual checks; false hides and disables it
    /// (Settings… while `disableSettings`, a destination in `excludeDestinations`).
    static func validate(_ menuItem: NSMenuItem, settings: AppSettings) -> Bool? { nil }

    /// From `OutputManager.perform`: the failure for a target the policy turns off, nil to go ahead.
    static func refusal(for target: DestinationTarget, settings: AppSettings) -> ExportResult? { nil }
}
