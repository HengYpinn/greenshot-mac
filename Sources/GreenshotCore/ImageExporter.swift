// Greenshot for Mac (Community) - an unofficial macOS port of Greenshot
// Copyright (C) 2026 Greenshot for Mac (Community) contributors
// SPDX-License-Identifier: GPL-3.0-or-later

import CoreGraphics
import Foundation
import ImageIO
import UniformTypeIdentifiers

/// The file formats Greenshot writes (upstream `OutputFileFormat` and the formats of its file format handlers:
/// `DefaultFileFormatHandler`, `ImageSharpFileFormatHandler` (TGA, PBM), `IconFileFormatHandler` and the PDF plugin's
/// `PdfFileFormatHandler`), and the `.greenshot` file of `GreenshotFileFormatHandler`.
public enum ImageFormat: String, Codable, CaseIterable, Sendable {
    case png, jpg, bmp, gif, tiff, webp, ico, tga, pbm, pdf
    /// A `.greenshot` file (`GreenshotFile`): the screenshot whose elements stay editable (upstream
    /// `OutputFormat.greenshot`). Only files are saved in it; what goes to another app is a plain image (`plainImage`,
    /// `imageFormats`).
    case greenshot

    public var fileExtension: String { rawValue }

    public var utType: UTType {
        switch self {
        case .png: return .png
        case .jpg: return .jpeg
        case .bmp: return .bmp
        case .gif: return .gif
        case .tiff: return .tiff
        case .webp: return .webP
        case .ico: return .ico
        case .tga: return UTType("com.truevision.tga-image") ?? UTType(filenameExtension: "tga") ?? .image
        case .pbm: return UTType("public.pbm") ?? UTType(filenameExtension: "pbm") ?? .image
        case .pdf: return .pdf
        case .greenshot:
            // The type declared in the app's Info.plist, or (in a `swift build` without the app bundle) the type macOS
            // makes up for the extension.
            return UTType(GreenshotFile.typeIdentifier)
                ?? UTType(filenameExtension: GreenshotFile.fileExtension, conformingTo: .png) ?? .png
        }
    }

    public var displayName: String {
        switch self {
        case .png: return "PNG"
        case .jpg: return "JPEG"
        case .bmp: return "BMP"
        case .gif: return "GIF"
        case .tiff: return "TIFF"
        case .webp: return "WebP (lossless)"
        case .ico: return "ICO (icon)"
        case .tga: return "TGA (Targa)"
        case .pbm: return "PBM (Netpbm)"
        case .pdf: return "PDF"
        case .greenshot: return "Greenshot (editable)"
        }
    }

    /// The MIME type (upstream's `RegisterFileFormat`).
    public var mimeType: String {
        switch self {
        case .png: return "image/png"
        case .jpg: return "image/jpeg"
        case .bmp: return "image/bmp"
        case .gif: return "image/gif"
        case .tiff: return "image/tiff"
        case .webp: return "image/webp"
        case .ico: return "image/x-icon"
        case .tga: return "image/x-tga"
        case .pbm: return "image/x-portable-bitmap"
        case .pdf: return "application/pdf"
        case .greenshot: return "application/octet-stream"
        }
    }

    /// Formats without transparency get a white background (a PDF page is white under the image anyway).
    var supportsAlpha: Bool {
        switch self {
        case .png, .tiff, .gif, .webp, .ico, .tga, .pdf, .greenshot: return true
        case .jpg, .bmp, .pbm: return false
        }
    }

    public init?(fileExtension: String) {
        switch fileExtension.lowercased() {
        case "png": self = .png
        case "jpg", "jpeg": self = .jpg
        case "bmp": self = .bmp
        case "gif": self = .gif
        case "tif", "tiff": self = .tiff
        case "webp": self = .webp
        case "ico": self = .ico
        case "tga": self = .tga
        case "pbm": self = .pbm
        case "pdf": self = .pdf
        case GreenshotFile.fileExtension: self = .greenshot
        default: return nil
        }
    }

