// Greenshot for Mac (Community) - an unofficial macOS port of Greenshot
// Copyright (C) 2026 Greenshot for Mac (Community) contributors
// SPDX-License-Identifier: GPL-3.0-or-later

import AppKit
import Carbon.HIToolbox
import GreenshotCore
import SwiftUI

extension Snapshots {
    /// Renders for the capture screen and the hotkey settings. Writes PNG files into `folder` with `write(_:to:)`; the helpers in Snapshots.swift
    /// (`editorWindow`, `overlay`, `form`, `settingsTab`, `capture`) do most of the work.
    static func renderCaptureExtras(to folder: URL, sample: CGImage, settings: SettingsStore) throws {
        try write(hotkeys(), to: folder.appendingPathComponent("settings-hotkeys.png"))
        // The region mode before a drag: the dotted crosshair with the position, the zoomer a fifth of the display.
        try write(captureScreen(sample: sample) { $0.mouseMoved(to: CGPoint(x: 700, y: 400)) },
                  to: folder.appendingPathComponent("capture-crosshair.png"))
        // A see-through zoomer (ZoomerOpacity 0.7) showing the edges of a fixed size area.
        try write(captureScreen(sample: sample, change: { $0.zoomerOpacity = 0.7 }) { controller in
            controller.switchMode(to: .fixedSize)
            controller.mouseMoved(to: CGPoint(x: 640, y: 360))
        }, to: folder.appendingPathComponent("capture-zoomer-translucent.png"))
        try renderWindowAreas(to: folder, sample: sample)
    }

    /// The areas inside a window (CAP-073): a made-up tree for the sample's window, as the Accessibility API would tell it.
    private static var sampleAreas: WindowArea {
        let chart = WindowArea(frame: CGRect(x: 100, y: 150, width: 450, height: 210), role: "AXGroup", name: "group “Chart”")
        let summary = WindowArea(frame: CGRect(x: 90, y: 390, width: 520, height: 110), role: "AXGroup", name: "group “Summary”")
        let image = WindowArea(frame: CGRect(x: 870, y: 150, width: 240, height: 180), role: "AXImage", name: "image “Sales by region”")
        let web = WindowArea(frame: CGRect(x: 50, y: 94, width: 1140, height: 646), role: "AXWebArea",
                             name: "HTML content “Quarterly report”", children: [chart, summary, image])
        let scroll = WindowArea(frame: web.frame, role: "AXScrollArea", name: "scroll area", children: [web])
        let toolbar = WindowArea(frame: CGRect(x: 50, y: 50, width: 1140, height: 44), role: "AXToolbar", name: "toolbar")
        return WindowArea(frame: CGRect(x: 50, y: 50, width: 1140, height: 690), role: "AXWindow", name: "standard window",
                          children: [toolbar, scroll])
    }

    private static func key(_ code: Int, _ characters: String = "") -> NSEvent {
        NSEvent.keyEvent(with: .keyDown, location: .zero, modifierFlags: [], timestamp: 0, windowNumber: 0, context: nil,
                         characters: characters, charactersIgnoringModifiers: characters, isARepeat: false,
                         keyCode: UInt16(code))!
    }

    private static func renderWindowAreas(to folder: URL, sample: CGImage) throws {
        let areasOn: (inout AppSettings) -> Void = { $0.windowCaptureSelectsAreas = true }
        // The smallest area under the mouse, with the keys and the details (D).
        try write(captureScreen(sample: sample, change: areasOn) { controller in
            controller.pretendAreas()
            controller.switchMode(to: .window)
            controller.useWindowAreas(sampleAreas, for: 1)
            controller.mouseMoved(to: CGPoint(x: 300, y: 250))
            controller.keyDown(key(kVK_ANSI_D, "d"))
        }, to: folder.appendingPathComponent("capture-window-areas.png"))
        // PgUp: the area around it.
        try write(captureScreen(sample: sample, change: areasOn) { controller in
            controller.pretendAreas()
            controller.switchMode(to: .window)
            controller.useWindowAreas(sampleAreas, for: 1)
            controller.mouseMoved(to: CGPoint(x: 300, y: 250))
            controller.keyDown(key(kVK_PageUp))
        }, to: folder.appendingPathComponent("capture-window-areas-larger.png"))
        // The app takes its time: the whole window and the turning mark.
        try write(captureScreen(sample: sample, change: areasOn) { controller in
            controller.pretendAreas(reading: 1, since: 1)
            controller.switchMode(to: .window)
            controller.mouseMoved(to: CGPoint(x: 300, y: 250))
        }, to: folder.appendingPathComponent("capture-window-areas-busy.png"))
        // The setting is on but Accessibility isn't allowed: whole windows, and the info panel says what to do.
        try write(captureScreen(sample: sample, change: areasOn) { controller in
            controller.switchMode(to: .window)
            controller.mouseMoved(to: CGPoint(x: 300, y: 250))
        }, to: folder.appendingPathComponent("capture-window-areas-no-access.png"))
        try write(captureSettings(), to: folder.appendingPathComponent("settings-capture-areas.png"))
    }

