// Greenshot for Mac (Community) - an unofficial macOS port of Greenshot
// Copyright (C) 2026 Greenshot for Mac (Community) contributors
// SPDX-License-Identifier: GPL-3.0-or-later

import AppKit
import GreenshotCore
import ServiceManagement

/// Opening the app when the user logs in, so the hotkeys work right after a restart. Greenshot's Windows installer
/// does the same with its "start with Windows" option, checked by default.
@MainActor
enum LaunchAtLogin {
    enum State { case on, off, needsApproval }

    private static let log = Log("LaunchAtLogin")

    static var state: State {
        switch SMAppService.mainApp.status {
        case .enabled: return .on
        case .requiresApproval: return .needsApproval
        default: return .off
        }
    }

    static let approvalHint = "Turn on \(AppInfo.name) in System Settings › General › Login Items & Extensions."

    /// Turns it on or off. Returns what the user still has to do or what went wrong, or nil when it is done.
    /// When macOS wants the user to approve the login item, its settings page is opened.
    @discardableResult
    static func set(_ on: Bool) -> String? {
        do {
            if on, state != .on {
                try SMAppService.mainApp.register()
            } else if !on, state != .off {
                try SMAppService.mainApp.unregister()
            }
        } catch {
            log.warn("Open at login could not be turned \(on ? "on" : "off")", error: error)
            return error.localizedDescription
        }
        log.info("Open at login turned \(on ? "on" : "off"), now \(state)")
        if on, state == .needsApproval {
            openSystemSettings()
            return approvalHint
        }
        return nil
    }

    static func openSystemSettings() {
        SMAppService.openSystemSettingsLoginItems()
    }

    /// Login items point at where the app is; an app run from a download or build folder may stop opening when
    /// it is moved.
    static var isInApplicationsFolder: Bool {
        let path = Bundle.main.bundlePath
        let userApplications = FileManager.default.homeDirectoryForCurrentUser.appendingPathComponent("Applications").path
        return path.hasPrefix("/Applications/") || path.hasPrefix(userApplications + "/")
    }

    static var moveToApplicationsTip: String {
        isInApplicationsFolder ? "" : "\n\nTip: move the app to your Applications folder first, so it keeps opening at login."
    }
}
