// Greenshot for Mac (Community) - an unofficial macOS port of Greenshot
// Copyright (C) 2026 Greenshot for Mac (Community) contributors
// Based on Greenshot, Copyright (C) 2007-2026 Thomas Braun, Jens Klingen, Robin Krom
// SPDX-License-Identifier: GPL-3.0-or-later

import AppKit
import GreenshotCore

/// A panel of the capture screen: its size, and how it draws itself into the box it was placed in.
struct OverlayPanel {
    let id: String
    let size: CGSize
    let draw: (CGRect) -> Void
}

/// What the capture screen draws on one display: the selection and its labels, the crosshair, the text lines and
/// QR codes, the zoomer and the panels (keys, info, preview, sizes). Ports of upstream
/// `Greenshot/Capturing/Views/CaptureWindow.xaml.cs` (drawing), `Overlays/HelpOverlay.cs`, `Overlays/InfoOverlay.cs`,
/// `Overlays/SelectionPreviewOverlay.cs`, and the panel of `Tools/FixedSizeCaptureTool.cs`.
extension OverlayMarksView {
    static let muted = NSColor.white.withAlphaComponent(0.6)

    /// A fifth of the smaller side of this display (upstream `ZoomerPlacement.GetSize`).
    var zoomerDiameter: CGFloat { CaptureZoomerPlacement.size(for: frozen.frame) }

    func drawMarks() {
        guard let controller, let context = NSGraphicsContext.current?.cgContext else { return }
        let cursor = local(controller.cursor)
        let cursorHere = bounds.contains(cursor)
        let selection = controller.selection.map { local($0) }

        // Dim everything outside the selection a little, so the capture screen is recognizable.
        let dim = CGMutablePath()
        dim.addRect(bounds)
        if let selection { dim.addRect(selection) }
        context.addPath(dim)
        context.setFillColor(NSColor.black.withAlphaComponent(selection == nil ? 0.12 : 0.35).cgColor)
        context.fillPath(using: .evenOdd)

        if controller.mode == .text { drawTextLines(controller, in: context) }
        if controller.mode == .region { drawBarcodes(controller, in: context) }

        if let selection, selection.intersects(bounds) {
            context.setStrokeColor(accent.cgColor)
            context.setLineWidth(1)
            context.stroke(selection.insetBy(dx: 0.5, dy: 0.5))
            if controller.mode != .text {
                let pixels = CaptureSelection.pixelSize(of: selection, scale: frozen.scale)
                drawSelectionLabels(for: selection, width: pixels.width, height: pixels.height, alpha: 1, in: context)
                drawSelectionNote(for: selection, pixels: pixels)
            }
        }

        // In the region and text modes, until a drag starts (upstream: dotted, with the position next to it).
        let crosshairMode = controller.mode == .region || controller.mode == .text
        let showsCrosshair = crosshairMode && controller.anchor == nil && cursorHere && controller.barcodeMenu == nil
        if showsCrosshair { drawCrosshair(at: cursor, in: context) }

        guard cursorHere else {
            panelFrames = [:]
            zoomerOffset = nil
            drawBarcodeMenu(controller)
            return
        }
        drawPanelsAndZoomer(controller, cursor: cursor, selection: selection, showsPosition: !showsCrosshair, in: context)
        drawStatus(controller)
        drawBarcodeHint(controller)
        drawBarcodeMenu(controller)
    }

    // MARK: Panels

