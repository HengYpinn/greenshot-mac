// Greenshot for Mac (Community) - an unofficial macOS port of Greenshot
// Copyright (C) 2026 Greenshot for Mac (Community) contributors
// Based on Greenshot, Copyright (C) 2007-2026 Thomas Braun, Jens Klingen, Robin Krom
// SPDX-License-Identifier: GPL-3.0-or-later

import CoreGraphics
import Foundation

/// The drawable elements of the editor. Upstream calls them containers (`Greenshot.Editor/Drawing/*Container.cs`).
public enum AnnotationKind: String, Codable, CaseIterable, Sendable {
    case rectangle, ellipse, line, arrow, freehand, text, highlight, obfuscate, counter, speechBubble, emoji
    /// A pasted or dropped picture (upstream `ImageContainer`).
    case image
    /// Marks where a strip was cut out of the image: a band across the whole image between two edges
    /// (upstream `CutMarkContainer`).
    case cutMark
    /// Torn edges of the whole image as an element that can be changed or removed later (upstream `TornEdgeContainer`).
    case tornEdge
    /// A picture that stays sharp at any size: the SVG it was made from (upstream `SvgContainer`).
    case svg
    /// The mouse pointer of the capture (upstream `CursorContainer`).
    case cursor
    /// A generated QR code or barcode, drawn from its `barcode` spec (upstream Zxing plugin `BarcodeContainer`).
    case barcode

    /// Elements that are a box: they get resize handles. Lines and arrows get two end points, freehand none.
    public var isBoxShaped: Bool {
        switch self {
        case .line, .arrow, .freehand: return false
        default: return true
        }
    }

    /// Elements whose text is typed in place: upstream `TextContainer` and its subclass `SpeechbubbleContainer`.
    public var hasEditableText: Bool {
        self == .text || self == .speechBubble
    }

    /// Elements whose content turns when the image is rotated (`Annotation.rotation`): upstream's
    /// `VectorGraphicsContainer` (SVG, emoji) and `ImageContainer` (pictures; the barcode element is one). The pointer
    /// stays upright, like upstream's `CursorContainer`; text never turns.
    public var turnsContentWithImage: Bool {
        switch self {
        case .svg, .emoji, .image, .barcode: return true
        default: return false
        }
    }
}

/// Upstream `PreparedFilter` values of the highlight container.
public enum HighlightMode: String, Codable, CaseIterable, Sendable {
    case text, area, grayscale, magnify

    /// Whether the highlight changes the image outside its area, not inside (upstream's filters with `Invert`: the
    /// area highlight's brightness and blur, the grayscale highlight's grayscale).
    public var changesOutside: Bool { self == .area || self == .grayscale }
}

/// Upstream `PreparedFilter` values of the obfuscate container.
public enum ObfuscateMode: String, Codable, CaseIterable, Sendable {
    case pixelate, blur
}

/// How the edges of a cut mark look (upstream `CutMarkStyle`).
public enum CutMarkStyle: String, Codable, CaseIterable, Sendable {
    case none, line, zigZag, wave, torn
}

/// Upstream `TEXT_HORIZONTAL_ALIGNMENT` (`StringAlignment` Near, Center, Far).
public enum HorizontalTextAlignment: String, Codable, CaseIterable, Sendable {
    case left, center, right
}

/// Upstream `TEXT_VERTICAL_ALIGNMENT`.
public enum VerticalTextAlignment: String, Codable, CaseIterable, Sendable {
    case top, center, bottom
}

/// Upstream `ArrowHeadCombination`.
public enum ArrowHeads: String, Codable, CaseIterable, Sendable {
    case none, start, end, both
}

public struct RGBAColor: Codable, Hashable, Sendable {
    public var red: Double
    public var green: Double
    public var blue: Double
    public var alpha: Double

    public init(red: Double, green: Double, blue: Double, alpha: Double = 1) {
        self.red = red
        self.green = green
        self.blue = blue
        self.alpha = alpha
    }

    public static let red = RGBAColor(red: 1, green: 0, blue: 0)
    public static let darkRed = RGBAColor(red: 139 / 255, green: 0, blue: 0)
    public static let blue = RGBAColor(red: 0, green: 0, blue: 1)
    public static let yellow = RGBAColor(red: 1, green: 1, blue: 0)
    public static let white = RGBAColor(red: 1, green: 1, blue: 1)
    public static let black = RGBAColor(red: 0, green: 0, blue: 0)
    public static let clear = RGBAColor(red: 0, green: 0, blue: 0, alpha: 0)
    /// .NET `Color.DimGray`.
    public static let dimGray = RGBAColor(red: 105 / 255, green: 105 / 255, blue: 105 / 255)

