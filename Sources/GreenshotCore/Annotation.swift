// Greenshot for Mac (Community) - an unofficial macOS port of Greenshot
// Copyright (C) 2026 Greenshot for Mac (Community) contributors
// Based on Greenshot, Copyright (C) 2007-2026 Thomas Braun, Jens Klingen, Robin Krom
// SPDX-License-Identifier: GPL-3.0-or-later

import CoreGraphics
import Foundation

/// The drawable elements of the editor. Upstream calls them containers (`Greenshot.Editor/Drawing/*Container.cs`).
public enum AnnotationKind: String, Codable, CaseIterable, Sendable {
    case rectangle, ellipse, line, arrow, freehand, text, highlight, obfuscate, counter

    /// Elements that are a box: they get eight resize handles. Lines and arrows get two end points, freehand none.
    public var isBoxShaped: Bool {
        switch self {
        case .line, .arrow, .freehand: return false
        default: return true
        }
    }
}

/// Upstream `PreparedFilter` values of the highlight container.
public enum HighlightMode: String, Codable, CaseIterable, Sendable {
    case text, area, grayscale, magnify
}

/// Upstream `PreparedFilter` values of the obfuscate container.
public enum ObfuscateMode: String, Codable, CaseIterable, Sendable {
    case pixelate, blur
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

    public init(lineColor: RGBAColor = .red, fillColor: RGBAColor = .clear, lineWidth: Double = 2, shadow: Bool = true,
                fontSize: Double = 15, bold: Bool = false, italic: Bool = false, arrowHeads: ArrowHeads = .end,
                highlightMode: HighlightMode = .text, obfuscateMode: ObfuscateMode = .pixelate,
                pixelSize: Double = 5, blurRadius: Double = 6, magnification: Double = 2) {
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
    }

    /// The defaults of upstream's `InitializeFields` per container. Font sizes are converted from Windows points
    /// at 96 DPI (11 pt there is about 15 pt on the Mac).
    public static func defaults(for kind: AnnotationKind) -> AnnotationStyle {
        switch kind {
        case .rectangle, .ellipse, .line:
            return AnnotationStyle()
        case .arrow:
            return AnnotationStyle(arrowHeads: .end)
        case .freehand:
            return AnnotationStyle(lineWidth: 3, shadow: false)
        case .text:
            return AnnotationStyle(lineColor: .red, fillColor: .clear, shadow: true, fontSize: 15)
        case .highlight:
            return AnnotationStyle(fillColor: .yellow, shadow: false, highlightMode: .text)
        case .obfuscate:
            return AnnotationStyle(shadow: false, obfuscateMode: .pixelate)
        case .counter:
            return AnnotationStyle(lineColor: .white, fillColor: .darkRed, lineWidth: 0, shadow: false, fontSize: 15, bold: true)
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
    public var text: String
    public var style: AnnotationStyle

    public init(id: UUID = UUID(), kind: AnnotationKind, start: CGPoint, end: CGPoint, points: [CGPoint] = [],
                text: String = "", style: AnnotationStyle? = nil) {
        self.id = id
        self.kind = kind
        self.start = start
        self.end = end
        self.points = points
        self.text = text
        self.style = style ?? .defaults(for: kind)
    }

    /// The box of the element (for freehand the box around its path).
    public var bounds: CGRect {
        if kind == .freehand, let first = points.first {
            return points.dropFirst().reduce(CGRect(origin: first, size: .zero)) { $0.union(CGRect(origin: $1, size: .zero)) }
        }
        return Geometry.rect(from: start, to: end)
    }

    public mutating func move(by delta: CGVector) {
        start = CGPoint(x: start.x + delta.dx, y: start.y + delta.dy)
        end = CGPoint(x: end.x + delta.dx, y: end.y + delta.dy)
        points = points.map { CGPoint(x: $0.x + delta.dx, y: $0.y + delta.dy) }
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
        case .text, .highlight, .obfuscate, .counter:
            return bounds.insetBy(dx: -tolerance / 2, dy: -tolerance / 2).contains(point)
        }
    }
}

/// The handles shown around the selected element.
public enum Handle: CaseIterable, Sendable {
    case topLeft, top, topRight, right, bottomRight, bottom, bottomLeft, left
    /// The two ends of a line or arrow.
    case start, end

    public static let boxHandles: [Handle] = [.topLeft, .top, .topRight, .right, .bottomRight, .bottom, .bottomLeft, .left]

    public static func handles(for annotation: Annotation) -> [Handle] {
        switch annotation.kind {
        case .line, .arrow: return [.start, .end]
        case .freehand: return []
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
        }
    }

    /// `original` with this handle dragged to `point`.
    public func drag(_ original: Annotation, to point: CGPoint) -> Annotation {
        var result = original
        switch self {
        case .start:
            result.start = point
            return result
        case .end:
            result.end = point
            return result
        default:
            break
        }
        let r = original.bounds
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
        case .start, .end: break
        }
        let rect = Geometry.rect(from: CGPoint(x: minX, y: minY), to: CGPoint(x: maxX, y: maxY))
        result.start = rect.origin
        result.end = CGPoint(x: rect.maxX, y: rect.maxY)
        return result
    }
}
