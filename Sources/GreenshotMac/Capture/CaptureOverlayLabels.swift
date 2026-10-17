// Greenshot for Mac (Community) - an unofficial macOS port of Greenshot
// Copyright (C) 2026 Greenshot for Mac (Community) contributors
// Based on Greenshot, Copyright (C) 2007-2026 Thomas Braun, Jens Klingen, Robin Krom
// SPDX-License-Identifier: GPL-3.0-or-later

import AppKit
import GreenshotCore

/// The rulers and the size of the selection, and the crosshair with the mouse position (upstream
/// `Greenshot/Capturing/Views/CaptureWindow.xaml.cs` `ShowLabels`, `DrawCrosshairLines`, `UpdateCrosshair`).
extension OverlayMarksView {
    static let rulerFont = NSFont.monospacedDigitSystemFont(ofSize: 9, weight: .medium)
    /// Upstream `RulerBackgroundBrush`: a light green behind the ruler labels.
    static let rulerBackground = NSColor(srgbRed: 0.85, green: 0.94, blue: 0.89, alpha: 0.78)

    /// The text of the ruler labels: a darker shade of the accent, readable on `rulerBackground`.
    var rulerText: NSColor { accent.blended(withFraction: 0.45, of: .black) ?? accent }

    /// The width ruler above the selection, the height ruler left of it and the size in the middle, as large as fits.
    /// `selection` is in this view's points, the size in pixels. `alpha` fades them in after a window selection moved.
    func drawSelectionLabels(for selection: CGRect, width: Int, height: Int, alpha: CGFloat, in context: CGContext) {
        guard alpha > 0 else { return }
        context.saveGState()
        context.setAlpha(alpha)
        context.beginTransparencyLayer(auxiliaryInfo: nil)
        // The numbers keep their order in right-to-left languages
        let widthText = rulerLabel(BidiText.isolatedLTR("\(width)"))
        let heightText = rulerLabel(BidiText.isolatedLTR("\(height)"))
        if let ruler = CaptureSelectionLabels.widthRuler(for: selection, labelSize: widthText.size(), display: bounds) {
            drawRuler(ruler, text: widthText, horizontal: true, in: context)
        }
        if let ruler = CaptureSelectionLabels.heightRuler(for: selection, labelSize: heightText.size(), display: bounds) {
            drawRuler(ruler, text: heightText, horizontal: false, in: context)
        }
        let sizeText = BidiText.isolatedLTR("\(width) × \(height)")
        let measured = NSAttributedString(string: sizeText, attributes: [.font: Self.sizeFont(CaptureSelectionLabels.measureSize)]).size()
        if let fontSize = CaptureSelectionLabels.sizeFontSize(for: selection.size, measured: measured) {
            let shadow = NSShadow()
            shadow.shadowColor = NSColor.black.withAlphaComponent(0.7)
            shadow.shadowBlurRadius = 2
            shadow.shadowOffset = .zero
            let text = NSAttributedString(string: sizeText, attributes: [.font: Self.sizeFont(fontSize), .foregroundColor: accent,
                                                                          .shadow: shadow])
            let size = text.size()
            text.draw(at: CGPoint(x: selection.midX - size.width / 2, y: selection.midY - size.height / 2))
        }
        context.endTransparencyLayer()
        context.restoreGState()
    }

    private static func sizeFont(_ size: CGFloat) -> NSFont {
        NSFont.monospacedDigitSystemFont(ofSize: size, weight: .bold)
    }

    func rulerLabel(_ text: String) -> NSAttributedString {
        NSAttributedString(string: text, attributes: [.font: Self.rulerFont, .foregroundColor: rulerText])
    }

    /// A ruler: the line with a tick at each end, the line left out behind its label.
    private func drawRuler(_ ruler: CaptureSelectionLabels.Ruler, text: NSAttributedString, horizontal: Bool, in context: CGContext) {
        context.setStrokeColor(accent.cgColor)
        context.setLineWidth(1)
        let label = ruler.label
        if horizontal {
            let y = ruler.start.y
            context.move(to: ruler.start)
            context.addLine(to: CGPoint(x: label.minX, y: y))
            context.move(to: CGPoint(x: label.maxX, y: y))
            context.addLine(to: ruler.end)
            for x in [ruler.start.x + 0.5, ruler.end.x - 0.5] {
                context.move(to: CGPoint(x: x, y: y - 3))
                context.addLine(to: CGPoint(x: x, y: y + 3))
            }
        } else {
            let x = ruler.start.x
            context.move(to: ruler.start)
            context.addLine(to: CGPoint(x: x, y: label.minY))
            context.move(to: CGPoint(x: x, y: label.maxY))
            context.addLine(to: ruler.end)
            for y in [ruler.start.y + 0.5, ruler.end.y - 0.5] {
                context.move(to: CGPoint(x: x - 3, y: y))
                context.addLine(to: CGPoint(x: x + 3, y: y))
            }
        }
        context.strokePath()
        drawRulerLabel(text, in: label)
    }

    /// A label of the rulers and the crosshair: on the light background, framed in the accent.
    func drawRulerLabel(_ text: NSAttributedString, in box: CGRect) {
        let path = NSBezierPath(roundedRect: box, xRadius: 3, yRadius: 3)
        Self.rulerBackground.setFill()
        path.fill()
        accent.setStroke()
        path.lineWidth = 1
        path.stroke()
        text.draw(at: CGPoint(x: box.minX + 2, y: box.minY))
    }

    /// The crosshair: two dotted lines across the display through the pixel under the mouse, one device pixel wide, and
    /// the mouse position in pixels next to it.
    func drawCrosshair(at cursor: CGPoint, in context: CGContext) {
        let scale = max(frozen.scale, 1)
        let pixel = CGPoint(x: (cursor.x * scale).rounded(.down), y: (cursor.y * scale).rounded(.down))
        let x = (pixel.x + 0.5) / scale
        let y = (pixel.y + 0.5) / scale
        context.saveGState()
        context.setStrokeColor(accent.withAlphaComponent(0.9).cgColor)
        context.setLineWidth(1 / scale)
        // Dotted: one pixel on, one off (upstream `DashStyle(1, 1)`).
        context.setLineDash(phase: 0, lengths: [1 / scale, 1 / scale])
        context.move(to: CGPoint(x: 0, y: y))
        context.addLine(to: CGPoint(x: bounds.maxX, y: y))
        context.move(to: CGPoint(x: x, y: 0))
        context.addLine(to: CGPoint(x: x, y: bounds.maxY))
        context.strokePath()
        context.restoreGState()

        let text = rulerLabel(BidiText.isolatedLTR("\(Int(pixel.x)), \(Int(pixel.y))"))
        let size = text.size()
        var box = CGRect(x: cursor.x + 5.5, y: cursor.y + 5.5, width: size.width + 4, height: size.height)
        // Next to the mouse, on the other side at the edges of the display.
        if box.maxX > bounds.maxX - 2 { box.origin.x = cursor.x - 5.5 - box.width }
        if box.maxY > bounds.maxY - 2 { box.origin.y = cursor.y - 5.5 - box.height }
        drawRulerLabel(text, in: box)
    }
}
