// SPDX-License-Identifier: GPL-3.0-or-later

import CoreGraphics
import Foundation
import ImageIO
import Testing
@testable import GreenshotCore

/// Opening image files (upstream `ImageHelper.Orientate`, `IconFileFormatHandler.TryLoadFromStream`).
struct ImageFileLoaderTests {
    /// What the picture should look like: 3 × 2, every pixel different.
    let upright = TestImage.make(width: 3, height: 2) { x, y in RGBA(r: UInt8(40 + x * 80), g: UInt8(60 + y * 120), b: 7, a: 255) }

    /// How a camera stores `upright` for each EXIF orientation (the inverse of what the reader has to do).
    private func stored(for orientation: Int) -> CGImage {
        let w = 3, h = 2
        func p(_ x: Int, _ y: Int) -> RGBA { TestImage.pixel(upright, x, y) }
        switch orientation {
        case 2: return TestImage.make(width: w, height: h) { x, y in p(w - 1 - x, y) }
        case 3: return TestImage.make(width: w, height: h) { x, y in p(w - 1 - x, h - 1 - y) }
        case 4: return TestImage.make(width: w, height: h) { x, y in p(x, h - 1 - y) }
        case 5: return TestImage.make(width: h, height: w) { a, b in p(b, a) }
        case 6: return TestImage.make(width: h, height: w) { a, b in p(w - 1 - b, a) }
        case 7: return TestImage.make(width: h, height: w) { a, b in p(w - 1 - b, h - 1 - a) }
        case 8: return TestImage.make(width: h, height: w) { a, b in p(b, h - 1 - a) }
        default: return upright
        }
    }

    @Test(arguments: 1...8)
    func exifOrientationIsApplied(orientation: Int) throws {
        let data = NSMutableData()
        let destination = try #require(CGImageDestinationCreateWithData(data, "public.tiff" as CFString, 1, nil))
        CGImageDestinationAddImage(destination, stored(for: orientation), [kCGImagePropertyOrientation: orientation] as CFDictionary)
        #expect(CGImageDestinationFinalize(destination))
        let loaded = try #require(ImageFileLoader.load(data: data as Data))
        #expect(loaded.image.width == 3 && loaded.image.height == 2, "orientation \(orientation)")
        for y in 0..<2 {
            for x in 0..<3 {
                #expect(TestImage.pixel(loaded.image, x, y) == TestImage.pixel(upright, x, y), "orientation \(orientation) at \(x), \(y)")
            }
        }
    }

    @Test func resolutionGivesThePixelsPerPoint() throws {
        let data = try ImageExporter.data(for: upright, format: .png, scale: 2)
        #expect(try #require(ImageFileLoader.load(data: data)).scale == 2)
        #expect(try #require(ImageFileLoader.load(data: try ImageExporter.data(for: upright, format: .png))).scale == 1)
    }

    @Test func iconsOpenAtTheirBiggestSize() throws {
        let small = try ImageExporter.data(for: TestImage.solid(width: 16, height: 16, .red), format: .png)
        let big = try ImageExporter.data(for: TestImage.solid(width: 32, height: 32, .blue), format: .png)
        let data = Self.icon(entries: [(16, small), (32, big)])
        let loaded = try #require(ImageFileLoader.load(data: data))
        #expect(loaded.image.width == 32)
        #expect(TestImage.pixel(loaded.image, 5, 5) == .blue)
    }

    @Test func fileURLsLoad() throws {
        let url = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString + ".png")
        defer { try? FileManager.default.removeItem(at: url) }
        try ImageExporter.write(upright, to: url, format: .png, scale: 2)
        let loaded = try #require(ImageFileLoader.load(url))
        #expect(loaded.scale == 2 && loaded.image.width == 3)
    }

    /// An ICO file with PNG entries (ICONDIR + ICONDIRENTRY, little endian).
    static func icon(entries: [(size: Int, png: Data)]) -> Data {
        func le16(_ v: Int) -> [UInt8] { [UInt8(v & 0xFF), UInt8(v >> 8 & 0xFF)] }
        func le32(_ v: Int) -> [UInt8] { le16(v & 0xFFFF) + le16(v >> 16) }
        var data = Data(le16(0) + le16(1) + le16(entries.count))
        var offset = 6 + entries.count * 16
        for entry in entries {
            let side = UInt8(entry.size == 256 ? 0 : entry.size)
            data.append(contentsOf: [side, side, 0, 0] + le16(1) + le16(32) + le32(entry.png.count) + le32(offset))
            offset += entry.png.count
        }
        for entry in entries { data.append(entry.png) }
        return data
    }
}
