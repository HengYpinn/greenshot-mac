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
