// Greenshot for Mac (Community) - an unofficial macOS port of Greenshot
// Copyright (C) 2026 Greenshot for Mac (Community) contributors
// SPDX-License-Identifier: GPL-3.0-or-later

import AppKit
import GreenshotCore
import SwiftUI

extension Snapshots {
    /// Renders for the notifications after a capture and their settings. A macOS notification itself can't be rendered:
    /// `notification-summary.txt` lists what the app would post for made-up exports.
    static func renderNotificationExtras(to folder: URL, sample: CGImage, settings: SettingsStore) throws {
        let kinds: [(String, MessageKind, String, String)] = [
            // The app's own texts where it has them, so each language's render shows its translation.
            ("info", .info, String(localized: "Saved \("2026-10-17 12_00_00-Safari.png")"),
             String(localized: "\("~/Desktop") – click to show in Finder")),
            ("warning", .warning, String(localized: "Add CC and BCC in the mail"), "CC: team@example.com"),
            ("error", .error, "Upload script failed", "It ended with exit code 1."),
        ]
        for (name, kind, title, detail) in kinds {
            try write(toast(title: title, lines: [detail], kind: kind, sample: sample),
                      to: folder.appendingPathComponent("toast-\(name).png"))
        }
        let summary = summaryExample(barcodes: [])
        try write(toast(title: summary.title, lines: summary.lines, kind: summary.kind, sample: sample),
                  to: folder.appendingPathComponent("toast-summary.png"))
        if let thumbnail = NotificationThumbnail.make(sample) {
            try ImageExporter.write(thumbnail, to: folder.appendingPathComponent("notification-thumbnail.png"), format: .png)
            print("Wrote \(folder.appendingPathComponent("notification-thumbnail.png").path)")
        }
        if let icon = NativeNotifications.statusIconPNG(.error) {
            try icon.write(to: folder.appendingPathComponent("notification-icon-error.png"))
        }
        try write(notificationSettings(.allowed), to: folder.appendingPathComponent("settings-notifications.png"))
        try write(notificationSettings(.off), to: folder.appendingPathComponent("settings-notifications-off.png"))
        try write(notificationSettings(.inApp), to: folder.appendingPathComponent("settings-notifications-in-app.png"))
        let dump = folder.appendingPathComponent("notification-summary.txt")
        try notificationDump().write(to: dump, atomically: true, encoding: .utf8)
        print("Wrote \(dump.path)")
    }

    /// The in-app panel over a piece of the sample, as it would sit in the corner of the screen.
    private static func toast(title: String, lines: [String], kind: MessageKind, sample: CGImage) -> NSBitmapImageRep? {
        let content = ToastPanel.makeView(title: title, lines: lines, kind: kind)
        content.appearance = NSAppearance(named: .aqua)
        let size = content.fittingSize
        let backdrop = NSImageView(frame: NSRect(x: 0, y: 0, width: size.width + 32, height: size.height + 32))
        backdrop.image = NSImage(cgImage: sample, size: NSSize(width: sample.width / 2, height: sample.height / 2))
        backdrop.imageScaling = .scaleAxesIndependently
        content.frame = NSRect(x: 16, y: 16, width: size.width, height: size.height)
        backdrop.addSubview(content)
        let window = NSWindow(contentRect: backdrop.bounds, styleMask: [.borderless], backing: .buffered, defer: false)
        window.contentView = backdrop
        keepAlive.append(window)
        return capture(backdrop)
    }

    private static func notificationSettings(_ state: NotificationState) -> NSBitmapImageRep? {
        let defaults = UserDefaults(suiteName: "greenshot-mac-snapshots-notifications")!
        defaults.removePersistentDomain(forName: "greenshot-mac-snapshots-notifications")
        let store = SettingsStore(defaults: defaults)
        let hosting = NSHostingView(rootView: Form { NotificationSettings(store: store, state: state) }.formStyle(.grouped))
        hosting.frame = NSRect(x: 0, y: 0, width: 620, height: 260)
        let window = NSWindow(contentRect: hosting.frame, styleMask: [.titled], backing: .buffered, defer: false)
        window.contentView = hosting
        keepAlive.append(window)
        hosting.layoutSubtreeIfNeeded()
        return capture(hosting)
    }

    /// Made-up exports of one capture: the clipboard, a saved file, an upload and a failed command.
    private static func summaryExample(barcodes: [NotificationBarcode]) -> NotificationSummaryContent {
        func by(_ name: String, _ result: ExportResult) -> ExportResult {
            var result = result
            result.exportedBy = name
            return result
        }
        let saved = URL(fileURLWithPath: NSHomeDirectory() + "/Desktop/2026-10-17 12_00_00-Safari.png")
        let exports = [by("Copy to clipboard", .succeeded()),
                       by("Save Directly", .succeeded(fileURL: saved)),
                       by("Upload to Box", .succeeded(link: URL(string: "https://app.box.com/s/abc123"), target: "Box")),
                       by("Upload script", .failed("It ended with exit code 1.", target: "Upload script"))]
        return NotificationSummary.make(title: "Safari – Greenshot", exports: exports, barcodes: barcodes, settings: AppSettings())!
    }

    /// What the macOS notification would carry: title, body, buttons and what a click gets back.
    private static func notificationDump() -> String {
        var cases: [(String, NotificationSummaryContent?)] = []
        var summary = summaryExample(barcodes: [NotificationBarcode(text: "https://\u{0430}pple.com/login", isQRCode: true),
                                                NotificationBarcode(text: "WIFI:S:Home;T:WPA;P:secret;;", isQRCode: true)])
        summary.captureId = NotificationCaptureStore.newId(now: Date(timeIntervalSince1970: 1_790_000_000))
        cases.append(("Four exports and two QR codes", summary))
        var levelWarnings = AppSettings()
        levelWarnings.notificationLevel = .warnings
        cases.append(("Only a successful export, level Warnings and errors",
                      NotificationSummary.make(title: "Safari", exports: [.succeeded()], settings: levelWarnings)))
        cases.append(("Every export declined (the picker was closed)",
                      NotificationSummary.make(title: "Safari", exports: [.declined], settings: AppSettings())))
        var text = ""
        for (name, content) in cases {
            text += "== \(name)\n"
            guard let content else {
                text += "(nothing posted)\n\n"
                continue
            }
            let payload = NotificationPayload(captureId: content.captureId, savedFile: content.savedFile?.path, links: content.links,
                                              title: content.title, date: Date(timeIntervalSince1970: 1_790_000_000))
            text += "kind: \(content.kind)\ntitle: \(content.title)\nbody:\n"
            text += content.lines.map { "  " + $0 }.joined(separator: "\n") + "\n"
            text += "category: \(content.categoryIdentifier ?? NativeNotifications.messageCategory)\n"
            text += "buttons: \(content.actions.map(\.title).joined(separator: ", "))\n"
            text += "copy link choices: \(content.links.map(\.text).joined(separator: " | "))\n"
            text += "opens without buttons: \(content.opens?.absoluteString ?? "-")\n"
            text += "userInfo: \(payload.userInfo.keys.sorted().joined(separator: ", "))\n\n"
        }
        return text
    }
}