    private func drawPanelsAndZoomer(_ controller: CaptureOverlayController, cursor: CGPoint, selection: CGRect?,
                                     showsPosition: Bool, in context: CGContext) {
        let preview = controller.previewPlacement == .off ? nil : previewPanel(controller)
        let previewAtZoomer = controller.previewPlacement == .zoomer && controller.showsZoomer
        var panels: [OverlayPanel] = []
        if controller.mode == .fixedSize { panels.append(sizesPanel(controller)) }
        if controller.helpVisible { panels.append(tablePanel(id: "help", title: "Keys", rows: controller.helpLines())) }
        if controller.infoVisible { panels.append(tablePanel(id: "info", title: "Info", rows: controller.infoLines())) }
        if let preview, !previewAtZoomer { panels.append(preview) }

        var placed: [CGRect] = []
        var frames: [String: CGRect] = [:]
        let loose = selection.map { [$0] } ?? []
        for panel in panels {
            let box = CapturePanelPlacement.place(size: panel.size, monitor: bounds, cursor: cursor, current: panelFrames[panel.id],
                                                  avoid: placed, avoidLoosely: loose)
            placed.append(box)
            frames[panel.id] = box
            panel.draw(box)
        }
        panelFrames = frames

        guard controller.showsZoomer else {
            zoomerOffset = nil
            return
        }
        let inZoomer = previewAtZoomer ? preview : nil
        let diameter = zoomerDiameter
        // The magnifier with room for the position below it.
        let size = inZoomer?.size ?? CGSize(width: diameter, height: diameter + (showsPosition ? 24 : 0))
        let offset = CaptureZoomerPlacement.offset(cursor: cursor, current: zoomerOffset, size: size, monitor: bounds,
                                                   avoid: placed + loose)
        zoomerOffset = offset
        let slot = CGRect(origin: CGPoint(x: cursor.x + offset.x, y: cursor.y + offset.y), size: size)
        if let inZoomer {
            inZoomer.draw(slot)
        } else {
            drawZoomer(at: cursor, in: CGRect(origin: slot.origin, size: CGSize(width: diameter, height: diameter)),
                       selection: selection, showsPosition: showsPosition, opacity: controller.zoomerOpacity, context: context)
        }
    }

    func panelBackground(_ box: CGRect) {
        NSColor.black.withAlphaComponent(0.72).setFill()
        NSBezierPath(roundedRect: box, xRadius: 8, yRadius: 8).fill()
    }

    static func width(_ text: String, _ font: NSFont) -> CGFloat {
        NSAttributedString(string: text, attributes: [.font: font]).size().width
    }

    /// Keys and what they do, or names and values: the keys and the info panel.
    func tablePanel(id: String, title: String, rows: [(String, String)]) -> OverlayPanel {
        let titleFont = NSFont.systemFont(ofSize: 12, weight: .bold)
        let keyFont = NSFont.systemFont(ofSize: 12, weight: .semibold)
        let textFont = NSFont.systemFont(ofSize: 12)
        let keyWidth = rows.map { Self.width($0.0, keyFont) }.max() ?? 0
        let textWidth = rows.map { Self.width($0.1, textFont) }.max() ?? 0
        let lineHeight: CGFloat = 18
        let width = max(keyWidth + textWidth + 36, Self.width(title, titleFont) + 24)
        let size = CGSize(width: width.rounded(.up), height: CGFloat(rows.count) * lineHeight + 42)
        let accent = self.accent
        return OverlayPanel(id: id, size: size) { [weak self] box in
            self?.panelBackground(box)
            NSAttributedString(string: title, attributes: [.font: titleFont, .foregroundColor: NSColor.white])
                .draw(at: CGPoint(x: box.minX + 12, y: box.minY + 9))
            for (index, row) in rows.enumerated() {
                let y = box.minY + 32 + CGFloat(index) * lineHeight
                NSAttributedString(string: row.0, attributes: [.font: keyFont, .foregroundColor: accent])
                    .draw(at: CGPoint(x: box.minX + 12, y: y))
                NSAttributedString(string: row.1, attributes: [.font: textFont, .foregroundColor: NSColor.white])
                    .draw(at: CGPoint(x: box.minX + 24 + keyWidth, y: y))
            }
        }
    }

