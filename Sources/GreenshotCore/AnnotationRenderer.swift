// Greenshot for Mac (Community) - an unofficial macOS port of Greenshot
// Copyright (C) 2026 Greenshot for Mac (Community) contributors
// Based on Greenshot, Copyright (C) 2007-2026 Thomas Braun, Jens Klingen, Robin Krom
// SPDX-License-Identifier: GPL-3.0-or-later

import AppKit
import CoreImage
import CoreImage.CIFilterBuiltins

/// Draws a capture with its annotations. The editor shows exactly this image and every export writes it,
/// so what you see is what you save.
///
/// Filters (highlight, obfuscate) work on everything drawn below them, like upstream's `FilterContainer`.
public enum AnnotationRenderer {
    static let ciContext = CIContext(options: [.cacheIntermediates: false])
    static let sRGB = CGColorSpace(name: CGColorSpace.sRGB)!

    /// The base image with `annotations` drawn on it, at the pixel size of `base`.
    /// - Parameters:
    ///   - scale: pixels per point of the capture; style sizes are multiplied with it.
    ///   - hiddenID: an element to leave out (the text being edited in place).
    public static func flatten(base: CGImage, annotations: [Annotation], scale: CGFloat, hiding hiddenID: UUID? = nil) -> CGImage? {
        guard let context = makeContext(width: base.width, height: base.height) else { return nil }
        context.draw(base, in: CGRect(x: 0, y: 0, width: base.width, height: base.height))
        // From here on the origin is at the top left, like the annotation coordinates.
        context.translateBy(x: 0, y: CGFloat(base.height))
        context.scaleBy(x: 1, y: -1)

        let previous = NSGraphicsContext.current
        NSGraphicsContext.current = NSGraphicsContext(cgContext: context, flipped: true)
        defer { NSGraphicsContext.current = previous }

        var counter = 0
        for annotation in annotations {
            if annotation.kind == .counter { counter += 1 }
            guard annotation.id != hiddenID else { continue }
            context.saveGState()
            draw(annotation, number: counter, in: context, scale: scale)
            context.restoreGState()
        }
        return context.makeImage()
    }

    /// The font of a text element; `size` in pixels.
    public static func font(for style: AnnotationStyle, size: CGFloat) -> NSFont {
        let base = NSFont.systemFont(ofSize: size, weight: style.bold ? .bold : .regular)
        guard style.italic else { return base }
        let descriptor = base.fontDescriptor.withSymbolicTraits(base.fontDescriptor.symbolicTraits.union(.italic))
        return NSFont(descriptor: descriptor, size: size) ?? base
    }

    static func makeContext(width: Int, height: Int) -> CGContext? {
        CGContext(data: nil, width: width, height: height, bitsPerComponent: 8, bytesPerRow: 0, space: sRGB,
                  bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue)
    }

    // MARK: - Elements

    static func draw(_ a: Annotation, number: Int, in context: CGContext, scale: CGFloat) {
        let style = a.style
        let lineWidth = CGFloat(style.lineWidth) * scale
        switch a.kind {
        case .rectangle:
            drawShape(CGPath(rect: a.bounds, transform: nil), style: style, lineWidth: lineWidth, in: context, scale: scale)
        case .ellipse:
            drawShape(CGPath(ellipseIn: a.bounds, transform: nil), style: style, lineWidth: lineWidth, in: context, scale: scale)
        case .line:
            let path = CGMutablePath()
            path.move(to: a.start)
            path.addLine(to: a.end)
            stroke(path, style: style, lineWidth: lineWidth, in: context, scale: scale)
        case .arrow:
            drawArrow(a, lineWidth: lineWidth, in: context, scale: scale)
        case .freehand:
            stroke(freehandPath(a.points), style: style, lineWidth: lineWidth, in: context, scale: scale)
        case .text:
            drawText(a, in: context, scale: scale)
        case .counter:
            drawCounter(a, number: number, in: context, scale: scale)
        case .highlight:
            drawHighlight(a, in: context, scale: scale)
        case .obfuscate:
            drawObfuscate(a, in: context, scale: scale)
        }
    }

