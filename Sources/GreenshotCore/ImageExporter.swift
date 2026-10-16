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
    public static func data(for image: CGImage, format: ImageFormat, quality: Int = 80, scale: CGFloat = 1) throws -> Data {
        let data = NSMutableData()
        guard let destination = CGImageDestinationCreateWithData(data, format.utType.identifier as CFString, 1, nil) else {
            throw ImageExportError.encodingFailed(format)
        }
        let source = format.supportsAlpha ? image : (opaque(image) ?? image)
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
    public static func write(_ image: CGImage, to url: URL, format: ImageFormat, quality: Int = 80, scale: CGFloat = 1) throws {
        let encoded = try data(for: image, format: format, quality: quality, scale: scale)
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
