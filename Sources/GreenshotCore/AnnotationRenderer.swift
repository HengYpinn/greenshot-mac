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
    ///   - hiddenID: the element whose text is being edited in place: it is drawn without its text (its frame, fill
    ///     and a speech bubble's shape stay around the text field).
    ///   - counterStart: the number of the first counter.
    ///   - cutElements: the elements whose cut marks and torn edges cut the image, when not all of them are among
    ///     `annotations` (Apply to the Image draws some of the document's): their shadow is shared (`CutShadow`).
    public static func flatten(base: CGImage, annotations: [Annotation], scale: CGFloat, hiding hiddenID: UUID? = nil,
                               counterStart: Int = 1, cutElements: [Annotation]? = nil) -> CGImage? {
        guard let context = makeContext(width: base.width, height: base.height) else { return nil }
        context.draw(base, in: CGRect(x: 0, y: 0, width: base.width, height: base.height))
        // From here on the origin is at the top left, like the annotation coordinates.
        context.translateBy(x: 0, y: CGFloat(base.height))
        context.scaleBy(x: 1, y: -1)

        let previous = NSGraphicsContext.current
        NSGraphicsContext.current = NSGraphicsContext(cgContext: context, flipped: true)
        defer { NSGraphicsContext.current = previous }

        let cutSource = cutElements ?? annotations
        let cuts = cutSource.contains { AnnotationKind.cutEdgeKinds.contains($0.kind) }
            ? CutShadow(cutSource, canvas: CGRect(x: 0, y: 0, width: base.width, height: base.height), scale: scale)
            : nil
        let canvas = CGRect(x: 0, y: 0, width: base.width, height: base.height)
        let inverted = invertedHighlightGroups(annotations.filter { $0.id != hiddenID || $0.kind.hasEditableText },
                                               canvas: canvas)
        let cutKinds = cutSource.filter { AnnotationKind.cutEdgeKinds.contains($0.kind) }
        var drawnGroups: [InvertedHighlightGroup] = []
        var counter = counterStart - 1
        for (index, annotation) in annotations.enumerated() {
            if annotation.kind == .counter { counter += 1 }
            var shown = annotation
            if annotation.id == hiddenID {
                guard annotation.kind.hasEditableText else { continue }
                shown.text = ""
            }
            let mode = annotation.style.highlightMode
            // Upstream draws the group where the first of its highlights that is on the canvas (the repainted area)
            // comes in the drawing order (`DrawingBounds.IntersectsWith(clipRectangle)`).
            if annotation.kind == .highlight, let group = inverted[mode], !drawnGroups.contains(where: { $0.mode == mode }),
               !annotation.bounds.integral.intersection(canvas).isEmpty {
                let key = InvertedEffectKey(base: base, below: Array(annotations[..<index]), hiddenID: hiddenID,
                                            counterStart: counterStart, cutElements: cutKinds, scale: scale, mode: mode,
                                            style: group.style, earlierAreas: drawnGroups.map(\.areas))
                context.saveGState()
                drawInvertedHighlight(group, in: context, scale: scale, key: key)
                context.restoreGState()
                drawnGroups.append(group)
            }
            context.saveGState()
            draw(shown, number: counter, in: context, scale: scale, cuts: cuts)
            context.restoreGState()
        }
        return context.makeImage()
    }

    /// The highlights of one mode that change the image outside their area (area and grayscale, upstream's filters with
    /// `Invert`), drawn once together.
    struct InvertedHighlightGroup: Equatable {
        var mode: HighlightMode
        /// The first highlight's of the mode in the drawing order, on the canvas or not (upstream's
        /// `idleContainers.First()`; upstream prefers a selected one, which the renderer doesn't know).
        var style: AnnotationStyle
        /// Their areas on the canvas, whole pixels, in drawing order.
        var areas: [CGRect]
    }

    /// The groups of `annotations` by mode. A mode whose highlights are all off the canvas has none: it changes nothing.
    static func invertedHighlightGroups(_ annotations: [Annotation], canvas: CGRect) -> [HighlightMode: InvertedHighlightGroup] {
        var groups: [HighlightMode: InvertedHighlightGroup] = [:]
        for a in annotations where a.kind == .highlight && a.style.highlightMode.changesOutside {
            let mode = a.style.highlightMode
            var group = groups[mode] ?? InvertedHighlightGroup(mode: mode, style: a.style, areas: [])
            let rect = a.bounds.integral.intersection(canvas)
            if !rect.isEmpty { group.areas.append(rect) }
            groups[mode] = group
        }
        return groups.filter { !$0.value.areas.isEmpty }
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

    static func draw(_ a: Annotation, number: Int, in context: CGContext, scale: CGFloat, cuts: CutShadow? = nil) {
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
        case .image, .cursor:
            drawPicture(a, in: context, scale: scale)
        case .cutMark:
            drawCutMark(a, in: context, scale: scale, cuts: cuts)
        case .tornEdge:
            drawTornEdge(a, in: context, scale: scale, cuts: cuts)
        case .svg:
            drawSvg(a, in: context, scale: scale)
        case .barcode:
            drawBarcode(a, in: context, scale: scale)
        }
    }

    /// Upstream `CutMarkContainer.Draw`: the gap filled with the fill color or made transparent (upstream's export
    /// mode, so what is saved is what is shown), the shadow the rest of the image casts into it, and the line along
    /// the edges. With other cut marks or torn edges in `cuts` the shadow is shared with them (upstream `CutShadow`).
    static func drawCutMark(_ a: Annotation, in context: CGContext, scale: CGFloat, cuts: CutShadow? = nil) {
        let style = a.style
        let canvas = canvasBounds(context)
        let shared = cuts.flatMap { $0.isAlone(a.id) ? nil : $0 }
        guard let shape = cuts?.cut(a.id)?.cutMark ?? CutMark.shape(of: a, imageSize: canvas.size, scale: scale) else {
            return
        }
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
            if let shared {
                shared.drawShadow(of: a.id, layout: a.cutEdges ?? CutEdgeLayout(), in: context, scale: scale)
            } else {
                // The parts of the image on both sides cast their shadow into the gap.
                let outside = CGMutablePath()
                outside.addRect(canvas)
                outside.addPath(shape.gap)
                drawCutShadow(into: shape.gap, areaRule: .winding, caster: outside, casterRule: .evenOdd,
                              layout: a.cutEdges ?? CutEdgeLayout(), in: context, scale: scale)
            }
        }

        let lineWidth = CGFloat(style.lineWidth) * scale
        if lineWidth > 0, style.lineColor.isVisible {
            // The edges are part of the image: where another element cut it away they don't show.
            shared?.clipOutOtherCuts(than: a.id, in: context)
            context.setStrokeColor(style.lineColor.cgColor)
            context.setLineWidth(lineWidth)
            context.setLineJoin(.round)
            context.setLineCap(.round)
            context.addLines(between: shape.first)
            context.addLines(between: shape.second)
            context.strokePath()
        }
    }

    /// Upstream `TornEdgeContainer.Draw`: the torn off parts filled with the fill color or made transparent (export
    /// mode, like cut marks), the shadow the part that stays casts into them, and the line along the torn sides. With
    /// other cut marks or torn edges in `cuts` the shadow is shared with them (upstream `CutShadow`).
    static func drawTornEdge(_ a: Annotation, in context: CGContext, scale: CGFloat, cuts: CutShadow? = nil) {
        let style = a.style
        let canvas = canvasBounds(context)
        let shared = cuts.flatMap { $0.isAlone(a.id) ? nil : $0 }
        guard let shape = cuts?.cut(a.id)?.tornEdge ?? TornEdge.shape(of: a, imageSize: canvas.size, scale: scale) else {
            return
        }
        context.saveGState()
        context.addPath(shape.tornOff)
        if style.fillColor.isVisible {
            context.setFillColor(style.fillColor.cgColor)
        } else {
            context.setBlendMode(.clear)
        }
        context.fillPath(using: .evenOdd)
        context.restoreGState()

        if style.shadow {
            if let shared {
                shared.drawShadow(of: a.id, layout: a.cutEdges ?? CutEdgeLayout(), in: context, scale: scale)
            } else {
                drawCutShadow(into: shape.tornOff, areaRule: .evenOdd, caster: shape.kept, casterRule: .winding,
                              layout: a.cutEdges ?? CutEdgeLayout(), in: context, scale: scale)
            }
        }

        let lineWidth = CGFloat(style.lineWidth) * scale
        if lineWidth > 0, style.lineColor.isVisible {
            shared?.clipOutOtherCuts(than: a.id, in: context)
            context.setStrokeColor(style.lineColor.cgColor)
            context.setLineWidth(lineWidth)
            context.setLineJoin(.round)
            context.setLineCap(.round)
            for side in shape.tornSides { context.addLines(between: side) }
            context.strokePath()
        }
    }

    /// Upstream `CutShadow`: the part of the image that stays (`caster`) casts a soft shadow into the cut `area`, as
    /// dark, soft and far as the element's settings say. Upstream `ImageHelper.CreateShadow` puts the shadow `size`
    /// pixels in and the image at `offset + size - 1`, and `CutShadow.Draw` draws the image back at its place, so the
    /// shadow lies `1 - offset` points down right of what casts it (2 points with the default offset of -1).
    static func drawCutShadow(into area: CGPath, areaRule: CGPathFillRule, caster: CGPath, casterRule: CGPathFillRule,
                              layout: CutEdgeLayout, in context: CGContext, scale: CGFloat) {
        context.saveGState()
        context.addPath(area)
        context.clip(using: areaRule)
        setCutShadow(layout, in: context, scale: scale)
        context.addPath(caster)
        context.setFillColor(CGColor(gray: 0, alpha: 1))
        context.fillPath(using: casterRule)
        context.restoreGState()
    }

    /// The shadow of a cut mark or torn edges as `drawCutShadow` describes it, for what is drawn next.
    static func setCutShadow(_ layout: CutEdgeLayout, in context: CGContext, scale: CGFloat) {
        let right = CGFloat(1 - layout.shadowOffsetX) * scale
        let down = CGFloat(1 - layout.shadowOffsetY) * scale
        let blur = CGFloat(max(1, layout.shadowSize)) * scale
        // Shadow offsets are in the bitmap's own space (y up) and ignore the flipped CTM, so "down" is negative.
        context.setShadow(offset: CGSize(width: right, height: -down), blur: blur,
                          color: CGColor(gray: 0, alpha: CGFloat(min(max(layout.shadowDarkness, 0), 1))))
    }

    /// Upstream `ImageContainer.Draw`: the picture stretched into the box, turned like the element (`rotation`), with an
    /// optional shadow.
    static func drawPicture(_ a: Annotation, in context: CGContext, scale: CGFloat) {
        let box = a.bounds
        guard box.width > 0, box.height > 0, let picture = picture(of: a) else { return }
        withShadow(a.style.shadow, in: context, scale: scale) {
            context.interpolationQuality = .high
            withContentRotation(a, in: context) { content in
                drawUpright(picture, in: content, context: context)
            }
        }
    }

    /// Runs `draw` with the element's content box (`Annotation.contentBounds`) and the context turned about the box's
    /// centre by the element's `rotation`, so what `draw` puts into the box comes out turned into `bounds`. The context
    /// is y-down, so a positive quarter turn is clockwise on screen, like upstream's `Graphics.RotateTransform`. Exact
    /// quarter turns keep a box with whole-pixel edges on whole pixels. Upstream turns a bitmap of the turned box's size
    /// (`ImageHelper.Rotate`), which squeezes and clips; drawing at the unturned size keeps the content whole and sharp.
    static func withContentRotation(_ a: Annotation, in context: CGContext, _ draw: (CGRect) -> Void) {
        let turns = a.contentQuarterTurns
        guard turns != 0 else {
            draw(a.bounds)
            return
        }
        let box = a.bounds
        context.saveGState()
        context.translateBy(x: box.midX, y: box.midY)
        context.concatenate(quarterTurn(turns))
        context.translateBy(x: -box.midX, y: -box.midY)
        draw(a.contentBounds)
        context.restoreGState()
    }

    /// `turns` clockwise quarter turns (in a y-down space) as an exact matrix.
    static func quarterTurn(_ turns: Int) -> CGAffineTransform {
        switch (turns % 4 + 4) % 4 {
        case 1: return CGAffineTransform(a: 0, b: 1, c: -1, d: 0, tx: 0, ty: 0)
        case 2: return CGAffineTransform(a: -1, b: 0, c: 0, d: -1, tx: 0, ty: 0)
        case 3: return CGAffineTransform(a: 0, b: -1, c: 1, d: 0, tx: 0, ty: 0)
        default: return .identity
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

    /// Upstream `TextContainer.Draw`: the box like a rectangle (`RectangleContainer.DrawRectangle`: fill, a frame of
    /// the line width in the line colour, the shadow of both), then the text, with a shadow only when there is no fill.
    static func drawText(_ a: Annotation, in context: CGContext, scale: CGFloat) {
        let style = a.style
        drawShape(CGPath(rect: a.bounds, transform: nil), style: style, lineWidth: CGFloat(style.lineWidth) * scale,
                  in: context, scale: scale)
        var textStyle = style
        if style.fillColor.isVisible { textStyle.shadow = false }
        drawAlignedText(a.text, style: textStyle, in: textRect(for: a, scale: scale), context: context, scale: scale)
    }

    /// How far the text of a text element or speech bubble is inside its box: a little, plus half the frame, like
    /// upstream `TextContainer.DrawText` (which moves it in by half the line width).
    static func textInset(of style: AnnotationStyle, scale: CGFloat) -> CGFloat {
        2 * scale + ceil(CGFloat(max(style.lineWidth, 0)) * scale / 2)
    }

    /// The area the text of a text element or speech bubble is laid out in, inside its frame.
    public static func textRect(for a: Annotation, scale: CGFloat) -> CGRect {
        let inset = textInset(of: a.style, scale: scale)
        return a.bounds.insetBy(dx: inset, dy: inset)
    }

    /// The box a text element needs to show `text` in one go (upstream `TextContainer.FitToText`), at most `maxWidth`
    /// pixels wide; longer lines wrap. Pixels.
    public static func textBoxSize(_ text: String, style: AnnotationStyle, scale: CGFloat, maxWidth: CGFloat) -> CGSize {
        let inset = textInset(of: style, scale: scale)
        let string = attributedText(text, style: style, pixelsPerPoint: scale)
        let room = max(maxWidth - 2 * inset, scale)
        let measured = string.boundingRect(with: CGSize(width: room, height: .greatestFiniteMagnitude),
                                           options: [.usesLineFragmentOrigin, .usesFontLeading])
        // A pixel to spare, so the same text doesn't wrap when it is drawn into exactly this width.
        let width = min(ceil(measured.width) + scale, room) + 2 * inset
        let height = ceil(measured.height) + scale + 2 * inset
        return CGSize(width: width, height: height)
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
    /// here it is the system's Apple Color Emoji), turned like the element (upstream `EmojiContainer.ComputeBitmap`).
    static func drawEmoji(_ a: Annotation, in context: CGContext, scale: CGFloat) {
        let box = a.bounds
        let side = min(box.width, box.height)
        guard side > 0, !a.text.isEmpty else { return }
        let fontSize = side * emojiFontScale
        let font = NSFont(name: "Apple Color Emoji", size: fontSize) ?? NSFont.systemFont(ofSize: fontSize)
        let glyph = NSAttributedString(string: a.text, attributes: [.font: font])
        let size = glyph.size()
        withShadow(a.style.shadow, in: context, scale: scale) {
            withContentRotation(a, in: context) { content in
                glyph.draw(at: CGPoint(x: content.midX - size.width / 2, y: content.midY - size.height / 2))
            }
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
        case .pixelate: result = ImagePixelation.pixelated(source, blockSize: CGFloat(a.style.pixelSize) * scale, element: a.id)
        case .blur: result = blurred(source, radius: CGFloat(a.style.blurRadius) * scale)
        }
        if let result { drawUpright(result, in: rect, context: context) }
    }

    /// What the area highlight does to the image outside its area: blurred with `blurRadius` pixels (upstream
    /// `BlurFilter`) and made darker by adding brightness − 1 to every channel (upstream `BrightnessFilter` with
    /// `ImageHelper.CreateAdjustAttributes`, 0.9 by default).
    static func areaHighlightOutside(_ image: CGImage, blurRadius: CGFloat, brightness: CGFloat) -> CGImage? {
        filtered(image) { input in
            var output = input
            if blurRadius > 0 {
                let blur = CIFilter.gaussianBlur()
                blur.inputImage = output
                blur.radius = Float(blurRadius)
                output = blur.outputImage ?? output
            }
            // Upstream adds the offset to the stored (sRGB) values; Core Image works on linear light, so convert around it.
            let offset = brightness - 1
            let toSRGB = CIFilter.linearToSRGBToneCurve()
            toSRGB.inputImage = output
            let adjust = CIFilter.colorMatrix()
            adjust.inputImage = toSRGB.outputImage ?? output
            adjust.biasVector = CIVector(x: offset, y: offset, z: offset, w: 0)
            let toLinear = CIFilter.sRGBToneCurveToLinear()
            toLinear.inputImage = adjust.outputImage ?? output
            return toLinear.outputImage ?? output
        }
    }

    /// A highlight element. The area and grayscale highlights change the image outside their area; `flatten` draws
    /// that once for all highlights of a mode (`drawInvertedHighlight`), so here they only add their shadow.
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
        case .magnify:
            let factor = max(CGFloat(style.magnification), 1)
            let sourceRect = CGRect(x: rect.midX - rect.width / factor / 2, y: rect.midY - rect.height / factor / 2,
                                    width: rect.width / factor, height: rect.height / factor).integral.intersection(canvas)
            guard !sourceRect.isEmpty, let source = snapshot(context, rect: sourceRect) else { return }
            context.interpolationQuality = .high
            drawUpright(source, in: rect, context: context)
        case .area, .grayscale:
            break
        }
    }

    /// Upstream `DrawableContainerList.Draw` since 4b3d9dee: the highlights whose filter works outside their area are
    /// drawn once per mode, where the first of them on the canvas is in the drawing order, with every one of their
    /// `areas` left out (`AbstractFilter.ApplyWithClipping` with `Invert`: the whole bitmap, `ExcludeClip` of each
    /// area). So a second area highlight doesn't darken the first one's area, and elements drawn between them stay on
    /// top. The group's style is the first highlight's (`InvertedHighlightGroup.style`).
    /// - Area: everything outside darker and blurred (upstream `BrightnessFilter` and `BlurFilter`, `Invert = true`).
    /// - Grayscale: everything outside grey (upstream `GrayscaleFilter { Invert = true }`, `HighlightContainer.cs`).
    ///
    /// The changed picture of the whole canvas is kept (`invertedEffects`, by `key`), so a redraw where nothing below
    /// the group changed, such as dragging an element above it or one of the highlights, doesn't make it again.
    static func drawInvertedHighlight(_ group: InvertedHighlightGroup, in context: CGContext, scale: CGFloat,
                                      key: InvertedEffectKey? = nil) {
        guard !group.areas.isEmpty, let changed = invertedEffect(group, of: context, scale: scale, key: key) else { return }
        let holes = CGMutablePath()
        for area in group.areas { holes.addRect(area) }
        // The canvas without the areas; subtracting their union also leaves out where two areas overlap (an even-odd
        // clip would bring the overlap back).
        let outside = CGPath(rect: canvasBounds(context), transform: nil).subtracting(holes)
        context.addPath(outside)
        context.clip()
        // Replaces the pixels, so half transparent ones aren't laid over themselves.
        context.setBlendMode(.copy)
        drawUpright(changed, in: canvasBounds(context), context: context)
    }

    /// The whole canvas as `group`'s filter changes it: kept from an earlier draw with the same `key`, else made from
    /// what `context` holds now.
    static func invertedEffect(_ group: InvertedHighlightGroup, of context: CGContext, scale: CGFloat,
                               key: InvertedEffectKey?) -> CGImage? {
        let name = group.mode.rawValue as NSString
        if let key, let kept = invertedEffects.object(forKey: name), kept.key == key { return kept.image }
        guard let whole = context.makeImage() else { return nil }
        let changed: CGImage?
        switch group.mode {
        case .area:
            changed = areaHighlightOutside(whole, blurRadius: CGFloat(group.style.blurRadius) * scale,
                                           brightness: CGFloat(group.style.brightness))
        case .grayscale:
            changed = grayscale(whole)
        case .text, .magnify:
            changed = nil
        }
        if let key, let changed {
            invertedEffects.setObject(InvertedEffect(key: key, image: changed), forKey: name,
                                      cost: changed.bytesPerRow * changed.height)
        }
        return changed
    }

    /// Everything the canvas below an inverted highlight group depends on: the image (the same object; images never
    /// change), the elements drawn before the group with the one being edited, how counters are numbered, the cut marks
    /// and torn edges (their shadow is shared), the scale, the group's mode and style, and the areas of groups drawn
    /// earlier.
    struct InvertedEffectKey: Equatable {
        let base: CGImage
        let below: [Annotation]
        let hiddenID: UUID?
        let counterStart: Int
        let cutElements: [Annotation]
        let scale: CGFloat
        let mode: HighlightMode
        let style: AnnotationStyle
        let earlierAreas: [[CGRect]]

        static func == (lhs: InvertedEffectKey, rhs: InvertedEffectKey) -> Bool {
            guard lhs.base === rhs.base, lhs.mode == rhs.mode, lhs.scale == rhs.scale, lhs.hiddenID == rhs.hiddenID,
                  lhs.counterStart == rhs.counterStart, lhs.style == rhs.style, lhs.earlierAreas == rhs.earlierAreas else {
                return false
            }
            return lhs.below == rhs.below && lhs.cutElements == rhs.cutElements
        }
    }

    final class InvertedEffect {
        let key: InvertedEffectKey
        let image: CGImage

        init(key: InvertedEffectKey, image: CGImage) {
            self.key = key
            self.image = image
        }
    }

    /// The last changed canvas per mode (two at most); given back under memory pressure.
    static let invertedEffects: NSCache<NSString, InvertedEffect> = {
        let cache = NSCache<NSString, InvertedEffect>()
        cache.totalCostLimit = 512 * 1024 * 1024
        return cache
    }()

    /// The image without colour.
    static func grayscale(_ image: CGImage) -> CGImage? {
        filtered(image) { input in
            let filter = CIFilter.colorControls()
            filter.inputImage = input
            filter.saturation = 0
            return filter.outputImage ?? input
        }
    }
}