    public var isVisible: Bool { alpha > 0 }

    public var cgColor: CGColor {
        CGColor(srgbRed: red, green: green, blue: blue, alpha: alpha)
    }
}

/// The settable properties of an element (upstream "fields"). Sizes are in points; the renderer multiplies them
/// with the pixels per point of the capture, so a 2 pt line looks the same on a Retina and a normal display.
public struct AnnotationStyle: Codable, Equatable, Sendable {
    /// Outline color; the text color for text and counters.
    public var lineColor: RGBAColor
    /// Fill color; the background of text, the circle of counters, the highlight color of the text highlighter.
    public var fillColor: RGBAColor
    public var lineWidth: Double
    public var shadow: Bool
    public var fontSize: Double
    public var bold: Bool
    public var italic: Bool
    public var arrowHeads: ArrowHeads
    public var highlightMode: HighlightMode
    public var obfuscateMode: ObfuscateMode
    public var pixelSize: Double
    public var blurRadius: Double
    public var magnification: Double
    public var cutMarkStyle: CutMarkStyle
    /// How deep the edges of a cut mark go into the image, points (upstream `TOOTH_HEIGHT`).
    public var toothHeight: Double
    /// How wide a tooth of a cut mark is, points (upstream `TOOTH_RANGE`).
    public var toothRange: Double
    /// The font family of text and speech bubbles; empty is the system font (upstream `FONT_FAMILY`).
    public var fontFamily: String
    public var horizontalAlignment: HorizontalTextAlignment
    public var verticalAlignment: VerticalTextAlignment
    /// How bright the area outside an area highlight is, 0–2 (upstream `BRIGHTNESS`, 0.9).
    public var brightness: Double

    public init(lineColor: RGBAColor = .red, fillColor: RGBAColor = .clear, lineWidth: Double = 2, shadow: Bool = true,
                fontSize: Double = 11, bold: Bool = false, italic: Bool = false, arrowHeads: ArrowHeads = .end,
                highlightMode: HighlightMode = .text, obfuscateMode: ObfuscateMode = .pixelate,
                pixelSize: Double = 5, blurRadius: Double = 6, magnification: Double = 2,
                cutMarkStyle: CutMarkStyle = .torn, toothHeight: Double = 12, toothRange: Double = 20,
                fontFamily: String = "", horizontalAlignment: HorizontalTextAlignment = .center,
                verticalAlignment: VerticalTextAlignment = .center, brightness: Double = 0.9) {
        self.lineColor = lineColor
        self.fillColor = fillColor
        self.lineWidth = lineWidth
        self.shadow = shadow
        self.fontSize = fontSize
        self.bold = bold
        self.italic = italic
        self.arrowHeads = arrowHeads
        self.highlightMode = highlightMode
        self.obfuscateMode = obfuscateMode
        self.pixelSize = pixelSize
        self.blurRadius = blurRadius
        self.magnification = magnification
        self.cutMarkStyle = cutMarkStyle
        self.toothHeight = toothHeight
        self.toothRange = toothRange
        self.fontFamily = fontFamily
        self.horizontalAlignment = horizontalAlignment
        self.verticalAlignment = verticalAlignment
        self.brightness = brightness
    }

