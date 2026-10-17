// Greenshot for Mac (Community) - an unofficial macOS port of Greenshot
// Copyright (C) 2026 Greenshot for Mac (Community) contributors
// Based on Greenshot, Copyright (C) 2007-2026 Thomas Braun, Jens Klingen, Robin Krom
// SPDX-License-Identifier: GPL-3.0-or-later

import CoreGraphics

/// One size of the fixed-size mode's list: a size of the settings, or one of the last region captures.
public struct FixedSizeEntry: Equatable, Sendable {
    public var size: CaptureSize
    public var isRecent: Bool

    public init(size: CaptureSize, isRecent: Bool) {
        self.size = size
        self.isRecent = isRecent
    }
}

/// The geometry and the size list of the fixed-size mode: a rectangle of a chosen size (in pixels) follows the mouse,
/// held at a corner or the middle, its edges snap to nearby window and display edges.
/// Port of upstream `Greenshot/Capturing/Tools/FixedSizeCaptureTool.cs`. Rectangles are Quartz global points.
public enum FixedSizeCapture {
    /// The number of remembered region sizes.
    public static let recentSizesCount = 5
    /// An edge closer than this (points) to an edge of a window or display snaps to it (upstream `SnapDistance`, 8).
    public static let snapDistance: CGFloat = 8

    /// The rectangle of `size` pixels with the mouse at `anchor`. At a corner the pixel under the mouse is the corner
    /// pixel of the capture, so the zoomer shows exactly where the capture starts or ends. The rectangle lies on the
    /// pixel grid of a display with `scale` pixels per point.
    public static func place(cursor: CGPoint, size: CaptureSize, anchor: FixedCaptureAnchor, scale: CGFloat) -> CGRect {
        let scale = max(scale, 1)
        let x = (cursor.x * scale).rounded(.down)
        let y = (cursor.y * scale).rounded(.down)
        let width = CGFloat(size.width)
        let height = CGFloat(size.height)
        let left: CGFloat
        switch anchor {
        case .topRight, .bottomRight: left = x - width + 1
        case .center: left = x - (width / 2).rounded(.down)
        case .topLeft, .bottomLeft: left = x
        }
        let top: CGFloat
        switch anchor {
        case .bottomLeft, .bottomRight: top = y - height + 1
        case .center: top = y - (height / 2).rounded(.down)
        case .topLeft, .topRight: top = y
        }
        return CGRect(x: left / scale, y: top / scale, width: width / scale, height: height / scale)
    }

    /// Moves `rect` so that, per direction, the edge closest to an edge of one of `bounds` lies on it, when it is
    /// within `distance`.
    public static func snap(_ rect: CGRect, to bounds: [CGRect], distance: CGFloat = snapDistance) -> CGRect {
        let dx = nearest(bounds.flatMap { [$0.minX, $0.maxX] }, rect.minX, rect.maxX, distance)
        let dy = nearest(bounds.flatMap { [$0.minY, $0.maxY] }, rect.minY, rect.maxY, distance)
        return rect.offsetBy(dx: dx, dy: dy)
    }

    private static func nearest(_ edges: [CGFloat], _ start: CGFloat, _ end: CGFloat, _ distance: CGFloat) -> CGFloat {
        var move: CGFloat = 0
        var moveDistance = distance + 0.001
        for edge in edges {
            for candidate in [edge - start, edge - end] where abs(candidate) < moveDistance {
                move = candidate
                moveDistance = abs(candidate)
            }
        }
        return move
    }

    /// Moves `rect` into `bounds` when it fits; a larger rectangle is left as it is (and cut off later).
    public static func keepInside(_ rect: CGRect, _ bounds: CGRect) -> CGRect {
        guard rect.width <= bounds.width, rect.height <= bounds.height else { return rect }
        let x = min(max(rect.minX, bounds.minX), bounds.maxX - rect.width)
        let y = min(max(rect.minY, bounds.minY), bounds.maxY - rect.height)
        return CGRect(x: x, y: y, width: rect.width, height: rect.height)
    }

    /// The rectangle the mode captures now: placed at the mouse, snapped (unless `snapping` is off), kept on the
    /// display with the mouse and cut to the desktop. Empty when nothing of it is on a display.
    public static func selection(cursor: CGPoint, size: CaptureSize, anchor: FixedCaptureAnchor, scale: CGFloat,
                                 monitor: CGRect, desktop: CGRect, snapTargets: [CGRect], snapping: Bool) -> CGRect {
        var rect = place(cursor: cursor, size: size, anchor: anchor, scale: scale)
        if snapping { rect = snap(rect, to: [monitor] + snapTargets) }
        let result = keepInside(keepInside(rect, monitor), desktop).intersection(desktop)
        return result.isNull ? .zero : result
    }

    /// The sizes of the settings, then the recent sizes that aren't among them (each size once).
    public static func sizes(configured: [CaptureSize], recent: [CaptureSize]) -> [FixedSizeEntry] {
        var entries: [FixedSizeEntry] = []
        for (list, isRecent) in [(configured, false), (recent, true)] {
            for size in list where size.width > 0 && size.height > 0 && !entries.contains(where: { $0.size == size }) {
                entries.append(FixedSizeEntry(size: size, isRecent: isRecent))
            }
        }
        return entries
    }

    /// The recent sizes after a capture of `size`: newest first, each size once, at most `recentSizesCount`.
    public static func remember(_ size: CaptureSize, in recent: [CaptureSize]) -> [CaptureSize] {
        guard size.width > 0, size.height > 0 else { return recent }
        return [size] + recent.filter { $0 != size }.prefix(recentSizesCount - 1)
    }

    /// The index in a list of `count` sizes after stepping `change` from `index`; wraps around.
    public static func step(_ index: Int, by change: Int, count: Int) -> Int {
        guard count > 0 else { return 0 }
        return ((index + change) % count + count) % count
    }

    /// Parses a list typed in the settings ("640x480, 800x600" or one per line); invalid parts are skipped.
    public static func parseSizes(_ text: String) -> [CaptureSize] {
        text.split(whereSeparator: { $0 == "," || $0 == ";" || $0.isNewline })
            .compactMap { CaptureSize(String($0).replacingOccurrences(of: "×", with: "x")) }
    }
}