    /// Runs `body` with a soft drop shadow to the bottom right, drawn once for everything in `body`.
    static func withShadow(_ enabled: Bool, in context: CGContext, scale: CGFloat, _ body: () -> Void) {
        guard enabled else {
            body()
            return
        }
        context.saveGState()
        // Shadow offsets are in the bitmap's own space (y up) and ignore the flipped CTM, so "down" is negative.
        context.setShadow(offset: CGSize(width: 2 * scale, height: -2 * scale), blur: 3 * scale,
                          color: CGColor(gray: 0, alpha: 0.5))
        context.beginTransparencyLayer(auxiliaryInfo: nil)
        body()
        context.endTransparencyLayer()
        context.restoreGState()
    }

    static func drawShape(_ path: CGPath, style: AnnotationStyle, lineWidth: CGFloat, in context: CGContext, scale: CGFloat) {
        let lineVisible = lineWidth > 0 && style.lineColor.isVisible
        guard lineVisible || style.fillColor.isVisible else { return }
        withShadow(style.shadow, in: context, scale: scale) {
            if style.fillColor.isVisible {
                context.addPath(path)
                context.setFillColor(style.fillColor.cgColor)
                context.fillPath()
            }
            if lineVisible {
                context.addPath(path)
                context.setStrokeColor(style.lineColor.cgColor)
                context.setLineWidth(lineWidth)
                context.setLineJoin(.miter)
                context.strokePath()
            }
        }
    }

    static func stroke(_ path: CGPath, style: AnnotationStyle, lineWidth: CGFloat, in context: CGContext, scale: CGFloat) {
        guard lineWidth > 0, style.lineColor.isVisible else { return }
        withShadow(style.shadow, in: context, scale: scale) {
            context.addPath(path)
            context.setStrokeColor(style.lineColor.cgColor)
            context.setLineWidth(lineWidth)
            context.setLineCap(.round)
            context.setLineJoin(.round)
            context.strokePath()
        }
    }

    static func drawArrow(_ a: Annotation, lineWidth: CGFloat, in context: CGContext, scale: CGFloat) {
        let style = a.style
        guard style.lineColor.isVisible else { return }
        let width = max(lineWidth, scale)
        let headLength = width * 4 + 4 * scale
        let headWidth = headLength * 0.75
        let dx = a.end.x - a.start.x
        let dy = a.end.y - a.start.y
        let length = (dx * dx + dy * dy).squareRoot()
        guard length > 0 else { return }
        let ux = dx / length
        let uy = dy / length

        func head(at tip: CGPoint, direction: CGFloat) -> (CGPath, CGPoint) {
            let base = CGPoint(x: tip.x - ux * headLength * direction, y: tip.y - uy * headLength * direction)
            let path = CGMutablePath()
            path.move(to: tip)
            path.addLine(to: CGPoint(x: base.x - uy * headWidth / 2, y: base.y + ux * headWidth / 2))
            path.addLine(to: CGPoint(x: base.x + uy * headWidth / 2, y: base.y - ux * headWidth / 2))
            path.closeSubpath()
            return (path, base)
        }

        var lineStart = a.start
        var lineEnd = a.end
        var heads: [CGPath] = []
        if style.arrowHeads == .end || style.arrowHeads == .both {
            let (path, base) = head(at: a.end, direction: 1)
            heads.append(path)
            lineEnd = base
        }
        if style.arrowHeads == .start || style.arrowHeads == .both {
            let (path, base) = head(at: a.start, direction: -1)
            heads.append(path)
            lineStart = base
        }

        withShadow(style.shadow, in: context, scale: scale) {
            context.setStrokeColor(style.lineColor.cgColor)
            context.setFillColor(style.lineColor.cgColor)
            if length > headLength * CGFloat(heads.count) {
                context.move(to: lineStart)
                context.addLine(to: lineEnd)
                context.setLineWidth(width)
                context.setLineCap(.butt)
                context.strokePath()
            }
            for path in heads {
                context.addPath(path)
                context.fillPath()
            }
        }
    }