    /// Every property falls back to its default, so the styles remembered by an older version (without the newer
    /// properties) still load.
    public init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        let d = AnnotationStyle()
        func value<T: Decodable>(_ key: CodingKeys, _ fallback: T) -> T {
            (try? c.decodeIfPresent(T.self, forKey: key)) ?? fallback
        }
        // Element files and pasted elements can come from anywhere: sizes outside what the editor offers (or not
        // finite) would make the renderer trap or loop for ages.
        func limited(_ number: Double, _ range: ClosedRange<Double>, _ fallback: Double) -> Double {
            number.isFinite ? min(max(number, range.lowerBound), range.upperBound) : fallback
        }
        lineColor = value(.lineColor, d.lineColor)
        fillColor = value(.fillColor, d.fillColor)
        lineWidth = limited(value(.lineWidth, d.lineWidth), 0...100, d.lineWidth)
        shadow = value(.shadow, d.shadow)
        fontSize = limited(value(.fontSize, d.fontSize), 1...500, d.fontSize)
        bold = value(.bold, d.bold)
        italic = value(.italic, d.italic)
        arrowHeads = value(.arrowHeads, d.arrowHeads)
        highlightMode = value(.highlightMode, d.highlightMode)
        obfuscateMode = value(.obfuscateMode, d.obfuscateMode)
        pixelSize = limited(value(.pixelSize, d.pixelSize), 1...100, d.pixelSize)
        blurRadius = limited(value(.blurRadius, d.blurRadius), 0...100, d.blurRadius)
        magnification = limited(value(.magnification, d.magnification), 1...8, d.magnification)
        cutMarkStyle = value(.cutMarkStyle, d.cutMarkStyle)
        toothHeight = limited(value(.toothHeight, d.toothHeight), 1...100, d.toothHeight)
        toothRange = limited(value(.toothRange, d.toothRange), 2...500, d.toothRange)
        fontFamily = value(.fontFamily, d.fontFamily)
        horizontalAlignment = value(.horizontalAlignment, d.horizontalAlignment)
        verticalAlignment = value(.verticalAlignment, d.verticalAlignment)
        brightness = limited(value(.brightness, d.brightness), 0...2, d.brightness)
    }

    /// The defaults of upstream's `InitializeFields` per container. Upstream's font sizes are pixels (its text fonts
    /// are `GraphicsUnit.Pixel`, `TextContainer.CreateFont`), and a pixel of Windows at 100 % is a point here, so the
    /// numbers stay: text 11, speech bubbles 20 (the `.greenshot` import keeps a file's sizes the same way).
    public static func defaults(for kind: AnnotationKind) -> AnnotationStyle {
        switch kind {
        case .rectangle, .ellipse, .line:
            return AnnotationStyle()
        case .arrow:
            return AnnotationStyle(arrowHeads: .end)
        case .freehand:
            return AnnotationStyle(lineWidth: 3, shadow: false)
        case .text:
            // Upstream TextContainer: red, 11 px.
            return AnnotationStyle(lineColor: .red, fillColor: .clear, shadow: true, fontSize: 11)
        case .highlight:
            // The area highlight blurs with radius 3 and darkens by 10 % (upstream `BlurFilter`, `BrightnessFilter`).
            return AnnotationStyle(fillColor: .yellow, shadow: false, highlightMode: .text, blurRadius: 3, brightness: 0.9)
        case .obfuscate:
            return AnnotationStyle(shadow: false, obfuscateMode: .pixelate)
        case .counter:
            // Upstream StepLabelContainer has no font size: its number is sized from the circle, which starts 30 × 30
            // (`DefaultSize`). Here the font size is the radius a new counter gets (CanvasView), so 15 makes that circle.
            return AnnotationStyle(lineColor: .white, fillColor: .darkRed, lineWidth: 0, shadow: false, fontSize: 15, bold: true)
        case .speechBubble:
            // Upstream SpeechbubbleContainer: blue outline and text on white, 20 px bold.
            return AnnotationStyle(lineColor: .blue, fillColor: .white, lineWidth: 2, shadow: false, fontSize: 20, bold: true)
        case .emoji:
            return AnnotationStyle(shadow: false)
        case .image, .svg, .cursor:
            // Upstream ImageContainer: only a shadow field, off.
            return AnnotationStyle(lineWidth: 0, shadow: false)
        case .barcode:
            // Upstream BarcodeContainer is an ImageContainer: only a shadow field, off.
            return AnnotationStyle(lineWidth: 0, shadow: false)
        case .cutMark, .tornEdge:
            // Upstream CutMarkContainer.InitializeFields.
            return AnnotationStyle(lineColor: .dimGray, fillColor: .clear, lineWidth: 0, shadow: true,
                                   cutMarkStyle: .torn, toothHeight: 12, toothRange: 20)
        }
    }
}

