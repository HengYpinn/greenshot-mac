// Greenshot for Mac (Community) - an unofficial macOS port of Greenshot
// Copyright (C) 2026 Greenshot for Mac (Community) contributors
// Based on Greenshot, Copyright (C) 2007-2026 Thomas Braun, Jens Klingen, Robin Krom
// SPDX-License-Identifier: GPL-3.0-or-later

import CoreGraphics
import CryptoKit
import Foundation

/// Pixelate of the obfuscate element: port of upstream `Greenshot.Editor/Drawing/Filters/PixelizationFilter.cs`
/// ("Prevent reversing our pixelate", 1aa2febb). A plain block average can be reversed by trying candidate texts and
/// comparing their pixelation, so the blocks have random sizes and the colors random noise, from a secret that is made
/// for every element and only kept in memory: every repaint and the export use the same noise, but nobody can
/// reproduce it.
public enum ImagePixelation {
    /// `image` in blocks of about `blockSize` pixels; `element` is the obfuscate element's id, which picks its secret.
    public static func pixelated(_ image: CGImage, blockSize: CGFloat, element: UUID) -> CGImage? {
        // A size from a crafted element file can be anything; Int() of an infinite or huge value traps.
        let size = blockSize.isFinite ? Int(min(max(blockSize.rounded(), 1), 4096)) : 1
        return pixelated(image, blockSize: size, key: key(for: element))
    }

    // MARK: The secret

    private static let lock = NSLock()
    private static var keys: [UUID: SymmetricKey] = [:]

    /// The secret of an element: random, made the first time it is asked for and never written anywhere (upstream's
    /// `[NonSerialized]` key and IV), so it is gone when the app quits.
    public static func key(for element: UUID) -> SymmetricKey {
        lock.lock()
        defer { lock.unlock() }
        if let key = keys[element] { return key }
        let key = SymmetricKey(size: .bits256)
        keys[element] = key
        return key
    }

    // MARK: Pixelation

    /// Upstream `PixelizationFilter.Apply`: rows of random height (the block size ± a third, at least 2), in every row
    /// columns of random width, every block filled with its average color plus noise: per block ±12 and per pixel ±3,
    /// both scaled down by how much the block's colors differ, so a block of one color stays exactly that color. A block
    /// size of 1 or less leaves the image as it is.
    public static func pixelated(_ image: CGImage, blockSize: Int, key: SymmetricKey) -> CGImage? {
        let width = image.width
        let height = image.height
        guard blockSize > 1, width > 0, height > 0 else { return image }
        let size = min(blockSize, width, height)
        guard let context = AnnotationRenderer.makeContext(width: width, height: height), let data = context.data else { return nil }
        context.draw(image, in: CGRect(x: 0, y: 0, width: width, height: height))
        let rowBytes = context.bytesPerRow
        let pixels = data.bindMemory(to: UInt8.self, capacity: rowBytes * height)
        var random = NoiseStream(key: key)

        let rows = boundaries(length: height, blockSize: size, random: &random)
        for rowIndex in 0..<(rows.count - 1) {
            let top = rows[rowIndex]
            let bottom = rows[rowIndex + 1]
            let columns = boundaries(length: width, blockSize: size, random: &random)
            for columnIndex in 0..<(columns.count - 1) {
                let block = Block(left: columns[columnIndex], right: columns[columnIndex + 1], top: top, bottom: bottom)
                fill(block, pixels: pixels, rowBytes: rowBytes, random: &random)
            }
        }
        return context.makeImage()
    }

    /// The start of every block along a side of `length` pixels, and `length` at the end: steps of `blockSize` plus a
    /// random jitter of up to a third of it, at least 2.
    static func boundaries(length: Int, blockSize: Int, random: inout NoiseStream) -> [Int] {
        let jitter = max(1, blockSize / 3)
        var result = [0]
        var position = 0
        while position < length {
            position += max(blockSize + random.next(in: -jitter...jitter), 2)
            result.append(min(position, length))
        }
        return result
    }

    struct Block {
        var left, right, top, bottom: Int
    }

