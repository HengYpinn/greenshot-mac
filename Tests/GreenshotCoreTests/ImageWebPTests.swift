// SPDX-License-Identifier: GPL-3.0-or-later

import CoreGraphics
import Foundation
import ImageIO
import Testing
@testable import GreenshotCore

/// The lossless WebP encoder: every image must come back from ImageIO's decoder pixel for pixel.
struct ImageWebPTests {
    @Test func containerAndHeader() throws {
        let data = try ImageWebPEncoder.encode(TestImage.solid(width: 300, height: 7, .red))
        let bytes = [UInt8](data)
        #expect(String(decoding: bytes[0..<4], as: UTF8.self) == "RIFF")
        #expect(Int(bytes[4]) | Int(bytes[5]) << 8 | Int(bytes[6]) << 16 | Int(bytes[7]) << 24 == bytes.count - 8)
        #expect(String(decoding: bytes[8..<16], as: UTF8.self) == "WEBPVP8L")
        #expect(bytes[20] == 0x2F)
        // 14 bits width - 1, 14 bits height - 1, alpha used, version 0.
        let header = UInt32(bytes[21]) | UInt32(bytes[22]) << 8 | UInt32(bytes[23]) << 16 | UInt32(bytes[24]) << 24
        #expect(header & 0x3FFF == 299 && header >> 14 & 0x3FFF == 6 && header >> 28 & 1 == 0 && header >> 29 == 0)
        #expect(bytes.count % 2 == 0)
    }

    @Test func oneColor() throws {
        try roundTrip(TestImage.solid(width: 40, height: 30, RGBA(r: 12, g: 200, b: 99, a: 255)))
    }

    @Test func twoColorsAndTinySizes() throws {
        try roundTrip(TestImage.make(width: 9, height: 5) { x, y in (x + y) % 2 == 0 ? .black : .white })
        try roundTrip(TestImage.solid(width: 1, height: 1, .blue))
        try roundTrip(TestImage.make(width: 3, height: 7) { x, y in RGBA(r: UInt8(x * 80), g: UInt8(y * 30), b: 5, a: 255) })
    }

    @Test func noiseUsesEveryValue() throws {
        var generator = SeededRandom(seed: 42)
        let noise = TestImage.make(width: 64, height: 48) { _, _ in
            RGBA(r: UInt8.random(in: 0...255, using: &generator), g: UInt8.random(in: 0...255, using: &generator),
                 b: UInt8.random(in: 0...255, using: &generator), a: 255)
        }
        try roundTrip(noise)
        // Every green value exactly as often: all code lengths 8.
        try roundTrip(TestImage.make(width: 256, height: 3) { x, _ in RGBA(r: 7, g: UInt8(x), b: 7, a: 255) })
    }

    @Test func repeatsBecomeCopies() throws {
        // Stripes and rows that repeat the row above: long and overlapping copies.
        let stripes = TestImage.make(width: 700, height: 60) { x, y in
            y % 20 < 10 ? RGBA(r: UInt8(x % 7 * 30), g: 40, b: 200, a: 255) : RGBA(r: 250, g: 250, b: 250, a: 255)
        }
        let data = try roundTrip(stripes)
        #expect(data.count < 700 * 60 / 4)
    }

    @Test func transparencyIsKept() throws {
        // Premultiplied, like every bitmap here: no color above the alpha.
        let faded = TestImage.make(width: 30, height: 20) { x, y in
            let alpha: UInt8 = x < 10 ? 0 : UInt8(x * 8)
            return RGBA(r: alpha, g: min(UInt8(y * 12), alpha), b: 0, a: alpha)
        }
        let data = try ImageWebPEncoder.encode(faded)
        #expect((UInt32(data[24]) >> 4) & 1 == 1)
        let decoded = try decode(data)
        for y in stride(from: 0, to: 20, by: 3) {
            for x in stride(from: 0, to: 30, by: 3) {
                #expect(TestImage.pixel(decoded, x, y).isClose(to: TestImage.pixel(faded, x, y), tolerance: 2), "\(x), \(y)")
            }
        }
    }

    @Test func theSampleScreenshotRoundTrips() throws {
        // Text, gradients and flat areas like a real capture.
        let capture = TestImage.make(width: 400, height: 260) { x, y in
            if (40..<360).contains(x) && (30..<230).contains(y) {
                if y % 18 < 12 && (x / 7 + y / 18) % 5 != 0 && x % 7 < 5 { return RGBA(r: 30, g: 30, b: 35, a: 255) }
                return .white
            }
            return RGBA(r: UInt8(200 + y / 10), g: UInt8(210 + y / 20), b: 240, a: 255)
        }
        let data = try roundTrip(capture)
        let png = try ImageExporter.data(for: capture, format: .png)
        #expect(data.count < png.count * 2)
    }

    @Test func tooWideForWebP() {
        #expect(throws: ImageExportError.self) { try ImageWebPEncoder.encode(TestImage.solid(width: 16385, height: 1, .red)) }
    }

    @Test func prefixCodes() {
        #expect(ImageWebPEncoder.prefix(1) == (0, 0, 0))
        #expect(ImageWebPEncoder.prefix(4) == (3, 0, 0))
        #expect(ImageWebPEncoder.prefix(5) == (4, 1, 0) && ImageWebPEncoder.prefix(6) == (4, 1, 1))
        #expect(ImageWebPEncoder.prefix(7) == (5, 1, 0))
        #expect(ImageWebPEncoder.prefix(4096).code == 23)
        #expect(ImageWebPEncoder.prefix(1 << 20).code == 39)
    }

    @Test func codeLengthsStayWithinTheLimit() {
        // Fibonacci counts make the deepest Huffman trees.
        var counts = [1, 1]
        while counts.count < 30 { counts.append(counts[counts.count - 1] + counts[counts.count - 2]) }
        let lengths = PrefixCode.codeLengths(counts, limit: 15)
        #expect((14...15).contains(lengths.max() ?? 0))
        // Still a complete code.
        let kraft = lengths.reduce(0.0) { $0 + pow(2, -Double($1)) }
        #expect(abs(kraft - 1) < 1e-9)
    }

    @Test func savedThroughTheExporter() throws {
        #expect(ImageFormat(fileExtension: "webp") == .webp && ImageFormat.webp.utType == .webP)
        let image = TestImage.make(width: 20, height: 10) { x, _ in x < 10 ? .red : .blue }
        let data = try ImageExporter.data(for: image, options: ImageOutputOptions(format: .webp, scale: 2))
        let loaded = try #require(ImageFileLoader.load(data: data))
        #expect(TestImage.pixel(loaded.image, 15, 5) == .blue)
    }

    // MARK: Helpers

    @discardableResult
    private func roundTrip(_ image: CGImage, sourceLocation: SourceLocation = #_sourceLocation) throws -> Data {
        let data = try ImageWebPEncoder.encode(image)
        let decoded = try decode(data)
        #expect(decoded.width == image.width && decoded.height == image.height, sourceLocation: sourceLocation)
        var mismatches = 0
        for y in 0..<image.height {
            for x in 0..<image.width where TestImage.pixel(decoded, x, y) != TestImage.pixel(image, x, y) {
                mismatches += 1
            }
        }
        #expect(mismatches == 0, "\(mismatches) pixels differ", sourceLocation: sourceLocation)
        return data
    }

    private func decode(_ data: Data) throws -> CGImage {
        let source = try #require(CGImageSourceCreateWithData(data as CFData, nil))
        return try #require(CGImageSourceCreateImageAtIndex(source, 0, nil))
    }
}
