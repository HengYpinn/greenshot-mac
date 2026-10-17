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

    /// The image on the clipboard at its full resolution, with its pixels per point, upright: a copied image file,
    /// image data, or a `data:` image of copied HTML (`ImagePasteboard`).
    static func image() -> (image: CGImage, scale: CGFloat)? {
        ImagePasteboard.image(from: .general)
    }
}

enum ImageLoader {
    /// An image file with its pixels per point, taken from its resolution (144 dpi screenshots are Retina, 2x), turned
    /// upright by its EXIF orientation; for icons the biggest size (`ImageFileLoader`).
    static func load(_ url: URL) -> (image: CGImage, scale: CGFloat)? {
        ImageFileLoader.load(url)
    }

    static func bitmap(of image: NSImage) -> (image: CGImage, scale: CGFloat)? {
        ImagePasteboard.bitmap(of: image)
    }

    /// The image an HTML copy on the clipboard points to (`<img src="https://…">`), downloaded (upstream
    /// `ClipboardService.GetImageAsync`): the first source that gives an image. Nil when there is none.
    static func downloadedHTMLImage() async -> (image: CGImage, scale: CGFloat)? {
        let urls = await MainActor.run { ImagePasteboard.webImageURLs(on: .general) }
        for url in urls {
            if let image = await ImagePasteboard.downloadImage(from: url) { return image }
        }
        return nil
    }
}
