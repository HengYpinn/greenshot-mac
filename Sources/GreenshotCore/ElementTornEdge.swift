// Greenshot for Mac (Community) - an unofficial macOS port of Greenshot
// Copyright (C) 2026 Greenshot for Mac (Community) contributors
// Based on Greenshot, Copyright (C) 2007-2026 Thomas Braun, Jens Klingen, Robin Krom
// SPDX-License-Identifier: GPL-3.0-or-later

import CoreGraphics
import Foundation

/// Torn edges as an element, ported from upstream `Greenshot.Editor/Drawing/TornEdgeContainer.cs` (commit 9f6726c0):
/// the edges of the whole capture torn along the chosen sides, which can be changed or removed later. Outside of the
/// torn edges is transparent or the fill color, with the shadow the rest of the image casts. The element always covers
/// the whole image; when it is added the canvas grows by the room its shadow needs (`CutEdgeLayout`'s margins), and the
/// torn edges are inside that room. The edges come from the element's seed, so they only change on New Random Edges.
public enum TornEdge {
    public struct Shape {
        /// The outline of the part that stays, clockwise from the top left (image pixels, origin top left).
        public var outline: [CGPoint]
        /// The points of every torn side, for the line along them.
        public var tornSides: [[CGPoint]]
        /// The part that stays.
        public var kept: CGPath
        /// The torn off parts: the image with the part that stays as a hole (fill it with the even-odd rule).
        public var tornOff: CGPath
    }

    /// The room on every side for the shadow of `settings`, points (upstream `TornEdgeContainer.GetShadowMargin`).
    public static func shadowMargin(_ settings: TornEdgeSettings) -> Int {
        guard settings.shadow else { return 0 }
        return max(1, settings.shadowSize) + max(abs(settings.shadowOffsetX), abs(settings.shadowOffsetY))
    }

    /// The shape of torn edges on an image of `imageSize`; nil when there is nothing to draw (style None, no torn side,
    /// or no room inside the margins). `scale` is pixels per point.
    public static func shape(of a: Annotation, imageSize: CGSize, scale: CGFloat) -> Shape? {
        shape(imageSize: imageSize, layout: a.cutEdges ?? CutEdgeLayout(), style: a.style.cutMarkStyle,
              toothHeight: CGFloat(a.style.toothHeight) * scale, toothRange: CGFloat(a.style.toothRange) * scale,
              seed: CutMark.seed(of: a))
    }

    /// Upstream `CreateOutline` and `HasEdges`. Sizes are image pixels.
    static func shape(imageSize: CGSize, layout: CutEdgeLayout, style: CutMarkStyle, toothHeight: CGFloat,
                      toothRange: CGFloat, seed: UInt64) -> Shape? {
        let marginLeft = CGFloat(layout.marginLeft)
        let marginTop = CGFloat(layout.marginTop)
        let width = (imageSize.width - marginLeft - CGFloat(layout.marginRight)).rounded(.down)
        let height = (imageSize.height - marginTop - CGFloat(layout.marginBottom)).rounded(.down)
        let edges = [layout.top, layout.right, layout.bottom, layout.left]
        guard style != .none, width > 2, height > 2, edges.contains(true) else { return nil }
        let teeth = max(1, min(toothHeight.rounded(), (min(width, height) / 3).rounded(.down)))
        var random = SeededRandom(seed: seed)
        var outline: [CGPoint] = []
        var sides: [[CGPoint]] = []

        // Each side from its start corner to its end corner; `map` turns (along the side, into the image) into image
        // pixels. A torn side leaves its corner to the torn side next to it.
        func addSide(_ torn: Bool, tornBefore: Bool, tornAfter: Bool, length: CGFloat, from start: CGPoint, to end: CGPoint,
                     _ map: (CGFloat, CGFloat) -> CGPoint) {
            guard torn else {
                outline += [start, end]
                return
            }
            let insetStart = tornBefore ? teeth : 0
            let insetEnd = tornAfter ? teeth : 0
            let sideLength = max(1, length - insetStart - insetEnd)
            let side = CutMark.edge(style: style, length: sideLength, toothHeight: teeth, toothRange: toothRange,
                                    random: &random).map { map(insetStart + $0.x, $0.y) }
            outline += side
            sides.append(side)
        }
        let top = layout.top, right = layout.right, bottom = layout.bottom, left = layout.left
        addSide(top, tornBefore: left, tornAfter: right, length: width, from: .zero, to: CGPoint(x: width, y: 0)) {
            CGPoint(x: $0, y: $1)
        }
        addSide(right, tornBefore: top, tornAfter: bottom, length: height, from: CGPoint(x: width, y: 0),
                to: CGPoint(x: width, y: height)) { CGPoint(x: width - $1, y: $0) }
        addSide(bottom, tornBefore: right, tornAfter: left, length: width, from: CGPoint(x: width, y: height),
                to: CGPoint(x: 0, y: height)) { CGPoint(x: width - $0, y: height - $1) }
        addSide(left, tornBefore: bottom, tornAfter: top, length: height, from: CGPoint(x: 0, y: height), to: .zero) {
            CGPoint(x: $1, y: height - $0)
        }
        // The torn edges are inside the room for the shadow.
        func shift(_ p: CGPoint) -> CGPoint { CGPoint(x: p.x + marginLeft, y: p.y + marginTop) }
        outline = outline.map(shift)
        sides = sides.map { $0.map(shift) }

        let kept = CGMutablePath()
        kept.addLines(between: outline)
        kept.closeSubpath()
        let tornOff = CGMutablePath()
        tornOff.addRect(CGRect(origin: .zero, size: imageSize))
        tornOff.addPath(kept)
        return Shape(outline: outline, tornSides: sides, kept: kept, tornOff: tornOff)
    }
}

