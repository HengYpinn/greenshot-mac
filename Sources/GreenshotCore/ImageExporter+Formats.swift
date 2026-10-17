// Greenshot for Mac (Community) - an unofficial macOS port of Greenshot
// Copyright (C) 2026 Greenshot for Mac (Community) contributors
// Based on Greenshot, Copyright (C) 2007-2026 Thomas Braun, Jens Klingen, Robin Krom
// SPDX-License-Identifier: GPL-3.0-or-later

import CoreGraphics
import Foundation
import ImageIO

/// The formats written without ImageIO, so they don't depend on what the macOS version can encode: upstream's
/// `IconFileFormatHandler` (ICO), the TGA and PBM encoders of `ImageSharpFileFormatHandler`, and the PDF plugin's
/// `PdfFileFormatHandler`.
enum ImageFormatEncoders {
    // MARK: TGA

    /// A run-length encoded 32-bit Targa file (type 10) with straight alpha, first row at the top, and the TGA 2.0
    /// footer. Upstream's ImageSharp default is 24 bits; the alpha is kept here.
    static func tga(_ image: CGImage) throws -> Data {
        let width = image.width
        let height = image.height
        guard width <= 0xFFFF, height <= 0xFFFF else { throw ImageExportError.tooLarge(.tga, maxSide: 0xFFFF) }
        guard let pixels = straightBGRA(image) else { throw ImageExportError.encodingFailed(.tga) }
        var data = Data([0, 0, 10, 0, 0, 0, 0, 0, 0, 0, 0, 0])
        data.append(contentsOf: le16(width) + le16(height) + [32, 0x28])
        data.reserveCapacity(18 + width * height * 2)
        for row in 0..<height {
            appendRunLengthRow(pixels, from: row * width, count: width, to: &data)
        }
        data.append(contentsOf: [UInt8](repeating: 0, count: 8))
        data.append(contentsOf: Array("TRUEVISION-XFILE.".utf8) + [0])
        return data
    }

    /// One row in packets that never cross the row (the TGA spec's advice): runs of 2...128 equal pixels, and raw
    /// stretches of up to 128 pixels between them.
    static func appendRunLengthRow(_ pixels: [UInt32], from start: Int, count: Int, to data: inout Data) {
        let end = start + count
        var i = start
        var raw: [UInt32] = []
        func flushRaw() {
            guard !raw.isEmpty else { return }
            data.append(UInt8(raw.count - 1))
            for pixel in raw { data.append(contentsOf: bytes(pixel)) }
            raw.removeAll(keepingCapacity: true)
        }
        while i < end {
            var run = 1
            while i + run < end, run < 128, pixels[i + run] == pixels[i] { run += 1 }
            if run >= 2 {
                flushRaw()
                data.append(0x80 | UInt8(run - 1))
                data.append(contentsOf: bytes(pixels[i]))
                i += run
            } else {
                raw.append(pixels[i])
                if raw.count == 128 { flushRaw() }
                i += 1
            }
        }
        flushRaw()
    }

    /// B, G, R, A of a pixel packed as `straightBGRA` packs it.
    private static func bytes(_ pixel: UInt32) -> [UInt8] {
        [UInt8(pixel >> 24), UInt8(pixel >> 16 & 0xFF), UInt8(pixel >> 8 & 0xFF), UInt8(pixel & 0xFF)]
    }

    /// The pixels top row first, each packed as B G R A (straight, not premultiplied alpha).
    static func straightBGRA(_ image: CGImage) -> [UInt32]? {
        guard let context = AnnotationRenderer.makeContext(width: image.width, height: image.height), let data = context.data else {
            return nil
        }
        context.draw(image, in: CGRect(x: 0, y: 0, width: image.width, height: image.height))
        let rowBytes = context.bytesPerRow
        let bytes = data.bindMemory(to: UInt8.self, capacity: rowBytes * image.height)
        var result = [UInt32](repeating: 0, count: image.width * image.height)
        for y in 0..<image.height {
            for x in 0..<image.width {
                let i = y * rowBytes + x * 4
                let alpha = bytes[i + 3]
                let red = ImageEffects.unpremultiply(bytes[i], alpha: max(alpha, 1))
                let green = ImageEffects.unpremultiply(bytes[i + 1], alpha: max(alpha, 1))
                let blue = ImageEffects.unpremultiply(bytes[i + 2], alpha: max(alpha, 1))
                let packed: UInt32 = UInt32(blue) << 24 | UInt32(green) << 16 | UInt32(red) << 8
                result[y * image.width + x] = alpha == 0 ? 0 : packed | UInt32(alpha)
            }
        }
        return result
    }

    // MARK: PBM