/// One element on the editor surface. Positions are in pixels of the image, origin at its top left.
public struct Annotation: Identifiable, Codable, Equatable, Sendable {
    public var id: UUID
    public var kind: AnnotationKind
    /// The first corner (box shapes) or the start point (lines, arrows).
    public var start: CGPoint
    /// The opposite corner or the end point.
    public var end: CGPoint
    /// The path of a freehand drawing.
    public var points: [CGPoint]
    /// The text of text and speech bubbles; the character of an emoji.
    public var text: String
    /// Where the tail of a speech bubble points (upstream `TargetAdorner`). See `tailTip` for when it is nil.
    public var tail: CGPoint?
    /// The picture of an image or pointer element as PNG; the SVG text of an SVG element.
    public var imageData: Data?
    /// The random parts of a cut mark's edges; nil takes them from the id.
    public var seed: UInt64?
    /// A cut mark across a vertical cut: it spans the whole height of the image and moves left and right. Nil or
    /// false is a mark across a horizontal cut, spanning the whole width (upstream `CutMarkContainer.IsHorizontal`).
    public var verticalCut: Bool?
    /// The shadow of a cut mark or torn edges, and which sides torn edges tear with the room outside them for the shadow
    /// (upstream `CutMarkContainer` / `TornEdgeContainer` private fields). Nil: the torn edge effect's defaults, all sides.
    public var cutEdges: CutEdgeLayout?
    /// What a barcode element shows (upstream `BarcodeContainer.Model`, the `ZxingModel` in its `Tag`); nil for other kinds.
    public var barcode: BarcodeSpec?
    /// Clockwise quarter turns of the content of a picture, SVG, emoji or barcode element, in degrees (0, 90, 180, 270;
    /// nil is 0). The image's Rotate turns it along (upstream `VectorGraphicsContainer.RotationAngle`,
    /// `ImageContainer.Transform`). `bounds` is the turned box; `contentBounds` the box the content is drawn into.
    public var rotation: Int?
    /// A counter's place in the order the counters came onto its document (upstream `Surface._stepLabels`, saved as
    /// `StepLabelContainer.Number`): counters are numbered in this order, not in drawing order (`counterNumbers`). The
    /// document gives it (`EditorDocument.add`, `addOpened`). Nil for other kinds, for counters not on a document yet and
    /// for those of files of earlier versions.
    public var counterOrder: Int?
    public var style: AnnotationStyle

    public init(id: UUID = UUID(), kind: AnnotationKind, start: CGPoint, end: CGPoint, points: [CGPoint] = [],
                text: String = "", tail: CGPoint? = nil, imageData: Data? = nil, style: AnnotationStyle? = nil) {
        self.id = id
        self.kind = kind
        self.start = start
        self.end = end
        self.points = points
        self.text = text
        self.tail = tail
        self.imageData = imageData
        self.style = style ?? .defaults(for: kind)
    }

    /// Whether the element is a cut mark across a vertical cut (a band down the whole image).
    public var isVerticalCutMark: Bool { kind == .cutMark && verticalCut == true }

    /// The box of the element (for freehand the box around its path).
    public var bounds: CGRect {
        if kind == .freehand, let first = points.first {
            return points.dropFirst().reduce(CGRect(origin: first, size: .zero)) { $0.union(CGRect(origin: $1, size: .zero)) }
        }
        return Geometry.rect(from: start, to: end)
    }

    /// The turn of the content as clockwise quarter turns, 0–3: `rotation` to the nearest quarter (a file can hold any
    /// number of degrees). Always 0 for kinds whose content doesn't turn (`turnsContentWithImage`), whatever a file says.
    public var contentQuarterTurns: Int {
        guard kind.turnsContentWithImage else { return 0 }
        return Annotation.normalizedRotation(rotation ?? 0).map { $0 / 90 } ?? 0
    }

    /// Whether the content lies on its side (a quarter or three quarters turned): its box has width and height swapped.
    public var isQuarterTurned: Bool { contentQuarterTurns % 2 == 1 }

    /// The box the content is drawn into before it is turned: `bounds`, with width and height swapped when the content
    /// lies on its side, around the same centre.
    public var contentBounds: CGRect {
        let box = bounds
        guard isQuarterTurned else { return box }
        return CGRect(x: box.midX - box.height / 2, y: box.midY - box.width / 2, width: box.height, height: box.width)
    }

    /// `degrees` as a clockwise quarter turn: 90, 180 or 270, rounded to the nearest quarter; nil for no turn. Negative
    /// angles count backwards (upstream keeps -90 after a counter-clockwise Rotate: C#'s `%` keeps the sign).
    public static func normalizedRotation(_ degrees: Int) -> Int? {
        let positive = (degrees % 360 + 360) % 360
        let quarter = (positive + 45) / 90 % 4 * 90
        return quarter == 0 ? nil : quarter
    }

