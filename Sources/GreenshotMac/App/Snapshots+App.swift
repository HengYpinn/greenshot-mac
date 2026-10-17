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
    }

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