    /// The fixed-size mode's list of sizes, the corner the mouse holds, and the hint about ⌥.
    func sizesPanel(_ controller: CaptureOverlayController) -> OverlayPanel {
        enum Row { case header(String), size(Int, FixedSizeEntry) }
        var rows: [Row] = []
        for (index, entry) in controller.fixedSizes.enumerated() {
            if entry.isRecent && (index == 0 || !controller.fixedSizes[index - 1].isRecent) { rows.append(.header("Recently captured")) }
            rows.append(.size(index, entry))
        }
        let font = NSFont.monospacedDigitSystemFont(ofSize: 12, weight: .regular)
        let bold = NSFont.monospacedDigitSystemFont(ofSize: 12, weight: .bold)
        let small = NSFont.systemFont(ofSize: 11)
        let lineHeight: CGFloat = 18
        let anchorText = controller.fixedAnchor.displayName
        let hint = "Hold ⌥ to place it without snapping"
        let width = max(Self.width(hint, small), 150, Self.width(anchorText, font) + 70) + 24
        let height = CGFloat(rows.count + 1) * lineHeight + 32 + 22 + 20
        let accent = self.accent
        let current = controller.fixedSizeIndex
        let anchor = controller.fixedAnchor
        return OverlayPanel(id: "sizes", size: CGSize(width: width.rounded(.up), height: height)) { [weak self] box in
            self?.panelBackground(box)
            let x = box.minX + 12
            NSAttributedString(string: "Sizes", attributes: [.font: NSFont.systemFont(ofSize: 12, weight: .bold), .foregroundColor: NSColor.white])
                .draw(at: CGPoint(x: x, y: box.minY + 9))
            var y = box.minY + 32
            for row in rows {
                switch row {
                case .header(let text):
                    NSAttributedString(string: text, attributes: [.font: small, .foregroundColor: Self.muted]).draw(at: CGPoint(x: x, y: y + 1))
                case .size(let index, let entry):
                    let key = index < 9 ? "\(index + 1)" : ""
                    NSAttributedString(string: key, attributes: [.font: bold, .foregroundColor: accent]).draw(at: CGPoint(x: x, y: y))
                    let highlighted = index == current
                    let text = "\(entry.size.width) × \(entry.size.height)"
                    NSAttributedString(string: text, attributes: [.font: highlighted ? bold : font,
                                                                  .foregroundColor: highlighted ? accent : NSColor.white])
                        .draw(at: CGPoint(x: x + 22, y: y))
                }
                y += lineHeight
            }
            y += 6
            NSAttributedString(string: "C", attributes: [.font: bold, .foregroundColor: accent]).draw(at: CGPoint(x: x, y: y))
            let icon = CGRect(x: x + 22, y: y + 2, width: 20, height: 14)
            Self.muted.setStroke()
            NSBezierPath(rect: icon.insetBy(dx: 0.5, dy: 0.5)).stroke()
            let dot = Self.anchorPoint(anchor, in: icon)
            accent.setFill()
            NSBezierPath(ovalIn: CGRect(x: dot.x - 3, y: dot.y - 3, width: 6, height: 6)).fill()
            NSAttributedString(string: anchorText, attributes: [.font: font, .foregroundColor: NSColor.white])
                .draw(at: CGPoint(x: icon.maxX + 8, y: y))
            NSAttributedString(string: hint, attributes: [.font: small, .foregroundColor: Self.muted])
                .draw(at: CGPoint(x: x, y: y + lineHeight + 8))
        }
    }

    static func anchorPoint(_ anchor: FixedCaptureAnchor, in rect: CGRect) -> CGPoint {
        switch anchor {
        case .topLeft: return CGPoint(x: rect.minX, y: rect.minY)
        case .topRight: return CGPoint(x: rect.maxX, y: rect.minY)
        case .bottomRight: return CGPoint(x: rect.maxX, y: rect.maxY)
        case .bottomLeft: return CGPoint(x: rect.minX, y: rect.maxY)
        case .center: return CGPoint(x: rect.midX, y: rect.midY)
        }
    }

