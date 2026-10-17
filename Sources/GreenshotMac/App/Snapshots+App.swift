// Greenshot for Mac (Community) - an unofficial macOS port of Greenshot
// Copyright (C) 2026 Greenshot for Mac (Community) contributors
// SPDX-License-Identifier: GPL-3.0-or-later

import AppKit
import GreenshotCore
import SwiftUI

extension Snapshots {
    /// Renders for the menu bar menu, Settings and the app windows. Writes PNG files into `folder` with `write(_:to:)`; the helpers in Snapshots.swift
    /// (`editorWindow`, `overlay`, `form`, `settingsTab`, `capture`) do most of the work.
    static func renderAppExtras(to folder: URL, sample: CGImage, settings: SettingsStore) throws {
        // The whole General and Expert tabs (the standard renders stop at the window's height), and General in dark.
        let general = GeneralSettings(store: settings, status: SystemStatus())
        try write(fullForm(general, height: 1080), to: folder.appendingPathComponent("app-settings-general-full.png"))
        try write(fullForm(general, height: 1080, appearance: NSAppearance(named: .darkAqua)),
                  to: folder.appendingPathComponent("app-settings-general-dark.png"))
        try write(fullForm(ExpertSettings(store: settings), height: 640), to: folder.appendingPathComponent("app-settings-expert-full.png"))

        // The window picture beside the window list.
        let size = MenuBarThumbnailLayout.size(for: CGSize(width: sample.width, height: sample.height))
        let thumbnail = MenuBarWindowThumbnail.contentView(image: NSImage(cgImage: sample, size: size))
        try write(form(thumbnail), to: folder.appendingPathComponent("menubar-thumbnail.png"))

        // The About panel's text, as wide as the panel shows it.
        let credits = NSTextView(frame: NSRect(x: 0, y: 0, width: 300, height: 10))
        credits.textStorage?.setAttributedString(AppAboutCredits.make())
        credits.textContainerInset = NSSize(width: 8, height: 8)
        credits.isVerticallyResizable = true
        credits.sizeToFit()
        try write(form(credits), to: folder.appendingPathComponent("app-about-credits.png"))

        try renderDiagnostics(to: folder)
    }

    /// The log viewer, Self-Service, bug report, welcome and About windows, from fixed sample data (no live timers, no
    /// network, nothing of this Mac's state that changes between runs).
    private static func renderDiagnostics(to folder: URL) throws {
        let logFile = FileManager.default.temporaryDirectory.appendingPathComponent("greenshot-snapshot-\(UUID().uuidString).log")
        try Data(sampleLog.utf8).write(to: logFile)
        defer { try? FileManager.default.removeItem(at: logFile) }

        let viewer = LogViewerModel(fileURL: logFile, followsLog: false)
        viewer.load()
        try write(window(LogViewerView(model: viewer), size: NSSize(width: 900, height: 520)),
                  to: folder.appendingPathComponent("app-logviewer.png"))
        let search = LogViewerModel(fileURL: logFile, followsLog: false, search: "upload")
        search.load()
        search.wrap = true
        try write(window(LogViewerView(model: search), size: NSSize(width: 900, height: 420)),
                  to: folder.appendingPathComponent("app-logviewer-search.png"))
    }

    /// A SwiftUI view in a window of `size`, rendered.
    static func window(_ view: some View, size: NSSize, appearance: NSAppearance? = NSAppearance(named: .aqua)) -> NSBitmapImageRep? {
        let hosting = NSHostingView(rootView: view.frame(width: size.width, height: size.height))
        hosting.frame = NSRect(origin: .zero, size: size)
        hosting.appearance = appearance
        let window = NSWindow(contentRect: hosting.frame, styleMask: [.titled], backing: .buffered, defer: false)
        window.appearance = appearance
        window.contentView = hosting
        keepAlive.append(window)
        hosting.layoutSubtreeIfNeeded()
        // Lets AppKit views inside (text views, tables) lay out and scroll before the picture is taken.
        RunLoop.current.run(until: Date().addingTimeInterval(0.05))
        hosting.layoutSubtreeIfNeeded()
        return capture(hosting)
    }

    /// A log as the app writes it, with an error, a multi-line entry and an upload.
    static let sampleLog = """
        2026-10-17 09:12:01,114 [main] INFO  - [App] Starting: Greenshot for Mac (Community) 1.4.0 (build 140, Apple silicon), macOS Version 27.0 (Build 27A100)
        2026-10-17 09:12:01,162 [main] INFO  - [Hotkeys] Registered 4 hotkeys
        2026-10-17 09:12:21,508 [9731] INFO  - [Update] Update check: newest release 1.4.0, this is 1.4.0
        2026-10-17 09:15:42,019 [main] INFO  - [Capture] Captured region 1280x720 on Built-in Retina Display
        2026-10-17 09:15:44,377 [main] INFO  - [Output] Saved ~/Desktop/2026-10-17 09_15_42-Safari.png
        2026-10-17 09:16:03,880 [main] DEBUG - [Editor] Opened an editor for 2026-10-17 09_15_42-Safari.png
        2026-10-17 09:17:10,245 [8812] WARN  - [Upload] Upload to Jira failed, trying again
            Foundation.URLError: The request timed out. (NSURLErrorDomain -1001)
        2026-10-17 09:17:16,902 [8812] INFO  - [Upload] Upload to Jira finished: SHOT-12
        2026-10-17 09:20:31,450 [main] ERROR - [Alert] The screenshot could not be taken
            Swift.CocoaError: You don’t have permission to save the file. (NSCocoaErrorDomain 513)
        2026-10-17 09:21:05,013 [main] INFO  - [Capture] Captured window "Quarterly report – Numbers" 1440x900

        """

    /// A settings form at full length, in the light or the given appearance.
    private static func fullForm(_ view: some View, height: CGFloat, appearance: NSAppearance? = NSAppearance(named: .aqua)) -> NSBitmapImageRep? {
        let hosting = NSHostingView(rootView: view.frame(width: 620, height: height))
        hosting.frame = NSRect(x: 0, y: 0, width: 620, height: height)
        hosting.appearance = appearance
        let window = NSWindow(contentRect: hosting.frame, styleMask: [.titled], backing: .buffered, defer: false)
        window.appearance = appearance
        window.contentView = hosting
        hosting.layoutSubtreeIfNeeded()
        return capture(hosting)
    }
}