extension Annotation {
    /// New torn edges for an image of `imageSize` with the torn edge effect's `settings` (upstream
    /// `new TornEdgeContainer(surface, settings, margin)`): `margin` pixels of room for the shadow on every side, the
    /// line of `style` (the last used torn edge style) and the teeth, shadow and background of the settings.
    public static func tornEdges(_ settings: TornEdgeSettings, imageSize: CGSize, margin: Int,
                                 style: AnnotationStyle = .defaults(for: .tornEdge),
                                 seed: UInt64 = .random(in: .min ... .max)) -> Annotation {
        tornEdges(settings, imageSize: imageSize, room: CutEdgeLayout(marginTop: margin, marginRight: margin,
                                                                      marginBottom: margin, marginLeft: margin),
                  edgeStyle: .torn, style: style, seed: seed)
    }

    /// Edges for the whole image (upstream `new TornEdgeContainer(surface, settings, margins, cutMarkStyle)`): the sides
    /// of `settings` in `edgeStyle`, with the room for the shadow of `room`'s margins.
    static func tornEdges(_ settings: TornEdgeSettings, imageSize: CGSize, room: CutEdgeLayout, edgeStyle: CutMarkStyle,
                          style: AnnotationStyle, seed: UInt64) -> Annotation {
        var element = Annotation(kind: .tornEdge, start: .zero, end: CGPoint(x: imageSize.width, y: imageSize.height),
                                 style: style)
        element.style.cutMarkStyle = edgeStyle
        element.cutEdges = CutEdgeLayout(marginTop: room.marginTop, marginRight: room.marginRight,
                                         marginBottom: room.marginBottom, marginLeft: room.marginLeft)
        element.seed = seed
        return element.applyingCutEdgeSettings(settings, scale: 1)
    }

    /// The settings of a cut mark or torn edges as torn edge settings, for the settings dialog (upstream
    /// `TornEdgeContainer.GetSettings` / `CutMarkContainer.GetSettings`).
    public var cutEdgeSettings: TornEdgeSettings {
        let layout = cutEdges ?? CutEdgeLayout()
        let range = Int(style.toothRange.rounded())
        return TornEdgeSettings(toothHeight: Int(style.toothHeight.rounded()), horizontalToothRange: range,
                                verticalToothRange: range, top: layout.top, left: layout.left, right: layout.right,
                                bottom: layout.bottom, shadow: style.shadow, shadowDarkness: layout.shadowDarkness,
                                shadowSize: layout.shadowSize, shadowOffsetX: layout.shadowOffsetX,
                                shadowOffsetY: layout.shadowOffsetY, backgroundColor: style.fillColor)
    }

