// Greenshot for Mac (Community) - an unofficial macOS port of Greenshot
// Copyright (C) 2026 Greenshot for Mac (Community) contributors
// Based on Greenshot, Copyright (C) 2007-2026 Thomas Braun, Jens Klingen, Robin Krom
// SPDX-License-Identifier: GPL-3.0-or-later

import AppKit
import CoreGraphics
import Foundation
import UniformTypeIdentifiers

private let log = Log("Editor")

/// SVG pictures (upstream `Greenshot.Editor/FileFormatHandlers/SvgFileFormatHandler.cs` and `Drawing/SvgContainer.cs`):
/// opened as a capture they are drawn into pixels; inserted into the editor they stay an SVG element that is drawn
/// from the SVG at every size, so it stays sharp. macOS draws SVG itself (`NSImage`); pictures the SVG links to on the
/// web or on disk are not loaded (upstream turns external resources off too), pictures inside it (`data:`) are.
public enum ElementSvg {
    /// The most SVG data that is read: far more than any drawing needs, and a limit for files from elsewhere.
    public static let maxBytes = 20 * 1024 * 1024
    /// The longest side of a drawn SVG, pixels (where image decoders stop, like the WebP limit).
    static let maxSide: CGFloat = 16384
    /// The most pixels a drawn SVG gets (64 megapixels, 256 MB).
    static let maxPixels: CGFloat = 64 * 1024 * 1024
    /// The pixels per point an SVG file is opened with: the Retina default (upstream draws it at its own size).
    static let openScale: CGFloat = 2
    /// The fewest and most pixels per point an SVG file is opened with: a huge one is drawn smaller, to the limits.
    static let minOpenScale: CGFloat = 0.1
    static let maxOpenScale: CGFloat = 8

    /// Whether this Mac can draw SVG (`NSImage` reads `public.svg-image`; checked once).
    public static let isSupported: Bool = NSImage.imageUnfilteredTypes.contains(UTType.svg.identifier)

    /// Whether `data` looks like an SVG: it starts with a tag (after a byte order mark and spaces) and has an `<svg`
    /// tag near the start (after an XML declaration, comments or a doctype).
    public static func isSVG(_ data: Data) -> Bool {
        guard !data.isEmpty, data.count <= maxBytes else { return false }
        var head = Data(data.prefix(4096))
        if head.starts(with: [0xEF, 0xBB, 0xBF]) { head = head.dropFirst(3) }
        guard let first = head.first(where: { ![0x20, 0x09, 0x0A, 0x0D].contains($0) }), first == UInt8(ascii: "<") else {
            return false
        }
        let text = String(decoding: head, as: UTF8.self)
        return text.range(of: "<svg", options: .caseInsensitive) != nil
    }

    /// Whether the file at `url` is an SVG by its name.
    public static func isSVGFile(_ url: URL) -> Bool {
        url.isFileURL && UTType(filenameExtension: url.pathExtension)?.conforms(to: .svg) == true
    }

    /// The data of the SVG file at `url`; nil when it isn't one, is bigger than `maxBytes` or can't be read.
    public static func data(ofFile url: URL) -> Data? {
        guard isSVGFile(url) else { return nil }
        let size = (try? url.resourceValues(forKeys: [.fileSizeKey]))?.fileSize ?? 0
        guard size <= maxBytes, let data = try? Data(contentsOf: url), isSVG(data) else { return nil }
        return data
    }

    /// The SVG as an image that draws itself at any size; nil when it isn't SVG, this Mac can't draw SVG, or it has
    /// no size.
    static func image(_ data: Data) -> NSImage? {
        guard isSupported, isSVG(data), let image = NSImage(data: data) else { return nil }
        let size = image.size
        guard size.width.isFinite, size.height.isFinite, size.width > 0, size.height > 0 else { return nil }
        return image
    }

    /// The SVG's own size in points: its width and height, else its viewBox (upstream `SvgDocument.Width/Height`).
    public static func size(of data: Data) -> CGSize? {
        image(data)?.size
    }

    /// The SVG drawn into `pixelSize` (made smaller to stay within the limits), transparent where it draws nothing.
    public static func render(_ data: Data, pixelSize: CGSize) -> CGImage? {
        render(image(data), pixelSize: pixelSize)
    }

    static func render(_ image: NSImage?, pixelSize: CGSize) -> CGImage? {
        // `limited` keeps a size that isn't finite as it is, and `Int` traps on it.
        guard let image, pixelSize.width.isFinite, pixelSize.height.isFinite else { return nil }
        let size = limited(pixelSize)
        let width = Int(size.width.rounded())
        let height = Int(size.height.rounded())
        guard width > 0, height > 0, let context = AnnotationRenderer.makeContext(width: width, height: height) else { return nil }
        let previous = NSGraphicsContext.current
        NSGraphicsContext.current = NSGraphicsContext(cgContext: context, flipped: false)
        image.draw(in: NSRect(x: 0, y: 0, width: width, height: height), from: .zero, operation: .sourceOver, fraction: 1)
        NSGraphicsContext.current = previous
        return context.makeImage()
    }

