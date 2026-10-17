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
        try write(canvasTornEdges(sample: sample, settings: settings), to: folder.appendingPathComponent("canvas-torn-edge-element.png"))
        try write(canvasTornEdgesStyled(sample: sample, settings: settings),
                  to: folder.appendingPathComponent("canvas-torn-edge-wave-fill.png"))
        try write(canvasCutMarkApplied(sample: sample, settings: settings), to: folder.appendingPathComponent("canvas-cut-mark-applied.png"))
        let cutEdgeSettings = TornEdgeSettingsForm(TornEdgeSettings(), showEdges: false)
        keepAlive.append(cutEdgeSettings)
        try write(form(cutEdgeSettings.view), to: folder.appendingPathComponent("canvas-cut-edge-settings.png"))
        try write(canvasSvg(sample: sample, settings: settings), to: folder.appendingPathComponent("canvas-svg-element.png"))
        try write(canvasPointer(sample: sample, settings: settings), to: folder.appendingPathComponent("canvas-cursor-element.png"))
    }

    /// Effects › Torn Edges as an element, selected: the property bar shows the cut edge style, teeth and range, and
    /// Apply to the Image.
    private static func canvasTornEdges(sample: CGImage, settings: SettingsStore) -> NSBitmapImageRep? {
        let doc = EditorDocument(image: sample, scale: 2, title: "Snapshot")
        doc.add(Annotation(kind: .rectangle, start: CGPoint(x: 120, y: 120), end: CGPoint(x: 520, y: 360)))
        return editorWindow(doc, settings: settings) { controller in
            controller.canvas.tool = .select
            controller.addTornEdges()
        }
    }

    /// Torn edges on the top and right only, wavy, with a fill color and a line along the edges.
    private static func canvasTornEdgesStyled(sample: CGImage, settings: SettingsStore) -> NSBitmapImageRep? {
        let doc = EditorDocument(image: sample, scale: 2, title: "Snapshot")
        var torn = TornEdgeSettings(left: false, bottom: false, backgroundColor: RGBAColor(red: 0.85, green: 0.92, blue: 1))
        torn.toothHeight = 16
        var style = AnnotationStyle.defaults(for: .tornEdge)
        style.lineWidth = 2
        style.lineColor = .blue
        guard let id = doc.addTornEdges(torn, style: style, seed: 2026), var element = doc.annotation(id) else { return nil }
        element.style.cutMarkStyle = .wave
        element.style.toothRange = 40
        doc.update(element)
        return editorWindow(doc, settings: settings) { controller in
            controller.canvas.tool = .select
            controller.canvas.select(id)
        }
    }

    /// A cut mark after Apply to the Image: the gap is in the pixels (transparent), the element is gone.
    private static func canvasCutMarkApplied(sample: CGImage, settings: SettingsStore) -> NSBitmapImageRep? {
        let doc = EditorDocument(image: sample, scale: 2, title: "Snapshot")
        var mark = Annotation(kind: .cutMark, start: CGPoint(x: 0, y: 380), end: CGPoint(x: 1280, y: 460))
        mark.seed = 2026
        doc.add(mark)
        doc.change { doc.applyToImage([mark.id]) }
        return editorWindow(doc, settings: settings) { $0.canvas.tool = .select }
    }

    /// An SVG element enlarged four times (sharp, drawn from the SVG) next to the same drawing as a picture element
    /// enlarged as much (blurred).
    private static func canvasSvg(sample: CGImage, settings: SettingsStore) -> NSBitmapImageRep? {
        let svg = Data("""
            <svg xmlns="http://www.w3.org/2000/svg" width="60" height="40" viewBox="0 0 60 40">
              <rect x="1" y="1" width="58" height="38" rx="6" fill="#ffffff" stroke="#1e5aa8" stroke-width="2"/>
              <path d="M10 30 L22 12 L32 24 L40 16 L50 30 Z" fill="#2e8b57"/>
              <circle cx="46" cy="10" r="5" fill="#f4b400"/>
            </svg>
            """.utf8)
        let doc = EditorDocument(image: sample, scale: 2, title: "Snapshot")
        guard var vector = Annotation.svg(svg, at: CGPoint(x: 80, y: 120), documentScale: 2),
              let small = ElementSvg.render(svg, pixelSize: CGSize(width: 60, height: 40)),
              var raster = Annotation.picture(small, pictureScale: 1, at: CGPoint(x: 660, y: 120), documentScale: 2) else {
            return nil
        }
        vector.end = CGPoint(x: 80 + 480, y: 120 + 320)
        raster.end = CGPoint(x: 660 + 480, y: 120 + 320)
        doc.add(vector)
        doc.add(raster)
        return editorWindow(doc, settings: settings) { controller in
            controller.canvas.tool = .select
            controller.canvas.select(vector.id)
        }
    }

    /// The captured mouse pointer as an element, selected (the arrow pointer stands in for a captured one).
    private static func canvasPointer(sample: CGImage, settings: SettingsStore) -> NSBitmapImageRep? {
        let cursor = NSCursor.arrow
        var rect = NSRect(origin: .zero, size: cursor.image.size)
        let context = NSGraphicsContext(bitmapImageRep: NSBitmapImageRep(bitmapDataPlanes: nil, pixelsWide: Int(rect.width * 2),
                                                                         pixelsHigh: Int(rect.height * 2), bitsPerSample: 8,
                                                                         samplesPerPixel: 4, hasAlpha: true, isPlanar: false,
                                                                         colorSpaceName: .deviceRGB, bytesPerRow: 0,
                                                                         bitsPerPixel: 0)!)
        guard let image = cursor.image.cgImage(forProposedRect: &rect, context: context, hints: nil) else { return nil }
        let scale = CGFloat(image.width) / cursor.image.size.width
        let hotSpot = CGPoint(x: cursor.hotSpot.x * scale, y: cursor.hotSpot.y * scale)
        let pointer = CapturedPointer(image: image, scale: scale, hotSpot: hotSpot,
                                      origin: CGPoint(x: 700 - hotSpot.x, y: 400 - hotSpot.y))
        let capture = Capture(image: sample, scale: 2, title: "Snapshot", pointer: pointer, imageWithoutPointer: sample)
        let doc = EditorDocument(image: capture.editorImage, scale: capture.scale, title: capture.title)
        return editorWindow(doc, settings: settings) { controller in
            controller.canvas.tool = .select
            controller.addCapturedPointer(of: capture)
        }
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