    /// A smooth path through the recorded mouse positions (quadratic curves through the midpoints).
    static func freehandPath(_ points: [CGPoint]) -> CGPath {
        let path = CGMutablePath()
        guard let first = points.first else { return path }
        path.move(to: first)
        guard points.count > 2 else {
            path.addLine(to: points.last ?? first)
            return path
        }
        for i in 1..<(points.count - 1) {
            let mid = CGPoint(x: (points[i].x + points[i + 1].x) / 2, y: (points[i].y + points[i + 1].y) / 2)
            path.addQuadCurve(to: mid, control: points[i])
        }
        path.addLine(to: points[points.count - 1])
        return path
    }

    static func drawText(_ a: Annotation, in context: CGContext, scale: CGFloat) {
        let style = a.style
        let rect = a.bounds
        if style.fillColor.isVisible {
            context.setFillColor(style.fillColor.cgColor)
            context.fill(rect)
        }
        guard !a.text.isEmpty, style.lineColor.isVisible else { return }
        let string = attributedText(a.text, style: style, pixelsPerPoint: scale)
        let inset = rect.insetBy(dx: 2 * scale, dy: 2 * scale)
        guard inset.width > 0 else { return }
        let measured = string.boundingRect(with: CGSize(width: inset.width, height: .greatestFiniteMagnitude),
                                           options: [.usesLineFragmentOrigin, .usesFontLeading])
        let y = inset.minY + max(0, (inset.height - measured.height) / 2)
        let target = CGRect(x: inset.minX, y: y, width: inset.width, height: ceil(measured.height) + 1)
        withShadow(style.shadow, in: context, scale: scale) {
            string.draw(with: target, options: [.usesLineFragmentOrigin, .usesFontLeading], context: nil)
        }
    }

    /// The text of a text element, centered like upstream's default `StringAlignment.Center`.
    public static func attributedText(_ text: String, style: AnnotationStyle, pixelsPerPoint: CGFloat) -> NSAttributedString {
        let paragraph = NSMutableParagraphStyle()
        paragraph.alignment = .center
        paragraph.lineBreakMode = .byWordWrapping
        return NSAttributedString(string: text, attributes: [
            .font: font(for: style, size: CGFloat(style.fontSize) * pixelsPerPoint),
            .foregroundColor: NSColor(cgColor: style.lineColor.cgColor) ?? .red,
            .paragraphStyle: paragraph,
        ])
    }

    static func drawCounter(_ a: Annotation, number: Int, in context: CGContext, scale: CGFloat) {
        let style = a.style
        let rect = a.bounds
        let diameter = min(rect.width, rect.height)
        guard diameter > 0 else { return }
        let circle = CGRect(x: rect.midX - diameter / 2, y: rect.midY - diameter / 2, width: diameter, height: diameter)
        let lineWidth = CGFloat(style.lineWidth) * scale
        withShadow(style.shadow, in: context, scale: scale) {
            if style.fillColor.isVisible {
                context.setFillColor(style.fillColor.cgColor)
                context.fillEllipse(in: circle)
            }
            if lineWidth > 0, style.lineColor.isVisible {
                context.setStrokeColor(style.lineColor.cgColor)
                context.setLineWidth(lineWidth)
                context.strokeEllipse(in: circle.insetBy(dx: lineWidth / 2, dy: lineWidth / 2))
            }
        }
        let label = NSAttributedString(string: String(number), attributes: [
            .font: NSFont.systemFont(ofSize: diameter * 0.55, weight: .bold),
            .foregroundColor: NSColor(cgColor: style.lineColor.cgColor) ?? .white,
        ])
        let size = label.size()
        label.draw(at: CGPoint(x: circle.midX - size.width / 2, y: circle.midY - size.height / 2))
    }

    // MARK: - Filters

    static func canvasBounds(_ context: CGContext) -> CGRect {
        CGRect(x: 0, y: 0, width: context.width, height: context.height)
    }

    /// The pixels already drawn in `rect` (top-left origin), as an image.
    static func snapshot(_ context: CGContext, rect: CGRect) -> CGImage? {
        context.makeImage()?.cropping(to: rect)
    }