    /// Decodes like the synthesized decoding, except `rotation`: any number of degrees (also one with a fraction, as
    /// another program may write) becomes the nearest quarter turn, and a value that isn't a number is ignored, so the
    /// element still loads instead of being left out as one of a newer version. The same for `counterOrder`, which only
    /// counters keep.
    public init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        id = try c.decode(UUID.self, forKey: .id)
        kind = try c.decode(AnnotationKind.self, forKey: .kind)
        start = try c.decode(CGPoint.self, forKey: .start)
        end = try c.decode(CGPoint.self, forKey: .end)
        points = try c.decode([CGPoint].self, forKey: .points)
        text = try c.decode(String.self, forKey: .text)
        tail = try c.decodeIfPresent(CGPoint.self, forKey: .tail)
        imageData = try c.decodeIfPresent(Data.self, forKey: .imageData)
        seed = try c.decodeIfPresent(UInt64.self, forKey: .seed)
        verticalCut = try c.decodeIfPresent(Bool.self, forKey: .verticalCut)
        cutEdges = try c.decodeIfPresent(CutEdgeLayout.self, forKey: .cutEdges)
        barcode = try c.decodeIfPresent(BarcodeSpec.self, forKey: .barcode)
        let degrees = (try? c.decodeIfPresent(Double.self, forKey: .rotation)) ?? nil
        rotation = degrees.flatMap(Annotation.quarterTurn(degrees:))
        let order = (try? c.decodeIfPresent(Int.self, forKey: .counterOrder)) ?? nil
        counterOrder = kind == .counter ? order : nil
        style = try c.decode(AnnotationStyle.self, forKey: .style)
    }

    /// The numbers the counters among `annotations` (in drawing order) show, by id, from `start`: in the order they came
    /// onto the document (`counterOrder`), whatever their drawing order (upstream `Surface.CountStepLabels`, "every
    /// single StepLabelContainer shows the number of the order it was created"). Counters without an order come after
    /// those with one, in drawing order: elements of a recipe are added on top of those already on a document.
    public static func counterNumbers(_ annotations: [Annotation], from start: Int) -> [UUID: Int] {
        var numbers: [UUID: Int] = [:]
        for (place, index) in counterSequence(annotations).enumerated() {
            numbers[annotations[index].id] = start + place
        }
        return numbers
    }

    /// The indices of the counters among `annotations` in the order they count (see `counterNumbers`).
    static func counterSequence(_ annotations: [Annotation]) -> [Int] {
        annotations.indices.filter { annotations[$0].kind == .counter }.sorted { a, b in
            let left = annotations[a].counterOrder ?? .max
            let right = annotations[b].counterOrder ?? .max
            return left == right ? a < b : left < right
        }
    }

    /// `degrees` (any number) to the nearest clockwise quarter turn, like `normalizedRotation`; nil for no turn or a
    /// value that isn't finite.
    static func quarterTurn(degrees: Double) -> Int? {
        guard degrees.isFinite else { return nil }
        let turn = degrees.truncatingRemainder(dividingBy: 360)
        let quarters = ((turn < 0 ? turn + 360 : turn) / 90).rounded()
        return normalizedRotation(Int(quarters) * 90)
    }

    /// A copy that is a new element: pasted, duplicated or loaded elements must never share the id of another one.
    public func withNewID() -> Annotation {
        var copy = self
        copy.id = UUID()
        return copy
    }

    /// The element with its geometry multiplied by `factor` (style sizes are points and stay), for pasting into an
    /// image with other pixels per point.
    public func scaled(by factor: CGFloat) -> Annotation {
        guard factor != 1 else { return self }
        func scale(_ p: CGPoint) -> CGPoint { CGPoint(x: p.x * factor, y: p.y * factor) }
        var copy = self
        copy.start = scale(start)
        copy.end = scale(end)
        copy.points = points.map(scale)
        copy.tail = tail.map(scale)
        if kind == .tornEdge { copy.cutEdges = cutEdges.map { $0.scaled(x: factor, y: factor) } }
        return copy
    }

    public mutating func move(by delta: CGVector) {
        // Torn edges always cover the whole image (upstream `TornEdgeContainer.MoveBy` → `SpanImage`).
        guard kind != .tornEdge else { return }
        start = CGPoint(x: start.x + delta.dx, y: start.y + delta.dy)
        end = CGPoint(x: end.x + delta.dx, y: end.y + delta.dy)
        points = points.map { CGPoint(x: $0.x + delta.dx, y: $0.y + delta.dy) }
        tail = tail.map { CGPoint(x: $0.x + delta.dx, y: $0.y + delta.dy) }
    }

    /// The tip of a speech bubble's tail. Without a set `tail` it is below the bottom left corner, where upstream's
    /// `SpeechbubbleContainer.Draw` puts the tail of a bubble that was not drawn with the mouse.
    public var tailTip: CGPoint {
        tail ?? CGPoint(x: bounds.minX - 20, y: bounds.maxY + 25)
    }

    /// The tail of a speech bubble: a triangle from the middle of the box to `tailTip`, with a base as wide as a tenth
    /// of the box's width plus height (upstream `SpeechbubbleContainer.CreateTail`). Empty when the tip is the middle.
    public var speechBubbleTail: CGPath {
        let box = bounds
        let center = CGPoint(x: box.midX, y: box.midY)
        let tip = tailTip
        let length = Geometry.distance(center, tip)
        let path = CGMutablePath()
        guard length > 0 else { return path }
        let halfWidth = min((box.width + box.height) / 20, box.width / 2, box.height / 2)
        // Half the base, at a right angle to the direction of the tip.
        let side = CGVector(dx: -(tip.y - center.y) / length * halfWidth, dy: (tip.x - center.x) / length * halfWidth)
        path.move(to: CGPoint(x: center.x + side.dx, y: center.y + side.dy))
        path.addLine(to: tip)
        path.addLine(to: CGPoint(x: center.x - side.dx, y: center.y - side.dy))
        path.closeSubpath()
        return path
    }

    /// Whether a click at `point` (image pixels) hits the element. `scale` is pixels per point, `tolerance` in pixels.
    /// Like upstream's `ClickableAt`: unfilled rectangles and ellipses are only hit near their outline.
    public func hitTest(_ point: CGPoint, scale: CGFloat, tolerance: CGFloat) -> Bool {
        let reach = max(tolerance, CGFloat(style.lineWidth) * scale / 2 + tolerance / 2)
        switch kind {
        case .line, .arrow:
            return Geometry.distance(from: point, toSegment: start, end) <= reach
        case .freehand:
            guard points.count > 1 else { return points.first.map { Geometry.distance($0, point) <= reach } ?? false }
            return zip(points, points.dropFirst()).contains { Geometry.distance(from: point, toSegment: $0, $1) <= reach }
        case .rectangle:
            let rect = bounds
            if style.fillColor.isVisible { return rect.insetBy(dx: -reach, dy: -reach).contains(point) }
            return rect.insetBy(dx: -reach, dy: -reach).contains(point) && !rect.insetBy(dx: reach, dy: reach).contains(point)
        case .ellipse:
            let rect = bounds
            guard rect.width > 0, rect.height > 0 else { return Geometry.distance(point, rect.origin) <= reach }
            func normalized(_ r: CGRect) -> CGFloat {
                guard r.width > 0, r.height > 0 else { return .infinity }
                let dx = (point.x - r.midX) / (r.width / 2)
                let dy = (point.y - r.midY) / (r.height / 2)
                return dx * dx + dy * dy
            }
            let outer = normalized(rect.insetBy(dx: -reach, dy: -reach))
            if style.fillColor.isVisible { return outer <= 1 }
            return outer <= 1 && normalized(rect.insetBy(dx: reach, dy: reach)) >= 1
        case .speechBubble:
            // Upstream `SpeechbubbleContainer.Contains`: the box, or the tail with its outline.
            if bounds.insetBy(dx: -tolerance / 2, dy: -tolerance / 2).contains(point) { return true }
            let tail = speechBubbleTail
            return tail.contains(point)
                || tail.copy(strokingWithWidth: reach * 2, lineCap: .round, lineJoin: .round, miterLimit: 10).contains(point)
        case .cutMark:
            // The band spans the whole image (upstream `ClickableAt` of the band).
            let band = bounds
            if isVerticalCutMark {
                return point.y >= 0 && point.x >= band.minX - tolerance / 2 && point.x <= band.maxX + tolerance / 2
            }
            return point.x >= 0 && point.y >= band.minY - tolerance / 2 && point.y <= band.maxY + tolerance / 2
        case .tornEdge:
            return hitsTornEdge(point, scale: scale)
        case .text, .highlight, .obfuscate, .counter, .emoji, .image, .svg, .cursor, .barcode:
            return bounds.insetBy(dx: -tolerance / 2, dy: -tolerance / 2).contains(point)
        }
    }
}

