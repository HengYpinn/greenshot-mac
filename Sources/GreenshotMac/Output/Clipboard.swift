// Greenshot for Mac (Community) - an unofficial macOS port of Greenshot
// Copyright (C) 2026 Greenshot for Mac (Community) contributors
// SPDX-License-Identifier: GPL-3.0-or-later

import AppKit
import GreenshotCore
import ImageIO

@MainActor
enum Clipboard {
    /// The formats a copy writes (Settings › Expert, upstream `ClipboardFormats`); set by the app delegate.
    static var formats: () -> [ClipboardFormat] = { ClipboardFormat.defaults }

    /// Puts the image on the clipboard in the chosen formats (default PNG and TIFF; upstream writes PNG and DIB).
    /// `scale` is the pixels per point: it sets the point size, so other apps paste a Retina capture at its real
    /// size and `image()` reads the scale back.
    static func copy(_ image: CGImage, scale: CGFloat) {
        let rep = NSBitmapImageRep(cgImage: image)
        rep.size = NSSize(width: CGFloat(image.width) / scale, height: CGFloat(image.height) / scale)
        var chosen = Set(formats())
        if chosen.isEmpty { chosen = [.png] }
        let item = NSPasteboardItem()
        let png = rep.representation(using: .png, properties: [:])
        if chosen.contains(.png), let png { item.setData(png, forType: .png) }
        if chosen.contains(.tiff), let tiff = rep.tiffRepresentation { item.setData(tiff, forType: .tiff) }
        if chosen.contains(.jpeg), let jpeg = try? ImageExporter.data(for: image, format: .jpg, quality: 90, scale: scale) {
            item.setData(jpeg, forType: NSPasteboard.PasteboardType("public.jpeg"))
        }
        if chosen.contains(.html), let png {
            let html = DestinationSupport.htmlSnippet(png: png, width: Int(rep.size.width.rounded()), height: Int(rep.size.height.rounded()))
            item.setString(html, forType: .html)
        }
        let pasteboard = NSPasteboard.general
        pasteboard.clearContents()
        pasteboard.writeObjects([item])
    }

    static func copy(text: String) {
        let pasteboard = NSPasteboard.general
        pasteboard.clearContents()
        pasteboard.setString(text, forType: .string)
    }

    /// The image on the clipboard at its full resolution, with its pixels per point.
    static func image() -> (image: CGImage, scale: CGFloat)? {
        guard let image = NSImage(pasteboard: .general) else { return nil }
        return ImageLoader.bitmap(of: image)
    }
}

enum ImageLoader {
    /// An image file with its pixels per point, taken from its resolution (144 dpi screenshots are Retina, 2x).
    static func load(_ url: URL) -> (image: CGImage, scale: CGFloat)? {
        guard let source = CGImageSourceCreateWithURL(url as CFURL, nil),
              let image = CGImageSourceCreateImageAtIndex(source, 0, nil) else { return nil }
        let properties = CGImageSourceCopyPropertiesAtIndex(source, 0, nil) as? [CFString: Any]
        let dpi = (properties?[kCGImagePropertyDPIWidth] as? NSNumber)?.doubleValue ?? 72
        return (image, CGFloat(min(max((dpi / 72).rounded(), 1), 4)))
    }

    static func bitmap(of image: NSImage) -> (image: CGImage, scale: CGFloat)? {
        let best = image.representations
            .compactMap { $0 as? NSBitmapImageRep }
            .max { $0.pixelsWide < $1.pixelsWide }
        if let best, let cgImage = best.cgImage {
            let scale = best.size.width > 0 ? CGFloat(best.pixelsWide) / best.size.width : 1
            return (cgImage, max(scale.rounded(), 1))
        }
        var rect = CGRect(origin: .zero, size: image.size)
        guard let cgImage = image.cgImage(forProposedRect: &rect, context: nil, hints: nil) else { return nil }
        return (cgImage, 1)
    }
}
