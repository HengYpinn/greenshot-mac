// Greenshot for Mac (Community) - an unofficial macOS port of Greenshot
// Copyright (C) 2026 Greenshot for Mac (Community) contributors
// SPDX-License-Identifier: GPL-3.0-or-later

import CoreGraphics
import Foundation
import ImageIO
import Testing
@testable import GreenshotCore

/// Upstream `Greenshot.Tests/Ipc/ImportCaptureTests.cs`.
struct BrowserImportDecoderTests {
    static func image(width: Int, height: Int) -> CGImage {
        let context = CGContext(data: nil, width: width, height: height, bitsPerComponent: 8, bytesPerRow: 0,
                                space: CGColorSpaceCreateDeviceRGB(), bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue)!
        context.setFillColor(CGColor(red: 0.2, green: 0.6, blue: 0.3, alpha: 1))
        context.fill(CGRect(x: 0, y: 0, width: width, height: height))
        return context.makeImage()!
    }

    static func encoded(_ type: String, width: Int = 12, height: Int = 7) -> Data {
        let data = NSMutableData()
        let destination = CGImageDestinationCreateWithData(data, type as CFString, 1, nil)!
        CGImageDestinationAddImage(destination, image(width: width, height: height), nil)
        _ = CGImageDestinationFinalize(destination)
        return data as Data
    }

    /// A PNG of only its signature, an IHDR with this size and IEND: the header claims a size no pixels back.
    static func pngHeader(width: UInt32, height: UInt32) -> Data {
        func bigEndian(_ value: UInt32) -> [UInt8] {
            let shifts: [UInt32] = [24, 16, 8, 0]
            return shifts.map { UInt8(truncatingIfNeeded: value >> $0) }
        }
        func chunk(_ type: String, _ body: [UInt8]) -> [UInt8] {
            let typed = Array(type.utf8) + body
            return bigEndian(UInt32(body.count)) + typed + bigEndian(crc32(typed))
        }
        var bytes: [UInt8] = [0x89, 0x50, 0x4E, 0x47, 0x0D, 0x0A, 0x1A, 0x0A]
        bytes += chunk("IHDR", bigEndian(width) + bigEndian(height) + [8, 6, 0, 0, 0])
        bytes += chunk("IEND", [])
        return Data(bytes)
    }

    static func crc32(_ bytes: [UInt8]) -> UInt32 {
        var crc: UInt32 = 0xFFFF_FFFF
        for byte in bytes {
            crc ^= UInt32(byte)
            for _ in 0..<8 {
                let mask: UInt32 = (crc & 1) == 1 ? 0xEDB8_8320 : 0
                crc = (crc >> 1) ^ mask
            }
        }
        return crc ^ 0xFFFF_FFFF
    }

    @Test(arguments: ["public.png", "public.jpeg"])
    func pngAndJpegAreAccepted(_ type: String) throws {
        let payload = Self.encoded(type).base64EncodedString()
        let image = try BrowserImportDecoder.decode(base64: payload).get()
        #expect(image.width == 12)
        #expect(image.height == 7)
    }

    @Test func whitespaceInTheBase64IsIgnored() throws {
        let base64 = Self.encoded("public.png").base64EncodedString(options: [.lineLength64Characters, .endLineWithLineFeed])
        let image = try BrowserImportDecoder.decode(base64: " " + base64 + "\n").get()
        #expect(image.width == 12)
    }

    @Test(arguments: ["com.compuserve.gif", "public.tiff", "com.microsoft.bmp"])
    func otherFormatsAreRefusedBeforeDecoding(_ type: String) {
        let result = BrowserImportDecoder.decode(base64: Self.encoded(type).base64EncodedString())
        #expect(result.failure == .unsupportedFormat)
        #expect(BrowserImportDecoder.Failure.unsupportedFormat.message == "only PNG and JPEG images are accepted")
    }

    @Test func missingAndInvalidPayloadsAreRefused() {
        #expect(BrowserImportDecoder.decode(base64: nil).failure == .missing)
        #expect(BrowserImportDecoder.decode(base64: "").failure == .missing)
        #expect(BrowserImportDecoder.decode(base64: "  ").failure == .missing)
        #expect(BrowserImportDecoder.decode(base64: "not base64!").failure == .notBase64)
        #expect(BrowserImportDecoder.Failure.missing.message.contains("missing"))
        #expect(BrowserImportDecoder.Failure.notBase64.message.contains("base64"))
    }

    @Test func truncatedPngIsRefused() {
        let png = Self.encoded("public.png", width: 64, height: 64)
        let truncated = png.prefix(png.count / 2)
        let result = BrowserImportDecoder.decode(base64: Data(truncated).base64EncodedString())
        #expect(result.failure == .undecodable)
    }

    @Test func truncatedJpegIsRefused() {
        let jpeg = Self.encoded("public.jpeg", width: 64, height: 64)
        let truncated = jpeg.prefix(jpeg.count - 20)
        let result = BrowserImportDecoder.decode(base64: Data(truncated).base64EncodedString())
        #expect(result.failure == .undecodable)
    }

    @Test func jpegHeaderClaimingAHugeSizeIsRefused() {
        // SOI, SOF0 (precision 8, 65535 × 65535, one component), EOI
        let bytes: [UInt8] = [0xFF, 0xD8, 0xFF, 0xC0, 0x00, 0x0B, 0x08, 0xFF, 0xFF, 0xFF, 0xFF, 0x01, 0x01, 0x11, 0x00,
                              0xFF, 0xD9]
        let result = BrowserImportDecoder.decode(data: Data(bytes))
        #expect(result.failure == .tooLarge(width: 65535, height: 65535))
    }

    @Test func headersOfGeneratedImages() throws {
        let png = try #require(BrowserImportDecoder.pngHeader([UInt8](Self.encoded("public.png", width: 30, height: 20))))
        #expect(png == BrowserImportDecoder.Header(width: 30, height: 20, isComplete: true))
        let jpeg = try #require(BrowserImportDecoder.jpegHeader([UInt8](Self.encoded("public.jpeg", width: 30, height: 20))))
        #expect(jpeg == BrowserImportDecoder.Header(width: 30, height: 20, isComplete: true))
        let headerOnly = try #require(BrowserImportDecoder.pngHeader([UInt8](Self.pngHeader(width: 5, height: 5).prefix(33))))
        #expect(!headerOnly.isComplete)
    }

    @Test(arguments: [(40000, 16), (20000, 20000)])
    func hugeSizesInTheHeaderAreRefusedBeforeDecoding(_ size: (Int, Int)) {
        let header = Self.pngHeader(width: UInt32(size.0), height: UInt32(size.1))
        let result = BrowserImportDecoder.decode(base64: header.base64EncodedString())
        #expect(result.failure == .tooLarge(width: size.0, height: size.1))
    }

    @Test func tooLargeMessageNamesTheLimits() {
        let message = BrowserImportDecoder.Failure.tooLarge(width: 40000, height: 16).message
        #expect(message == "the image is too large (40000x16, the maximum is 32767 pixels per side and 100 megapixels)")
    }

    @Test(arguments: [(1, 1, true), (32767, 1, true), (32768, 1, false), (1, 32768, false), (10000, 10000, true),
                      (10001, 10000, false), (0, 10, false), (10, -1, false)])
    func sizeLimits(_ row: (Int, Int, Bool)) {
        let accepted = BrowserImportDecoder.sizeFailure(width: row.0, height: row.1) == nil
        #expect(accepted == row.2)
    }
}

fileprivate extension Result {
    /// The error, nil on success.
    var failure: Failure? {
        if case .failure(let error) = self { return error }
        return nil
    }
}
