// SPDX-License-Identifier: GPL-3.0-or-later

import CoreGraphics

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
