// Greenshot for Mac (Community) - an unofficial macOS port of Greenshot
// Copyright (C) 2026 Greenshot for Mac (Community) contributors
// SPDX-License-Identifier: GPL-3.0-or-later

import AppKit
import GreenshotCore

extension Snapshots {
    /// Renders for the editor canvas: elements, styles, selection. Writes PNG files into `folder` with `write(_:to:)`; the helpers in Snapshots.swift
    /// (`editorWindow`, `overlay`, `form`, `settingsTab`, `capture`) do most of the work.
    static func renderCanvasExtras(to folder: URL, sample: CGImage, settings: SettingsStore) throws {
        try write(canvasText(sample: sample, settings: settings), to: folder.appendingPathComponent("canvas-text.png"))
        try write(canvasCrop(sample: sample, settings: settings), to: folder.appendingPathComponent("canvas-crop-vertical.png"))
        try write(canvasAreaHighlight(sample: sample, settings: settings), to: folder.appendingPathComponent("canvas-highlight-area.png"))
        try write(canvasPushOut(sample: sample, settings: settings), to: folder.appendingPathComponent("canvas-push-out.png"))
        try write(cutEdgePreviews(), to: folder.appendingPathComponent("canvas-cut-edge-previews.png"))
    }

    private static func textStyle(_ change: (inout AnnotationStyle) -> Void) -> AnnotationStyle {
        var style = AnnotationStyle.defaults(for: .text)
        change(&style)
        return style
    }

    /// Text elements with upstream's default 2 pt frame, without one, with a thick one and a fill, pasted text, and a
    /// speech bubble.
    private static func canvasText(sample: CGImage, settings: SettingsStore) -> NSBitmapImageRep? {
        let doc = EditorDocument(image: sample, scale: 2, title: "Snapshot")
        let framed = Annotation(kind: .text, start: CGPoint(x: 1300, y: 200), end: CGPoint(x: 2150, y: 330),
                                text: "Default: 2 pt frame", style: textStyle { $0.fontSize = 22 })
        doc.add(framed)
        doc.add(Annotation(kind: .text, start: CGPoint(x: 1300, y: 400), end: CGPoint(x: 2150, y: 530),
                           text: "No frame", style: textStyle { $0.fontSize = 22; $0.lineWidth = 0 }))
        doc.add(Annotation(kind: .text, start: CGPoint(x: 1300, y: 600), end: CGPoint(x: 2150, y: 760),
                           text: "6 pt frame, filled", style: textStyle {
                               $0.fontSize = 22; $0.lineWidth = 6; $0.lineColor = .blue; $0.fillColor = .yellow
                           }))
        doc.add(ElementClipboard.textElement("Pasted text\nkeeps its lines", at: CGPoint(x: 1300, y: 860),
                                             base: .defaults(for: .text), scale: 2, maxWidth: 2560))
        doc.add(Annotation(kind: .speechBubble, start: CGPoint(x: 1700, y: 1150), end: CGPoint(x: 2400, y: 1350),
                           text: "Bubble", tail: CGPoint(x: 1500, y: 1450)))
        return editorWindow(doc, settings: settings) { controller in
            controller.canvas.tool = .text
            controller.canvas.select(framed.id)
        }
    }

    /// The crop tool in Crop Out Vertically with an area drawn: the columns to cut out are shaded, with their handles.
    private static func canvasCrop(sample: CGImage, settings: SettingsStore) -> NSBitmapImageRep? {
        let doc = EditorDocument(image: sample, scale: 2, title: "Snapshot")
        return editorWindow(doc, settings: settings) { controller in
            controller.canvas.tool = .crop
            controller.canvas.selectCropMode(.vertical)
            controller.canvas.showCropArea(CGRect(x: 1000, y: 0, width: 420, height: doc.imageSize.height))
        }
    }

    /// The area highlight at upstream's brightness 0.9 and blur 3.
    private static func canvasAreaHighlight(sample: CGImage, settings: SettingsStore) -> NSBitmapImageRep? {
        let doc = EditorDocument(image: sample, scale: 2, title: "Snapshot")
        var style = AnnotationStyle.defaults(for: .highlight)
        style.highlightMode = .area
        let area = Annotation(kind: .highlight, start: CGPoint(x: 180, y: 800), end: CGPoint(x: 1100, y: 960), style: style)
        doc.add(area)
        return editorWindow(doc, settings: settings) { controller in
            controller.canvas.tool = .select
            controller.canvas.select(area.id)
        }
    }

    /// A picture element after Expand Capture and Move Outside › Right: the canvas is wider by the picture, which sits in
    /// the new transparent strip.
    private static func canvasPushOut(sample: CGImage, settings: SettingsStore) -> NSBitmapImageRep? {
        let doc = EditorDocument(image: sample, scale: 2, title: "Snapshot")
        guard let part = sample.cropping(to: CGRect(x: 1700, y: 260, width: 520, height: 420)),
              let picture = Annotation.picture(part, pictureScale: 2, at: CGPoint(x: 600, y: 400), documentScale: 2) else { return nil }
        doc.add(picture)
        doc.change { _ = doc.pushOut(picture.id, to: .right) }
        return editorWindow(doc, settings: settings) { $0.canvas.tool = .select }
    }

    /// The cut-edge styles' pictures for the pop-ups, side by side and enlarged.
    private static func cutEdgePreviews() -> NSBitmapImageRep? {
        let styles = CutMarkStyle.allCases
        let side = 64
        guard let rep = NSBitmapImageRep(bitmapDataPlanes: nil, pixelsWide: side * styles.count, pixelsHigh: side,
                                         bitsPerSample: 8, samplesPerPixel: 4, hasAlpha: true, isPlanar: false,
                                         colorSpaceName: .deviceRGB, bytesPerRow: 0, bitsPerPixel: 0) else { return nil }
        NSGraphicsContext.saveGraphicsState()
        NSGraphicsContext.current = NSGraphicsContext(bitmapImageRep: rep)
        NSGraphicsContext.current?.imageInterpolation = .none
        NSColor.windowBackgroundColor.setFill()
        NSRect(x: 0, y: 0, width: side * styles.count, height: side).fill()
        for (index, style) in styles.enumerated() {
            guard let image = CutMark.previewImage(style) else { continue }
            NSImage(cgImage: image, size: NSSize(width: 16, height: 16))
                .draw(in: NSRect(x: index * side, y: 0, width: side, height: side))
        }
        NSGraphicsContext.restoreGraphicsState()
        return rep
    }
}
