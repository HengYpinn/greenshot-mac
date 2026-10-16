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
    private var spaceObserver: NSObjectProtocol?
    private var spaceFollowGeneration = 0

    init(settings: SettingsStore, saver: ImageSaver) {
        self.settings = settings
        self.saver = saver
    }

    func open(_ capture: Capture) {
        if settings.value.reuseEditor, let editor = frontEditor(), editor.confirmReplace() {
            // Upstream `EditorDestination` reuses an open editor. A new capture is always unsaved here, so instead of
            // skipping changed editors (upstream) the front one asks to save first; Cancel opens a new editor.
            editor.show(capture.image, scale: capture.scale, title: capture.title, date: capture.date)
            guard let window = editor.window else { return }
            window.makeKeyAndOrderFront(nil)
            window.orderFrontRegardless()
            NSApp.activate()
            return
        }
        open(EditorDocument(image: capture.image, scale: capture.scale, title: capture.title, captureDate: capture.date))
    }

    /// The front-most editor.
    private func frontEditor() -> EditorWindowController? {
        NSApp.orderedWindows.lazy.compactMap { window in self.controllers.first { $0.window === window } }.first
            ?? controllers.last
    }

    /// Closes every editor, asking about each changed screenshot; stops when the user cancels.
    func closeAll() {
        for controller in controllers {
            guard controller.confirmCloseBeforeQuit() else { return }
            controller.window?.close()
        }
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
    /// Called when an editor opened or closed (the Dock icon follows).
    var onWindowsChange: (() -> Void)?

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
            self?.onWindowsChange?()
        }
        controller.onCloseAll = { [weak self] in self?.closeAll() }
        controllers.append(controller)
        onWindowsChange?()
        guard let window = controller.window else { return }
        // Shown before the (asynchronous since macOS 14) activation finishes, so it doesn't wait on the app in front.
        window.makeKeyAndOrderFront(nil)
        window.orderFrontRegardless()
        NSApp.activate()
        followSpaceSwitch(of: window)
    }

    /// When the app turns into a Dock app as it is activated from a full screen app, macOS switches to the desktop,
    /// a moment after the window was shown on the full screen app's Space. Made key again after the switch, the window
    /// moves along (its collection behavior is moveToActiveSpace) instead of staying behind.
    private func followSpaceSwitch(of window: NSWindow) {
        stopFollowingSpaceSwitch()
        spaceFollowGeneration += 1
        let generation = spaceFollowGeneration
        spaceObserver = NSWorkspace.shared.notificationCenter.addObserver(
            forName: NSWorkspace.activeSpaceDidChangeNotification, object: nil, queue: .main) { [weak self, weak window] _ in
            MainActor.assumeIsolated {
                self?.stopFollowingSpaceSwitch()
                window?.makeKeyAndOrderFront(nil)
            }
        }
        // Only a switch right after opening is followed.
        DispatchQueue.main.asyncAfter(deadline: .now() + 1.5) { [weak self] in
            MainActor.assumeIsolated {
                if self?.spaceFollowGeneration == generation { self?.stopFollowingSpaceSwitch() }
            }
        }
    }

    private func stopFollowingSpaceSwitch() {
        if let spaceObserver { NSWorkspace.shared.notificationCenter.removeObserver(spaceObserver) }
        spaceObserver = nil
    }
}
