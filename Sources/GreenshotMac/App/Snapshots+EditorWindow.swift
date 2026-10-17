// Greenshot for Mac (Community) - an unofficial macOS port of Greenshot
// Copyright (C) 2026 Greenshot for Mac (Community) contributors
// SPDX-License-Identifier: GPL-3.0-or-later

import AppKit
import GreenshotCore

extension Snapshots {
    /// Renders for the editor window: toolbar, status bar, zoom. Writes PNG files into `folder` with `write(_:to:)`; the helpers in Snapshots.swift
    /// (`editorWindow`, `overlay`, `form`, `settingsTab`, `capture`) do most of the work.
    static func renderEditorWindowExtras(to folder: URL, sample: CGImage, settings: SettingsStore) throws {
        func url(_ name: String) -> URL { folder.appendingPathComponent(name) }
        let file = URL(fileURLWithPath: NSHomeDirectory()).appendingPathComponent("Desktop/Screenshot 2026-10-17 at 10.00.00.png")

        // After a save: the message with its menu, the size and the zoom button.
        try write(editorWindow(snapshotDocument(sample), settings: settings) { controller in
            controller.showExportResult(.succeeded(fileURL: file), destination: "Save")
        }, to: url("editor-status-saved.png"))

        // A failed upload: the message in red.
        try write(editorWindow(snapshotDocument(sample), settings: settings) { controller in
            controller.showExportResult(.failed("The server did not answer."), destination: "Upload to Dropbox")
        }, to: url("editor-status-error.png"))

        // The area highlight's blur and brightness, the crop tool's modes.
        try write(editorWindow(snapshotDocument(sample), settings: settings) { controller in
            var style = settings.value.style(for: .highlight)
            style.highlightMode = .area
            settings.update { $0.editorStyles[AnnotationKind.highlight.rawValue] = style }
            controller.canvas.tool = .highlight
            controller.refreshProperties()
        }, to: url("editor-highlight-area.png"))
        try write(editorWindow(snapshotDocument(sample), settings: settings) { $0.canvas.tool = .crop },
                  to: url("editor-crop-bar.png"))

        // File › New Image at its matched window size, and a narrow editor (which toolbar buttons drop out).
        try write(editorAsPlaced(blankDocument(settings: settings), settings: settings), to: url("editor-blank.png"))
        try write(editorAsPlaced(snapshotDocument(sample), settings: settings, contentSize: NSSize(width: 700, height: 520)),
                  to: url("editor-narrow.png"))
    }

    private static func snapshotDocument(_ sample: CGImage) -> EditorDocument {
        let doc = EditorDocument(image: sample, scale: 2, title: "Snapshot")
        doc.add(Annotation(kind: .rectangle, start: CGPoint(x: 160, y: 300), end: CGPoint(x: 1100, y: 700)))
        return doc
    }

    private static func blankDocument(settings: SettingsStore) -> EditorDocument {
        let size = settings.value.defaultEditorSize
        let image = EditorWindowPlacement.blankImage(points: CGSize(width: size.width, height: size.height), scale: 2)!
        return EditorDocument(image: image, scale: 2, title: "Untitled", isModified: false)
    }

    /// The editor at the size it opens with (or `contentSize`), without `editorWindow`'s fixed size.
    private static func editorAsPlaced(_ doc: EditorDocument, settings: SettingsStore, contentSize: NSSize? = nil) -> NSBitmapImageRep? {
        let controller = EditorWindowController(document: doc, settings: settings, saver: ImageSaver(settings: settings)) { _ in }
        keepAlive.append(controller)
        guard let window = controller.window, let content = window.contentView else { return nil }
        if let contentSize { window.setContentSize(contentSize) }
        content.layoutSubtreeIfNeeded()
        controller.zoomToFitIfLarger()
        content.layoutSubtreeIfNeeded()
        return capture(content)
    }
}
