// Greenshot for Mac (Community) - an unofficial macOS port of Greenshot
// Copyright (C) 2026 Greenshot for Mac (Community) contributors
// SPDX-License-Identifier: GPL-3.0-or-later

import AppKit
import GreenshotCore
import SwiftUI

extension Snapshots {
    /// Renders of the screen recording: Settings › Video, the menu bar indicator and the countdown. A recording itself
    /// needs the screen recording permission; `recording-menu.txt` and `video-picker-menu.txt` list the menus.
    static func renderVideoExtras(to folder: URL, sample: CGImage, settings: SettingsStore) throws {
        try write(settingsTab(SettingsPane.video.rawValue, settings: settings), to: folder.appendingPathComponent("settings-video.png"))
        try write(customVideoSettings(), to: folder.appendingPathComponent("settings-video-custom.png"))
        try write(recordingIndicators(), to: folder.appendingPathComponent("recording-indicator.png"))
        try write(recordingCountdown(sample: sample), to: folder.appendingPathComponent("recording-countdown.png"))
        try writeText(recordingMenus(settings: settings), to: folder.appendingPathComponent("recording-menu.txt"))
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
        let states: [RecordingIndicatorState] = [.countdown(3), .recording(42), .paused(3725), .saving]
        let strip = NSView(frame: NSRect(x: 0, y: 0, width: 440, height: 24))
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

    /// The menu bar menu's record items without a recording, then the items of a running one.
    private static func recordingMenus(settings: SettingsStore) -> String {
        let controller = VideoRecordingController(settings: settings, saver: ImageSaver(settings: settings))
        let idle = NSMenu()
        controller.addMenuItems(to: idle)
        var text = "Menu bar menu, no recording:\n" + menuText(idle)
        let hotkey = KeyCombo(keyCode: 15, modifiers: KeyCombo.control | KeyCombo.option | KeyCombo.command)
        let states: [(String, RecordingIndicatorState)] = [("counting down", .countdown(3)), ("recording", .recording(42)),
                                                           ("paused", .paused(42)), ("saving", .saving)]
        for (name, state) in states {
            let menu = NSMenu()
            RecordingMenus.items(for: state, hotkey: hotkey, actions: RecordingActions()).forEach(menu.addItem)
            text += "\nWhile \(name) (hotkey ⌃⌥⌘R):\n" + menuText(menu)
        }
        return text
    }

    /// One line per item, submenus indented; the key equivalent after a tab.
    private static func menuText(_ menu: NSMenu, indent: String = "") -> String {
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

    private static func writeText(_ text: String, to url: URL) throws {
        try text.write(to: url, atomically: true, encoding: .utf8)
        print("Wrote \(url.path)")
    }
}
