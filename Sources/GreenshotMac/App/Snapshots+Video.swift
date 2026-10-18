// Greenshot for Mac (Community) - an unofficial macOS port of Greenshot
// Copyright (C) 2026 Greenshot for Mac (Community) contributors
// SPDX-License-Identifier: GPL-3.0-or-later

import AppKit
import GreenshotCore
import SwiftUI

extension Snapshots {
    /// Renders of the screen recording: Settings › Video, the menu bar indicator, the countdown and a recipe's frame
    /// around what is recorded. A recording itself needs the screen recording permission; `recording-menu.txt` and
    /// `video-picker-menu.txt` list the menus.
    static func renderVideoExtras(to folder: URL, sample: CGImage, settings: SettingsStore) throws {
        try write(settingsTab(SettingsPane.video.rawValue, settings: settings), to: folder.appendingPathComponent("settings-video.png"))
        try write(customVideoSettings(), to: folder.appendingPathComponent("settings-video-custom.png"))
        try write(recordingIndicators(), to: folder.appendingPathComponent("recording-indicator.png"))
        try write(recordingCountdown(sample: sample), to: folder.appendingPathComponent("recording-countdown.png"))
        try write(recordingBorder(sample: sample), to: folder.appendingPathComponent("recording-border.png"))
        try write(recordingBorderDisplays(sample: sample), to: folder.appendingPathComponent("recording-border-displays.png"))
        try writeText(recordingMenus(settings: settings), to: folder.appendingPathComponent("recording-menu.txt"))
        // Not video: the print options with an administrator's locks (RCP-132's dialog of one print; this file is the
        // recipe steps' snapshot file this wave).
        try write(form(lockedPrintOptions()), to: folder.appendingPathComponent("dialog-print-options-locked.png"))
        let file = URL(fileURLWithPath: "/Users/me/Movies/Greenshot/Greenshot_Recording_20261017_143005.mp4")
        try writeText(menuText(VideoOutput.pickerMenu(for: file)), to: folder.appendingPathComponent("video-picker-menu.txt"))
    }

    /// The whole tab with the custom preset, HEVC, grayscale and both sounds, tall enough for every section.
    private static func customVideoSettings() -> NSBitmapImageRep? {
        let suite = "greenshot-mac-snapshots-video"
        let defaults = UserDefaults(suiteName: suite)!
        defaults.removePersistentDomain(forName: suite)
        let store = SettingsStore(defaults: defaults)
        store.update { settings in
            settings.video.preset = .custom
            settings.video.frameRate = 60
            settings.video.bitrate = 8_000_000
            settings.video.scaleFactor = 0.75
            settings.video.format = .mp4HEVC
            settings.video.colorMode = .grayscale
            settings.video.audioSource = .systemAudioAndMicrophone
            settings.video.windowResizeBehavior = .scaleToFit
            settings.video.maximumDurationSeconds = 600
            settings.video.destinations = [.showInFinder, .copyPath]
        }
        let hosting = NSHostingView(rootView: VideoSettingsTab(store: store).frame(width: 620, height: 1280))
        hosting.frame = NSRect(x: 0, y: 0, width: 620, height: 1280)
        let window = NSWindow(contentRect: hosting.frame, styleMask: [.titled], backing: .buffered, defer: false)
        window.contentView = hosting
        hosting.layoutSubtreeIfNeeded()
        keepAlive.append(store)
        return capture(hosting)
    }

    /// The indicator's four looks side by side on a menu bar coloured strip.
    private static func recordingIndicators() -> NSBitmapImageRep? {
        let states: [RecordingIndicatorState] = [.countdown(3), .starting, .recording(42), .paused(3725), .saving]
        let strip = NSView(frame: NSRect(x: 0, y: 0, width: 540, height: 24))
        strip.wantsLayer = true
        strip.layer?.backgroundColor = NSColor(white: 0.93, alpha: 1).cgColor
        var x: CGFloat = 8
        for state in states {
            let button = NSButton(frame: .zero)
            button.isBordered = false
            RecordingStatusItem.configure(button, state: state)
            button.sizeToFit()
            button.frame = NSRect(x: x, y: 1, width: button.frame.width, height: 22)
            strip.addSubview(button)
            x += button.frame.width + 24
        }
        strip.appearance = NSAppearance(named: .aqua)
        let window = NSWindow(contentRect: strip.frame, styleMask: [.borderless], backing: .buffered, defer: false)
        window.contentView = strip
        return capture(strip)
    }

    /// The countdown in the middle of the sample screen.
    private static func recordingCountdown(sample: CGImage) -> NSBitmapImageRep? {
        let size = NSSize(width: 640, height: 400)
        let container = NSView(frame: NSRect(origin: .zero, size: size))
        let picture = NSImageView(frame: container.bounds)
        picture.image = NSImage(cgImage: sample, size: size)
        picture.imageScaling = .scaleAxesIndependently
        container.addSubview(picture)
        let countdown = RecordingCountdownView(frame: NSRect(x: size.width / 2 - 80, y: size.height / 2 - 80, width: 160, height: 160))
        countdown.seconds = 3
        container.addSubview(countdown)
        let window = NSWindow(contentRect: container.frame, styleMask: [.borderless], backing: .buffered, defer: false)
        window.contentView = container
        return capture(container)
    }