    /// The element with the settings of the settings dialog (upstream `TornEdgeContainer.ApplySettings`; for a cut mark
    /// `ApplyShadowSettings` and `SetToothSize` with the range across its cut, whose band keeps its gap). The sides only
    /// change on torn edges; the room for the shadow stays. `scale` is pixels per point.
    public func applyingCutEdgeSettings(_ settings: TornEdgeSettings, scale: CGFloat) -> Annotation {
        var result = self
        if kind == .cutMark {
            result = withToothHeight(Double(max(1, settings.toothHeight)), scale: scale)
            result.style.toothRange = Double(max(2, isVerticalCutMark ? settings.verticalToothRange : settings.horizontalToothRange))
        } else {
            result.style.toothHeight = Double(max(1, settings.toothHeight))
            result.style.toothRange = Double(max(2, settings.horizontalToothRange))
        }
        result.style.shadow = settings.shadow
        result.style.fillColor = settings.backgroundColor
        var layout = cutEdges ?? CutEdgeLayout()
        layout.shadowDarkness = min(max(settings.shadowDarkness, 0), 1)
        layout.shadowSize = min(max(settings.shadowSize, 1), 20)
        layout.shadowOffsetX = min(max(settings.shadowOffsetX, -20), 20)
        layout.shadowOffsetY = min(max(settings.shadowOffsetY, -20), 20)
        if kind == .tornEdge {
            layout.top = settings.top
            layout.right = settings.right
            layout.bottom = settings.bottom
            layout.left = settings.left
        }
        result.cutEdges = layout
        return result
    }

    /// Upstream `TornEdgeContainer.ClickableAt`: only the torn sides can be clicked, within the teeth and 4 points.
    /// `scale` is pixels per point.
    func hitsTornEdge(_ point: CGPoint, scale: CGFloat) -> Bool {
        let box = bounds
        guard box.contains(point) else { return false }
        let layout = cutEdges ?? CutEdgeLayout()
        let reach = (CGFloat(max(1, style.toothHeight)) + 4) * scale
        let x = point.x - box.minX
        let y = point.y - box.minY
        if layout.top && y < CGFloat(layout.marginTop) + reach { return true }
        if layout.right && x >= box.width - CGFloat(layout.marginRight) - reach { return true }
        if layout.bottom && y >= box.height - CGFloat(layout.marginBottom) - reach { return true }
        return layout.left && x < CGFloat(layout.marginLeft) + reach
    }
}

extension CutEdgeLayout {
    /// The layout after the image turned by a quarter: the sides and their room turn along.
    public func rotated(clockwise: Bool) -> CutEdgeLayout {
        var turned = self
        if clockwise {
            // The left side becomes the top, the top the right, and so on.
            (turned.top, turned.right, turned.bottom, turned.left) = (left, top, right, bottom)
            (turned.marginTop, turned.marginRight, turned.marginBottom, turned.marginLeft) =
                (marginLeft, marginTop, marginRight, marginBottom)
        } else {
            (turned.top, turned.right, turned.bottom, turned.left) = (right, bottom, left, top)
            (turned.marginTop, turned.marginRight, turned.marginBottom, turned.marginLeft) =
                (marginRight, marginBottom, marginLeft, marginTop)
        }
        return turned
    }

    /// The layout after the image was scaled by `sx`, `sy`: the room for the shadow scales along.
    public func scaled(x sx: CGFloat, y sy: CGFloat) -> CutEdgeLayout {
        var result = self
        result.marginLeft = Int((CGFloat(marginLeft) * sx).rounded())
        result.marginRight = Int((CGFloat(marginRight) * sx).rounded())
        result.marginTop = Int((CGFloat(marginTop) * sy).rounded())
        result.marginBottom = Int((CGFloat(marginBottom) * sy).rounded())
        return result
    }

    /// The layout after a crop that cut off the sides marked in `cut` (top, right, bottom, left): those sides lose their
    /// torn edge, and their room becomes `room`, the room the crop made there for the shadow of new edges (0 without
    /// them; upstream `Surface.ApplyCrop`). Nil when no torn side is left.
    func cropped(cutTop: Bool, cutRight: Bool, cutBottom: Bool, cutLeft: Bool, room: Int = 0) -> CutEdgeLayout? {
        var result = self
        if cutTop { result.top = false; result.marginTop = room }
        if cutRight { result.right = false; result.marginRight = room }
        if cutBottom { result.bottom = false; result.marginBottom = room }
        if cutLeft { result.left = false; result.marginLeft = room }
        return result.top || result.right || result.bottom || result.left ? result : nil
    }
}

