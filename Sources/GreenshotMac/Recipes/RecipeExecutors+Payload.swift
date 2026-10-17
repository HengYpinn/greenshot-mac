// Greenshot for Mac (Community) - an unofficial macOS port of Greenshot
// Copyright (C) 2026 Greenshot for Mac (Community) contributors
// Based on Greenshot, Copyright (C) 2007-2026 Thomas Braun, Jens Klingen, Robin Krom
// SPDX-License-Identifier: GPL-3.0-or-later

import AppKit
import GreenshotCore

/// The flow's capture (`RecipePayload`, upstream `ICapturePayload`) and the app's `Capture` / `EditorDocument`.
extension RecipePayload {
    /// A capture of the app: the mouse pointer becomes a movable element on the plain picture (upstream's
    /// `CursorContainer`), so effects move it along and the editor can move or delete it; an editor's capture keeps its
    /// elements.
    init(capture: Capture, sourceType: String) {
        if let editable = capture.editable {
            self.init(image: editable.image, scale: editable.scale, title: capture.title, captureDate: capture.date)
            annotations = editable.elements
        } else if let pointer = capture.pointer, let plain = capture.imageWithoutPointer,
                  let element = Annotation.pointer(pointer, documentScale: capture.scale,
                                                   imageSize: CGSize(width: plain.width, height: plain.height)) {
            self.init(image: plain, scale: capture.scale, title: capture.title, captureDate: capture.date)
            annotations = [element]
        } else {
            self.init(image: capture.image, scale: capture.scale, title: capture.title, captureDate: capture.date)
        }
        self.sourceType = sourceType
        metadata["CaptureMode"] = .string(sourceType)
        if !capture.title.isEmpty { metadata["WindowTitle"] = .string(capture.title) }
    }

    /// The capture for the app's destinations: the elements drawn in, and kept as elements for a `.greenshot` save.
    /// Remembers the capture's metadata (`source`, `url`, …) for the file name patterns of the export (BROWSER's
    /// `${source}`, `${url}`).
    @MainActor
    func exportCapture() -> Capture {
        CaptureMetadataStore.shared.record(patternMetadata, forCaptureAt: captureDate)
        var capture = Capture(image: flattened() ?? image, scale: scale, title: title, date: captureDate, text: nil)
        if !annotations.isEmpty {
            capture.editable = GreenshotFile.Contents(image: image, scale: scale, elements: annotations, title: title,
                                                      captureDate: captureDate)
        }
        return capture
    }

    /// The metadata as pattern values.
    var patternMetadata: [String: String] {
        var values: [String: String] = [:]
        for (key, value) in metadata where !value.isNull { values[key] = value.interpolationText }
        return values
    }

    /// The capture as an editor document, its elements still editable.
    @MainActor
    func editorDocument() -> EditorDocument {
        let document = EditorDocument(image: image, scale: scale, title: title, captureDate: captureDate)
        document.addOpened(annotations)
        return document
    }

    /// An editor's document as a payload (Source CurrentEditor).
    @MainActor
    init(document: EditorDocument) {
        self.init(image: document.baseImage, scale: document.scale, title: document.title, captureDate: document.captureDate)
        annotations = document.annotations
        fileURL = document.fileURL
        sourceType = "CurrentEditor"
        metadata["source"] = .string("Editor")
        metadata["CaptureMode"] = .string("CurrentEditor")
    }
}
