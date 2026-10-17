// Greenshot for Mac (Community) - an unofficial macOS port of Greenshot
// Copyright (C) 2026 Greenshot for Mac (Community) contributors
// Based on Greenshot, Copyright (C) 2007-2026 Thomas Braun, Jens Klingen, Robin Krom
// SPDX-License-Identifier: GPL-3.0-or-later

import CoreGraphics
import Foundation
import ImageIO

/// Checks and decodes the image of an IMPORT_CAPTURE request, a capture of the browser extension (upstream
/// `Ipc/BrowserExtension/ImportCaptureDecoder.cs`, docs/greenshot-proxy-and-integration.md §3.2a). Only PNG and JPEG are
/// accepted (what the browsers' capture API makes), checked by their signature, so ImageIO never parses other formats
/// coming from a browser. The size is read from the image header before decoding: a small file announcing a huge image
/// would otherwise make the decoder allocate gigabytes.
public enum BrowserImportDecoder {
    /// The largest width or height, the browsers' canvas limit (upstream `MaxSide`).
    public static let maxSide = 32767
    /// The most pixels, 100 megapixels, about 400 MB decoded (upstream `MaxPixels`).
    public static let maxPixels = 100_000_000

    private static let pngSignature: [UInt8] = [0x89, 0x50, 0x4E, 0x47, 0x0D, 0x0A, 0x1A, 0x0A]
    private static let jpegSignature: [UInt8] = [0xFF, 0xD8, 0xFF]

    /// Why a payload was refused; `message` is upstream's text.
    public enum Failure: Error, Equatable, Sendable {
        case missing
        case notBase64
        case unsupportedFormat
        case noSize
        case tooLarge(width: Int, height: Int)
        case undecodable

        public var message: String {
            switch self {
            case .missing: return "the image payload is missing"
            case .notBase64: return "the image payload is not valid base64"
            case .unsupportedFormat: return "only PNG and JPEG images are accepted"
            case .noSize: return "the image has no size"
            case .tooLarge(let width, let height):
                return "the image is too large (\(width)x\(height), the maximum is \(maxSide) pixels per side and \(maxPixels / 1_000_000) megapixels)"
            case .undecodable: return "the image could not be decoded"
            }
        }
    }

    /// The image of a base64 payload (without a `data:` prefix). Whitespace is ignored, like .NET's `FromBase64String`.
    public static func decode(base64 payload: String?) -> Result<CGImage, Failure> {
        guard let payload, !payload.allSatisfy(\.isWhitespace) else { return .failure(.missing) }
        let compact = payload.filter { !$0.isWhitespace }
        guard let data = Data(base64Encoded: compact) else { return .failure(.notBase64) }
        return decode(data: data)
    }

    /// The image of the file's bytes: signature, the size from the header, a complete file, then the pixels.
    public static func decode(data: Data) -> Result<CGImage, Failure> {
        let bytes = [UInt8](data)
        let header: Header?
        if bytes.starts(with: pngSignature) {
            header = pngHeader(bytes)
        } else if bytes.starts(with: jpegSignature) {
            header = jpegHeader(bytes)
        } else {
            return .failure(.unsupportedFormat)
        }
        // Read from the header itself, so nothing is decoded before the size is checked
        guard let header else { return .failure(.undecodable) }
        if let failure = sizeFailure(width: header.width, height: header.height) { return .failure(failure) }
        // ImageIO decodes a cut-off file without complaint (the rest stays empty): the file must be whole
        guard header.isComplete else { return .failure(.undecodable) }

        let options = [kCGImageSourceShouldCache: false] as CFDictionary
        let decodeOptions = [kCGImageSourceShouldCacheImmediately: true] as CFDictionary
        guard let source = CGImageSourceCreateWithData(data as CFData, options), CGImageSourceGetCount(source) > 0,
              let image = CGImageSourceCreateImageAtIndex(source, 0, decodeOptions),
              CGImageSourceGetStatusAtIndex(source, 0) == .statusComplete,
              image.width == header.width, image.height == header.height else { return .failure(.undecodable) }
        return .success(image)
    }

    /// What the header says: the size, and whether the file ends where its format says it ends.
    struct Header: Equatable {
        var width: Int
        var height: Int
        var isComplete: Bool
    }

    /// PNG: IHDR is the first chunk (width and height, big-endian); the chunks must lead to IEND within the data.
    static func pngHeader(_ bytes: [UInt8]) -> Header? {
        func uint32(at offset: Int) -> Int {
            var value = 0
            for index in offset..<(offset + 4) { value = value << 8 | Int(bytes[index]) }
            return value
        }
        guard bytes.count >= 33, Array(bytes[12..<16]) == Array("IHDR".utf8), uint32(at: 8) == 13 else { return nil }
        var header = Header(width: uint32(at: 16), height: uint32(at: 20), isComplete: false)
        var offset = 8
        while offset + 12 <= bytes.count {
            let length = uint32(at: offset)
            let type = Array(bytes[(offset + 4)..<(offset + 8)])
            let next = offset + 12 + length
            guard next <= bytes.count else { break }
            if type == Array("IEND".utf8) {
                header.isComplete = true
                break
            }
            offset = next
        }
        return header
    }

    /// JPEG: the size is in the start-of-frame segment (SOF0-SOF15 without DHT C4, JPG C8, DAC CC) before the scan;
    /// the file must end with the end-of-image marker FF D9.
    static func jpegHeader(_ bytes: [UInt8]) -> Header? {
        var offset = 2
        while offset + 4 <= bytes.count {
            guard bytes[offset] == 0xFF else { return nil }
            let marker = bytes[offset + 1]
            if marker == 0xFF {
                // Fill byte
                offset += 1
                continue
            }
            if marker == 0xD8 || (0xD0...0xD7).contains(marker) || marker == 0x01 {
                offset += 2
                continue
            }
            let length = Int(bytes[offset + 2]) << 8 | Int(bytes[offset + 3])
            guard length >= 2 else { return nil }
            if (0xC0...0xCF).contains(marker), ![0xC4, 0xC8, 0xCC].contains(marker) {
                guard offset + 9 <= bytes.count else { return nil }
                let height = Int(bytes[offset + 5]) << 8 | Int(bytes[offset + 6])
                let width = Int(bytes[offset + 7]) << 8 | Int(bytes[offset + 8])
                let complete = bytes.count >= 4 && bytes[bytes.count - 2] == 0xFF && bytes[bytes.count - 1] == 0xD9
                return Header(width: width, height: height, isComplete: complete)
            }
            // The scan or the end before a frame: no size
            if marker == 0xDA || marker == 0xD9 { return nil }
            offset += 2 + length
        }
        return nil
    }

    /// Nil when the size is within `maxSide` and `maxPixels` (upstream `IsAcceptableSize`), else why not.
    public static func sizeFailure(width: Int, height: Int) -> Failure? {
        guard width > 0, height > 0 else { return .noSize }
        let pixels = Int64(width) * Int64(height)
        if width > maxSide || height > maxSide || pixels > Int64(maxPixels) {
            return .tooLarge(width: width, height: height)
        }
        return nil
    }
}
