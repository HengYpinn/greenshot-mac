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

extension KeyCombo {
    init(event: NSEvent) {
        self.init(keyCode: UInt32(event.keyCode), modifiers: KeyCombo.carbonModifiers(from: event.modifierFlags))
    }

    static func carbonModifiers(from flags: NSEvent.ModifierFlags) -> UInt32 {
        var result: UInt32 = 0
        if flags.contains(.control) { result |= control }
        if flags.contains(.option) { result |= option }
        if flags.contains(.shift) { result |= shift }
        if flags.contains(.command) { result |= command }
        return result
    }

    var modifierFlags: NSEvent.ModifierFlags {
        var flags: NSEvent.ModifierFlags = []
        if modifiers & KeyCombo.control != 0 { flags.insert(.control) }
        if modifiers & KeyCombo.option != 0 { flags.insert(.option) }
        if modifiers & KeyCombo.shift != 0 { flags.insert(.shift) }
        if modifiers & KeyCombo.command != 0 { flags.insert(.command) }
        return flags
    }

    /// The key equivalent to show the shortcut in a menu, when the key can be shown there.
    var menuKeyEquivalent: String? {
        let name = KeyCombo.keyName(for: keyCode)
        if name.count == 1, let char = name.lowercased().first, char.isLetter || char.isNumber || char.isPunctuation {
            return String(char)
        }
        if name.hasPrefix("F"), let number = Int(name.dropFirst()), (1...20).contains(number),
           let scalar = UnicodeScalar(NSF1FunctionKey + number - 1) {
            return String(Character(scalar))
        }
        return nil
    }
}

@MainActor
enum Permissions {
    static let screenCaptureSettingsURL =
        URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_ScreenCapture")!

    static var hasScreenCapture: Bool { CGPreflightScreenCaptureAccess() }

    /// True when screenshots can be taken. Otherwise the first time asks macOS for the permission (its own
    /// prompt), and later times explain where to turn it on.
    static func ensureScreenCapture() -> Bool {
        if CGPreflightScreenCaptureAccess() { return true }
        if CGRequestScreenCaptureAccess() { return true }
        // Recent macOS versions add the app to the Screen Recording list only when it really tries to capture,
        // so try once in the background (it fails without the permission); then the user just turns it on.
        Task { _ = try? await SCShareableContent.excludingDesktopWindows(false, onScreenWindowsOnly: true) }
        let askedKey = "didRequestScreenCapture"
        if !UserDefaults.standard.bool(forKey: askedKey) {
            // The first time macOS shows its own prompt; explaining on top of it would be one dialog too many.
            UserDefaults.standard.set(true, forKey: askedKey)
            return false
        }
        explainScreenCapture()
        return false
    }

    static func explainScreenCapture() {
        let alert = NSAlert()
        alert.messageText = "Allow \(AppInfo.name) to record your screen"
        alert.informativeText = """
            macOS asks every app that takes screenshots for this permission.

            Open System Settings › Privacy & Security › Screen & System Audio Recording, turn on \
            \(AppInfo.name), then quit and reopen it.

            Not in the list? Click + below it and add \(AppInfo.name) from Applications.

            Already on? A rebuilt or moved copy counts as a new app: select it, remove it with −, then reopen \
            \(AppInfo.name) and allow it again.
            """
        alert.addButton(withTitle: "Open System Settings")
        alert.addButton(withTitle: "Later")
        NSApp.activate()
        if alert.runModal() == .alertFirstButtonReturn {
            NSWorkspace.shared.open(screenCaptureSettingsURL)
        }
    }

    static func isPermissionError(_ error: Error) -> Bool {
        let nsError = error as NSError
        return nsError.domain == SCStreamErrorDomain && nsError.code == SCStreamError.userDeclined.rawValue
    }
}

@MainActor
enum ErrorPresenter {
    static func show(_ error: Error, title: String = "The screenshot could not be taken") {
        if Permissions.isPermissionError(error) {
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
        let alert = NSAlert()
        alert.messageText = message
        alert.informativeText = detail
        NSApp.activate()
        alert.runModal()
    }
}

enum CameraSound {
    static func play() {
        let path = "/System/Library/Components/CoreAudio.component/Contents/SharedSupport/SystemSounds/system/Screen Capture.aif"
        let sound = NSSound(contentsOfFile: path, byReference: true) ?? NSSound(named: "Tink")
        sound?.play()
    }
}
