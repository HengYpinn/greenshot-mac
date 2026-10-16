// Greenshot for Mac (Community) - an unofficial macOS port of Greenshot
// Copyright (C) 2026 Greenshot for Mac (Community) contributors
// SPDX-License-Identifier: GPL-3.0-or-later

import CoreGraphics
import Foundation
import ImageIO
import UniformTypeIdentifiers

/// The file formats Greenshot writes (upstream `OutputFileFormat`).
public enum ImageFormat: String, Codable, CaseIterable, Sendable {
    case png, jpg, bmp, gif, tiff

    public var fileExtension: String { rawValue }

    public var utType: UTType {
        switch self {
        case .png: return .png
        case .jpg: return .jpeg
        case .bmp: return .bmp
        case .gif: return .gif
        case .tiff: return .tiff
        }
    }

    public var displayName: String {
        switch self {
        case .png: return "PNG"
        case .jpg: return "JPEG"
        case .bmp: return "BMP"
        case .gif: return "GIF"
        case .tiff: return "TIFF"
        }
    }

    /// Formats without transparency get a white background.
    var supportsAlpha: Bool { self == .png || self == .tiff || self == .gif }

    public init?(fileExtension: String) {
        switch fileExtension.lowercased() {
        case "png": self = .png
        case "jpg", "jpeg": self = .jpg
        case "bmp": self = .bmp
        case "gif": self = .gif
        case "tif", "tiff": self = .tiff
        default: return nil
        }
    }
}

public enum ImageExportError: Error, LocalizedError {
    case encodingFailed(ImageFormat)

    public var errorDescription: String? {
        switch self {
        case .encodingFailed(let format): return "The image could not be encoded as \(format.displayName)."
        }
    }
}

public enum ImageExporter {
    /// `quality` is 0–100 and only used for JPEG. `scale` is the capture's pixels per point: it is written as the
    /// resolution (72 dpi × scale, so 144 dpi for Retina), which is how `ImageLoader` and Preview find the real size.
    /// `maxColors` reduces PNG and GIF images to that many colours (upstream `OutputFileReduceColors`).
    public static func data(for image: CGImage, format: ImageFormat, quality: Int = 80, scale: CGFloat = 1,
                            maxColors: Int? = nil) throws -> Data {
        let data = NSMutableData()
        guard let destination = CGImageDestinationCreateWithData(data, format.utType.identifier as CFString, 1, nil) else {
            throw ImageExportError.encodingFailed(format)
        }
        var source = format.supportsAlpha ? image : (opaque(image) ?? image)
        if let maxColors, format == .png || format == .gif {
            source = ColorQuantizer.reduce(source, to: maxColors)
        }
        var properties: [CFString: Any] = [
            kCGImagePropertyDPIWidth: 72 * scale,
            kCGImagePropertyDPIHeight: 72 * scale,
        ]
        if format == .jpg {
            properties[kCGImageDestinationLossyCompressionQuality] = Double(min(max(quality, 1), 100)) / 100
        }
        CGImageDestinationAddImage(destination, source, properties as CFDictionary)
        guard CGImageDestinationFinalize(destination) else { throw ImageExportError.encodingFailed(format) }
        return data as Data
    }

    /// Writes the image, creating missing folders on the way.
    public static func write(_ image: CGImage, to url: URL, format: ImageFormat, quality: Int = 80, scale: CGFloat = 1,
                             maxColors: Int? = nil) throws {
        let encoded = try data(for: image, format: format, quality: quality, scale: scale, maxColors: maxColors)
        try FileManager.default.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
        try encoded.write(to: url, options: .atomic)
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