/// The handles shown around the selected element.
public enum Handle: CaseIterable, Sendable {
    case topLeft, top, topRight, right, bottomRight, bottom, bottomLeft, left
    /// The two ends of a line or arrow.
    case start, end
    /// The tip of a speech bubble's tail.
    case tail

    public static let boxHandles: [Handle] = [.topLeft, .top, .topRight, .right, .bottomRight, .bottom, .bottomLeft, .left]
    public static let cornerHandles: [Handle] = [.topLeft, .topRight, .bottomRight, .bottomLeft]

    public static func handles(for annotation: Annotation) -> [Handle] {
        switch annotation.kind {
        case .line, .arrow: return [.start, .end]
        case .freehand: return []
        case .speechBubble: return boxHandles + [.tail]
        // An emoji and a counter keep their aspect ratio (upstream `EmojiContainer` and `StepLabelContainer` scale with
        // `ScaleOptions.Rational`).
        case .emoji, .counter: return cornerHandles
        // A cut mark is only sized across the cut (upstream's top and bottom center grippers, left and right for a
        // vertical cut).
        case .cutMark: return annotation.isVerticalCutMark ? [.left, .right] : [.top, .bottom]
        // Torn edges always cover the whole image (upstream: no adorners).
        case .tornEdge: return []
        // An SVG keeps its aspect ratio (upstream `VectorGraphicsContainer`'s corner grippers, `ScaleOptions.Rational`).
        case .svg: return cornerHandles
        // A matrix code keeps its aspect ratio (upstream `BarcodeContainer.GetScaleOptions`: Rational for 2D codes).
        case .barcode: return annotation.barcodeKeepsAspect ? cornerHandles : boxHandles
        default: return boxHandles
        }
    }

