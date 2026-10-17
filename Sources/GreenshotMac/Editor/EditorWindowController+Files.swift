// Greenshot for Mac (Community) - an unofficial macOS port of Greenshot
// Copyright (C) 2026 Greenshot for Mac (Community) contributors
// Based on Greenshot, Copyright (C) 2007-2026 Thomas Braun, Jens Klingen, Robin Krom
// SPDX-License-Identifier: GPL-3.0-or-later

import AppKit
import GreenshotCore
import UniformTypeIdentifiers

/// `.greenshot` files from the editor (upstream `GreenshotFileFormatHandler`, the "Greenshot Editor" format of the save
/// dialog): the image with elements that stay editable. Save writes a `.greenshot` file in place, File › Save as
/// Greenshot File asks where.
extension EditorWindowController {
    private static let log = Log("Greenshot file")

    /// The type of `.greenshot` files: the one in Info.plist, or (in a `swift build` without the app bundle) the type
    /// macOS makes up for the extension.
    static var greenshotFileType: UTType { ImageFormat.greenshot.utType }

    /// The element files of Greenshot for Windows (`.gst`).
    static var windowsElementsFileType: UTType {
        UTType(filenameExtension: GreenshotFile.templateExtension, conformingTo: .data) ?? .data
    }

    /// File › Save as Greenshot File: asks for a `.greenshot` file and writes the image and its elements there.
    @objc func saveAsGreenshotFile(_ sender: Any?) {
        canvas.commitEditing()
        let document = editorDocument
        let panel = NSSavePanel()
        panel.title = "Save as Greenshot File"
        panel.message = "The elements stay editable when the file is opened again."
        panel.allowedContentTypes = [Self.greenshotFileType]
        let current = document.fileURL
        let name = current.map { $0.deletingPathExtension().lastPathComponent + "." + GreenshotFile.fileExtension }
        guard let url = saver.runSavePanel(panel, title: document.title, date: document.captureDate,
                                           fileExtension: GreenshotFile.fileExtension, editorFile: current, fileName: name) else { return }
        do {
            try GreenshotFile.write(document, to: url)
        } catch {
            saveFailed(url, destination: "Save as Greenshot File", error: error)
            return
        }
        saved(url, destination: "Save as Greenshot File")
    }

    /// Save of a document whose file is a `.greenshot`: written over it, unless the document `savesToNewFile` (a file
    /// of Greenshot for Windows, or one with elements this version could not read); the save dialog asks then.
    func saveGreenshotFile() -> Bool {
        let document = editorDocument
        do {
            guard try GreenshotFile.saveInPlace(document), let url = document.fileURL else {
                saveAsGreenshotFile(nil)
                return !document.isModified
            }
            saved(url, destination: "Save")
            return true
        } catch {
            saveFailed(document.fileURL, destination: "Save", error: error)
            return false
        }
    }

    private func saved(_ url: URL, destination: String) {
        Self.log.info("Saved a .greenshot file with \(editorDocument.annotations.count) elements")
        saver.notifySaved(url)
        showExportResult(.succeeded(fileURL: url), destination: destination)
    }

    private func saveFailed(_ url: URL?, destination: String, error: Error) {
        let name = url?.lastPathComponent ?? "the file"
        Self.log.error("Saving \(name) failed", error: error)
        ErrorPresenter.show(message: "The screenshot could not be saved to \(name)", detail: error.localizedDescription)
        showExportResult(.failed(error.localizedDescription), destination: destination)
    }

    /// The elements of a Greenshot for Windows `.gst` file (Object › Load Elements), for this image, with the message
    /// about those that can't be shown. Nil (after saying so) when the file can't be read.
    func windowsElements(from url: URL) -> (elements: [Annotation], message: String?)? {
        do {
            let data = try Data(contentsOf: url, options: .mappedIfSafe)
            let template = try GreenshotFile.readTemplate(data, scale: editorDocument.scale)
            return (template.elements, GreenshotFile.unreadableMessage(template.unreadable))
        } catch {
            Self.log.error("The elements of \(url.lastPathComponent) could not be read", error: error)
            ErrorPresenter.show(message: "The elements could not be loaded", detail: url.lastPathComponent)
            return nil
        }
    }
}