    /// A recipe's `ShowCaptureBorder`: the frame around a region on the sample screen (the panels' views where
    /// `RecordingBorder` puts them).
    private static func recordingBorder(sample: CGImage) -> NSBitmapImageRep? {
        let display = CGRect(x: 0, y: 0, width: 640, height: 400)
        let region = CGRect(x: 120, y: 80, width: 320, height: 200)
        return borderScreens([display], sample: sample, framing: [region])
    }

    /// Two displays side by side: a window over both (no line where it goes on to the right display), a region in the
    /// left display's top left corner and one in the right display's bottom right corner (the lines inside on the
    /// displays' edges).
    private static func recordingBorderDisplays(sample: CGImage) -> NSBitmapImageRep? {
        let displays = [CGRect(x: 0, y: 0, width: 480, height: 300), CGRect(x: 480, y: 0, width: 480, height: 300)]
        let areas = [CGRect(x: 380, y: 60, width: 220, height: 140), CGRect(x: 0, y: 0, width: 150, height: 90),
                     CGRect(x: 840, y: 220, width: 120, height: 80)]
        return borderScreens(displays, sample: sample, framing: areas)
    }

    /// `displays` (Quartz points from the top left of the picture) showing the sample, with the frame's panels around
    /// each of `areas`; a dark line between the displays.
    private static func borderScreens(_ displays: [CGRect], sample: CGImage, framing areas: [CGRect]) -> NSBitmapImageRep? {
        let bounds = displays.reduce(CGRect.null) { $0.union($1) }
        let container = NSView(frame: NSRect(origin: .zero, size: bounds.size))
        func appKit(_ rect: CGRect) -> NSRect {
            NSRect(x: rect.minX - bounds.minX, y: bounds.maxY - rect.maxY, width: rect.width, height: rect.height)
        }
        for display in displays {
            let picture = NSImageView(frame: appKit(display))
            picture.image = NSImage(cgImage: sample, size: display.size)
            picture.imageScaling = .scaleAxesIndependently
            container.addSubview(picture)
        }
        for display in displays.dropFirst() {
            let seam = NSBox(frame: appKit(CGRect(x: display.minX, y: display.minY, width: 1, height: display.height)))
            seam.boxType = .custom
            seam.fillColor = .black
            seam.borderWidth = 0
            container.addSubview(seam)
        }
        for area in areas {
            for piece in RecordingBorderGeometry.pieces(around: area, displays: displays) {
                let view = RecordingBorderView(frame: appKit(piece.frame))
                view.piece = piece
                container.addSubview(view)
            }
        }
        let window = NSWindow(contentRect: container.frame, styleMask: [.borderless], backing: .buffered, defer: false)
        window.contentView = container
        return capture(container)
    }

    /// The print options form with the colours, rotation and footer locked by a profile.
    private static func lockedPrintOptions() -> NSView {
        let policy = ManagedPolicy(source: ManagedValues(forced: ["Greenshot.printing.grayscale": true,
                                                                  "Greenshot.printing.allowRotate": true,
                                                                  "Greenshot.printing.footer": false]))
        let options = policy.effective(AppSettings()).printing
        let form = PrintOptionsForm(options: options, policy: policy)
        keepAlive.append(form)
        return form.view
    }

    /// The menu bar menu's record items without a recording, then the items of a running one.
    private static func recordingMenus(settings: SettingsStore) -> String {
        let controller = VideoRecordingController(settings: settings, saver: ImageSaver(settings: settings))
        let idle = NSMenu()
        controller.addMenuItems(to: idle)
        var text = "Menu bar menu, no recording:\n" + menuText(idle)
        let hotkey = KeyCombo(keyCode: 15, modifiers: KeyCombo.control | KeyCombo.option | KeyCombo.command)
        let states: [(String, RecordingIndicatorState)] = [("counting down", .countdown(3)), ("starting", .starting),
                                                           ("recording", .recording(42)),
                                                           ("paused", .paused(42)), ("saving", .saving)]
        for (name, state) in states {
            let menu = NSMenu()
            RecordingMenus.items(for: state, hotkey: hotkey, actions: RecordingActions()).forEach(menu.addItem)
            text += "\nWhile \(name) (hotkey ⌃⌥⌘R):\n" + menuText(menu)
        }
        return text
    }

    /// One line per item, submenus indented; the key equivalent after a tab. Also for the other areas' menu dumps.
    static func menuText(_ menu: NSMenu, indent: String = "") -> String {
        var lines = ""
        for item in menu.items {
            if item.isSeparatorItem {
                lines += indent + "---\n"
                continue
            }
            var line = indent + item.title
            if !item.keyEquivalent.isEmpty {
                let flags = item.keyEquivalentModifierMask
                let symbols: [(NSEvent.ModifierFlags, String)] = [(.control, "⌃"), (.option, "⌥"), (.shift, "⇧"), (.command, "⌘")]
                line += "\t" + symbols.filter { flags.contains($0.0) }.map(\.1).joined() + item.keyEquivalent.uppercased()
            }
            if !item.isEnabled { line += " (disabled)" }
            lines += line + "\n"
            if let submenu = item.submenu { lines += menuText(submenu, indent: indent + "    ") }
        }
        return lines
    }

    static func writeText(_ text: String, to url: URL) throws {
        try text.write(to: url, atomically: true, encoding: .utf8)
        print("Wrote \(url.path)")
    }
}