    /// The preview of the selection: enlarged with sharp pixels, or reduced to fit, with its size and zoom.
    func previewPanel(_ controller: CaptureOverlayController) -> OverlayPanel? {
        guard let preview = controller.previewImage() else { return nil }
        let pixels = CGSize(width: preview.image.width, height: preview.image.height)
        let screenScale = max(frozen.scale, 1)
        let box = CGSize(width: SelectionPreviewLayout.maxSize.width * screenScale, height: SelectionPreviewLayout.maxSize.height * screenScale)
        let scale = SelectionPreviewLayout.scale(for: pixels, fitting: box)
        let shown = CGSize(width: max(1, (pixels.width * scale / screenScale).rounded()),
                           height: max(1, (pixels.height * scale / screenScale).rounded()))
        let font = NSFont.monospacedDigitSystemFont(ofSize: 11, weight: .regular)
        let sizeText = "\(Int(pixels.width)) × \(Int(pixels.height))"
        let zoomText = SelectionPreviewLayout.percentText(scale)
        let textWidth = Self.width(sizeText, font) + 12 + Self.width(zoomText, font)
        let contentWidth = max(shown.width, textWidth)
        let size = CGSize(width: (contentWidth + 20).rounded(.up), height: shown.height + 42)
        let image = preview.image
        return OverlayPanel(id: "preview", size: size) { [weak self] panel in
            self?.panelBackground(panel)
            let target = CGRect(x: panel.minX + 10, y: panel.minY + 10, width: shown.width, height: shown.height)
            let interpolation: NSImageInterpolation = scale >= 1 ? .none : .high
            NSImage(cgImage: image, size: target.size)
                .draw(in: target, from: .zero, operation: .copy, fraction: 1, respectFlipped: true,
                      hints: [.interpolation: NSNumber(value: interpolation.rawValue)])
            Self.muted.setStroke()
            NSBezierPath(rect: target.insetBy(dx: -0.5, dy: -0.5)).stroke()
            let y = target.maxY + 7
            NSAttributedString(string: sizeText, attributes: [.font: font, .foregroundColor: NSColor.white])
                .draw(at: CGPoint(x: target.minX, y: y))
            NSAttributedString(string: zoomText, attributes: [.font: font, .foregroundColor: Self.muted])
                .draw(at: CGPoint(x: panel.maxX - 10 - Self.width(zoomText, font), y: y))
        }
    }

    // MARK: Labels

    func label(_ text: String, size: CGFloat = 12, weight: NSFont.Weight = .medium) -> NSAttributedString {
        NSAttributedString(string: text, attributes: [
            .font: NSFont.monospacedDigitSystemFont(ofSize: size, weight: weight),
            .foregroundColor: NSColor.white,
        ])
    }

    @discardableResult
    func drawBubble(_ text: NSAttributedString, at origin: CGPoint) -> CGRect {
        let size = text.size()
        let box = CGRect(x: origin.x, y: origin.y, width: size.width + 12, height: size.height + 6)
        NSColor.black.withAlphaComponent(0.75).setFill()
        NSBezierPath(roundedRect: box, xRadius: 5, yRadius: 5).fill()
        text.draw(at: CGPoint(x: box.minX + 6, y: box.minY + 3))
        return box
    }

    /// Below the selection: the window title in window mode (with D its details), and the size the fixed-size mode
    /// asked for when the area was cut off at the screen's edges. The size itself is on the rulers.
    private func drawSelectionNote(for selection: CGRect, pixels: (width: Int, height: Int)) {
        guard let controller else { return }
        var text = ""
        if controller.mode == .fixedSize, let size = controller.currentFixedSize, size.width != pixels.width || size.height != pixels.height {
            text = "Cut off from \(size.width) × \(size.height)"
        }
        if controller.mode == .window, let window = controller.hoveredWindow {
            text = window.menuTitle
            if controller.windowDetailsVisible { text += "\n" + Self.details(of: window) }
        }
        guard !text.isEmpty else { return }
        let string = label(text)
        let size = string.size()
        var origin = CGPoint(x: selection.minX, y: selection.maxY + 6)
        if origin.y + size.height + 8 > bounds.maxY { origin.y = selection.maxY - size.height - 12 }
        origin.x = min(max(origin.x, 4), bounds.maxX - size.width - 16)
        origin.y = max(origin.y, 4)
        drawBubble(string, at: origin)
    }

