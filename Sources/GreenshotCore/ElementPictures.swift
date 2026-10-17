// Greenshot for Mac (Community) - an unofficial macOS port of Greenshot
// Copyright (C) 2026 Greenshot for Mac (Community) contributors
// Based on Greenshot, Copyright (C) 2007-2026 Thomas Braun, Jens Klingen, Robin Krom
// SPDX-License-Identifier: GPL-3.0-or-later

import CoreGraphics
import Foundation
import ImageIO

/// What a dropped or pasted file or download becomes: an image element's picture, or an SVG element's SVG.
public enum ElementPicture {
    case picture(CGImage, scale: CGFloat)
    case svg(Data)
}

/// Reads the pictures that are dropped or pasted on the editor as image elements.
public enum ElementPictures {
    /// The file at `url` as an SVG element's SVG (upstream `SvgFileFormatHandler.LoadDrawablesFromStream`) or an image
    /// element's picture.
    public static func content(of url: URL) -> ElementPicture? {
        if ElementSvg.isSVGFile(url) {
            guard let data = ElementSvg.data(ofFile: url), ElementSvg.size(of: data) != nil else { return nil }
            return .svg(data)
        }
        return load(url).map { .picture($0.image, scale: $0.scale) }
    }

    /// `data` as an SVG element's SVG or an image element's picture.
    public static func content(of data: Data) -> ElementPicture? {
        if ElementSvg.isSVG(data) {
            return ElementSvg.size(of: data) != nil ? .svg(data) : nil
        }
        return load(data: data).map { .picture($0.image, scale: $0.scale) }
    }

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
