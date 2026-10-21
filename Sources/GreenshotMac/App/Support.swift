// Greenshot for Mac (Community) - an unofficial macOS port of Greenshot
// Copyright (C) 2026 Greenshot for Mac (Community) contributors
// SPDX-License-Identifier: GPL-3.0-or-later

import AppKit
import GreenshotCore
import ScreenCaptureKit

enum AppInfo {
    static let name = "Greenshot for Mac (Community)"
    static let upstreamURL = URL(string: "https://getgreenshot.org/")!
    static let upstreamSourceURL = URL(string: "https://github.com/greenshot/greenshot")!
    static let helpURL = URL(string: "https://getgreenshot.org/help/")!
    static let repositoryURL = URL(string: "https://github.com/HengYpinn/greenshot-mac")!
    static let issuesURL = URL(string: "https://github.com/HengYpinn/greenshot-mac/issues")!

    /// `~/Library/Logs/Greenshot for Mac (Community)`: the log file (upstream `%LOCALAPPDATA%\Greenshot`), the
    /// marker of the running app and the note of a fatal exception. `--settings-dir` doesn't move it, like upstream's
    /// `--ini-directory`.
    static var logsFolder: URL {
        FileManager.default.homeDirectoryForCurrentUser.appendingPathComponent("Library/Logs/\(name)", isDirectory: true)
    }

    static var logFile: URL { logsFolder.appendingPathComponent(LogFile.fileName) }
}

/// A menu item that runs a closure.
final class ClosureMenuItem: NSMenuItem {
    private let handler: () -> Void

    init(title: String, keyEquivalent: String = "", handler: @escaping () -> Void) {
        self.handler = handler
        super.init(title: title, action: #selector(run), keyEquivalent: keyEquivalent)
        target = self
    }

    required init(coder: NSCoder) {
        fatalError("not used")
    }

    @objc private func run() {
        handler()
    }
}

extension NSScreen {
    var displayID: CGDirectDisplayID {
        (deviceDescription[NSDeviceDescriptionKey("NSScreenNumber")] as? NSNumber)?.uint32Value ?? 0
    }
}

/// Converts between AppKit's and Quartz's global coordinates (see `Geometry`).
@MainActor
enum ScreenSpace {
    static var primaryScreenHeight: CGFloat { NSScreen.screens.first?.frame.height ?? 0 }

    static func quartz(_ appKitPoint: NSPoint) -> CGPoint {
        Geometry.quartzPoint(fromAppKit: appKitPoint, primaryScreenHeight: primaryScreenHeight)
    }

    static var mouseLocation: CGPoint { quartz(NSEvent.mouseLocation) }
}

@MainActor
enum Permissions {
    static let screenCaptureSettingsURL =
        URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_ScreenCapture")!

    /// Screenshots can be taken: macOS's preflight says so, or ScreenCaptureKit worked in this run although the
    /// preflight said no (`ensureScreenCapture`). It never asks macOS nor tries a capture, so status texts and features
    /// that must not prompt (window pictures in menus, the Jira title monitor) can read it.
    static var hasScreenCapture: Bool { CGPreflightScreenCaptureAccess() || worksDespitePreflight }

    private static let log = Log("Permissions")
    /// ScreenCaptureKit worked in this run although the preflight said no (the permission was turned on while the app
    /// runs), so later captures don't try again. A capture refused for the permission forgets it (`ErrorPresenter`).
    private static var worksDespitePreflight = false
    /// The check running now: a second capture at the same time waits for it instead of asking again.
    private static var pendingCheck: Task<Bool, Never>?

    /// True when screenshots can be taken. When macOS's preflight says no, macOS is asked (its own prompt, the first
    /// time), and one real try of ScreenCaptureKit, at most `ScreenCaptureAccess.probeTimeout` seconds, decides: it works
    /// when the permission was turned on while the app runs, and on recent macOS versions it puts the app into the
    /// Screen Recording list. Refused, the user is told (`ScreenCaptureAccess.decision`): a short note when macOS is
    /// asked for the first time (its prompt may be showing), else the explanation where to turn the permission on.
    static func ensureScreenCapture() async -> Bool {
        if CGPreflightScreenCaptureAccess() || worksDespitePreflight { return true }
        if let pendingCheck { return await pendingCheck.value }
        let check = Task { await checkScreenCapture() }
        pendingCheck = check
        let allowed = await check.value
        pendingCheck = nil
        return allowed
    }