    /// The formats of plain images, all but `.greenshot`: what external commands, Open With and the other apps get.
    public static var imageFormats: [ImageFormat] { allCases.filter { $0 != .greenshot } }

    /// The format for a plain image: a `.greenshot` file is for this app (and opens as an image in Greenshot for
    /// Windows), so another app gets PNG instead (upstream refuses the greenshot format where a rendered image is
    /// needed, `ImageIO.SaveRenderedImage`).
    public var plainImage: ImageFormat { self == .greenshot ? .png : self }
}

public enum ImageExportError: Error, LocalizedError {
    case encodingFailed(ImageFormat)
    /// The format can't store an image this big (WebP: 16384 pixels a side, TGA: 65535).
    case tooLarge(ImageFormat, maxSide: Int)

    public var errorDescription: String? {
        switch self {
        case .encodingFailed(let format): return "The image could not be encoded as \(format.displayName)."
        case let .tooLarge(format, maxSide):
            return "The image is too big for \(format.displayName): it can be at most \(maxSide) pixels wide and high."
        }
    }
}

/// Writes images in the formats of `ImageFormat`: upstream `ImageIO.SaveToStream` with the output settings of
/// `ImageIO.CreateImageForOutput` (`Greenshot.Base/Core/ImageIO.cs`) and the encoders of the file format handlers.
public enum ImageExporter {
    /// The "Software" tag written into PNG, JPEG and TIFF files (upstream `ImageIO.AddTag` and the "Software" text
    /// of `ImageSharpFileFormatHandler`): the app's name and, in the app bundle, its version.
    public static var software: String {
        let name = "Greenshot for Mac (Community)"
        guard let version = Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String,
              !version.isEmpty, !version.hasPrefix("__") else { return name }
        return "\(name) \(version)"
    }

    /// Encodes `image` as `options` say: colour reduction (`reduceColors`, `autoReduceColors`, always for GIF), the
    /// resolution, the JPEG quality and the "Software" tag.
    public static func data(for image: CGImage, options: ImageOutputOptions) throws -> Data {
        let format = options.format
        switch format {
        case .greenshot:
            // Only the image: the background of a file without elements (a fresh capture). The editor writes its
            // elements with `GreenshotFile.Contents(of:)`.
            let title = options.title.isEmpty ? nil : options.title
            return try GreenshotFile.Contents(image: image, scale: options.scale, title: title).encoded()
        case .pdf: return try ImageFormatEncoders.pdf(image, options: options)
        case .tga: return try ImageFormatEncoders.tga(prepared(image, options: options))
        case .pbm: return try ImageFormatEncoders.pbm(prepared(image, options: options))
        case .ico: return try ImageFormatEncoders.ico(prepared(image, options: options))
        case .webp: return try ImageWebPEncoder.encode(prepared(image, options: options))
        default: break
        }
        let data = NSMutableData()
        guard let destination = CGImageDestinationCreateWithData(data, format.utType.identifier as CFString, 1, nil) else {
            throw ImageExportError.encodingFailed(format)
        }
        let source = prepared(image, options: options)
        var properties: [CFString: Any] = [
            kCGImagePropertyDPIWidth: 72 * options.scale,
            kCGImagePropertyDPIHeight: 72 * options.scale,
        ]
        switch format {
        case .png:
            properties[kCGImagePropertyPNGDictionary] = [kCGImagePropertyPNGSoftware: software]
        case .jpg:
            properties[kCGImageDestinationLossyCompressionQuality] = Double(min(max(options.jpegQuality, 1), 100)) / 100
            properties[kCGImagePropertyTIFFDictionary] = [kCGImagePropertyTIFFSoftware: software]
        case .tiff:
            properties[kCGImagePropertyTIFFDictionary] = [kCGImagePropertyTIFFSoftware: software]
        default:
            break
        }
        CGImageDestinationAddImage(destination, source, properties as CFDictionary)
        guard CGImageDestinationFinalize(destination) else { throw ImageExportError.encodingFailed(format) }
        return data as Data
    }

