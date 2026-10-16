// Greenshot for Mac (Community) - an unofficial macOS port of Greenshot
// Copyright (C) 2026 Greenshot for Mac (Community) contributors
// SPDX-License-Identifier: GPL-3.0-or-later

import AppKit
import GreenshotCore

/// Opens editor windows and keeps them alive.
///
/// The app stays a menu bar app (no Dock icon) also while editors are open. A Dock app that gets activated from a
/// full screen app makes macOS jump to the desktop, away from where the user captured. Instead an editor opens where
/// the user is, also over a full screen app, and hides when another app is clicked; opening the app again (Spotlight,
/// Finder, the menu bar icon) brings the editors back.
@MainActor
final class EditorManager {
    private let settings: SettingsStore
    private let saver: ImageSaver
    private var controllers: [EditorWindowController] = []

    init(settings: SettingsStore, saver: ImageSaver) {
        self.settings = settings
        self.saver = saver
    }

    func open(_ capture: Capture) {
        open(EditorDocument(image: capture.image, scale: capture.scale, title: capture.title, captureDate: capture.date))
    }

    func open(fileURL: URL) {
        guard let loaded = ImageLoader.load(fileURL) else {
            ErrorPresenter.show(message: "The image could not be opened", detail: fileURL.lastPathComponent)
            return
        }
        open(EditorDocument(image: loaded.image, scale: loaded.scale, title: fileURL.deletingPathExtension().lastPathComponent,
                            fileURL: fileURL, isModified: false))
    }

    func openClipboard() {
        guard let pasted = Clipboard.image() else {
            ErrorPresenter.show(message: "There is no image on the clipboard", detail: "Copy an image first, then try again.")
            return
        }
        open(EditorDocument(image: pasted.image, scale: pasted.scale, title: "Clipboard"))
    }

    func chooseAndOpenFile() {
        let panel = NSOpenPanel()
        panel.allowedContentTypes = [.image]
        panel.allowsMultipleSelection = true
        NSApp.activate()
        guard panel.runModal() == .OK else { return }
        panel.urls.forEach(open(fileURL:))
    }

    var hasEditors: Bool { !controllers.isEmpty }

    /// Brings the open editors back after they hid. False when there are none.
    @discardableResult
    func showEditors() -> Bool {
        guard !controllers.isEmpty else { return false }
        NSApp.activate()
        for controller in controllers { controller.window?.orderFrontRegardless() }
        controllers.last?.window?.makeKey()
        return true
    }

    /// Asks about every changed screenshot before the app quits. False when the user cancelled.
    func confirmQuit() -> Bool {
        controllers.allSatisfy { $0.confirmCloseBeforeQuit() }
    }

    private func open(_ document: EditorDocument) {
        let controller = EditorWindowController(document: document, settings: settings, saver: saver) { [weak self] closed in
            self?.controllers.removeAll { $0 === closed }
        }
        controllers.append(controller)
        guard let window = controller.window else { return }
        // Shown before the (asynchronous since macOS 14) activation finishes, so it doesn't wait on the app in front.
        window.makeKeyAndOrderFront(nil)
        window.orderFrontRegardless()
        NSApp.activate()
    }
}
