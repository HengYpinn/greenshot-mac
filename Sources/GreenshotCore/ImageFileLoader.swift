// Greenshot for Mac (Community) - an unofficial macOS port of Greenshot
// Copyright (C) 2026 Greenshot for Mac (Community) contributors
// Based on Greenshot, Copyright (C) 2007-2026 Thomas Braun, Jens Klingen, Robin Krom
// SPDX-License-Identifier: GPL-3.0-or-later

import CoreGraphics
import Foundation
import ImageIO
import UniformTypeIdentifiers

/// Reads image files and image data with ImageIO (upstream's file format handlers, `ImageIO.LoadImage`): every format
/// macOS reads (PNG, JPEG, GIF, TIFF, BMP, HEIC, WebP, TGA, binary PBM/PPM, ICO, ...), upright by its EXIF orientation
/// (upstream `ImageHelper.Orientate`, which `ProcessEXIFOrientation` turns off; here it is always on, like in Preview),
/// with its pixels per point taken from its resolution (144 dpi screenshots are Retina, 2x). SVG files are drawn at
/// 2 pixels per point (`ElementSvg`).
public enum ImageFileLoader {
    /// The largest width or height of a picture the editor holds: the browsers' canvas limit, as for the browser import.
    public static let maxSide = BrowserImportDecoder.maxSide
    /// The most pixels of a picture: 200 megapixels (800 MB decoded), more than the biggest cameras make (150 MP medium
    /// format), so a photo opened on purpose is never refused, and far less than the 1.6 billion pixels that a PNG of
    /// 1.5 MB can claim. The browser import has its own, lower limit for what pages send.
    public static let maxPixels = 2 * BrowserImportDecoder.maxPixels

    public static func load(_ url: URL) -> (image: CGImage, scale: CGFloat)? {
        // ImageIO can't read SVG: macOS draws it (upstream `SvgFileFormatHandler`).
        if ElementSvg.isSVGFile(url) { return ElementSvg.rasterizedFile(url) }
        guard let source = CGImageSourceCreateWithURL(url as CFURL, nil) else { return nil }
        return load(source)
    }

    public static func load(data: Data) -> (image: CGImage, scale: CGFloat)? {
        guard let source = CGImageSourceCreateWithData(data as CFData, nil) else { return nil }
        return load(source)
    }

    static func load(_ source: CGImageSource) -> (image: CGImage, scale: CGFloat)? {
        let index = bestIndex(of: source)
        // The size comes from the header: a crafted file can claim billions of pixels with a few KB
        guard let size = pixelSize(of: source, at: index), isAcceptable(width: size.width, height: size.height),
              let decoded = CGImageSourceCreateImageAtIndex(source, index, nil) else { return nil }
        let properties = CGImageSourceCopyPropertiesAtIndex(source, index, nil) as? [CFString: Any]
        let dpi = (properties?[kCGImagePropertyDPIWidth] as? NSNumber)?.doubleValue ?? 72
        let orientation = (properties?[kCGImagePropertyOrientation] as? NSNumber)?.intValue ?? 1
        let image = oriented(decoded, orientation: orientation) ?? decoded
        return (image, CGFloat(min(max((dpi / 72).rounded(), 1), 4)))
    }

    /// The pixel size the header of frame `index` claims; nil when it has none. Nothing is decoded.
    static func pixelSize(of source: CGImageSource, at index: Int) -> (width: Int, height: Int)? {
        guard index >= 0, index < CGImageSourceGetCount(source),
              let properties = CGImageSourceCopyPropertiesAtIndex(source, index, nil) as? [CFString: Any],
              let width = (properties[kCGImagePropertyPixelWidth] as? NSNumber)?.intValue,
              let height = (properties[kCGImagePropertyPixelHeight] as? NSNumber)?.intValue else { return nil }
        return (width, height)
    }

    /// Whether a picture of this size may be decoded: within `maxSide` and `maxPixels` (the product can't overflow).
    static func isAcceptable(width: Int, height: Int) -> Bool {
        guard width > 0, height > 0, width <= maxSide, height <= maxSide else { return false }
        let (pixels, overflow) = width.multipliedReportingOverflow(by: height)
        return !overflow && pixels <= maxPixels
    }

    /// The frame to open: for icons (ICO, ICNS, CUR) the biggest one, like upstream's `IconFileFormatHandler`, which
    /// takes the 256 px "Vista" entry or else the biggest; for everything else the first (GIF frame, TIFF page).
    static func bestIndex(of source: CGImageSource) -> Int {
        let count = CGImageSourceGetCount(source)
        guard count > 1, let type = CGImageSourceGetType(source).flatMap({ UTType($0 as String) }),
              type.conforms(to: .ico) || type.conforms(to: .icns) || type.identifier == "com.microsoft.cur" else { return 0 }
        var best = 0
        var bestPixels = 0
        for index in 0..<count {
            guard let size = pixelSize(of: source, at: index), isAcceptable(width: size.width, height: size.height) else { continue }
            if size.width * size.height > bestPixels {
                best = index
                bestPixels = size.width * size.height
            }
        }
        return best
    }

    /// `image` turned and mirrored so that it shows the way its EXIF `orientation` (1...8, `CGImagePropertyOrientation`)
    /// says; nil for 1 (already upright) or a value out of range.
    public static func oriented(_ image: CGImage, orientation: Int) -> CGImage? {
        guard (2...8).contains(orientation) else { return nil }
        let w = CGFloat(image.width)
        let h = CGFloat(image.height)
        let turned = orientation >= 5
        let size = turned ? CGSize(width: h, height: w) : CGSize(width: w, height: h)
        // In the bitmap's coordinates (origin bottom left). Clockwise maps (x, y) to (y, w - x) like
        // `ImageOperations.rotate`; the mirrored turns flip the result horizontally.
        let clockwise = CGAffineTransform(a: 0, b: -1, c: 1, d: 0, tx: 0, ty: w)
        let counterClockwise = CGAffineTransform(a: 0, b: 1, c: -1, d: 0, tx: h, ty: 0)
        let mirror = CGAffineTransform(a: -1, b: 0, c: 0, d: 1, tx: size.width, ty: 0)
        let transform: CGAffineTransform
        switch orientation {
        case 2: transform = mirror                                          // upMirrored
        case 3: transform = CGAffineTransform(a: -1, b: 0, c: 0, d: -1, tx: w, ty: h) // down
        case 4: transform = CGAffineTransform(a: 1, b: 0, c: 0, d: -1, tx: 0, ty: h)  // downMirrored
        case 5: transform = clockwise.concatenating(mirror)                 // leftMirrored (transpose)
        case 6: transform = clockwise                                       // right
        case 7: transform = counterClockwise.concatenating(mirror)          // rightMirrored (transverse)
        default: transform = counterClockwise                               // left
        }
        guard let context = AnnotationRenderer.makeContext(width: Int(size.width), height: Int(size.height)) else { return nil }
        context.concatenate(transform)
        context.draw(image, in: CGRect(x: 0, y: 0, width: w, height: h))
        return context.makeImage()
    }
}
