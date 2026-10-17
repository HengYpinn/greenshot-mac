// Greenshot for Mac (Community) - an unofficial macOS port of Greenshot
// Copyright (C) 2026 Greenshot for Mac (Community) contributors
// Based on Greenshot, Copyright (C) 2007-2026 Thomas Braun, Jens Klingen, Robin Krom
// SPDX-License-Identifier: GPL-3.0-or-later

import CoreGraphics
import Foundation
import ImageIO

/// Reads the pictures that are dropped or pasted on the editor as image elements.
public enum ElementPictures {
    /// The image file at `url` (see `largestImage(in:)`).
    public static func load(_ url: URL) -> (image: CGImage, scale: CGFloat)? {
        guard let source = CGImageSourceCreateWithURL(url as CFURL, nil) else { return nil }
        return largestImage(in: source)
    }

    /// The image in `data` (see `largestImage(in:)`).
    public static func load(data: Data) -> (image: CGImage, scale: CGFloat)? {
        guard let source = CGImageSourceCreateWithData(data as CFData, nil) else { return nil }
        return largestImage(in: source)
    }

    /// The largest image of a source with several (the sizes of an .ico or .icns icon, the pages of a TIFF), with its
    /// pixels per point from its resolution (144 dpi is 2×). Upstream `IconContainer` shows the icon at its own size;
    /// the largest one looks best when it is made smaller.
    public static func largestImage(in source: CGImageSource) -> (image: CGImage, scale: CGFloat)? {
        let count = CGImageSourceGetCount(source)
        guard count > 0 else { return nil }
        var best: (index: Int, pixels: Int)?
        for index in 0..<count {
            guard let properties = CGImageSourceCopyPropertiesAtIndex(source, index, nil) as? [CFString: Any] else { continue }
            let width = (properties[kCGImagePropertyPixelWidth] as? NSNumber)?.intValue ?? 0
            let height = (properties[kCGImagePropertyPixelHeight] as? NSNumber)?.intValue ?? 0
            if width * height > (best?.pixels ?? -1) { best = (index, width * height) }
        }
        let index = best?.index ?? 0
        guard let image = CGImageSourceCreateImageAtIndex(source, index, nil) else { return nil }
        let properties = CGImageSourceCopyPropertiesAtIndex(source, index, nil) as? [CFString: Any]
        let dpi = (properties?[kCGImagePropertyDPIWidth] as? NSNumber)?.doubleValue ?? 72
        return (image, CGFloat(min(max((dpi / 72).rounded(), 1), 4)))
    }
}
