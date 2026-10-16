// Greenshot for Mac (Community) - an unofficial macOS port of Greenshot
// Copyright (C) 2026 Greenshot for Mac (Community) contributors
// Based on Greenshot, Copyright (C) 2007-2026 Thomas Braun, Jens Klingen, Robin Krom
// SPDX-License-Identifier: GPL-3.0-or-later

import CoreGraphics
import Foundation

/// Finding the content of an image: upstream `ImageHelper.FindAutoCropRectangle` / `FindAutoCropNativeRect`
/// (`Greenshot.Base/Core/ImageHelper.cs`), used by Auto Crop and Shrink Canvas.
public enum AutoCrop {
    /// The box of the pixels that differ from the color of one of the corners of `area` (the whole image when nil)
    /// by more than `difference` (0...255, upstream `AutoCropDifference`, 10 by default); of the four corners the one
    /// that keeps the biggest box wins. Nil when there is nothing to crop: the area has only that color, or the
    /// content fills it. Image pixels, origin top left.
    public static func contentRect(of image: CGImage, difference: Int, area: CGRect? = nil) -> CGRect? {
        let bounds = CGRect(x: 0, y: 0, width: image.width, height: image.height)
        let scan = (area ?? bounds).standardized.integral.intersection(bounds)
        guard !scan.isEmpty, let pixels = Pixels(image) else { return nil }
        let left = Int(scan.minX), top = Int(scan.minY), right = Int(scan.maxX) - 1, bottom = Int(scan.maxY) - 1
        var corners: [RGBAPixel] = []
        for (x, y) in [(left, top), (right, top), (left, bottom), (right, bottom)] {
            let corner = pixels.color(x, y)
            if !corners.contains(corner) { corners.append(corner) }
        }
        var best: CGRect?
        for corner in corners {
            guard let found = box(in: pixels, area: scan, differingFrom: corner, by: difference), found != scan else { continue }
            if found.width * found.height > (best.map { $0.width * $0.height } ?? 0) { best = found }
        }
        return best
    }

    /// The box of the pixels that are not fully transparent, or nil when there is no transparent margin around them
    /// (or the whole image is transparent): what Shrink Canvas keeps.
    public static func opaqueBounds(of image: CGImage) -> CGRect? {
        guard let pixels = Pixels(image) else { return nil }
        var minX = Int.max, minY = Int.max, maxX = Int.min, maxY = Int.min
        for y in 0..<image.height {
            for x in 0..<image.width where pixels.alpha(x, y) > 0 {
                minX = min(minX, x)
                maxX = max(maxX, x)
                minY = min(minY, y)
                maxY = max(maxY, y)
            }
        }
        guard minX != Int.max else { return nil }
        let rect = CGRect(x: minX, y: minY, width: maxX - minX + 1, height: maxY - minY + 1)
        return rect == CGRect(x: 0, y: 0, width: image.width, height: image.height) ? nil : rect
    }

    /// Upstream `FindAutoCropNativeRect`: the box of the pixels of `area` whose average red, green and blue
    /// difference or whose alpha difference to `reference` is more than `difference`.
    static func box(in pixels: Pixels, area: CGRect, differingFrom reference: RGBAPixel, by difference: Int) -> CGRect? {
        var minX = Int.max, minY = Int.max, maxX = Int.min, maxY = Int.min
        for y in Int(area.minY)..<Int(area.maxY) {
            for x in Int(area.minX)..<Int(area.maxX) where differs(pixels.color(x, y), reference, by: difference) {
                minX = min(minX, x)
                maxX = max(maxX, x)
                minY = min(minY, y)
                maxY = max(maxY, y)
            }
        }
        guard minX != Int.max else { return nil }
        return CGRect(x: minX, y: minY, width: maxX - minX + 1, height: maxY - minY + 1)
    }

    /// Typed steps rather than one expression: Swift 6.1 type-checks long mixed integer expressions slowly.
    static func differs(_ color: RGBAPixel, _ reference: RGBAPixel, by difference: Int) -> Bool {
        let red: Int = abs(Int(color.red) - Int(reference.red))
        let green: Int = abs(Int(color.green) - Int(reference.green))
        let blue: Int = abs(Int(color.blue) - Int(reference.blue))
        let alpha: Int = abs(Int(color.alpha) - Int(reference.alpha))
        return (red + green + blue) / 3 > difference || alpha > difference
    }

    /// One premultiplied pixel.
    struct RGBAPixel: Equatable {
        var red, green, blue, alpha: UInt8
    }

    /// The pixels of an image as premultiplied RGBA bytes, origin top left.
    struct Pixels {
        let bytes: [UInt8]
        let rowBytes: Int

        init?(_ image: CGImage) {
            guard let context = AnnotationRenderer.makeContext(width: image.width, height: image.height) else { return nil }
            context.draw(image, in: CGRect(x: 0, y: 0, width: image.width, height: image.height))
            guard let data = context.data else { return nil }
            rowBytes = context.bytesPerRow
            // The bitmap's first row is the top row of the image.
            bytes = Array(UnsafeBufferPointer(start: data.bindMemory(to: UInt8.self, capacity: rowBytes * image.height),
                                              count: rowBytes * image.height))
        }

        func color(_ x: Int, _ y: Int) -> RGBAPixel {
            let i = y * rowBytes + x * 4
            return RGBAPixel(red: bytes[i], green: bytes[i + 1], blue: bytes[i + 2], alpha: bytes[i + 3])
        }

        func alpha(_ x: Int, _ y: Int) -> UInt8 {
            bytes[y * rowBytes + x * 4 + 3]
        }
    }
}