    /// D in window mode: what identifies the window, for reporting a problem with an app.
    static func details(of window: WindowInfo) -> String {
        let f = window.frame
        let title = window.title.isEmpty ? "(no title)" : window.title
        return "Window \(window.id) · \(window.appName) (pid \(window.pid))\n\(title)\n"
            + "\(Int(f.minX)), \(Int(f.minY))  \(Int(f.width)) × \(Int(f.height)) pt"
    }

    /// "Recognising text…" while the text mode waits for the text recognition.
    private func drawStatus(_ controller: CaptureOverlayController) {
        guard controller.mode == .text else { return }
        let text: String
        if controller.recognizingText {
            text = "Recognising text…"
        } else if controller.textLines?.isEmpty == true {
            text = "No text found"
        } else {
            return
        }
        let string = label(text, size: 13)
        let size = string.size()
        drawBubble(string, at: CGPoint(x: bounds.midX - size.width / 2 - 6, y: 16))
    }

    // MARK: Text and QR codes

    private func drawTextLines(_ controller: CaptureOverlayController, in context: CGContext) {
        let lines = controller.textLines ?? []
        context.setStrokeColor(accent.withAlphaComponent(0.55).cgColor)
        context.setLineWidth(1)
        for line in lines {
            let box = local(line.bounds)
            if box.intersects(bounds) { context.stroke(box.insetBy(dx: -1.5, dy: -1.5)) }
        }
        context.setFillColor(accent.withAlphaComponent(0.35).cgColor)
        if controller.anchor != nil, let selection = controller.selection {
            for words in TextCaptureSelection.selectedWords(in: selection, lines: lines) {
                for word in words { context.fill(local(word.bounds).insetBy(dx: -1, dy: -1)) }
            }
        } else if let line = controller.hoveredLine {
            context.fill(local(line.bounds).insetBy(dx: -2, dy: -2))
        }
    }

    private func drawBarcodes(_ controller: CaptureOverlayController, in context: CGContext) {
        guard !controller.barcodes.isEmpty else { return }
        context.saveGState()
        context.setLineDash(phase: 0, lengths: [6, 4])
        context.setLineWidth(2)
        for barcode in controller.barcodes {
            let box = local(barcode.bounds)
            guard box.intersects(bounds) else { continue }
            context.setStrokeColor(NSColor.white.cgColor)
            context.stroke(box)
            context.setStrokeColor(accent.cgColor)
            context.setLineDash(phase: 5, lengths: [6, 4])
            context.stroke(box)
            context.setLineDash(phase: 0, lengths: [6, 4])
        }
        context.restoreGState()
    }

    /// The content of the QR code under the mouse.
    private func drawBarcodeHint(_ controller: CaptureOverlayController) {
        guard controller.barcodeMenu == nil, let barcode = controller.hoveredBarcode else { return }
        let box = local(barcode.bounds)
        let string = label("\(barcode.symbology): \(BarcodeMenu.shortened(barcode.payload)) – click for actions", size: 11)
        let size = string.size()
        var origin = CGPoint(x: box.minX, y: box.maxY + 6)
        if origin.y + size.height + 8 > bounds.maxY { origin.y = box.minY - size.height - 12 }
        origin.x = min(max(origin.x, 4), bounds.maxX - size.width - 16)
        drawBubble(string, at: origin)
    }

