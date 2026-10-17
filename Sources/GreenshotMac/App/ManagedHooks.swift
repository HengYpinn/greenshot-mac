// Greenshot for Mac (Community) - an unofficial macOS port of Greenshot
// Copyright (C) 2026 Greenshot for Mac (Community) contributors
// Based on Greenshot, Copyright (C) 2007-2026 Thomas Braun, Jens Klingen, Robin Krom
// SPDX-License-Identifier: GPL-3.0-or-later

import AppKit
import GreenshotCore

/// The admin policy's hooks in files other packages own: what `disableSettings` and `excludeDestinations` turn off
/// (upstream `TrayMenu.cs` `DisableSettings`, `DestinationBase.IsExcludedByConfiguration`).
@MainActor
enum ManagedHooks {
    /// From `AppDelegate.validateMenuItem`: nil leaves the item to the usual checks; false hides and disables it
    /// (Settings… while `disableSettings`, a destination in `excludeDestinations`).
    static func validate(_ menuItem: NSMenuItem, settings: AppSettings) -> Bool? {
        let off: Bool
        if menuItem.action == #selector(AppDelegate.showSettings(_:)) {
            off = settings.disableSettings
        } else if menuItem.action == #selector(AppDelegate.sendToDestination(_:)),
                  let box = menuItem.representedObject as? DestinationTargetBox {
            off = settings.isDestinationExcluded(box.target.policyDestination)
        } else {
            return nil
        }
        // Shown again once the policy allows it.
        menuItem.isHidden = off
        return off ? false : nil
    }

    /// From `OutputManager.perform`: the failure for a target the policy turns off, nil to go ahead. Every way to a
    /// destination ends there: the picker, the File menu, the editor's buttons, automation.
    static func refusal(for target: DestinationTarget, settings: AppSettings) -> ExportResult? {
        let destination = target.policyDestination
        guard settings.isDestinationExcluded(destination) else { return nil }
        return .failed(String(localized: "\(destination.displayName) is turned off by your organisation."))
    }
}

extension DestinationTarget {
    /// The destination whose setting decides about this target, e.g. Save as PDF… for `.pdfAs`.
    var policyDestination: CaptureDestination {
        switch self {
        case .destination(let destination): return destination
        case .pdfAs: return .pdf
        case .externalCommand: return .externalCommand
        case .application: return .openWith
        case .addToEditor: return .editor
        case .printer: return .printer
        case .jiraIssue: return .jira
        case .confluencePage: return .confluence
        case .office(let app, _): return app.destination
        }
    }
}