extension EditorDocument {
    /// Upstream `Surface.AddTornEdges`: tears the edges of the capture as an element that can be changed later. The
    /// canvas grows by the room the shadow needs on every side (in the background color; the elements move along) and
    /// the element covers the new image. There is only one: when there are torn edges already, nothing changes and
    /// their id comes back. Nil when the canvas could not grow.
    @discardableResult
    public func addTornEdges(_ settings: TornEdgeSettings, style: AnnotationStyle = .defaults(for: .tornEdge),
                             seed: UInt64 = .random(in: .min ... .max)) -> UUID? {
        if let existing = annotations.first(where: { $0.kind == .tornEdge }) { return existing.id }
        let margin = Int((CGFloat(TornEdge.shadowMargin(settings)) * scale).rounded())
        if margin > 0 {
            let background = settings.backgroundColor.isVisible ? settings.backgroundColor.cgColor : nil
            guard resizeCanvas(left: margin, right: margin, top: margin, bottom: margin, background: background) else {
                return nil
            }
        }
        let element = Annotation.tornEdges(settings, imageSize: imageSize, margin: margin, style: style, seed: seed)
        add(element)
        return element.id
    }

    /// Crops like `crop(to:)`; torn edges lose the sides that were cut off, and go when none is left (upstream
    /// `Surface.ApplyCrop`). Returns false when nothing was cropped.
    ///
    /// With an `edgeStyle` other than none (the crop bar's cut edge style, upstream's `CropContainer` CUT_MARK_STYLE), the
    /// sides that were cut off get edges in that style, as new torn edges: the teeth, shadow and background of the torn
    /// edge effect's `settings`, the line of `style` (the last used torn edge style). Like `addTornEdges` the canvas grows
    /// by the room the shadow needs, here only on those sides, and the torn edges that were there already take that room.
    @discardableResult
    public func cropKeepingEdges(to rect: CGRect, edgeStyle: CutMarkStyle = .none,
                                 settings: TornEdgeSettings = TornEdgeSettings(),
                                 style: AnnotationStyle = .defaults(for: .tornEdge),
                                 seed: UInt64 = .random(in: .min ... .max)) -> Bool {
        let size = imageSize
        let target = rect.standardized.integral.intersection(CGRect(origin: .zero, size: size))
        guard !target.isEmpty else { return false }
        let cutTop = target.minY > 0
        let cutRight = target.maxX < size.width
        let cutBottom = target.maxY < size.height
        let cutLeft = target.minX > 0
        let withEdges = edgeStyle != .none && (cutTop || cutRight || cutBottom || cutLeft)
        let torn = annotations.filter { $0.kind == .tornEdge }
        guard crop(to: rect) else { return false }

        var margin = withEdges ? Int((CGFloat(TornEdge.shadowMargin(settings)) * scale).rounded()) : 0
        if margin > 0 {
            // The room is part of the torn off area: transparent or the background color.
            let background = settings.backgroundColor.isVisible ? settings.backgroundColor.cgColor : nil
            func room(_ cut: Bool) -> Int { cut ? margin : 0 }
            if !resizeCanvas(left: room(cutLeft), right: room(cutRight), top: room(cutTop), bottom: room(cutBottom),
                             background: background) {
                margin = 0
            }
        }
        for element in torn {
            let layout = element.cutEdges ?? CutEdgeLayout()
            guard let cropped = layout.cropped(cutTop: cutTop, cutRight: cutRight, cutBottom: cutBottom, cutLeft: cutLeft,
                                               room: margin) else {
                remove(element.id)
                continue
            }
            guard var current = annotation(element.id) else { continue }
            current.cutEdges = cropped
            update(current.spanning(imageSize))
        }
        if withEdges {
            var sides = settings
            (sides.top, sides.right, sides.bottom, sides.left) = (cutTop, cutRight, cutBottom, cutLeft)
            let room = CutEdgeLayout(marginTop: cutTop ? margin : 0, marginRight: cutRight ? margin : 0,
                                     marginBottom: cutBottom ? margin : 0, marginLeft: cutLeft ? margin : 0)
            add(Annotation.tornEdges(sides, imageSize: imageSize, room: room, edgeStyle: edgeStyle, style: style, seed: seed))
        }
        return true
    }
}
