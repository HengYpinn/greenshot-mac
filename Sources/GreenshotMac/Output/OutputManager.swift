// Greenshot for Mac (Community) - an unofficial macOS port of Greenshot
// Copyright (C) 2026 Greenshot for Mac (Community) contributors
// Based on Greenshot, Copyright (C) 2007-2026 Thomas Braun, Jens Klingen, Robin Krom
// SPDX-License-Identifier: GPL-3.0-or-later

import AppKit
import GreenshotCore

/// Sends a capture to the configured destinations, or asks with upstream's destination picker menu.
@MainActor
final class OutputManager {
    private let settings: SettingsStore
    private let saver: ImageSaver
    private let editors: EditorManager

    init(settings: SettingsStore, saver: ImageSaver, editors: EditorManager) {
        self.settings = settings
        self.saver = saver
        self.editors = editors
    }

    func handle(_ capture: Capture) {
        let destinations = settings.value.destinations
        if destinations.isEmpty || destinations.contains(.picker) {
            showPicker(for: capture)
        } else {
            destinations.forEach { perform($0, with: capture) }
        }
    }

    func perform(_ destination: CaptureDestination, with capture: Capture) {
        switch destination {
        case .picker:
            showPicker(for: capture)
        case .editor:
            editors.open(capture)
        case .clipboard:
            Clipboard.copy(capture.image)
            saver.notify("Copied to the clipboard")
        case .file:
            saver.saveDirectly(capture.image, title: capture.title, date: capture.date)
        case .fileAs:
            saver.saveAs(capture.image, title: capture.title, date: capture.date)
        case .printer:
            Printing.print(capture.image, scale: capture.scale, window: nil)
        }
    }

    /// The menu at the mouse that asks where the capture goes.
    private func showPicker(for capture: Capture) {
        let menu = NSMenu(title: "Send screenshot to")
        menu.autoenablesItems = false
        let header = NSMenuItem(title: "\(capture.image.width) × \(capture.image.height) – \(capture.title)", action: nil, keyEquivalent: "")
        header.isEnabled = false
        menu.addItem(header)
        menu.addItem(.separator())
        let folder = (settings.value.outputFolderURL.path as NSString).abbreviatingWithTildeInPath
        let choices: [(CaptureDestination, String)] = [
            (.editor, "Open in Image Editor"),
            (.file, "Save Directly (\(folder))"),
            (.fileAs, "Save As…"),
            (.clipboard, "Copy to Clipboard"),
            (.printer, "Print…"),
        ]
        for (destination, title) in choices {
            // NSMenu sends the action after it has closed, so dialogs and windows open normally, and before
            // popUp returns, so the caller sees an opened editor when it decides where the focus goes.
            menu.addItem(ClosureMenuItem(title: title) { [weak self] in self?.perform(destination, with: capture) })
        }
        menu.addItem(.separator())
        menu.addItem(ClosureMenuItem(title: "Discard") {})
        // Activating (for keyboard navigation in the menu) while an editor window is open could switch to that
        // window's Space, away from where the user captured; the menu works with the mouse without it.
        if !NSApp.windows.contains(where: { $0.isVisible && $0.canBecomeMain }) {
            NSApp.activate()
        }
        menu.popUp(positioning: nil, at: NSEvent.mouseLocation, in: nil)
    }
}
