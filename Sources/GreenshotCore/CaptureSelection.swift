// Greenshot for Mac (Community) - an unofficial macOS port of Greenshot
// Copyright (C) 2026 Greenshot for Mac (Community) contributors
// Based on Greenshot, Copyright (C) 2007-2026 Thomas Braun, Jens Klingen, Robin Krom
// SPDX-License-Identifier: GPL-3.0-or-later

import CoreGraphics

/// The rectangle a drag selects on the capture screen.
public enum CaptureSelection {
    /// The rectangle from `anchor` to `cursor` (Quartz global points) on the pixel grid of a display with `scale` pixels
    /// per point. The pixels under both corners belong to it, so the size shown is exactly the size of the capture
    /// (upstream `Greenshot/Capturing/Tools/RegionCaptureTool.cs`: the selection is `Width + 1` by `Height + 1`).
    /// A click is one pixel.
    public static func rect(from anchor: CGPoint, to cursor: CGPoint, scale: CGFloat) -> CGRect {
        let scale = max(scale, 1)
        let ax = (anchor.x * scale).rounded(.down), ay = (anchor.y * scale).rounded(.down)
        let cx = (cursor.x * scale).rounded(.down), cy = (cursor.y * scale).rounded(.down)
        let left = min(ax, cx), top = min(ay, cy)
        let right = max(ax, cx) + 1, bottom = max(ay, cy) + 1
        return CGRect(x: left / scale, y: top / scale, width: (right - left) / scale, height: (bottom - top) / scale)
    }

    /// Whether a selection is large enough to be captured, by the mouse or by Enter: at least 3 points in one direction
    /// and a point in the other. A smaller one is a click, which captures nothing, so the user can just try again
    /// (upstream `RegionCaptureTool.EndSelection` with its `MinimumSize` of 3 pixels in both directions; a line of
    /// text one point high can be captured here). A click is one pixel, also on a display of one pixel per point.
    public static func isCapturable(_ rect: CGRect) -> Bool {
        (rect.width >= 3 || rect.height >= 3) && rect.width >= 1 && rect.height >= 1
    }

    /// The size of `rect` in whole pixels of a display with `scale` pixels per point.
    public static func pixelSize(of rect: CGRect, scale: CGFloat) -> (width: Int, height: Int) {
        (Int((rect.width * scale).rounded()), Int((rect.height * scale).rounded()))
    }
}

/// Where the size labels of a selection go (upstream `CaptureWindow.xaml.cs` `ShowLabels`): a ruler with the width above
/// the selection, one with the height left of it, and the size in the middle, as large as fits. All in the same space
/// (a display's points); the caller measures the texts.
public enum CaptureSelectionLabels {
    /// Distance between the selection and its rulers.
    public static let rulerDistance: CGFloat = 8
    /// The size in the middle is drawn at this font size times how often it fits, at most `largestSize`, not below
    /// `smallestSize`.
    public static let measureSize: CGFloat = 12
    public static let largestSize: CGFloat = 20
    public static let smallestSize: CGFloat = 4

    /// A ruler along one side of the selection: the line from `start` to `end`, with its label in `label` (the line is
    /// left out behind the label).
    public struct Ruler: Equatable, Sendable {
        public var start: CGPoint
        public var end: CGPoint
        public var label: CGRect
    }

    /// The width ruler above `selection`, or inside it when there is no room above on `display`; nil when the selection
    /// is too narrow for the label.
    public static func widthRuler(for selection: CGRect, labelSize: CGSize, display: CGRect) -> Ruler? {
        guard selection.width > labelSize.width + 9 else { return nil }
        var y = selection.minY - rulerDistance + 0.5
        if y - labelSize.height / 2 < display.minY { y = selection.minY + rulerDistance + 0.5 }
        let label = CGRect(x: selection.midX - labelSize.width / 2 - 2, y: y - labelSize.height / 2,
                           width: labelSize.width + 4, height: labelSize.height)
        return Ruler(start: CGPoint(x: selection.minX, y: y), end: CGPoint(x: selection.maxX, y: y), label: label)
    }

    /// The height ruler left of `selection`, with its label left of the line, or inside the selection (label right of
    /// the line) when there is no room on `display`; nil when the selection is too low for the label.
    public static func heightRuler(for selection: CGRect, labelSize: CGSize, display: CGRect) -> Ruler? {
        guard selection.height > labelSize.height + 9 else { return nil }
        var x = selection.minX - rulerDistance + 0.5
        var labelX = x - labelSize.width - 2
        if labelX < display.minX {
            x = selection.minX + rulerDistance + 0.5
            labelX = x - 2
        }
        let label = CGRect(x: labelX, y: selection.midY - labelSize.height / 2, width: labelSize.width + 4, height: labelSize.height)
        return Ruler(start: CGPoint(x: x, y: selection.minY), end: CGPoint(x: x, y: selection.maxY), label: label)
    }

    /// The font size of the size in the middle of `selection`, for a text that is `measured` large at `measureSize`;
    /// nil when it wouldn't be readable.
    public static func sizeFontSize(for selection: CGSize, measured: CGSize) -> CGFloat? {
        guard measured.width > 0, measured.height > 0 else { return nil }
        let ratio = min(selection.height / (measured.height * 2), selection.width / (measured.width * 2))
        let size = min(measureSize * ratio, largestSize)
        return size >= smallestSize ? size : nil
    }
}

/// The zoomer's picture: `CaptureZoomerPlacement.sourcePixels` pixels across around the pixel under the mouse, drawn
/// into `zoom` (upstream `CaptureWindow.xaml.cs` `UpdateZoomer`, `UpdateZoomerSelection`).
public struct CaptureZoomerGeometry: Sendable {
    /// Where the zoomer is drawn.
    public var zoom: CGRect
    /// The pixel under the mouse, in pixels of the display's picture.
    public var cursorPixel: CGPoint

    public init(zoom: CGRect, cursorPixel: CGPoint) {
        self.zoom = zoom
        self.cursorPixel = cursorPixel
    }

    /// Points per pixel.
    public var magnification: CGFloat { zoom.width / CaptureZoomerPlacement.sourcePixels }

    /// The pixels shown, the one under the mouse in the middle.
    public var source: CGRect {
        let half = (CaptureZoomerPlacement.sourcePixels / 2).rounded(.down)
        return CGRect(x: cursorPixel.x - half, y: cursorPixel.y - half,
                      width: CaptureZoomerPlacement.sourcePixels, height: CaptureZoomerPlacement.sourcePixels)
    }

    /// Where a rectangle of pixels is in the zoomer, e.g. the pixel under the mouse or the selection's edges.
    public func frame(ofPixels rect: CGRect) -> CGRect {
        let source = self.source
        let scale = magnification
        return CGRect(x: zoom.minX + (rect.minX - source.minX) * scale, y: zoom.minY + (rect.minY - source.minY) * scale,
                      width: rect.width * scale, height: rect.height * scale)
    }
}