    private func drawBarcodeMenu(_ controller: CaptureOverlayController) {
        guard let menu = controller.barcodeMenu else { return }
        let frame = local(menu.frame)
        guard frame.intersects(bounds) else { return }
        NSColor(white: 0.12, alpha: 0.95).setFill()
        NSBezierPath(roundedRect: frame, xRadius: 6, yRadius: 6).fill()
        NSColor.white.withAlphaComponent(0.25).setStroke()
        NSBezierPath(roundedRect: frame.insetBy(dx: 0.5, dy: 0.5), xRadius: 6, yRadius: 6).stroke()
        for (index, item) in menu.items.enumerated() {
            let box = local(item.frame)
            if index == menu.hovered {
                NSColor.controlAccentColor.setFill()
                NSBezierPath(roundedRect: box, xRadius: 4, yRadius: 4).fill()
            }
            let text = NSAttributedString(string: item.title, attributes: [.font: BarcodeMenu.font, .foregroundColor: NSColor.white])
            text.draw(at: CGPoint(x: box.minX + 10, y: box.midY - text.size().height / 2))
        }
    }

    // MARK: Zoomer

    /// The magnifier in `zoom`: `CaptureZoomerPlacement.sourcePixels` pixels of the frozen picture across, the pixel under
    /// the mouse framed, and the selection's edges, so you see whether a pixel is in or out (upstream
    /// `UpdateZoomerSelection`). `opacity` below 1 lets the screen show through (upstream `ZoomerOpacity`).
    private func drawZoomer(at cursor: CGPoint, in zoom: CGRect, selection: CGRect?, showsPosition: Bool, opacity: CGFloat,
                            context: CGContext) {
        guard opacity > 0 else { return }
        let scale = frozen.scale
        let pixel = CGPoint(x: (cursor.x * scale).rounded(.down), y: (cursor.y * scale).rounded(.down))
        let geometry = CaptureZoomerGeometry(zoom: zoom, cursorPixel: pixel)
        let source = geometry.source
        let imageBounds = CGRect(x: 0, y: 0, width: frozen.image.width, height: frozen.image.height)
        let visible = source.intersection(imageBounds)

        context.saveGState()
        if opacity < 1 {
            context.setAlpha(opacity)
            context.beginTransparencyLayer(auxiliaryInfo: nil)
        }
        context.saveGState()
        context.addEllipse(in: zoom)
        context.clip()
        // Black where the picture ends; see-through, the screen shows there instead (upstream hides its checkerboard).
        if opacity >= 1 {
            context.setFillColor(NSColor.black.cgColor)
            context.fill(zoom)
        }
        if !visible.isEmpty, let crop = frozen.image.cropping(to: visible) {
            let destination = geometry.frame(ofPixels: visible)
            NSImage(cgImage: crop, size: destination.size)
                .draw(in: destination, from: .zero, operation: .copy, fraction: 1, respectFlipped: true,
                      hints: [.interpolation: NSNumber(value: NSImageInterpolation.none.rawValue)])
        }
        if let selection {
            let pixels = CGRect(x: selection.minX * scale, y: selection.minY * scale,
                                width: selection.width * scale, height: selection.height * scale)
            context.setStrokeColor(accent.withAlphaComponent(0.9).cgColor)
            context.setLineWidth(1.5)
            context.stroke(geometry.frame(ofPixels: pixels))
        }
        let center = geometry.frame(ofPixels: CGRect(x: pixel.x, y: pixel.y, width: 1, height: 1))
        context.setStrokeColor(accent.cgColor)
        context.setLineWidth(1)
        context.stroke(center.insetBy(dx: -0.5, dy: -0.5))
        context.restoreGState()

        context.setStrokeColor(NSColor.white.cgColor)
        context.setLineWidth(2)
        context.strokeEllipse(in: zoom.insetBy(dx: 1, dy: 1))
        context.setStrokeColor(NSColor.black.withAlphaComponent(0.5).cgColor)
        context.setLineWidth(1)
        context.strokeEllipse(in: zoom.insetBy(dx: -0.5, dy: -0.5))
        if opacity < 1 { context.endTransparencyLayer() }
        context.restoreGState()

        // The crosshair shows the position next to the mouse; without it (fixed size, while dragging) it is below the zoomer.
        guard showsPosition else { return }
        let coordinates = label("\(Int(pixel.x)), \(Int(pixel.y))", size: 11)
        let size = coordinates.size()
        drawBubble(coordinates, at: CGPoint(x: zoom.midX - size.width / 2 - 6, y: zoom.maxY + 4))
    }
}

