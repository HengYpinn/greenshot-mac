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
    ///   - hiddenID: the element whose text is being edited in place. A text element is left out; a speech bubble
    ///     is drawn without its text, as the frame around the text field.
    ///   - counterStart: the number of the first counter.
    public static func flatten(base: CGImage, annotations: [Annotation], scale: CGFloat, hiding hiddenID: UUID? = nil,
                               counterStart: Int = 1) -> CGImage? {
        guard let context = makeContext(width: base.width, height: base.height) else { return nil }
        context.draw(base, in: CGRect(x: 0, y: 0, width: base.width, height: base.height))
        // From here on the origin is at the top left, like the annotation coordinates.
        context.translateBy(x: 0, y: CGFloat(base.height))
        context.scaleBy(x: 1, y: -1)

        let previous = NSGraphicsContext.current
        NSGraphicsContext.current = NSGraphicsContext(cgContext: context, flipped: true)
        defer { NSGraphicsContext.current = previous }

        var counter = counterStart - 1
        for annotation in annotations {
            if annotation.kind == .counter { counter += 1 }
            var shown = annotation
            if annotation.id == hiddenID {
                guard annotation.kind == .speechBubble else { continue }
                shown.text = ""
            }
            context.saveGState()
            draw(shown, number: counter, in: context, scale: scale)
            context.restoreGState()
        }
        return context.makeImage()
    }

    /// The font of a text element; `size` in pixels.
    public static func font(for style: AnnotationStyle, size: CGFloat) -> NSFont {
        if !style.fontFamily.isEmpty {
            var traits: NSFontTraitMask = []
            if style.bold { traits.insert(.boldFontMask) }
            if style.italic { traits.insert(.italicFontMask) }
            if let font = NSFontManager.shared.font(withFamily: style.fontFamily, traits: traits, weight: 5, size: size) {
                return font
            }
            // The family has no bold or italic face: its regular one, else the system font.
            if let font = NSFontManager.shared.font(withFamily: style.fontFamily, traits: [], weight: 5, size: size) {
                return font
            }
        }
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
        case .speechBubble:
            drawSpeechBubble(a, in: context, scale: scale)
        case .emoji:
            drawEmoji(a, in: context, scale: scale)
        case .image:
            drawPicture(a, in: context, scale: scale)
        case .cutMark:
            drawCutMark(a, in: context, scale: scale)
        }
    }

    /// Upstream `CutMarkContainer.Draw`: the gap filled with the fill color or made transparent (upstream's export
    /// mode, so what is saved is what is shown), the shadow the rest of the image casts into it, and the line along
    /// the edges.
    static func drawCutMark(_ a: Annotation, in context: CGContext, scale: CGFloat) {
        let style = a.style
        let canvas = canvasBounds(context)
        guard let shape = CutMark.shape(band: CutMark.band(of: a, imageSize: canvas.size), style: style.cutMarkStyle,
                                        toothHeight: CGFloat(style.toothHeight) * scale,
                                        toothRange: CGFloat(style.toothRange) * scale, seed: CutMark.seed(of: a),
                                        vertical: a.isVerticalCutMark) else { return }
        context.saveGState()
        context.addPath(shape.gap)
        if style.fillColor.isVisible {
            context.setFillColor(style.fillColor.cgColor)
        } else {
            context.setBlendMode(.clear)
        }
        context.fillPath()
        context.restoreGState()

        if style.shadow {
            // Like upstream's CutShadow: the parts of the image cast a soft shadow into the gap. Everything but the gap
            // is filled, clipped to the gap, so only the shadow of it shows.
            context.saveGState()
            context.addPath(shape.gap)
            context.clip()
            context.setShadow(offset: .zero, blur: 6 * scale, color: CGColor(gray: 0, alpha: 0.6))
            let outside = CGMutablePath()
            outside.addRect(canvas.insetBy(dx: -20 * scale, dy: -20 * scale))
            outside.addPath(shape.gap)
            context.addPath(outside)
            context.setFillColor(CGColor(gray: 0, alpha: 1))
            context.fillPath(using: .evenOdd)
            context.restoreGState()
        }

        let lineWidth = CGFloat(style.lineWidth) * scale
        if lineWidth > 0, style.lineColor.isVisible {
            context.setStrokeColor(style.lineColor.cgColor)
            context.setLineWidth(lineWidth)
            context.setLineJoin(.round)
            context.setLineCap(.round)
            context.addLines(between: shape.first)
            context.addLines(between: shape.second)
            context.strokePath()
        }
    }

    /// Upstream `ImageContainer.Draw`: the picture stretched into the box, with an optional shadow.
    static func drawPicture(_ a: Annotation, in context: CGContext, scale: CGFloat) {
        let box = a.bounds
        guard box.width > 0, box.height > 0, let picture = picture(of: a) else { return }
        withShadow(a.style.shadow, in: context, scale: scale) {
            context.interpolationQuality = .high
            drawUpright(picture, in: box, context: context)
        }
    }

    private final class DecodedPicture {
        let byteCount: Int
        let image: CGImage

        init(byteCount: Int, image: CGImage) {
            self.byteCount = byteCount
            self.image = image
        }
    }

    /// Decoded pictures by element: an element's picture never changes, and decoding PNG on every redraw is slow.
    private static let pictures = NSCache<NSUUID, DecodedPicture>()

    /// The picture of an image element.
    public static func picture(of a: Annotation) -> CGImage? {
        guard let data = a.imageData else { return nil }
        let key = a.id as NSUUID
        if let cached = pictures.object(forKey: key), cached.byteCount == data.count { return cached.image }
        guard let source = CGImageSourceCreateWithData(data as CFData, nil),
              let image = CGImageSourceCreateImageAtIndex(source, 0, nil) else { return nil }
        pictures.setObject(DecodedPicture(byteCount: data.count, image: image), forKey: key)
        return image
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
        if style.fillColor.isVisible {
            context.setFillColor(style.fillColor.cgColor)
            context.fill(a.bounds)
        }
        drawAlignedText(a.text, style: style, in: textRect(for: a, scale: scale), context: context, scale: scale)
    }

    /// The area the text of a text element or speech bubble is laid out in. A bubble's text stays inside its
    /// outline, like upstream `TextContainer.DrawText` (which moves it in by half the line width).
    public static func textRect(for a: Annotation, scale: CGFloat) -> CGRect {
        var inset = 2 * scale
        if a.kind == .speechBubble { inset += ceil(CGFloat(a.style.lineWidth) * scale / 2) }
        return a.bounds.insetBy(dx: inset, dy: inset)
    }

    /// Where `text` is drawn in `rect`: wrapped at its width, placed by the style's vertical alignment
    /// (upstream `StringFormat.LineAlignment`; text taller than the box starts at its top).
    public static func textFrame(_ text: String, style: AnnotationStyle, in rect: CGRect, scale: CGFloat) -> CGRect {
        let string = attributedText(text, style: style, pixelsPerPoint: scale)
        let measured = string.boundingRect(with: CGSize(width: rect.width, height: .greatestFiniteMagnitude),
                                           options: [.usesLineFragmentOrigin, .usesFontLeading])
        let room = max(0, rect.height - measured.height)
        let y: CGFloat
        switch style.verticalAlignment {
        case .top: y = rect.minY
        case .center: y = rect.minY + room / 2
        case .bottom: y = rect.minY + room
        }
        return CGRect(x: rect.minX, y: y, width: rect.width, height: ceil(measured.height) + 1)
    }

    /// `text` in `rect`, aligned like the style says.
    static func drawAlignedText(_ text: String, style: AnnotationStyle, in rect: CGRect, context: CGContext, scale: CGFloat) {
        guard !text.isEmpty, style.lineColor.isVisible, rect.width > 0 else { return }
        let string = attributedText(text, style: style, pixelsPerPoint: scale)
        let target = textFrame(text, style: style, in: rect, scale: scale)
        withShadow(style.shadow, in: context, scale: scale) {
            string.draw(with: target, options: [.usesLineFragmentOrigin, .usesFontLeading], context: nil)
        }
    }

    /// The rounded box of a speech bubble (upstream `SpeechbubbleContainer.CreateBubble`): the corners get smaller
    /// in a small bubble, down to square ones.
    static func speechBubbleBody(_ a: Annotation, lineWidth: CGFloat, scale: CGFloat) -> CGPath {
        let box = a.bounds
        // Upstream's value is the size of the corner arc's box, so the radius is half of it.
        let cornerSize = min(30 * scale, min(box.width, box.height) / 2 - lineWidth)
        guard cornerSize > 0 else { return CGPath(rect: box, transform: nil) }
        return CGPath(roundedRect: box, cornerWidth: cornerSize / 2, cornerHeight: cornerSize / 2, transform: nil)
    }

    /// Upstream `SpeechbubbleContainer.Draw`. Upstream strokes and fills the box and the tail separately, clipping
    /// each outline where the other shape covers it; filling and outlining their union draws the same shape in one go.
    static func drawSpeechBubble(_ a: Annotation, in context: CGContext, scale: CGFloat) {
        let style = a.style
        let lineWidth = CGFloat(style.lineWidth) * scale
        let shape = speechBubbleBody(a, lineWidth: lineWidth, scale: scale).union(a.speechBubbleTail)
        drawShape(shape, style: style, lineWidth: lineWidth, in: context, scale: scale)
        drawAlignedText(a.text, style: style, in: textRect(for: a, scale: scale), context: context, scale: scale)
    }

    /// The emoji, as big as fits in the element's square (upstream `EmojiRenderer`, which uses the Twemoji font;
    /// here it is the system's Apple Color Emoji).
    static func drawEmoji(_ a: Annotation, in context: CGContext, scale: CGFloat) {
        let box = a.bounds
        let side = min(box.width, box.height)
        guard side > 0, !a.text.isEmpty else { return }
        let fontSize = side * emojiFontScale
        let font = NSFont(name: "Apple Color Emoji", size: fontSize) ?? NSFont.systemFont(ofSize: fontSize)
        let glyph = NSAttributedString(string: a.text, attributes: [.font: font])
        let size = glyph.size()
        withShadow(a.style.shadow, in: context, scale: scale) {
            glyph.draw(at: CGPoint(x: box.midX - size.width / 2, y: box.midY - size.height / 2))
        }
    }

    /// Font size per pixel of the emoji's square. Upstream renders at 95 %; Apple Color Emoji glyphs are about as big
    /// as their font size and sit a little low in the line, so 90 % keeps every one inside the square.
    static let emojiFontScale: CGFloat = 0.9

    /// The paragraph alignment of a style (upstream's default is `StringAlignment.Center`).
    public static func alignment(of style: AnnotationStyle) -> NSTextAlignment {
        switch style.horizontalAlignment {
        case .left: return .left
        case .center: return .center
        case .right: return .right
        }
    }

    /// The text of a text element, aligned like its style says.
    public static func attributedText(_ text: String, style: AnnotationStyle, pixelsPerPoint: CGFloat) -> NSAttributedString {
        let paragraph = NSMutableParagraphStyle()
        paragraph.alignment = alignment(of: style)
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

    /// The shadow around a filter's area, drawn outside it only, so the filter inside sees the image as it is.
    static func drawOuterShadow(of rect: CGRect, in context: CGContext, scale: CGFloat) {
        context.saveGState()
        let outside = CGMutablePath()
        outside.addRect(canvasBounds(context).insetBy(dx: -20 * scale, dy: -20 * scale))
        outside.addRect(rect)
        context.addPath(outside)
        context.clip(using: .evenOdd)
        context.setShadow(offset: CGSize(width: 2 * scale, height: -2 * scale), blur: 3 * scale, color: CGColor(gray: 0, alpha: 0.5))
        context.setFillColor(CGColor(gray: 0, alpha: 1))
        context.fill(rect)
        context.restoreGState()
    }

    static func drawObfuscate(_ a: Annotation, in context: CGContext, scale: CGFloat) {
        let rect = a.bounds.integral.intersection(canvasBounds(context))
        guard !rect.isEmpty, let source = snapshot(context, rect: rect) else { return }
        if a.style.shadow { drawOuterShadow(of: rect, in: context, scale: scale) }
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
        if style.shadow && style.highlightMode != .area { drawOuterShadow(of: rect, in: context, scale: scale) }
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
