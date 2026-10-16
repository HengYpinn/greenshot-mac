// Greenshot for Mac (Community) - an unofficial macOS port of Greenshot
// Copyright (C) 2026 Greenshot for Mac (Community) contributors
// Based on Greenshot, Copyright (C) 2007-2026 Thomas Braun, Jens Klingen, Robin Krom
// SPDX-License-Identifier: GPL-3.0-or-later

import CoreGraphics
import Foundation

/// Where the image and the footer go on a printed page.
///
/// Port of `DrawImageForPrint` in upstream `Greenshot/Helpers/PrintHelper.cs`: the footer takes its height off the
/// bottom of the page; "allow rotate" turns the image a quarter when its orientation doesn't match the page's;
/// the image is fitted into the page only when that shrinks it (allow shrink) or enlarges it (allow enlarge);
/// then it is centred or put in the top left corner (top right after a rotation, like upstream).
public struct PrintLayout: Equatable, Sendable {
    /// The image's rectangle on the page, in points, origin top left. After a rotation it is the rotated image's.
    public var imageRect: CGRect
    /// Turn the image 90° counterclockwise before drawing it into `imageRect` (upstream `Rotate270FlipNone`).
    public var rotated: Bool
    /// The footer text's top left corner, horizontally centred under the image area; nil without a footer.
    public var footerOrigin: CGPoint?

    public init(imageRect: CGRect, rotated: Bool, footerOrigin: CGPoint?) {
        self.imageRect = imageRect
        self.rotated = rotated
        self.footerOrigin = footerOrigin
    }

    /// `image` and `page` are in points; `footer` is the measured footer text, nil without one.
    public static func layout(image: CGSize, page: CGSize, footer: CGSize?, options: PrintSettings) -> PrintLayout {
        let footerHeight = footer?.height ?? 0
        let area = CGSize(width: page.width, height: max(page.height - footerHeight, 0))

        var size = image
        var rotated = false
        if options.allowRotate {
            let pageIsLandscape = area.width > area.height
            let pageIsPortrait = area.width < area.height
            if (pageIsLandscape && image.width < image.height) || (pageIsPortrait && image.width > image.height) {
                size = CGSize(width: image.height, height: image.width)
                rotated = true
            }
        }

        if options.allowShrink || options.allowEnlarge {
            let fitted = fit(size, in: area)
            if (options.allowShrink && fitted.width < size.width) || (options.allowEnlarge && fitted.width > size.width) {
                size = fitted
            }
        }

        let origin: CGPoint
        if options.center {
            origin = CGPoint(x: (area.width - size.width) / 2, y: (area.height - size.height) / 2)
        } else if rotated {
            origin = CGPoint(x: area.width - size.width, y: 0)
        } else {
            origin = .zero
        }

        let footerOrigin = footer.map { CGPoint(x: (page.width - $0.width) / 2, y: area.height) }
        return PrintLayout(imageRect: CGRect(origin: origin, size: size), rotated: rotated, footerOrigin: footerOrigin)
    }

    /// `size` scaled uniformly to fill as much of `bounds` as fits (upstream `ScaleHelper.GetScaledSize`).
    public static func fit(_ size: CGSize, in bounds: CGSize) -> CGSize {
        guard size.width > 0, size.height > 0 else { return size }
        let factor = min(bounds.width / size.width, bounds.height / size.height)
        return CGSize(width: size.width * factor, height: size.height * factor)
    }
}

/// The colour options of upstream's print dialog, applied to the image before it is printed.
public enum PrintColors {
    /// Applies grayscale, monochrome (with `monochromeThreshold`, 0–255: brighter is white) and inversion, in that
    /// order (upstream applies monochrome before invert). Returns the image unchanged without any of them.
    public static func apply(_ image: CGImage, options: PrintSettings) -> CGImage {
        guard options.grayscale || options.monochrome || options.inverted else { return image }
        let width = image.width
        let height = image.height
        guard let context = CGContext(data: nil, width: width, height: height, bitsPerComponent: 8, bytesPerRow: 0,
                                      space: CGColorSpace(name: CGColorSpace.sRGB)!,
                                      bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue),
              let data = context.data else { return image }
        context.draw(image, in: CGRect(x: 0, y: 0, width: width, height: height))
        let bytesPerRow = context.bytesPerRow
        let bytes = data.bindMemory(to: UInt8.self, capacity: bytesPerRow * height)
        let threshold = Double(min(max(options.monochromeThreshold, 0), 255))
        for row in 0..<height {
            for column in 0..<width {
                let i = row * bytesPerRow + column * 4
                let a = Double(bytes[i + 3])
                var r = Double(bytes[i]), g = Double(bytes[i + 1]), b = Double(bytes[i + 2])
                if options.grayscale || options.monochrome {
                    let luma = 0.299 * r + 0.587 * g + 0.114 * b
                    r = luma; g = luma; b = luma
                }
                if options.monochrome {
                    // Compare the unpremultiplied brightness with the threshold.
                    let value = a > 0 ? r * 255 / a : 0
                    let level = value > threshold ? a : 0
                    r = level; g = level; b = level
                }
                if options.inverted {
                    r = a - r; g = a - g; b = a - b
                }
                bytes[i] = UInt8(min(max(r.rounded(), 0), a))
                bytes[i + 1] = UInt8(min(max(g.rounded(), 0), a))
                bytes[i + 2] = UInt8(min(max(b.rounded(), 0), a))
            }
        }
        return context.makeImage() ?? image
    }
}
