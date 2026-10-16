// Greenshot for Mac (Community) - an unofficial macOS port of Greenshot
// Copyright (C) 2026 Greenshot for Mac (Community) contributors
// SPDX-License-Identifier: GPL-3.0-or-later

import AppKit
import ImageIO

@MainActor
enum Clipboard {
    /// Puts the image on the clipboard as PNG and TIFF (upstream writes PNG and DIB).
    static func copy(_ image: CGImage) {
        let rep = NSBitmapImageRep(cgImage: image)
        let item = NSPasteboardItem()
        if let png = rep.representation(using: .png, properties: [:]) { item.setData(png, forType: .png) }
        if let tiff = rep.tiffRepresentation { item.setData(tiff, forType: .tiff) }
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

@MainActor
enum Printing {
    static func print(_ image: CGImage, scale: CGFloat, window: NSWindow?) {
        let size = NSSize(width: CGFloat(image.width) / scale, height: CGFloat(image.height) / scale)
        let view = NSImageView(frame: NSRect(origin: .zero, size: size))
        view.image = NSImage(cgImage: image, size: size)
        view.imageScaling = .scaleProportionallyDown
        let info = (NSPrintInfo.shared.copy() as? NSPrintInfo) ?? NSPrintInfo()
        info.horizontalPagination = .fit
        info.verticalPagination = .fit
        info.isHorizontallyCentered = true
        info.isVerticallyCentered = true
        info.orientation = size.width > size.height ? .landscape : .portrait
        let operation = NSPrintOperation(view: view, printInfo: info)
        operation.showsPrintPanel = true
        operation.showsProgressPanel = true
        NSApp.activate()
        if let window {
            operation.runModal(for: window, delegate: nil, didRun: nil, contextInfo: nil)
        } else {
            operation.run()
        }
    }
}