    /// A binary Netpbm pixmap ("P6", 8 bits per color) of the image on white. ImageIO's own writer makes the text
    /// form, twelve bytes a pixel, and older macOS versions have none.
    static func pbm(_ image: CGImage) throws -> Data {
        let width = image.width
        let height = image.height
        guard let context = CGContext(data: nil, width: width, height: height, bitsPerComponent: 8, bytesPerRow: 0,
                                      space: CGColorSpace(name: CGColorSpace.sRGB)!,
                                      bitmapInfo: CGImageAlphaInfo.noneSkipLast.rawValue),
              let pixels = context.data else { throw ImageExportError.encodingFailed(.pbm) }
        let rect = CGRect(x: 0, y: 0, width: width, height: height)
        context.setFillColor(CGColor(gray: 1, alpha: 1))
        context.fill(rect)
        context.draw(image, in: rect)
        let rowBytes = context.bytesPerRow
        let bytes = pixels.bindMemory(to: UInt8.self, capacity: rowBytes * height)
        var data = Data("P6\n\(width) \(height)\n255\n".utf8)
        data.reserveCapacity(data.count + width * height * 3)
        for y in 0..<height {
            for x in 0..<width {
                let i = y * rowBytes + x * 4
                data.append(contentsOf: [bytes[i], bytes[i + 1], bytes[i + 2]])
            }
        }
        return data
    }

    // MARK: ICO

    /// Upstream `IconFileFormatHandler.TrySaveToStream`: one icon of the best size (16, 32 or 48 when the image fits,
    /// else 256), the image fitted into the square on transparency, stored as PNG.
    static func ico(_ image: CGImage) throws -> Data {
        let side = iconSize(for: CGSize(width: image.width, height: image.height))
        guard let icon = fitted(image, into: side) else { throw ImageExportError.encodingFailed(.ico) }
        let png = try ImageExporter.data(for: icon, options: ImageOutputOptions(format: .png))
        var data = Data(le16(0) + le16(1) + le16(1))
        let size = UInt8(side == 256 ? 0 : side)
        data.append(contentsOf: [size, size, 0, 0] + le16(1) + le16(32) + le32(png.count) + le32(6 + 16))
        data.append(png)
        return data
    }

    /// The side of the icon: the first of 16, 32 and 48 that the image fits in, else 256.
    static func iconSize(for size: CGSize) -> Int {
        [16, 32, 48].first { CGFloat($0) >= size.width && CGFloat($0) >= size.height } ?? 256
    }

    /// The image scaled to fit a square of `side` pixels, centered on transparency.
    static func fitted(_ image: CGImage, into side: Int) -> CGImage? {
        if image.width == side && image.height == side { return image }
        guard let context = AnnotationRenderer.makeContext(width: side, height: side) else { return nil }
        let factor = min(CGFloat(side) / CGFloat(image.width), CGFloat(side) / CGFloat(image.height))
        let width = (CGFloat(image.width) * factor).rounded()
        let height = (CGFloat(image.height) * factor).rounded()
        context.interpolationQuality = .high
        context.draw(image, in: CGRect(x: ((CGFloat(side) - width) / 2).rounded(), y: ((CGFloat(side) - height) / 2).rounded(),
                                       width: width, height: height))
        return context.makeImage()
    }

    // MARK: PDF

    /// The PDF plugin's file format (`PdfFileFormatHandler`, `PdfDocumentWriter`): one page laid out by the PDF
    /// settings, white under the image, like `PdfLayout.write`.
    static func pdf(_ image: CGImage, options: ImageOutputOptions) throws -> Data {
        let scale = max(options.scale, 1)
        let layout = PdfLayout.layout(image: CGSize(width: CGFloat(image.width) / scale, height: CGFloat(image.height) / scale),
                                      settings: options.pdf)
        let data = NSMutableData()
        var mediaBox = CGRect(origin: .zero, size: layout.pageSize)
        let info: [CFString: Any] = [kCGPDFContextTitle: options.title, kCGPDFContextCreator: ImageExporter.software]
        guard let consumer = CGDataConsumer(data: data as CFMutableData),
              let context = CGContext(consumer: consumer, mediaBox: &mediaBox, info as CFDictionary) else {
            throw ImageExportError.encodingFailed(.pdf)
        }
        context.beginPDFPage(nil)
        context.setFillColor(CGColor(gray: 1, alpha: 1))
        context.fill(mediaBox)
        context.interpolationQuality = .high
        context.draw(image, in: layout.imageRect)
        context.endPDFPage()
        context.closePDF()
        return data as Data
    }

    // MARK: Helpers

    static func le16(_ value: Int) -> [UInt8] { [UInt8(value & 0xFF), UInt8(value >> 8 & 0xFF)] }
    static func le32(_ value: Int) -> [UInt8] { le16(value & 0xFFFF) + le16(value >> 16 & 0xFFFF) }
}