    public func position(in annotation: Annotation) -> CGPoint {
        let r = annotation.bounds
        switch self {
        case .topLeft: return CGPoint(x: r.minX, y: r.minY)
        case .top: return CGPoint(x: r.midX, y: r.minY)
        case .topRight: return CGPoint(x: r.maxX, y: r.minY)
        case .right: return CGPoint(x: r.maxX, y: r.midY)
        case .bottomRight: return CGPoint(x: r.maxX, y: r.maxY)
        case .bottom: return CGPoint(x: r.midX, y: r.maxY)
        case .bottomLeft: return CGPoint(x: r.minX, y: r.maxY)
        case .left: return CGPoint(x: r.minX, y: r.midY)
        case .start: return annotation.start
        case .end: return annotation.end
        case .tail: return annotation.tailTip
        }
    }

    /// `original` with this handle dragged to `point` (upstream `ScaleHelper.Scale`).
    /// - Parameters:
    ///   - keepAspect: a corner keeps the box's aspect ratio (Shift, upstream `ScaleOptions.Rational`). Emoji and
    ///     counters always keep theirs.
    ///   - centered: the box grows or shrinks around its centre: the opposite side moves the other way (Option, upstream
    ///     Ctrl = `ScaleOptions.Centered`).
    public func drag(_ original: Annotation, to point: CGPoint, keepAspect: Bool = false, centered: Bool = false) -> Annotation {
        var result = original
        switch self {
        case .start:
            result.start = point
            return result
        case .end:
            result.end = point
            return result
        case .tail:
            // Only the tip moves; the box stays (upstream's target gripper).
            result.tail = point
            return result
        default:
            break
        }
        let aspect = keepAspect || original.kind == .emoji || original.kind == .counter || original.barcodeKeepsAspect
        let rect = drag(original.bounds, to: point, keepAspect: aspect || original.kind == .svg,
                        square: original.kind == .emoji || original.kind == .counter, centered: centered)
        result.start = rect.origin
        result.end = CGPoint(x: rect.maxX, y: rect.maxY)
        return result
    }