    /// Writes the image as `options` say, creating missing folders on the way. A PDF without a title gets the file's
    /// name as its title.
    public static func write(_ image: CGImage, to url: URL, options: ImageOutputOptions) throws {
        var options = options
        if options.title.isEmpty { options.title = url.deletingPathExtension().lastPathComponent }
        let encoded = try data(for: image, options: options)
        try FileManager.default.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
        try encoded.write(to: url, options: .atomic)
    }

    /// `quality` is 0–100 and only used for JPEG. `scale` is the capture's pixels per point: it is written as the
    /// resolution (72 dpi × scale, so 144 dpi for Retina), which is how `ImageLoader` and Preview find the real size.
    /// `maxColors` reduces the colours to that many (upstream `OutputFileReduceColors`).
    public static func data(for image: CGImage, format: ImageFormat, quality: Int = 80, scale: CGFloat = 1,
                            maxColors: Int? = nil) throws -> Data {
        try data(for: image, options: options(format, quality: quality, scale: scale, maxColors: maxColors))
    }

    /// Writes the image, creating missing folders on the way.
    public static func write(_ image: CGImage, to url: URL, format: ImageFormat, quality: Int = 80, scale: CGFloat = 1,
                             maxColors: Int? = nil) throws {
        try write(image, to: url, options: options(format, quality: quality, scale: scale, maxColors: maxColors))
    }

    private static func options(_ format: ImageFormat, quality: Int, scale: CGFloat, maxColors: Int?) -> ImageOutputOptions {
        ImageOutputOptions(format: format, jpegQuality: quality, scale: scale, reduceColors: maxColors != nil,
                           reduceColorsTo: maxColors ?? 256)
    }

    // MARK: - Output settings

    /// The image as it is encoded: on white for formats without transparency, then with its colours reduced
    /// (upstream `CreateImageForOutput`).
    static func prepared(_ image: CGImage, options: ImageOutputOptions) -> CGImage {
        let format = options.format
        let source = format.supportsAlpha ? image : (opaque(image) ?? image)
        return reducedColors(source, options: options)
    }

    /// Upstream `CreateImageForOutput`'s colour reduction: with "Reduce colours" (always for GIF, which has 256 colours
    /// at most) the image gets at most `reduceColorsTo` colours; with "Auto reduce colours" an image without
    /// transparency that has fewer than 256 colours does too. An opaque result becomes an 8-bit palette image, so PNG,
    /// TIFF and GIF files are written with a palette and get smaller, like upstream's 8-bit images. Images with
    /// transparency keep 32 bits (a palette image here has no alpha). JPEG keeps all its colours.
    static func reducedColors(_ image: CGImage, options: ImageOutputOptions) -> CGImage {
        let format = options.format
        guard format.reducesColors else { return image }
        let limit = min(max(options.reduceColorsTo, 2), 256)
        let forced = options.reduceColors || format == .gif
        guard forced || options.autoReduceColors else { return image }
        let opaque = !ImageOperations.hasTransparency(image)
        if !forced {
            // Upstream counts the colours and only reduces when there are fewer than 256 (and no alpha).
            guard opaque, ImageEffects.colorCount(image, atMost: 255) <= 255 else { return image }
        }
        let reduced = ColorQuantizer.reduce(image, to: limit)
        guard opaque, format.writesPalette else { return reduced }
        return ColorQuantizer.indexed(reduced) ?? reduced
    }

