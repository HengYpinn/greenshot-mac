// Greenshot for Mac (Community) - an unofficial macOS port of Greenshot
// Copyright (C) 2026 Greenshot for Mac (Community) contributors
// Based on Greenshot, Copyright (C) 2007-2026 Thomas Braun, Jens Klingen, Robin Krom
// SPDX-License-Identifier: GPL-3.0-or-later

import AppKit
import GreenshotCore

/// Exports from the editor and what they leave: the status bar message (upstream `SurfaceMessageReceived`,
/// `UpdateStatusLabel`), the saved file and the upload link (`Surface.LastSaveFullPath`, `UploadUrl`), and the menu
/// on the message after a save (`fileSavedStatusContextMenu`: copy the path, show the folder).
extension EditorWindowController {
    /// The time in front of a message (upstream `DateTime.Now.ToLongTimeString()`).
    private static let timeFormatter: DateFormatter = {
        let formatter = DateFormatter()
        formatter.dateStyle = .none
        formatter.timeStyle = .medium
        return formatter
    }()

    /// Shows a message in the status bar (upstream `UpdateStatusLabel`): errors in red with a warning sign.
    func showStatusMessage(_ message: String, isError: Bool = false) {
        let line = EditorWindowStatus.line(.init(text: message, isError: isError), time: Self.timeFormatter.string(from: Date()))
        statusBar.setMessage(line, isError: isError, menu: nil)
    }

    /// Shows how an export of this editor's image ended (upstream `ExportResultHandler` + `SurfaceMessageReceived`),
    /// remembers its file or link and clears the unsaved-changes mark when the result says so. `destination` names the
    /// destination, e.g. "Clipboard", "Upload to Box".
    func showExportResult(_ result: ExportResult, destination: String) {
        guard result.status != .declined else { return }
        var menu: NSMenu?
        if result.isSucceeded {
            // Only a save counts as this editor's file (upstream `LastSaveFullPath`): mail, Open With and the external
            // commands report the temporary file they were given, which must not end up behind Show in Finder.
            if let file = result.fileURL, result.clearsModified {
                lastSavedURL = file
                menu = savedFileMenu()
            }
            if let link = result.link {
                uploadURL = link
                menu = uploadMenu()
            }
            if result.clearsModified {
                editorDocument.markSaved()
                refreshDocumentState()
            }
        }
        guard let message = EditorWindowStatus.message(for: result, destination: destination) else { return }
        let line = EditorWindowStatus.line(message, time: Self.timeFormatter.string(from: Date()))
        statusBar.setMessage(line, isError: message.isError, menu: message.isError ? nil : menu)
    }

    /// This editor's image as a capture for the destinations, with the document for a save as `.greenshot` file.
    var currentCapture: Capture {
        Capture(image: editorDocument.flattened(), scale: editorDocument.scale, title: editorDocument.title,
                date: editorDocument.captureDate, editable: GreenshotFile.Contents(of: editorDocument))
    }

    /// Sends this editor's image to a destination (the toolbar's destination buttons, Print), the way the File menu's
    /// entries do: the output manager runs it and reports back with `showExportResult`.
    func export(_ target: DestinationTarget) {
        canvas.commitEditing()
        guard let output = (NSApp.delegate as? AppDelegate)?.output else { return }
        output.perform(target, with: currentCapture, window: window)
    }

    private func savedFileMenu() -> NSMenu {
        let menu = NSMenu(title: String(localized: "Saved file"))
        let copy = menu.addItem(withTitle: String(localized: "Copy Path to Clipboard"), action: #selector(copyFilePath(_:)), keyEquivalent: "")
        copy.target = self
        let show = menu.addItem(withTitle: String(localized: "Show in Finder"), action: #selector(showInFinder(_:)), keyEquivalent: "")
        show.target = self
        return menu
    }

    private func uploadMenu() -> NSMenu {
        let menu = NSMenu(title: String(localized: "Upload"))
        let copy = menu.addItem(withTitle: String(localized: "Copy Link"), action: #selector(copyUploadLink(_:)), keyEquivalent: "")
        copy.target = self
        let open = menu.addItem(withTitle: String(localized: "Open Link"), action: #selector(openUploadLink(_:)), keyEquivalent: "")
        open.target = self
        return menu
    }

    /// Upstream "Copy path to clipboard" of the saved file.
    @objc func copyFilePath(_ sender: Any?) {
        guard let url = lastSavedURL else { return }
        Clipboard.copy(text: url.path)
    }

    /// Upstream "Open directory in Explorer": the file in Finder, or its folder when the file is gone.
    @objc func showInFinder(_ sender: Any?) {
        guard let url = lastSavedURL else { return }
        if FileManager.default.fileExists(atPath: url.path) {
            NSWorkspace.shared.activateFileViewerSelecting([url])
        } else {
            NSWorkspace.shared.open(url.deletingLastPathComponent())
        }
    }

    @objc func copyUploadLink(_ sender: Any?) {
        guard let url = uploadURL else { return }
        Clipboard.copy(text: url.absoluteString)
    }

    @objc func openUploadLink(_ sender: Any?) {
        guard let url = uploadURL else { return }
        NSWorkspace.shared.open(url)
    }

    /// The menu items of this file: nil for the others.
    func validateExportMenuItem(_ item: NSMenuItem) -> Bool? {
        switch item.action {
        case #selector(copyFilePath(_:)), #selector(showInFinder(_:)): return lastSavedURL != nil
        case #selector(copyUploadLink(_:)), #selector(openUploadLink(_:)): return uploadURL != nil
        default: return nil
        }
    }
}
