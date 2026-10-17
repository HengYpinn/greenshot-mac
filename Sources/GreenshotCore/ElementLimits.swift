// Greenshot for Mac (Community) - an unofficial macOS port of Greenshot
// Copyright (C) 2026 Greenshot for Mac (Community) contributors
// Based on Greenshot, Copyright (C) 2007-2026 Thomas Braun, Jens Klingen, Robin Krom
// SPDX-License-Identifier: GPL-3.0-or-later

import CoreGraphics
import Foundation

/// Limits for the positions of elements that come from outside the app: `.greenshot` files (this app's and Greenshot
/// for Windows'), `.gst` and `.greenshot-elements` files, and pasted elements. Every way they are read goes through
/// `withinLimits(_:unreadable:)`. A position that is not finite or absurdly far away (an SVG element ending at
/// 1e300, 1e300) makes the conversions to whole pixels trap, when it is drawn or pushed out of the image.
extension Annotation {
    /// How far from the image's top left a position may be, pixels: far beyond any image (decoders stop at about
    /// 16384 a side), and small enough that sizes made from it are whole numbers of pixels.
    public static let maxCoordinate: CGFloat = 1_000_000

    /// What the editor calls an element left out by the limits (see `GreenshotFile.unreadableMessage`).
    public static var outOfLimitsName: String { String(localized: "Damaged element") }

    /// Whether the start, end, tail and freehand path are finite and within `maxCoordinate` of the origin.
    public var hasLimitedGeometry: Bool {
        func limited(_ point: CGPoint) -> Bool {
            point.x.isFinite && point.y.isFinite && abs(point.x) <= Self.maxCoordinate && abs(point.y) <= Self.maxCoordinate
        }
        return limited(start) && limited(end) && (tail.map(limited) ?? true) && points.allSatisfy(limited)
    }

    /// `elements` without those whose geometry is out of the limits, and `unreadable` with an `outOfLimitsName` for
    /// each one left out.
    public static func withinLimits(_ elements: [Annotation], unreadable: [String] = [])
        -> (elements: [Annotation], unreadable: [String]) {
        let kept = elements.filter(\.hasLimitedGeometry)
        let dropped = elements.count - kept.count
        guard dropped > 0 else { return (kept, unreadable) }
        log.warn("\(dropped) element(s) with a position that isn't finite or is too far away were left out")
        return (kept, unreadable + Array(repeating: outOfLimitsName, count: dropped))
    }
}

private let log = Log("Editor")
