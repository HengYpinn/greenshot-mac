// Greenshot for Mac (Community) - an unofficial macOS port of Greenshot
// Copyright (C) 2026 Greenshot for Mac (Community) contributors
// Based on Greenshot, Copyright (C) 2007-2026 Thomas Braun, Jens Klingen, Robin Krom
// SPDX-License-Identifier: GPL-3.0-or-later

import CoreGraphics
import Foundation

/// Where things are in a recording.
public enum RecordingGeometry {
    /// The part of a region one display records.
    public struct DisplayRegion: Equatable, Sendable {
        /// The index of the display in the list given.
        public var displayIndex: Int
        /// The part on that display, in points from the display's top left corner (`SCStreamConfiguration.sourceRect`).
        public var sourceRect: CGRect
        /// The same part in Quartz global points.
        public var globalRect: CGRect
    }

    /// A stream records one display: a region over several displays records the part on the display it covers most,
    /// like upstream `InitializeCaptureItem` for regions. `displays` are the displays' frames in Quartz global points
    /// (`CGDisplayBounds`). Nil when the region is on no display.
    public static func displayRegion(for region: CGRect, displays: [CGRect]) -> DisplayRegion? {
        let region = region.standardized.integral
        var best: (index: Int, area: CGFloat, part: CGRect)?
        for (index, frame) in displays.enumerated() {
            let part = frame.intersection(region)
            guard !part.isNull, part.width >= 1, part.height >= 1 else { continue }
            let area = part.width * part.height
            if best == nil || area > best!.area { best = (index, area, part) }
        }
        guard let best else { return nil }
        let display = displays[best.index]
        let source = CGRect(x: best.part.minX - display.minX, y: best.part.minY - display.minY,
                            width: best.part.width, height: best.part.height)
        return DisplayRegion(displayIndex: best.index, sourceRect: source, globalRect: best.part)
    }

    /// Where a window's picture of size `content` goes in a video of size `canvas` (upstream `WindowResizeBehavior`):
    /// letterbox keeps the window's size (scaled down only when it is larger), scale-to-fit fills the video; both keep
    /// the proportions and centre the picture. Whole pixels.
    public static func placement(content: CGSize, canvas: CGSize, behavior: WindowResizeBehavior) -> CGRect {
        guard content.width > 0, content.height > 0, canvas.width > 0, canvas.height > 0 else {
            return CGRect(origin: .zero, size: canvas)
        }
        let horizontal = canvas.width / content.width
        let vertical = canvas.height / content.height
        let fit = min(horizontal, vertical)
        let factor = behavior == .letterboxFixedCanvas ? min(1, fit) : fit
        let width = min(canvas.width, (content.width * factor).rounded())
        let height = min(canvas.height, (content.height * factor).rounded())
        let x = ((canvas.width - width) / 2).rounded(.down)
        let y = ((canvas.height - height) / 2).rounded(.down)
        return CGRect(x: x, y: y, width: width, height: height)
    }

    /// The even pixel size of a stream for content of `points` at `scale` pixels per point times `factor`.
    public static func streamSize(points: CGSize, scale: CGFloat, factor: Double) -> (width: Int, height: Int) {
        let pixelsWide = Double(points.width * scale) * factor
        let pixelsHigh = Double(points.height * scale) * factor
        let width = Int((pixelsWide + 0.000_001).rounded(.down))
        let height = Int((pixelsHigh + 0.000_001).rounded(.down))
        return (max(2, width & ~1), max(2, height & ~1))
    }
}
