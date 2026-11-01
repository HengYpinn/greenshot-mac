// Greenshot for Mac (Community) - an unofficial macOS port of Greenshot
// Copyright (C) 2026 Greenshot for Mac (Community) contributors
// Based on Greenshot, Copyright (C) 2007-2026 Thomas Braun, Jens Klingen, Robin Krom
// SPDX-License-Identifier: GPL-3.0-or-later

import CoreGraphics
import Foundation
import ImageIO

/// Limits for elements that come from outside the app: `.greenshot` files (this app's and Greenshot for Windows'),
/// `.gst` and `.greenshot-elements` files, and pasted elements. Every way they are read goes through
/// `withinLimits(_:unreadable:)`. A position that is not finite or absurdly far away (an SVG element ending at
/// 1e300, 1e300) makes the conversions to whole pixels trap, when it is drawn or pushed out of the image; tens of
/// thousands of elements, or pictures of billions of pixels in all, make every redraw take seconds.
extension Annotation {
    /// How far from the image's top left a position may be, pixels: far beyond any image (decoders stop at about
    /// 16384 a side), and small enough that sizes made from it are whole numbers of pixels.
    public static let maxCoordinate: CGFloat = 1_000_000

    /// The most elements a document takes from a file or the clipboard: far more than any drawing has, and few enough
    /// that drawing all of them again after every change stays quick.
    public static let maxElements = 5_000
    /// The most pixels the pictures of a document's elements may have in all, by the sizes their files claim (an SVG
    /// by the size it is drawn at): two of the biggest pictures a file may hold, or twenty full-screen captures of a 6K
    /// display. Each picture is decoded when it is drawn: this keeps the time and memory that takes within bounds.
    public static let maxPicturePixels = 2 * ImageFileLoader.maxPixels

    /// What the editor calls an element left out by the limits (see `GreenshotFile.unreadableMessage`).
    public static var outOfLimitsName: String { String(localized: "Damaged element") }

    /// Whether the start, end, tail and freehand path are finite and within `maxCoordinate` of the origin.
    public var hasLimitedGeometry: Bool {
        func limited(_ point: CGPoint) -> Bool {
            point.x.isFinite && point.y.isFinite && abs(point.x) <= Self.maxCoordinate && abs(point.y) <= Self.maxCoordinate
        }
        return limited(start) && limited(end) && (tail.map(limited) ?? true) && points.allSatisfy(limited)
    }

    /// The pixels of the picture in `data` by its header, nothing is decoded: of the frame `ImageFileLoader` opens;
    /// 0 when it has no size or one too big to be decoded at all.
    static func picturePixels(of data: Data) -> Int {
        guard let source = CGImageSourceCreateWithData(data as CFData, nil),
              let size = ImageFileLoader.pixelSize(of: source, at: ImageFileLoader.bestIndex(of: source)),
              ImageFileLoader.isAcceptable(width: size.width, height: size.height) else { return 0 }
        return size.width * size.height
    }

    /// The pixels of the element's picture (see `maxPicturePixels`); 0 for the kinds without one.
    var picturePixels: Int {
        switch kind {
        case .image, .cursor:
            return imageData.map(Self.picturePixels(of:)) ?? 0
        case .svg:
            let size = ElementSvg.limited(bounds.size)
            return Int(size.width * size.height)
        default:
            return 0
        }
    }

    /// `elements` without those whose geometry is out of the limits, those after the first `maxElements` and the
    /// pictures that would pass `maxPicturePixels`, and `unreadable` with an `outOfLimitsName` for each one left out.
    public static func withinLimits(_ elements: [Annotation], unreadable: [String] = [])
        -> (elements: [Annotation], unreadable: [String]) {
        let limited = elements.filter(\.hasLimitedGeometry)
        if limited.count < elements.count {
            log.warn("\(elements.count - limited.count) element(s) with a position that isn't finite or is too far away were left out")
        }
        var kept: [Annotation] = []
        var pixelsLeft = maxPicturePixels
        for element in limited where kept.count < maxElements {
            let pixels = element.picturePixels
            guard pixels <= pixelsLeft else { continue }
            pixelsLeft -= pixels
            kept.append(element)
        }
        if kept.count < limited.count {
            log.warn("\(limited.count - kept.count) element(s) past the limits of elements or picture pixels were left out")
        }
        let dropped = elements.count - kept.count
        guard dropped > 0 else { return (kept, unreadable) }
        return (kept, unreadable + Array(repeating: outOfLimitsName, count: dropped))
    }
}

private let log = Log("Editor")