    /// The new rows of Settings › Capture, the areas turned on without the Accessibility permission.
    private static func captureSettings() -> NSBitmapImageRep? {
        let suite = "greenshot-mac-snapshots-capture-areas"
        let defaults = UserDefaults(suiteName: suite)!
        defaults.removePersistentDomain(forName: suite)
        let store = SettingsStore(defaults: defaults)
        store.update { $0.windowCaptureSelectsAreas = true }
        let root = Form {
            Section("Capturing") {
                Toggle("Keep the window shadow in window captures", isOn: store.binding(\.includeWindowShadow))
                WindowAreasSetting(store: store, accessibility: AccessibilityStatus(fixed: false))
                HDRSetting(store: store)
            }
        }.formStyle(.grouped)
        let hosting = NSHostingView(rootView: root)
        hosting.frame = NSRect(x: 0, y: 0, width: 620, height: 260)
        let window = NSWindow(contentRect: hosting.frame, styleMask: [.titled], backing: .buffered, defer: false)
        window.contentView = hosting
        keepAlive.append(window)
        hosting.layoutSubtreeIfNeeded()
        return capture(hosting)
    }

    /// The capture screen on the sample after `act`, with settings changed by `change` (`overlay(sample:mode:)` without
    /// its fixed steps).
    private static func captureScreen(sample: CGImage, change: (inout AppSettings) -> Void = { _ in },
                                      act: (CaptureOverlayController) -> Void) -> NSBitmapImageRep? {
        let suite = "greenshot-mac-snapshots-capture"
        let defaults = UserDefaults(suiteName: suite)!
        defaults.removePersistentDomain(forName: suite)
        let store = SettingsStore(defaults: defaults)
        store.update(change)
        let screen = FrozenScreen(displayID: 1, frame: CGRect(x: 0, y: 0, width: 1280, height: 800), scale: 2, image: sample)
        let windows = [WindowInfo(id: 1, frame: CGRect(x: 50, y: 50, width: 1140, height: 690), title: "Quarterly report",
                                  appName: "Preview", pid: 1)]
        let controller = CaptureOverlayController(screens: [screen], windows: windows, mode: .region, zoomer: true,
                                                  settings: store) { _ in }
        let view = OverlayMarksView(frame: NSRect(x: 0, y: 0, width: 1280, height: 800), frozen: screen, controller: controller)
        act(controller)
        let size = view.bounds.size
        guard let rep = NSBitmapImageRep(bitmapDataPlanes: nil, pixelsWide: Int(size.width * 2), pixelsHigh: Int(size.height * 2),
                                         bitsPerSample: 8, samplesPerPixel: 4, hasAlpha: true, isPlanar: false,
                                         colorSpaceName: .deviceRGB, bytesPerRow: 0, bitsPerPixel: 0) else { return nil }
        // Points first, so the context draws at 2 pixels per point.
        rep.size = size
        guard let context = NSGraphicsContext(bitmapImageRep: rep) else { return nil }
        NSGraphicsContext.saveGraphicsState()
        NSGraphicsContext.current = context
        NSImage(cgImage: sample, size: size).draw(in: NSRect(origin: .zero, size: size))
        context.cgContext.translateBy(x: 0, y: size.height)
        context.cgContext.scaleBy(x: 1, y: -1)
        NSGraphicsContext.current = NSGraphicsContext(cgContext: context.cgContext, flipped: true)
        view.draw(view.bounds)
        NSGraphicsContext.restoreGraphicsState()
        return rep
    }

    /// The Hotkeys section with a hotkey of two steps, a clash and a message about keys that can't be used.
    private static func hotkeys() -> NSBitmapImageRep? {
        let defaults = UserDefaults(suiteName: "greenshot-mac-snapshots-hotkeys")!
        defaults.removePersistentDomain(forName: "greenshot-mac-snapshots-hotkeys")
        let store = SettingsStore(defaults: defaults)
        let all = KeyCombo.control | KeyCombo.option | KeyCombo.command
        store.update { values in
            values.hotkeys.text = KeyCombo(chords: [KeyChord(keyCode: UInt32(kVK_ANSI_K), modifiers: all),
                                                    KeyChord(keyCode: UInt32(kVK_ANSI_C), modifiers: 0)])
            values.hotkeys.clipboard = KeyCombo(keyCode: UInt32(kVK_ANSI_K), modifiers: all)
        }
        let problem = KeyCombo(keyCode: UInt32(kVK_ANSI_A), modifiers: KeyCombo.shift).validationProblem ?? ""
        let root = Form { HotkeysSection(store: store, initialProblems: ["Capture window": problem]) }.formStyle(.grouped)
        let hosting = NSHostingView(rootView: root)
        hosting.frame = NSRect(x: 0, y: 0, width: 620, height: 470)
        let window = NSWindow(contentRect: hosting.frame, styleMask: [.titled], backing: .buffered, defer: false)
        window.contentView = hosting
        keepAlive.append(window)
        hosting.layoutSubtreeIfNeeded()
        return capture(hosting)
    }
}