    /// One block: its average color (premultiplied, so the colors stay within the alpha) with the noise. Plain local
    /// sums rather than arrays: this runs for every block on every repaint.
    private static func fill(_ block: Block, pixels: UnsafeMutablePointer<UInt8>, rowBytes: Int, random: inout NoiseStream) {
        var sumR = 0, sumG = 0, sumB = 0, sumA = 0
        var minR = 255, minG = 255, minB = 255, maxR = 0, maxG = 0, maxB = 0
        for y in block.top..<block.bottom {
            var i = y * rowBytes + block.left * 4
            for _ in block.left..<block.right {
                let r = Int(pixels[i]), g = Int(pixels[i + 1]), b = Int(pixels[i + 2])
                sumR += r
                sumG += g
                sumB += b
                sumA += Int(pixels[i + 3])
                minR = min(minR, r)
                maxR = max(maxR, r)
                minG = min(minG, g)
                maxG = max(maxG, g)
                minB = min(minB, b)
                maxB = max(maxB, b)
                i += 4
            }
        }
        let count = (block.right - block.left) * (block.bottom - block.top)
        guard count > 0 else { return }
        let alpha = sumA / count
        let spread = max(maxR - minR, maxG - minG, maxB - minB)
        // Upstream: no noise for one color, full noise from a difference of 32 on.
        let strength: Double = min(1, Double(spread) / 32)
        let blockRange = Int((12 * strength).rounded())
        let pixelRange = Int((3 * strength).rounded())
        let red = sumR / count + (blockRange > 0 ? random.next(in: -blockRange...blockRange) : 0)
        let green = sumG / count + (blockRange > 0 ? random.next(in: -blockRange...blockRange) : 0)
        let blue = sumB / count + (blockRange > 0 ? random.next(in: -blockRange...blockRange) : 0)
        for y in block.top..<block.bottom {
            var i = y * rowBytes + block.left * 4
            for _ in block.left..<block.right {
                if pixelRange > 0 {
                    pixels[i] = clamped(red + random.next(in: -pixelRange...pixelRange), alpha)
                    pixels[i + 1] = clamped(green + random.next(in: -pixelRange...pixelRange), alpha)
                    pixels[i + 2] = clamped(blue + random.next(in: -pixelRange...pixelRange), alpha)
                } else {
                    pixels[i] = clamped(red, alpha)
                    pixels[i + 1] = clamped(green, alpha)
                    pixels[i + 2] = clamped(blue, alpha)
                }
                pixels[i + 3] = UInt8(alpha)
                i += 4
            }
        }
    }

    private static func clamped(_ value: Int, _ alpha: Int) -> UInt8 {
        UInt8(min(max(value, 0), alpha))
    }
}

/// Cryptographically secure random numbers that repeat for the same key: the ChaCha20 key stream (ChaChaPoly over
/// zeros, a new nonce per buffer). Upstream's `CryptoRandomBuffer` encrypts zeros with AES-CBC for the same purpose.
struct NoiseStream {
    private let key: SymmetricKey
    private var counter: UInt64 = 0
    private var buffer: [UInt8] = []
    private var index = 0
    private static let zeros = [UInt8](repeating: 0, count: 16384)

    init(key: SymmetricKey) {
        self.key = key
    }

    mutating func nextUInt32() -> UInt32 {
        if index + 4 > buffer.count { refill() }
        let value = UInt32(buffer[index]) | UInt32(buffer[index + 1]) << 8 | UInt32(buffer[index + 2]) << 16
            | UInt32(buffer[index + 3]) << 24
        index += 4
        return value
    }

    /// Upstream `GetNextInt`: an even pick from `range` (rejection sampling, no modulo bias).
    mutating func next(in range: ClosedRange<Int>) -> Int {
        let span = UInt32(range.upperBound - range.lowerBound + 1)
        guard span > 1 else { return range.lowerBound }
        let limit = UInt32.max - UInt32.max % span
        var value = nextUInt32()
        while value >= limit { value = nextUInt32() }
        return range.lowerBound + Int(value % span)
    }

    private mutating func refill() {
        var nonce = [UInt8](repeating: 0, count: 12)
        withUnsafeBytes(of: counter.littleEndian) { nonce.replaceSubrange(0..<8, with: $0) }
        counter += 1
        index = 0
        if let chachaNonce = try? ChaChaPoly.Nonce(data: nonce),
           let sealed = try? ChaChaPoly.seal(Self.zeros, using: key, nonce: chachaNonce) {
            buffer = Array(sealed.ciphertext)
        } else {
            // Never expected; the noise is then random but not repeatable.
            var generator = SystemRandomNumberGenerator()
            buffer = (0..<Self.zeros.count).map { _ in UInt8.random(in: 0...255, using: &generator) }
        }
    }
}
