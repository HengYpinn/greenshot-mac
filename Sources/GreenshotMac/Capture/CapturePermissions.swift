// Greenshot for Mac (Community) - an unofficial macOS port of Greenshot
// Copyright (C) 2026 Greenshot for Mac (Community) contributors
// SPDX-License-Identifier: GPL-3.0-or-later

import AppKit
import ApplicationServices
import GreenshotCore

private let log = Log("Capture")

/// The two permissions only optional features need: Accessibility for the areas inside windows (window mode) and for
/// hotkeys that tell the left from the right modifier key, Input Monitoring as the lesser choice for those hotkeys.
/// macOS asks only when the user turns such a feature on, never during a capture (the capture screen would cover the
/// question).
extension Permissions {
    static let accessibilitySettingsURL =
        URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_Accessibility")!
    static let inputMonitoringSettingsURL =
        URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_ListenEvent")!

    /// Greenshot may read other apps' windows and filter keys (System Settings › Privacy & Security › Accessibility).
    static var hasAccessibility: Bool { AXIsProcessTrusted() }

    /// Greenshot may watch the keyboard (System Settings › Privacy & Security › Input Monitoring).
    static var canListenToKeys: Bool { CGPreflightListenEventAccess() }

    /// Asks macOS for the Accessibility permission: its own dialog, which leads to System Settings. True when it is
    /// already allowed.
    @discardableResult
    static func requestAccessibility() -> Bool {
        let options = [kAXTrustedCheckOptionPrompt.takeUnretainedValue() as String: true] as CFDictionary
        let trusted = AXIsProcessTrustedWithOptions(options)
        log.info("Accessibility permission \(trusted ? "allowed" : "requested")")
        return trusted
    }
}

/// Whether Accessibility (and Input Monitoring) is allowed, for a settings row; checked again whenever the app becomes
/// active, since macOS tells nobody when the user changes it.
@MainActor
final class AccessibilityStatus: ObservableObject {
    @Published private(set) var isAllowed: Bool
    @Published private(set) var canListenToKeys: Bool
    private var observer: NSObjectProtocol?

    /// Hotkeys can tell the left modifier keys from the right ones (the event tap can run).
    var canTellSides: Bool { isAllowed || canListenToKeys }

    /// `fixed` for the snapshots: the row as if the permissions were (not) allowed.
    init(fixed: Bool? = nil) {
        isAllowed = fixed ?? Permissions.hasAccessibility
        canListenToKeys = fixed ?? Permissions.canListenToKeys
        guard fixed == nil else { return }
        observer = NotificationCenter.default.addObserver(forName: NSApplication.didBecomeActiveNotification, object: nil,
                                                          queue: .main) { [weak self] _ in
            MainActor.assumeIsolated { self?.refresh() }
        }
    }

    deinit {
        if let observer { NotificationCenter.default.removeObserver(observer) }
    }

    func refresh() {
        let allowed = Permissions.hasAccessibility
        if allowed != isAllowed { isAllowed = allowed }
        let listens = Permissions.canListenToKeys
        if listens != canListenToKeys { canListenToKeys = listens }
    }
}
