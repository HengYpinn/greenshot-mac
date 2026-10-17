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
    /// Keeps unsaved editors for the next start (EditorSessionKeeper.swift).
    private lazy var sessions = EditorSessionKeeper.standard()
    private let log = Log("Editor")

    init(settings: SettingsStore, saver: ImageSaver) {
        self.settings = settings
        self.saver = saver
    }

    func open(_ capture: Capture) {
        if settings.value.reuseEditor, let editor = reusableEditor() {
            editor.show(capture.editorImage, scale: capture.scale, title: capture.title, date: capture.date)
            editor.addCapturedPointer(of: capture)
            guard let window = editor.window else { return }
            window.makeKeyAndOrderFront(nil)
            window.orderFrontRegardless()
            NSApp.activate()
            return
        }
        open(EditorDocument(image: capture.editorImage, scale: capture.scale, title: capture.title, captureDate: capture.date))
        controllers.last?.addCapturedPointer(of: capture)
    }

    /// Opens the unsaved editors kept when the app last quit for a logout, restart or shut down, or ended without
    /// quitting (upstream `RestartManagerHelper.RestoreState` with `--restore`). They are still unsaved, and Save goes to
    /// the file they showed.
    func restoreSavedEditors() {
        let crashed = (NSApp.delegate as? AppDelegate)?.previousRunEndedAbnormally ?? false
        let files = sessions.keptFiles()
        guard !files.isEmpty else { return }
        log.info("Restoring \(files.count) unsaved editors (the last run ended abnormally: \(crashed))")
        for file in files {
            guard let kept = sessions.claim(file), let session = kept.contents.session else { continue }
            let document = EditorDocument(restoring: kept.contents) { FileManager.default.fileExists(atPath: $0.path) }
            let controller = open(document)
            sessions.adopt(kept, for: document)
            let message: String
            switch session.reason {
            case .quit: message = "Reopened after the last logout or restart, not saved yet."
            case .autosave where crashed: message = "Restored after Greenshot quit unexpectedly, not saved yet."
            case .autosave: message = "Restored, not saved yet."
            }
            controller.showStatusMessage(message)
        }
        sessions.settleRestoredEditors()
    }

    /// The editor a new capture goes to with "reuse the editor": like upstream `EditorDestination`, the front-most one
    /// without unsaved changes. A capture is unsaved until it is saved or exported, so often every editor has changes:
    /// then the front one asks to save first instead of opening another window (upstream would); Cancel opens a new
    /// editor.
    private func reusableEditor() -> EditorWindowController? {
        let editors = editorsFrontToBack()
        for editor in editors {
            editor.canvas.commitEditing()
            if !editor.editorDocument.isModified { return editor }
        }
        guard let front = editors.first, front.confirmReplace() else { return nil }
        return front
    }

    /// The editors, front-most first; hidden ones (another app is active) after those on screen, newest first.
    private func editorsFrontToBack() -> [EditorWindowController] {
        let onScreen = NSApp.orderedWindows.compactMap { window in controllers.first { $0.window === window } }
        return onScreen + controllers.reversed().filter { editor in !onScreen.contains { $0 === editor } }
    }

    /// The front-most editor.
    private func frontEditor() -> EditorWindowController? {
        editorsFrontToBack().first
    }

    /// Closes every editor, asking about each changed screenshot; stops when the user cancels.
    func closeAll() {
        for controller in controllers {
            guard controller.confirmCloseBeforeQuit() else { return }
            controller.window?.close()
        }
    }

    func open(fileURL: URL) {
        if GreenshotFile.isGreenshotFile(fileURL) {
            openGreenshotFile(fileURL)
            return
        }
        guard let loaded = ImageLoader.load(fileURL) else {
            ErrorPresenter.show(message: "The image could not be opened", detail: fileURL.lastPathComponent)
            return
        }
        open(EditorDocument(image: loaded.image, scale: loaded.scale, title: fileURL.deletingPathExtension().lastPathComponent,
                            fileURL: fileURL, isModified: false))
    }

    /// Opens a `.greenshot` file (upstream `ImageIO.LoadGreenshotSurface`): the image and its elements, which stay
    /// editable. A file of Greenshot for Windows shows the elements this editor has; the status bar names the others.
    private func openGreenshotFile(_ url: URL) {
        guard let contents = GreenshotFile.read(contentsOf: url) else {
            ErrorPresenter.show(message: "The Greenshot file could not be opened", detail: url.lastPathComponent)
            return
        }
        log.info("Opened a .greenshot file (\(contents.origin)) with \(contents.elements.count) elements, "
                 + "\(contents.unreadable.count) left out")
        let controller = open(EditorDocument(opening: contents, from: url))
        if let message = contents.openStatus { controller.showStatusMessage(message, isError: contents.elementsFailed) }
    }

    /// Opens the image on the clipboard; for a copied web page part, the image it shows is downloaded first (upstream
    /// `ClipboardHelper` reads `<img src>` from the HTML on the clipboard).
    func openClipboard() {
        if let pasted = Clipboard.image() {
            open(EditorDocument(image: pasted.image, scale: pasted.scale, title: "Clipboard"))
            return
        }
        Task { @MainActor [weak self] in
            guard let downloaded = await ImageLoader.downloadedHTMLImage() else {
                ErrorPresenter.show(message: "There is no image on the clipboard", detail: "Copy an image first, then try again.")
                return
            }
            self?.open(EditorDocument(image: downloaded.image, scale: downloaded.scale, title: "Clipboard"))
        }
    }

    func chooseAndOpenFile() {
        let panel = NSOpenPanel()
        panel.allowedContentTypes = [.image, EditorWindowController.greenshotFileType]
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

    /// Asks about every changed screenshot before the app quits. False when the user cancelled. When macOS logs out,
    /// restarts or shuts down (or keeps windows at quit), the changed screenshots are kept for the next start instead,
    /// without asking: a question would cancel the logout (upstream `RestartManagerHelper.SaveEditorState`).
    func confirmQuit() -> Bool {
        for controller in controllers { controller.canvas.commitEditing() }
        if controllers.contains(where: { $0.editorDocument.isModified }), sessions.quitKeepsEditors() {
            sessions.keep(controllers.map(\.editorDocument))
        } else {
            guard controllers.allSatisfy({ $0.confirmCloseBeforeQuit() }) else { return false }
            // Every screenshot was saved or its changes discarded.
            sessions.forgetAll()
        }
        // Quitting doesn't close the windows: the front editor's place is the one the next editor gets.
        frontEditor()?.savePlacement()
        return true
    }

    @discardableResult
    private func open(_ document: EditorDocument) -> EditorWindowController {
        let controller = EditorWindowController(document: document, settings: settings, saver: saver) { [weak self] closed in
            self?.controllers.removeAll { $0 === closed }
            self?.sessions.forget(closed.editorDocument.id)
            self?.onWindowsChange?()
        }
        controller.onCloseAll = { [weak self] in self?.closeAll() }
        controller.onDocumentStateChange = { [weak self] changed in self?.sessions.documentChanged(changed.editorDocument) }
        controllers.append(controller)
        onWindowsChange?()
        sessions.documentChanged(document)
        guard let window = controller.window else { return controller }
        // Shown before the (asynchronous since macOS 14) activation finishes, so it doesn't wait on the app in front.
        window.makeKeyAndOrderFront(nil)
        window.orderFrontRegardless()
        NSApp.activate()
        followSpaceSwitch(of: window)
        return controller
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

    /// The open editors, sorted by title like upstream's `ImageEditorForm.Editors`.
    var openEditors: [OpenEditor] {
        controllers.map { OpenEditor(id: $0.editorDocument.id, title: $0.editorDocument.title) }
            .sorted { $0.title.localizedStandardCompare($1.title) == .orderedAscending }
    }

    /// Adds a capture to an open editor as an image element 10 points from the top left (upstream
    /// `Surface.AddImageContainer(image, 10, 10)`), selects it and brings that editor to the front. False when the
    /// editor was closed meanwhile or the image could not be added.
    @discardableResult
    func addImage(_ capture: Capture, toEditor id: UUID) -> Bool {
        guard let editor = controllers.first(where: { $0.editorDocument.id == id }) else { return false }
        let document = editor.editorDocument
        editor.canvas.commitEditing()
        let origin = CGPoint(x: 10 * document.scale, y: 10 * document.scale)
        let room = CGSize(width: max(document.imageSize.width - origin.x, 1), height: max(document.imageSize.height - origin.y, 1))
        guard let element = Annotation.picture(capture.image, pictureScale: capture.scale, at: origin,
                                               documentScale: document.scale, fitting: room) else { return false }
        editor.canvas.insert([element])
        editor.window?.makeKeyAndOrderFront(nil)
        NSApp.activate()
        return true
    }

    /// An editor with a blank white image (upstream `TrayActions.OpenEmptyEditor` and `ImageEditorForm()`): Settings ›
    /// Editor's size (upstream `DefaultEditorSize`, 500 × 500) in points, at the screen's resolution. It counts as
    /// unchanged until something is drawn on it.
    func openEmptyEditor() {
        let size = settings.value.defaultEditorSize
        let scale = NSScreen.main?.backingScaleFactor ?? 2
        guard let image = EditorWindowPlacement.blankImage(points: CGSize(width: max(size.width, 1), height: max(size.height, 1)),
                                                           scale: scale) else { return }
        open(EditorDocument(image: image, scale: scale, title: "Untitled", isModified: false))
    }
}

/// An open editor, for upstream's "Add to editor - <title>" destinations (`EditorDestination(IImageEditor)`; upstream
/// shows the first 20 characters of the title).
struct OpenEditor: Equatable {
    /// `EditorDocument.id`: stays the same while the window is open, also when a reused editor gets a new capture.
    let id: UUID
    let title: String
}
