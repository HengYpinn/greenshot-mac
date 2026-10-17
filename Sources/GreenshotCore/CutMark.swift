// Greenshot for Mac (Community) - an unofficial macOS port of Greenshot
// Copyright (C) 2026 Greenshot for Mac (Community) contributors
// Based on Greenshot, Copyright (C) 2007-2026 Thomas Braun, Jens Klingen, Robin Krom
// SPDX-License-Identifier: GPL-3.0-or-later

import CoreGraphics
import Foundation

/// The shape of a cut mark, ported from upstream `Greenshot.Editor/Drawing/CutMarkContainer.cs` (`GetBand`,
/// `CreateEdges`, `CreateGapPath`) and `Greenshot.Editor/Helpers/CutOutHelper.cs` (`CreateEdge`).
///
/// A horizontal cut mark is a band across the whole width of the image. Its first edge goes into the part above the
/// cut, its second one into the part below; between them is the gap, which shows where the strip was cut out.
/// A vertical cut mark (`Annotation.verticalCut`, made by cutting out columns) is the same turned by a quarter: a
/// band down the whole height, its first edge going into the part on the left, its second into the part on the right.
public enum CutMark {
    public struct Shape {
        /// The edge along the first side of the gap (the top, or the left of a vertical cut), along the cut
        /// (image pixels).
        public var first: [CGPoint]
        /// The edge along the second side of the gap (the bottom, or the right of a vertical cut).
        public var second: [CGPoint]
        /// The outline of the gap.
        public var gap: CGPath
    }

    /// The band of a cut mark: its thickness across the whole image (the full width, or the full height of a
    /// vertical cut).
    public static func band(of a: Annotation, imageSize: CGSize) -> CGRect {
        let box = a.bounds
        if a.isVerticalCutMark { return CGRect(x: box.minX, y: 0, width: box.width, height: imageSize.height) }
        return CGRect(x: 0, y: box.minY, width: imageSize.width, height: box.height)
    }

    /// The height of a band for a gap of `gap`, two teeth and the gap (upstream `GetBandSize`).
    public static func bandSize(toothHeight: CGFloat, gap: CGFloat) -> CGFloat {
        2 * max(1, toothHeight) + gap
    }

    /// The seed of an element's random edges.
    static func seed(of a: Annotation) -> UInt64 {
        if let seed = a.seed { return seed }
        let bytes = a.id.uuid
        return [bytes.0, bytes.1, bytes.2, bytes.3, bytes.4, bytes.5, bytes.6, bytes.7]
            .reduce(UInt64(0)) { ($0 << 8) | UInt64($1) }
    }

    /// The edges and the gap of a cut mark, nil for the style None or an empty band. Sizes are image pixels. The
    /// band of a `vertical` cut runs down the image: its length is the band's height.
    public static func shape(band: CGRect, style: CutMarkStyle, toothHeight: CGFloat, toothRange: CGFloat,
                             seed: UInt64, vertical: Bool = false) -> Shape? {
        guard style != .none, band.width > 0, band.height > 0 else { return nil }
        let length = vertical ? band.height : band.width
        let thickness = vertical ? band.width : band.height
        let teeth = min(max(1, toothHeight), thickness / 2)
        var random = SeededRandom(seed: seed)
        let first = edge(style: style, length: length, toothHeight: teeth, toothRange: toothRange, random: &random)
        let second = edge(style: style, length: length, toothHeight: teeth, toothRange: toothRange, random: &random)
        // Along the cut, across the cut (upstream `CreateEdges`' `Map`).
        func map(_ along: CGFloat, _ across: CGFloat) -> CGPoint {
            vertical ? CGPoint(x: band.minX + across, y: band.minY + along) : CGPoint(x: band.minX + along, y: band.minY + across)
        }
        let firstEdge = first.map { map($0.x, teeth - $0.y) }
        let secondEdge = second.map { map($0.x, thickness - teeth + $0.y) }
        let gap = CGMutablePath()
        gap.addLines(between: firstEdge + secondEdge.reversed())
        gap.closeSubpath()
        return Shape(first: firstEdge, second: secondEdge, gap: gap)
    }

    /// One edge along the cut (upstream `CutOutHelper.CreateEdge`): x from 0 to `length`, y how deep the edge goes
    /// into its part, 0 up to `toothHeight`.
    static func edge(style: CutMarkStyle, length: CGFloat, toothHeight: CGFloat, toothRange: CGFloat,
                     random: inout SeededRandom) -> [CGPoint] {
        let height = max(1, toothHeight)
        let range = max(2, toothRange)
        var points: [CGPoint] = []
        switch style {
        case .zigZag:
            var i = 0
            while true {
                let along = min(CGFloat(i) * range / 2, length)
                points.append(CGPoint(x: along, y: i % 2 == 0 ? 0 : height))
                if along >= length { break }
                i += 1
            }
        case .wave:
            var along: CGFloat = 0
            while true {
                let clamped = min(along, length)
                let wave = 1 + sin(CGFloat.pi * clamped / range)
                points.append(CGPoint(x: clamped, y: height / 2 * wave))
                if along >= length { break }
                along += 2
            }
        case .torn:
            // Like the torn edge effect: a random depth at every tooth.
            var i = 0
            let deepest = max(1, Int(height.rounded()))
            while true {
                let along = min(CGFloat(i) * range, length)
                points.append(CGPoint(x: along, y: CGFloat(Int.random(in: 1...deepest, using: &random))))
                if along >= length { break }
                i += 1
            }
        case .line, .none:
            points = [CGPoint(x: 0, y: 0), CGPoint(x: length, y: 0)]
        }
        return points
    }
}

extension Annotation {
    /// A cut mark with another tooth height: the band grows or shrinks on both sides so the gap keeps its size
    /// (upstream `CutMarkContainer.OnOwnFieldChanged`). `scale` is pixels per point.
    public func withToothHeight(_ toothHeight: Double, scale: CGFloat) -> Annotation {
        var result = self
        let old = max(1, style.toothHeight)
        let new = max(1, toothHeight)
        result.style.toothHeight = toothHeight
        guard kind == .cutMark, new != old else { return result }
        let delta = CGFloat(new - old) * scale
        let band = bounds
        if isVerticalCutMark {
            let width = max(2 * CGFloat(new) * scale, band.width + 2 * delta)
            let left = band.minX - delta
            result.start = CGPoint(x: left, y: band.minY)
            result.end = CGPoint(x: left + width, y: band.maxY)
            return result
        }
        let height = max(2 * CGFloat(new) * scale, band.height + 2 * delta)
        let top = band.minY - delta
        result.start = CGPoint(x: band.minX, y: top)
        result.end = CGPoint(x: band.maxX, y: top + height)
        return result
    }

    /// A cut mark across the whole image: the full width, or the full height of a vertical cut (upstream
    /// `SpanImage`). Other elements come back as they are.
    public func spanning(_ imageSize: CGSize) -> Annotation {
        guard kind == .cutMark else { return self }
        var result = self
        let band = bounds
        if isVerticalCutMark {
            result.start = CGPoint(x: band.minX, y: 0)
            result.end = CGPoint(x: band.maxX, y: imageSize.height)
        } else {
            result.start = CGPoint(x: 0, y: band.minY)
            result.end = CGPoint(x: imageSize.width, y: band.maxY)
        }
        return result
    }
}

extension CutMark {
    /// A small picture of `style` for the cut-edge pop-ups (upstream `ImageEditorForm.CreateCutMarkPreview`).
    public static func previewImage(_ style: CutMarkStyle, pointSize: CGFloat = 16, scale: CGFloat = 2) -> CGImage? { nil }
}