    /// The box `r` with this handle dragged to `point`. `square` keeps a square even when `r` is not one.
    public func drag(_ r: CGRect, to point: CGPoint, keepAspect: Bool = false, square: Bool = false, centered: Bool = false) -> CGRect {
        let center = CGPoint(x: r.midX, y: r.midY)
        let aspect: CGFloat? = square ? 1 : (keepAspect && r.width > 0 && r.height > 0 ? r.width / r.height : nil)
        if let aspect, let opposite = oppositeCorner(in: r) {
            let anchor = centered ? center : opposite
            let corner = Self.aspectEnd(from: anchor, to: point, aspect: aspect)
            let other = centered ? CGPoint(x: 2 * center.x - corner.x, y: 2 * center.y - corner.y) : anchor
            return Geometry.rect(from: other, to: corner)
        }
        var minX = r.minX, minY = r.minY, maxX = r.maxX, maxY = r.maxY
        switch self {
        case .topLeft: minX = point.x; minY = point.y
        case .top: minY = point.y
        case .topRight: maxX = point.x; minY = point.y
        case .right: maxX = point.x
        case .bottomRight: maxX = point.x; maxY = point.y
        case .bottom: maxY = point.y
        case .bottomLeft: minX = point.x; maxY = point.y
        case .left: minX = point.x
        case .start, .end, .tail: break
        }
        if centered {
            // The side opposite the dragged one mirrors it around the centre.
            switch self {
            case .topLeft, .left, .bottomLeft: maxX = 2 * center.x - minX
            case .topRight, .right, .bottomRight: minX = 2 * center.x - maxX
            default: break
            }
            switch self {
            case .topLeft, .top, .topRight: maxY = 2 * center.y - minY
            case .bottomLeft, .bottom, .bottomRight: minY = 2 * center.y - maxY
            default: break
            }
        }
        return Geometry.rect(from: CGPoint(x: minX, y: minY), to: CGPoint(x: maxX, y: maxY))
    }

    /// The corner of a box from `anchor` towards `point` with `aspect` (width / height), as big as covers `point`.
    static func aspectEnd(from anchor: CGPoint, to point: CGPoint, aspect: CGFloat) -> CGPoint {
        let dx = point.x - anchor.x
        let dy = point.y - anchor.y
        let width = max(abs(dx), abs(dy) * aspect)
        let height = width / aspect
        return CGPoint(x: anchor.x + (dx < 0 ? -width : width), y: anchor.y + (dy < 0 ? -height : height))
    }

    /// The corner that stays put while this corner handle is dragged.
    private func oppositeCorner(in r: CGRect) -> CGPoint? {
        switch self {
        case .topLeft: return CGPoint(x: r.maxX, y: r.maxY)
        case .topRight: return CGPoint(x: r.minX, y: r.maxY)
        case .bottomRight: return CGPoint(x: r.minX, y: r.minY)
        case .bottomLeft: return CGPoint(x: r.maxX, y: r.minY)
        default: return nil
        }
    }
}

extension CropMode {
    /// The handles of the crop area (upstream `CropContainer`: all eight, or only the two edges across a cut-out).
    public var handles: [Handle] {
        switch self {
        case .vertical: return [.left, .right]
        case .horizontal: return [.top, .bottom]
        case .crop, .auto: return Handle.boxHandles
        }
    }

    /// The handle of the crop area `rect` at `point`, within `reach` pixels.
    public func handle(at point: CGPoint, of rect: CGRect, reach: CGFloat) -> Handle? {
        let box = Annotation(kind: .rectangle, start: rect.origin, end: CGPoint(x: rect.maxX, y: rect.maxY))
        return handles.first { Geometry.distance($0.position(in: box), point) <= reach }
    }
}

extension Annotation {
    /// An image element showing `picture` (upstream `ImageContainer`), its top left at `origin`, at its point size
    /// (`pictureScale` pixels per point) on an image with `documentScale` pixels per point, made smaller to fit in
    /// `fitting` (image pixels) when it is bigger. Nil when the picture can't be stored as PNG.
    public static func picture(_ picture: CGImage, pictureScale: CGFloat, at origin: CGPoint, documentScale: CGFloat,
                               fitting limit: CGSize? = nil) -> Annotation? {
        guard let data = try? ImageExporter.data(for: picture, format: .png, scale: pictureScale) else { return nil }
        let factor = documentScale / max(pictureScale, 1)
        var size = CGSize(width: CGFloat(picture.width) * factor, height: CGFloat(picture.height) * factor)
        if let limit, limit.width > 0, limit.height > 0, size.width > limit.width || size.height > limit.height {
            let shrink = min(limit.width / size.width, limit.height / size.height)
            size = CGSize(width: size.width * shrink, height: size.height * shrink)
        }
        return Annotation(kind: .image, start: origin, end: CGPoint(x: origin.x + size.width, y: origin.y + size.height),
                          imageData: data)
    }
}