    private static func checkScreenCapture() async -> Bool {
        let askedKey = "didRequestScreenCapture"
        let askedBefore = UserDefaults.standard.bool(forKey: askedKey)
        if CGRequestScreenCaptureAccess() { return true }
        UserDefaults.standard.set(true, forKey: askedKey)
        let probe = await ScreenCaptureAccess.probe(within: ScreenCaptureAccess.probeTimeout) {
            do {
                _ = try await SCShareableContent.excludingDesktopWindows(false, onScreenWindowsOnly: true)
                return .works
            } catch {
                return isPermissionError(error) ? .refused : .failed
            }
        }
        switch ScreenCaptureAccess.decision(probe: probe, askedBefore: askedBefore) {
        case .granted:
            log.info("Screen Recording: the preflight says no, but ScreenCaptureKit works")
            worksDespitePreflight = true
            return true
        case .note:
            log.info("Screen Recording not allowed (\(probe)); macOS may be asking the user")
            noteScreenCapture()
            return false
        case .explain:
            log.info("Screen Recording not allowed (\(probe))")
            explainScreenCapture()
            return false
        }
    }

    /// A capture failed because the permission is off (again): the next capture checks once more.
    static func screenCaptureWasRefused() {
        worksDespitePreflight = false
    }

    /// The first refusal: macOS may be showing its own prompt, so a short message instead of a second dialog. A click
    /// opens the setting.
    private static func noteScreenCapture() {
        Toast.show(String(localized: "Allow \(AppInfo.name) to record your screen"),
                   detail: String(localized: "Turn it on in System Settings › Privacy & Security › Screen & System Audio Recording."),
                   kind: .warning, action: { NSWorkspace.shared.open(screenCaptureSettingsURL) })
    }

    static func explainScreenCapture() {
        let alert = NSAlert()
        alert.messageText = String(localized: "Allow \(AppInfo.name) to record your screen")
        alert.informativeText = String(localized: """
            macOS asks every app that takes screenshots for this permission.

            Open System Settings › Privacy & Security › Screen & System Audio Recording, turn on \
            \(AppInfo.name), then quit and reopen it.

            Not in the list? Click + below it and add \(AppInfo.name) from Applications.

            Already on? A rebuilt or moved copy counts as a new app: select it, remove it with −, then reopen \
            \(AppInfo.name) and allow it again.
            """)
        alert.addButton(withTitle: String(localized: "Open System Settings"))
        alert.addButton(withTitle: String(localized: "Later"))
        NSApp.activate()
        if alert.runModal() == .alertFirstButtonReturn {
            NSWorkspace.shared.open(screenCaptureSettingsURL)
        }
    }

    nonisolated static func isPermissionError(_ error: Error) -> Bool {
        let nsError = error as NSError
        return nsError.domain == SCStreamErrorDomain && nsError.code == SCStreamError.userDeclined.rawValue
    }
}

/// Alerts about errors. Every alert is logged too, so the log viewer and a bug report show what the user saw.
@MainActor
enum ErrorPresenter {
    private static let log = Log("Alert")

    static func show(_ error: Error, title: String = String(localized: "The screenshot could not be taken")) {
        log.error(title, error: error)
        if Permissions.isPermissionError(error) {
            Permissions.screenCaptureWasRefused()
            Permissions.explainScreenCapture()
            return
        }
        let alert = NSAlert()
        alert.alertStyle = .warning
        alert.messageText = title
        alert.informativeText = error.localizedDescription
        NSApp.activate()
        alert.runModal()
    }

    static func show(message: String, detail: String) {
        log.warn("\(message): \(detail)")
        let alert = NSAlert()
        alert.messageText = message
        alert.informativeText = detail
        NSApp.activate()
        alert.runModal()
    }
}

