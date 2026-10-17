// Greenshot for Mac (Community) - an unofficial macOS port of Greenshot
// Copyright (C) 2026 Greenshot for Mac (Community) contributors
// Based on Greenshot, Copyright (C) 2007-2026 Thomas Braun, Jens Klingen, Robin Krom
// SPDX-License-Identifier: GPL-3.0-or-later

import CoreGraphics
import Foundation
import ImageIO

/// An edge of the image (upstream `Direction`), for the element context menu's Expand capture and move outside, Stretch
/// and Dock to edge.
public enum ElementEdge: CaseIterable, Sendable {
    case top, right, bottom, left

    public var title: String {
        switch self {
        case .top: return "Top"
        case .right: return "Right"
        case .bottom: return "Bottom"
        case .left: return "Left"
        }
    }
}

extension Annotation {
    /// The element stretched so its box becomes `rect`: corners, end points and the freehand path are mapped from the
    /// old box to the new one; a speech bubble's tail stays, like when a handle is dragged. A line without width (or
    /// height) gets its start on the left (top) and its end on the right (bottom), like upstream setting `Width`.
    public func withBounds(_ rect: CGRect) -> Annotation {
        let old = bounds
        // Torn edges always cover the whole image (upstream `TornEdgeContainer.ApplyBounds` → `SpanImage`).
        guard rect != old, kind != .tornEdge else { return self }
        if rect.size == old.size {
            var moved = self
            moved.move(by: CGVector(dx: rect.minX - old.minX, dy: rect.minY - old.minY))
            return moved
        }
        let sx = old.width > 0 ? rect.width / old.width : 0
        let sy = old.height > 0 ? rect.height / old.height : 0
        func map(_ p: CGPoint) -> CGPoint {
            CGPoint(x: rect.minX + (p.x - old.minX) * sx, y: rect.minY + (p.y - old.minY) * sy)
        }
        var result = self
        result.start = map(start)
        result.end = map(end)
        result.points = points.map(map)
        if !kind.isBoxShaped && kind != .freehand {
            if old.width == 0 && rect.width > 0 {
                result.start.x = rect.minX
                result.end.x = rect.maxX
            }
            if old.height == 0 && rect.height > 0 {
                result.start.y = rect.minY
                result.end.y = rect.maxY
            }
        }
        return result
    }

    /// The element moved against `edge` of an image of `imageSize` (upstream `DrawableContainer.SnapToEdge`).
    public func docked(to edge: ElementEdge, imageSize: CGSize) -> Annotation {
        let box = bounds
        var delta = CGVector.zero
        switch edge {
        case .left: delta.dx = -box.minX
        case .right: delta.dx = imageSize.width - box.maxX
        case .top: delta.dy = -box.minY
        case .bottom: delta.dy = imageSize.height - box.maxY
        }
        var moved = self
        moved.move(by: delta)
        return moved
    }

    /// Whether "Reset size" applies: upstream `HasDefaultSize` (image, icon, SVG, metafile and cursor containers; the
    /// Mac has image and SVG elements).
    public var hasDefaultSize: Bool { [.image, .svg].contains(kind) && imageData != nil }

    /// The size of an image element's picture at its own pixels per point (from its resolution), or of an SVG at its
    /// own size, on an image with `documentScale` pixels per point (upstream `ImageContainer.DefaultSize`,
    /// `SvgContainer.DefaultSize`).
    public func defaultSize(documentScale: CGFloat) -> CGSize? {
        if kind == .svg {
            guard let data = imageData, let size = ElementSvg.size(of: data) else { return nil }
            return CGSize(width: size.width * documentScale, height: size.height * documentScale)
        }
        guard hasDefaultSize, let data = imageData, let source = CGImageSourceCreateWithData(data as CFData, nil),
              let properties = CGImageSourceCopyPropertiesAtIndex(source, 0, nil) as? [CFString: Any],
              let width = (properties[kCGImagePropertyPixelWidth] as? NSNumber)?.doubleValue,
              let height = (properties[kCGImagePropertyPixelHeight] as? NSNumber)?.doubleValue else { return nil }
        let dpi = (properties[kCGImagePropertyDPIWidth] as? NSNumber)?.doubleValue ?? 72
        let pictureScale = CGFloat(min(max((dpi / 72).rounded(), 1), 4))
        let factor = documentScale / pictureScale
        return CGSize(width: CGFloat(width) * factor, height: CGFloat(height) * factor)
    }
}

extension EditorDocument {
    /// Moves each element with one of `ids` against `edge` (upstream `DrawableContainerList.SnapAllToEdge`).
    public func dock(_ ids: Set<UUID>, to edge: ElementEdge) {
        let size = imageSize
        for element in annotations(ids) { update(element.docked(to: edge, imageSize: size)) }
    }

    /// Upstream's Stretch › Width (Height): each element with one of `ids` becomes as wide (high) as the image, then
    /// they are docked to the left (top).
    public func stretch(_ ids: Set<UUID>, width: Bool) {
        let size = imageSize
        for element in annotations(ids) {
            var box = element.bounds
            if width { box.size.width = size.width } else { box.size.height = size.height }
            update(element.withBounds(box))
        }
        dock(ids, to: width ? .left : .top)
    }

    /// Upstream's Expand capture and move outside (`DrawableContainerList.PushOut`): the canvas grows on `edge` by the
    /// element's width or height (transparent, upstream `ResizeCanvasEffect`), and the element moves into the new
    /// strip. False when the element has no size in that direction.
    @discardableResult
    public func pushOut(_ id: UUID, to edge: ElementEdge) -> Bool {
        // Torn edges always cover the whole image.
        guard let element = annotation(id), element.kind != .tornEdge else { return false }
        let box = element.bounds
        let width = Int(box.width.rounded(.up))
        let height = Int(box.height.rounded(.up))
        let grown: Bool
        switch edge {
        case .left: grown = width > 0 && resizeCanvas(left: width, right: 0, top: 0, bottom: 0)
        case .right: grown = width > 0 && resizeCanvas(left: 0, right: width, top: 0, bottom: 0)
        case .top: grown = height > 0 && resizeCanvas(left: 0, right: 0, top: height, bottom: 0)
        case .bottom: grown = height > 0 && resizeCanvas(left: 0, right: 0, top: 0, bottom: height)
        }
        guard grown, let moved = annotation(id) else { return false }
        update(moved.docked(to: edge, imageSize: imageSize))
        return true
    }

    /// Whether one of the elements with `ids` has a default size to go back to.
    public func canResetSize(_ ids: Set<UUID>) -> Bool {
        annotations(ids).contains { $0.hasDefaultSize }
    }

    /// Upstream "Reset size": the elements with a default size get it back, their top left stays.
    public func resetSize(_ ids: Set<UUID>) {
        for element in annotations(ids) {
            guard let size = element.defaultSize(documentScale: scale) else { continue }
            update(element.withBounds(CGRect(origin: element.bounds.origin, size: size)))
        }
    }
}
