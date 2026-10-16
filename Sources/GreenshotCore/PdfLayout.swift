// Greenshot for Mac (Community) - an unofficial macOS port of Greenshot
// Copyright (C) 2026 Greenshot for Mac (Community) contributors
// Based on Greenshot, Copyright (C) 2007-2026 Thomas Braun, Jens Klingen, Robin Krom
// SPDX-License-Identifier: GPL-3.0-or-later

import CoreGraphics
import Foundation

/// The page of a one-page PDF and where the screenshot goes on it: port of `CalculateLayout` in upstream
/// `Greenshot.Plugin.Pdf/PdfDocumentWriter.cs` and its `PdfPageSizes`. All sizes are PDF points (1/72 inch);
/// margins and the custom page size are in the settings' `unit`.
public struct PdfLayout: Equatable, Sendable {
    public var pageSize: CGSize
    /// The image's rectangle, in PDF coordinates (origin bottom left).
    public var imageRect: CGRect

    public init(pageSize: CGSize, imageRect: CGRect) {
        self.pageSize = pageSize
        self.imageRect = imageRect
    }

    /// The preset paper sizes in millimetres, portrait (upstream `PdfPageSizes.ForPreset`).
    public static func presetMillimetres(_ size: PDFSettings.PageSize) -> CGSize? {
        switch size {
        case .a3: return CGSize(width: 297, height: 420)
        case .a4: return CGSize(width: 210, height: 297)
        case .a5: return CGSize(width: 148, height: 210)
        case .a6: return CGSize(width: 105, height: 148)
        case .letter: return CGSize(width: 215.9, height: 279.4)
        case .image, .custom: return nil
        }
    }

    /// `image` is the screenshot's size in points (pixels / scale, i.e. 72 dpi per point).
    public static func layout(image: CGSize, settings: PDFSettings) -> PdfLayout {
        let unit = settings.unit.points
        let left = max(settings.marginLeft, 0) * unit
        let right = max(settings.marginRight, 0) * unit
        let top = max(settings.marginTop, 0) * unit
        let bottom = max(settings.marginBottom, 0) * unit
        let millimetre = PDFSettings.Unit.mm.points

        let page: CGSize
        switch settings.pageSize {
        case .image:
            page = CGSize(width: image.width + left + right, height: image.height + top + bottom)
        case .custom:
            page = CGSize(width: max(settings.customWidth, 1) * unit, height: max(settings.customHeight, 1) * unit)
        case .a3, .a4, .a5, .a6, .letter:
            let mm = presetMillimetres(settings.pageSize)!
            page = CGSize(width: mm.width * millimetre, height: mm.height * millimetre)
        }

        let available = CGSize(width: max(page.width - left - right, 1), height: max(page.height - top - bottom, 1))
        var scale = image.width > 0 && image.height > 0 ? min(available.width / image.width, available.height / image.height) : 1
        if settings.pageSize == .image || settings.scaling == .shrinkToFit {
            scale = min(1, scale)
        }
        let size = CGSize(width: image.width * scale, height: image.height * scale)
        let x = left + (available.width - size.width) / 2
        let y = page.height - top - (available.height - size.height) / 2 - size.height
        return PdfLayout(pageSize: page, imageRect: CGRect(origin: CGPoint(x: x, y: y), size: size))
    }

    /// Writes a one-page PDF with the image laid out by `layout(image:settings:)`; formats without transparency
    /// would print a black background, so the page is white under the image.
    public static func write(_ image: CGImage, scale: CGFloat, settings: PDFSettings, title: String, to url: URL) throws {
        let layout = Self.layout(image: CGSize(width: CGFloat(image.width) / scale, height: CGFloat(image.height) / scale),
                                 settings: settings)
        try FileManager.default.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
        var mediaBox = CGRect(origin: .zero, size: layout.pageSize)
        let info: [CFString: Any] = [kCGPDFContextTitle: title, kCGPDFContextCreator: "Greenshot for Mac (Community)"]
        guard let context = CGContext(url as CFURL, mediaBox: &mediaBox, info as CFDictionary) else {
            throw CocoaError(.fileWriteUnknown, userInfo: [NSFilePathErrorKey: url.path])
        }
        context.beginPDFPage(nil)
        context.setFillColor(CGColor(gray: 1, alpha: 1))
        context.fill(mediaBox)
        context.interpolationQuality = .high
        context.draw(image, in: layout.imageRect)
        context.endPDFPage()
        context.closePDF()
    }
}
