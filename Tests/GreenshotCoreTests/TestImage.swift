// SPDX-License-Identifier: GPL-3.0-or-later

import Compression
import CoreGraphics
import Foundation

struct RGBA: Equatable, CustomStringConvertible {
    var r: UInt8, g: UInt8, b: UInt8, a: UInt8

    static let white = RGBA(r: 255, g: 255, b: 255, a: 255)
    static let black = RGBA(r: 0, g: 0, b: 0, a: 255)
    static let red = RGBA(r: 255, g: 0, b: 0, a: 255)
    static let blue = RGBA(r: 0, g: 0, b: 255, a: 255)
    static let yellow = RGBA(r: 255, g: 255, b: 0, a: 255)

    var description: String { "(\(r), \(g), \(b), \(a))" }

    func isClose(to other: RGBA, tolerance: Int = 6) -> Bool {
        abs(Int(r) - Int(other.r)) <= tolerance && abs(Int(g) - Int(other.g)) <= tolerance
            && abs(Int(b) - Int(other.b)) <= tolerance && abs(Int(a) - Int(other.a)) <= tolerance
    }
}

enum TestImage {
    /// An sRGB image whose pixel at (x, y), origin top left, is `color(x, y)`.
    static func make(width: Int, height: Int, _ color: (Int, Int) -> RGBA) -> CGImage {
        var bytes = [UInt8](repeating: 0, count: width * height * 4)
        for y in 0..<height {
            for x in 0..<width {
                let c = color(x, y)
                let i = (y * width + x) * 4
                bytes[i] = c.r
                bytes[i + 1] = c.g
                bytes[i + 2] = c.b
                bytes[i + 3] = c.a
            }
        }
        let context = CGContext(data: &bytes, width: width, height: height, bitsPerComponent: 8, bytesPerRow: width * 4,
                                space: CGColorSpace(name: CGColorSpace.sRGB)!,
                                bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue)!
        return context.makeImage()!
    }

    static func solid(width: Int, height: Int, _ color: RGBA) -> CGImage {
        make(width: width, height: height) { _, _ in color }
    }

    /// A 1-bit PNG of `side` × `side` red pixels: 24 KB for 14142 × 14142 (200 megapixels), which take a decoder
    /// most of a second.
    static func hugePNG(side: Int) -> Data {
        let header = bigEndian(side) + bigEndian(side) + [1, 3, 0, 0, 0]
        let rows = zlibOfZeros(((side + 7) / 8 + 1) * side)
        let chunks = pngChunk("IHDR", header) + pngChunk("PLTE", [255, 0, 0]) + pngChunk("IDAT", rows) + pngChunk("IEND", [])
        return Data([0x89, 0x50, 0x4E, 0x47, 0x0D, 0x0A, 0x1A, 0x0A] + chunks)
    }

    /// A 1-bit deflate TIFF of `side` × `side` black pixels (24 KB for 200 megapixels): no PNG, so a Greenshot for
    /// Windows file's picture of it is converted.
    static func hugeTIFF(side: Int) -> Data {
        func le16(_ value: Int) -> [UInt8] { [UInt8(value & 0xFF), UInt8(value >> 8 & 0xFF)] }
        func le32(_ value: Int) -> [UInt8] { le16(value & 0xFFFF) + le16(value >> 16) }
        let strip = zlibOfZeros((side + 7) / 8 * side)
        // Width, height, 1 bit, deflate, black is zero, the strip, 1 sample, rows per strip, strip bytes.
        let entries: [(tag: Int, type: Int, value: Int)] = [(256, 4, side), (257, 4, side), (258, 3, 1), (259, 3, 8), (262, 3, 1),
                                                            (273, 4, 8 + 2 + 9 * 12 + 4), (277, 3, 1), (278, 4, side),
                                                            (279, 4, strip.count)]
        var data: [UInt8] = [0x49, 0x49, 42, 0] + le32(8) + le16(entries.count)
        for entry in entries {
            data += le16(entry.tag) + le16(entry.type) + le32(1)
            data += entry.type == 3 ? le16(entry.value) + [0, 0] : le32(entry.value)
        }
        return Data(data + le32(0) + strip)
    }

    private static func bigEndian(_ value: Int) -> [UInt8] {
        [UInt8(value >> 24 & 0xFF), UInt8(value >> 16 & 0xFF), UInt8(value >> 8 & 0xFF), UInt8(value & 0xFF)]
    }

    /// A zlib stream of `count` zero bytes.
    private static func zlibOfZeros(_ count: Int) -> [UInt8] {
        let input = [UInt8](repeating: 0, count: count)
        var output = [UInt8](repeating: 0, count: count / 100 + 4096)
        let written = compression_encode_buffer(&output, output.count, input, count, nil, COMPRESSION_ZLIB)
        // The Adler-32 of zeros: 1 for the sum, the count for the sum of sums.
        let adler = (count % 65_521) << 16 | 1
        return [0x78, 0x9C] + output[..<written] + bigEndian(adler)
    }

    private static func pngChunk(_ type: String, _ data: [UInt8]) -> [UInt8] {
        let typed = Array(type.utf8) + data
        var crc: UInt32 = 0xFFFF_FFFF
        for byte in typed {
            crc ^= UInt32(byte)
            for _ in 0..<8 { crc = crc & 1 == 1 ? crc >> 1 ^ 0xEDB8_8320 : crc >> 1 }
        }
        return bigEndian(data.count) + typed + bigEndian(Int(~crc))
    }

    /// The pixel at (x, y), origin top left.
    static func pixel(_ image: CGImage, _ x: Int, _ y: Int) -> RGBA {
        var bytes = [UInt8](repeating: 0, count: 4)
        let context = CGContext(data: &bytes, width: 1, height: 1, bitsPerComponent: 8, bytesPerRow: 4,
                                space: CGColorSpace(name: CGColorSpace.sRGB)!,
                                bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue)!
        // Shift the image so that pixel (x, y) lands on the single pixel of the context (whose origin is bottom left).
        context.draw(image, in: CGRect(x: -x, y: y - image.height + 1, width: image.width, height: image.height))
        return RGBA(r: bytes[0], g: bytes[1], b: bytes[2], a: bytes[3])
    }
}