/// The texts of the keys and the info panel (upstream `HelpOverlay.cs`, `InfoOverlay.cs`).
extension CaptureOverlayController {
    /// The keys that work now: those of the mode first, then those of every mode.
    func helpLines() -> [(String, String)] {
        var lines: [(String, String)] = []
        let arrows = ("← → ↑ ↓", "move one pixel, with ⌃ ten")
        switch mode {
        case .region:
            lines = [("Drag", "select a region"), ("Enter", "start and finish a selection with the keys"), arrows,
                     ("Shift", "keep a drag to one direction"), ("Z", "zoomer on or off")]
            if !barcodes.isEmpty { lines.append(("Click a QR code", "copy or open what it says")) }
        case .window:
            lines = [("Click, Enter", "capture the window"), ("D", "window details on or off")]
        case .fixedSize:
            lines = [("Click, Enter", "capture the area"), ("1 – 9", "pick a size"), ("PgUp PgDn, [ ]", "previous or next size"),
                     ("C", "hold it at another corner"), ("⌥", "hold to place it without snapping"), arrows, ("Z", "zoomer on or off")]
        case .text:
            lines = [("Click a line", "copy its text"), ("Drag", "select words, copy their text"),
                     ("Enter", "start and finish a selection with the keys"), arrows, ("Shift", "keep a drag to one direction"),
                     ("Z", "zoomer on or off")]
        }
        lines.append(("Space", mode == .region || mode == .window ? "switch between region and window" : "back to region"))
        if mode != .fixedSize { lines.append(("F", "capture a fixed size")) }
        if mode != .text { lines.append(("T", "capture text")) }
        if pointerScreens != nil { lines.append(("M", pointerVisible ? "leave out the mouse pointer" : "include the mouse pointer")) }
        lines += [("H, F1", "hide the keys"), ("I", infoVisible ? "hide the info" : "show the info"),
                  ("P", "preview: in a corner, at the zoomer, off"), ("Esc", "cancel")]
        return lines
    }

    /// The display with the mouse, all displays, the selection, the window under the mouse and the mouse position.
    /// Positions and display sizes in points, as macOS counts them, the selection in pixels like its label.
    func infoLines() -> [(String, String)] {
        var lines: [(String, String)] = []
        if let screen = cursorScreen {
            let name = NSScreen.screens.first { $0.displayID == screen.displayID }?.localizedName ?? "Display \(screen.displayID)"
            let f = screen.frame
            lines.append(("Screen", "\(name), \(Int(f.width)) × \(Int(f.height)) (\(screen.image.width) × \(screen.image.height) px)"))
        }
        if screens.count > 1 {
            let all = desktopBounds
            lines.append(("All screens", "\(Int(all.width)) × \(Int(all.height))"))
        }
        if let rect = selection {
            let scale = cursorScreen?.scale ?? 1
            let width = Int((rect.width * scale).rounded())
            let height = Int((rect.height * scale).rounded())
            lines.append(("Selection", "\(width) × \(height) px at \(Int(rect.minX.rounded())), \(Int(rect.minY.rounded()))"))
        } else {
            lines.append(("Selection", "None"))
        }
        let title = windowUnderCursor?.menuTitle ?? "–"
        lines.append(("Window", title.count > 48 ? String(title.prefix(47)) + "…" : title))
        lines.append(("Mouse", "\(Int(cursor.x.rounded(.down))), \(Int(cursor.y.rounded(.down)))"))
        if pointerScreens != nil { lines.append(("Pointer", pointerVisible ? "in the capture" : "not in the capture")) }
        return lines
    }
}