    /// The image on white, for formats without an alpha channel.
    static func opaque(_ image: CGImage) -> CGImage? {
        guard let context = CGContext(data: nil, width: image.width, height: image.height, bitsPerComponent: 8, bytesPerRow: 0,
                                      space: CGColorSpace(name: CGColorSpace.sRGB)!,
                                      bitmapInfo: CGImageAlphaInfo.noneSkipLast.rawValue) else { return nil }
        let rect = CGRect(x: 0, y: 0, width: image.width, height: image.height)
        context.setFillColor(CGColor(gray: 1, alpha: 1))
        context.fill(rect)
        context.draw(image, in: rect)
        return context.makeImage()
    }
}

extension ImageFormat {
    /// Whether "Reduce colours" applies: not to JPEG, whose compression brings the colours back, nor to PDF.
    var reducesColors: Bool { self != .jpg && self != .pdf && self != .greenshot }

    /// Whether ImageIO writes an 8-bit palette image as a palette file (BMP comes out with 24 bits anyway).
    var writesPalette: Bool { self == .png || self == .gif || self == .tiff }

    /// Whether the quality setting changes the file: only JPEG is lossy here (upstream's quality dialog greys the
    /// slider out for the other formats).
    public var usesQuality: Bool { self == .jpg }
}

/// Reduces an image to at most N colours with median cut: port of upstream `WuQuantizer` use for
/// `OutputFileReduceColors` (a different algorithm with the same purpose). Alpha is kept as it is; the colours of
/// the visible pixels are reduced.
public enum ColorQuantizer {
    public static func reduce(_ image: CGImage, to maxColors: Int) -> CGImage {
        let limit = min(max(maxColors, 2), 256)
        let width = image.width
        let height = image.height
        guard let context = CGContext(data: nil, width: width, height: height, bitsPerComponent: 8, bytesPerRow: 0,
                                      space: CGColorSpace(name: CGColorSpace.sRGB)!,
                                      bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue),
              let data = context.data else { return image }
        context.draw(image, in: CGRect(x: 0, y: 0, width: width, height: height))
        let bytesPerRow = context.bytesPerRow
        let bytes = data.bindMemory(to: UInt8.self, capacity: bytesPerRow * height)

        // The distinct colours (premultiplied RGB of pixels that aren't fully transparent) with their counts.
        var counts: [UInt32: Int] = [:]
        for row in 0..<height {
            for column in 0..<width {
                let i = row * bytesPerRow + column * 4
                guard bytes[i + 3] > 0 else { continue }
                counts[key(bytes[i], bytes[i + 1], bytes[i + 2]), default: 0] += 1
            }
        }
        guard counts.count > limit else { return image }

        let palette = medianCut(counts.map { (color: $0.key, count: $0.value) }, boxes: limit)
        for row in 0..<height {
            for column in 0..<width {
                let i = row * bytesPerRow + column * 4
                guard bytes[i + 3] > 0, let mapped = palette[key(bytes[i], bytes[i + 1], bytes[i + 2])] else { continue }
                let a = bytes[i + 3]
                bytes[i] = min(UInt8(truncatingIfNeeded: mapped >> 16), a)
                bytes[i + 1] = min(UInt8(truncatingIfNeeded: mapped >> 8), a)
                bytes[i + 2] = min(UInt8(truncatingIfNeeded: mapped), a)
            }
        }
        return context.makeImage() ?? image
    }