    /// Draws `image` into `rect` of the flipped context the right way up.
    static func drawUpright(_ image: CGImage, in rect: CGRect, context: CGContext) {
        context.saveGState()
        context.translateBy(x: rect.minX, y: rect.maxY)
        context.scaleBy(x: 1, y: -1)
        context.draw(image, in: CGRect(origin: .zero, size: rect.size))
        context.restoreGState()
    }

    static func filtered(_ image: CGImage, _ apply: (CIImage) -> CIImage) -> CGImage? {
        let input = CIImage(cgImage: image)
        let output = apply(input.clampedToExtent()).cropped(to: input.extent)
        return ciContext.createCGImage(output, from: input.extent, format: .RGBA8, colorSpace: sRGB)
    }

    static func pixelated(_ image: CGImage, blockSize: CGFloat) -> CGImage? {
        filtered(image) { input in
            let filter = CIFilter.pixellate()
            filter.inputImage = input
            filter.scale = Float(max(blockSize, 1))
            filter.center = .zero
            return filter.outputImage ?? input
        }
    }

    static func blurred(_ image: CGImage, radius: CGFloat) -> CGImage? {
        filtered(image) { input in
            let filter = CIFilter.gaussianBlur()
            filter.inputImage = input
            filter.radius = Float(max(radius, 0))
            return filter.outputImage ?? input
        }
    }

    static func drawObfuscate(_ a: Annotation, in context: CGContext, scale: CGFloat) {
        let rect = a.bounds.integral.intersection(canvasBounds(context))
        guard !rect.isEmpty, let source = snapshot(context, rect: rect) else { return }
        let result: CGImage?
        switch a.style.obfuscateMode {
        case .pixelate: result = pixelated(source, blockSize: CGFloat(a.style.pixelSize) * scale)
        case .blur: result = blurred(source, radius: CGFloat(a.style.blurRadius) * scale)
        }
        if let result { drawUpright(result, in: rect, context: context) }
    }

    static func drawHighlight(_ a: Annotation, in context: CGContext, scale: CGFloat) {
        let canvas = canvasBounds(context)
        let rect = a.bounds.integral.intersection(canvas)
        guard !rect.isEmpty else { return }
        let style = a.style
        switch style.highlightMode {
        case .text:
            // Upstream HighlightFilter keeps the darker of each color channel: a marker pen.
            context.setBlendMode(.darken)
            context.setFillColor(style.fillColor.cgColor)
            context.fill(rect)
        case .grayscale:
            guard let source = snapshot(context, rect: rect),
                  let gray = filtered(source, { input in
                      let filter = CIFilter.colorControls()
                      filter.inputImage = input
                      filter.saturation = 0
                      return filter.outputImage ?? input
                  }) else { return }
            drawUpright(gray, in: rect, context: context)
        case .magnify:
            let factor = max(CGFloat(style.magnification), 1)
            let sourceRect = CGRect(x: rect.midX - rect.width / factor / 2, y: rect.midY - rect.height / factor / 2,
                                    width: rect.width / factor, height: rect.height / factor).integral.intersection(canvas)
            guard !sourceRect.isEmpty, let source = snapshot(context, rect: sourceRect) else { return }
            context.interpolationQuality = .high
            drawUpright(source, in: rect, context: context)
        case .area:
            // Upstream: an inverted brightness and blur filter, everything outside the area gets darker and blurred.
            guard let whole = context.makeImage(), let inside = whole.cropping(to: rect),
                  let dimmed = filtered(whole, { input in
                      let blur = CIFilter.gaussianBlur()
                      blur.inputImage = input
                      blur.radius = Float(3 * scale)
                      let dim = CIFilter.colorMatrix()
                      dim.inputImage = blur.outputImage ?? input
                      dim.rVector = CIVector(x: 0.7, y: 0, z: 0, w: 0)
                      dim.gVector = CIVector(x: 0, y: 0.7, z: 0, w: 0)
                      dim.bVector = CIVector(x: 0, y: 0, z: 0.7, w: 0)
                      return dim.outputImage ?? input
                  }) else { return }
            drawUpright(dimmed, in: canvas, context: context)
            drawUpright(inside, in: rect, context: context)
        }
    }
}