    /// `size` made smaller, keeping its aspect ratio, so it has at most `maxSide` pixels a side and `maxPixels` in all.
    static func limited(_ size: CGSize) -> CGSize {
        let width = max(size.width, 1)
        let height = max(size.height, 1)
        let sideFactor = min(1, maxSide / max(width, height))
        let areaFactor = min(1, (maxPixels / (width * height)).squareRoot())
        let factor = min(sideFactor, areaFactor)
        // Made smaller: rounded down, so it stays within the limits.
        let rule: FloatingPointRoundingRule = factor < 1 ? .down : .toNearestOrAwayFromZero
        return CGSize(width: max((width * factor).rounded(rule), 1), height: max((height * factor).rounded(rule), 1))
    }

    /// An SVG file drawn into a picture for opening it as a capture, at 2 pixels per point (fewer when that would
    /// pass the limits); nil when `url` is not an SVG this Mac can draw (upstream `SvgFileFormatHandler.TryLoadFromStream`).
    public static func rasterizedFile(_ url: URL) -> (image: CGImage, scale: CGFloat)? {
        guard isSVGFile(url) else { return nil }
        guard let data = data(ofFile: url), let image = image(data) else {
            log.info("Can't draw the SVG \(url.lastPathComponent)")
            return nil
        }
        let points = image.size
        let pixels = limited(CGSize(width: points.width * openScale, height: points.height * openScale))
        guard let picture = render(image, pixelSize: pixels) else { return nil }
        // An SVG of absurd size (1e300 points is drawn into a few pixels) gets no absurd pixels per point.
        let scale = min(max(CGFloat(picture.width) / points.width, minOpenScale), maxOpenScale)
        return (picture, scale)
    }

    // MARK: Drawing elements

    private final class Decoded {
        let byteCount: Int
        let image: NSImage

        init(byteCount: Int, image: NSImage) {
            self.byteCount = byteCount
            self.image = image
        }
    }

    private final class Drawn {
        let image: CGImage

        init(image: CGImage) {
            self.image = image
        }
    }

    /// The SVG of each element, read once; an element's SVG never changes.
    private static let decoded = NSCache<NSUUID, Decoded>()
    /// The SVG of each element drawn at the sizes it was last shown, so redrawing the canvas doesn't draw it again. A
    /// resize draws it at every step, so only the newest few sizes are kept.
    private static let drawn: NSCache<NSString, Drawn> = {
        let cache = NSCache<NSString, Drawn>()
        cache.countLimit = 32
        return cache
    }()

    /// The SVG of element `a` drawn at `pixelSize`.
    static func picture(of a: Annotation, pixelSize: CGSize) -> CGImage? {
        // An element can be any size (a file can say 1e300): nothing for sizes that aren't finite or round to nothing,
        // and huge ones at the size `render` draws them, which is whole pixels within the limits.
        guard let data = a.imageData, pixelSize.width.isFinite, pixelSize.height.isFinite,
              pixelSize.width.rounded() >= 1, pixelSize.height.rounded() >= 1 else { return nil }
        let size = limited(pixelSize)
        let width = Int(size.width)
        let height = Int(size.height)
        let key = "\(a.id.uuidString) \(data.count) \(width)x\(height)" as NSString
        if let cached = drawn.object(forKey: key) { return cached.image }
        let id = a.id as NSUUID
        var svg = decoded.object(forKey: id).flatMap { $0.byteCount == data.count ? $0.image : nil }
        if svg == nil, let image = image(data) {
            decoded.setObject(Decoded(byteCount: data.count, image: image), forKey: id)
            svg = image
        }
        guard let picture = render(svg, pixelSize: CGSize(width: width, height: height)) else { return nil }
        drawn.setObject(Drawn(image: picture), forKey: key)
        return picture
    }
}

extension Annotation {
    /// An SVG element (upstream `SvgContainer`) showing `data`, its top left at `origin`, at the SVG's own size on an
    /// image with `documentScale` pixels per point, made smaller to fit in `fitting` (image pixels) when it is bigger.
    /// Nil when `data` is not an SVG this Mac can draw.
    public static func svg(_ data: Data, at origin: CGPoint, documentScale: CGFloat, fitting limit: CGSize? = nil) -> Annotation? {
        guard let points = ElementSvg.size(of: data) else { return nil }
        var size = CGSize(width: points.width * documentScale, height: points.height * documentScale)
        if let limit, limit.width > 0, limit.height > 0, size.width > limit.width || size.height > limit.height {
            let shrink = min(limit.width / size.width, limit.height / size.height)
            size = CGSize(width: size.width * shrink, height: size.height * shrink)
        }
        return Annotation(kind: .svg, start: origin, end: CGPoint(x: origin.x + size.width, y: origin.y + size.height),
                          imageData: data)
    }
}

extension AnnotationRenderer {
    /// Upstream `VectorGraphicsContainer.Draw`: the SVG drawn at the size of the element's box, so it is sharp at
    /// every size (upstream `SvgContainer.ComputeBitmap` draws it at `Width` × `Height`).
    static func drawSvg(_ a: Annotation, in context: CGContext, scale: CGFloat) {
        let box = a.bounds
        guard box.width >= 1, box.height >= 1, let picture = ElementSvg.picture(of: a, pixelSize: box.size) else { return }
        context.interpolationQuality = .high
        drawUpright(picture, in: box, context: context)
    }
}
