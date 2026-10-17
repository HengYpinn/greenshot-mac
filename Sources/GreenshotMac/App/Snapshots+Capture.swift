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