    /// The image as an 8-bit palette image (indexed sRGB), or nil when it has transparency (a palette image here has no
    /// alpha) or more than 256 colours. ImageIO writes such an image as a palette PNG, TIFF or GIF.
    public static func indexed(_ image: CGImage) -> CGImage? {
        let width = image.width
        let height = image.height
        guard let context = CGContext(data: nil, width: width, height: height, bitsPerComponent: 8, bytesPerRow: 0,
                                      space: CGColorSpace(name: CGColorSpace.sRGB)!,
                                      bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue),
              let data = context.data else { return nil }
        context.draw(image, in: CGRect(x: 0, y: 0, width: width, height: height))
        let bytesPerRow = context.bytesPerRow
        let bytes = data.bindMemory(to: UInt8.self, capacity: bytesPerRow * height)
        var indices: [UInt32: UInt8] = [:]
        var table: [UInt8] = []
        var pixels = [UInt8](repeating: 0, count: width * height)
        for row in 0..<height {
            for column in 0..<width {
                let i = row * bytesPerRow + column * 4
                guard bytes[i + 3] == 255 else { return nil }
                let color = key(bytes[i], bytes[i + 1], bytes[i + 2])
                if let index = indices[color] {
                    pixels[row * width + column] = index
                    continue
                }
                guard indices.count < 256 else { return nil }
                let index = UInt8(indices.count)
                indices[color] = index
                table += [bytes[i], bytes[i + 1], bytes[i + 2]]
                pixels[row * width + column] = index
            }
        }
        guard let base = CGColorSpace(name: CGColorSpace.sRGB),
              let space = CGColorSpace(indexedBaseSpace: base, last: max(indices.count - 1, 0), colorTable: table),
              let provider = CGDataProvider(data: Data(pixels) as CFData) else { return nil }
        return CGImage(width: width, height: height, bitsPerComponent: 8, bitsPerPixel: 8, bytesPerRow: width, space: space,
                       bitmapInfo: CGBitmapInfo(rawValue: CGImageAlphaInfo.none.rawValue), provider: provider, decode: nil,
                       shouldInterpolate: false, intent: .defaultIntent)
    }

    private static func key(_ r: UInt8, _ g: UInt8, _ b: UInt8) -> UInt32 {
        UInt32(r) << 16 | UInt32(g) << 8 | UInt32(b)
    }

    private static func channel(_ color: UInt32, _ index: Int) -> Int {
        Int((color >> UInt32(16 - index * 8)) & 0xFF)
    }

    /// Splits the colours into at most `boxes` boxes (the one with the widest channel range first, at its weighted
    /// median) and maps every colour to its box's average.
    static func medianCut(_ colors: [(color: UInt32, count: Int)], boxes: Int) -> [UInt32: UInt32] {
        typealias Entry = (color: UInt32, count: Int)
        func widest(_ box: [Entry]) -> (channel: Int, range: Int) {
            var best = (channel: 0, range: -1)
            for c in 0..<3 {
                var low = 255, high = 0
                for entry in box {
                    let v = channel(entry.color, c)
                    low = min(low, v)
                    high = max(high, v)
                }
                if high - low > best.range { best = (c, high - low) }
            }
            return best
        }
        var work: [(entries: [Entry], channel: Int, range: Int)] = []
        let first = widest(colors)
        work.append((colors, first.channel, first.range))
        while work.count < boxes {
            guard let index = work.indices.max(by: { work[$0].range < work[$1].range }), work[index].range > 0 else { break }
            let box = work.remove(at: index)
            let sorted = box.entries.sorted { channel($0.color, box.channel) < channel($1.color, box.channel) }
            let total = sorted.reduce(0) { $0 + $1.count }
            var running = 0
            var split = 1
            for (i, entry) in sorted.enumerated() {
                running += entry.count
                if running * 2 >= total {
                    split = min(max(i + 1, 1), sorted.count - 1)
                    break
                }
            }
            for part in [Array(sorted[..<split]), Array(sorted[split...])] {
                let w = widest(part)
                work.append((part, w.channel, w.range))
            }
        }
        var palette: [UInt32: UInt32] = [:]
        for box in work {
            var sums = [0, 0, 0]
            var total = 0
            for entry in box.entries {
                for c in 0..<3 { sums[c] += channel(entry.color, c) * entry.count }
                total += entry.count
            }
            let average = key(UInt8(sums[0] / max(total, 1)), UInt8(sums[1] / max(total, 1)), UInt8(sums[2] / max(total, 1)))
            for entry in box.entries { palette[entry.color] = average }
        }
        return palette
    }
}
