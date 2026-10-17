// SPDX-License-Identifier: GPL-3.0-or-later

import CoreGraphics
import CryptoKit
import Foundation
import Testing
@testable import GreenshotCore

/// The pixelate that can't be reversed (upstream `PixelizationFilter`, 1aa2febb).
struct ImagePixelationTests {
    /// Stripes and a gradient: every block has different colors in it.
    let busy = TestImage.make(width: 60, height: 40) { x, y in
        RGBA(r: UInt8((x * 37 + y * 11) % 256), g: x % 3 == 0 ? 20 : 220, b: UInt8(y * 6), a: 255)
    }
    let key = SymmetricKey(size: .bits256)

    @Test func theSameSecretGivesTheSamePixels() throws {
        let first = try #require(ImagePixelation.pixelated(busy, blockSize: 8, key: key))
        let second = try #require(ImagePixelation.pixelated(busy, blockSize: 8, key: key))
        #expect(pixels(first) == pixels(second))
        let other = try #require(ImagePixelation.pixelated(busy, blockSize: 8, key: SymmetricKey(size: .bits256)))
        #expect(pixels(first) != pixels(other))
        #expect(first.width == busy.width && first.height == busy.height)
    }

    @Test func aBlockOfOneColorHasNoNoise() throws {
        let solid = TestImage.solid(width: 30, height: 20, RGBA(r: 10, g: 200, b: 90, a: 255))
        let result = try #require(ImagePixelation.pixelated(solid, blockSize: 6, key: key))
        let red: UInt32 = 10 << 24, green: UInt32 = 200 << 16, blue: UInt32 = 90 << 8
        let expected: UInt32 = red | green | blue | 255
        #expect(Set(pixels(result)) == [expected])
    }

    @Test func busyBlocksAreNoisyNotPlainAverages() throws {
        let result = try #require(ImagePixelation.pixelated(busy, blockSize: 10, key: key))
        // A plain block average gives each block one color; the noise makes many more.
        #expect(Set(pixels(result)).count > 200)
        // And much fewer than the original's, which is what pixelation is for: neighbours are close to each other.
        let a = TestImage.pixel(result, 3, 3), b = TestImage.pixel(result, 4, 3)
        #expect(abs(Int(a.g) - Int(b.g)) <= 6)
    }

    @Test func theNoiseStaysCloseToTheBlockAverage() throws {
        // Black and white pixels: every block that is not the last of its row or column is at least 7 × 7 pixels
        // (10 ± 3), so its average is 124...130; block noise ±12 and pixel noise ±3 keep every pixel within 15 of it.
        let checker = TestImage.make(width: 120, height: 90) { x, y in (x + y) % 2 == 0 ? .black : .white }
        let result = try #require(ImagePixelation.pixelated(checker, blockSize: 10, key: key))
        for y in 0..<(90 - 13) {
            for x in 0..<(120 - 13) {
                let p = TestImage.pixel(result, x, y)
                #expect([p.r, p.g, p.b].allSatisfy { (109...145).contains(Int($0)) } && p.a == 255, "\(x), \(y): \(p)")
            }
        }
    }

    @Test func anElementLooksTheSameInEveryRepaintAndExport() throws {
        // The renderer keys the noise by the element's id for the life of the app (upstream: per filter, not stored).
        var style = AnnotationStyle.defaults(for: .obfuscate)
        style.pixelSize = 6
        let element = Annotation(kind: .obfuscate, start: CGPoint(x: 5, y: 5), end: CGPoint(x: 55, y: 35), style: style)
        let first = try #require(AnnotationRenderer.flatten(base: busy, annotations: [element], scale: 1))
        let second = try #require(AnnotationRenderer.flatten(base: busy, annotations: [element], scale: 1))
        #expect(pixels(first) == pixels(second))
        var copy = element
        copy.id = UUID()
        let other = try #require(AnnotationRenderer.flatten(base: busy, annotations: [copy], scale: 1))
        #expect(pixels(first) != pixels(other))
    }

    @Test func blockSizeOneChangesNothing() throws {
        let required11 = try #require(ImagePixelation.pixelated(busy, blockSize: 1, key: key))
        #expect(required11 === busy)
    }

    @Test func blocksHaveRandomSizesAroundTheBlockSize() {
        var random = NoiseStream(key: key)
        let edges = ImagePixelation.boundaries(length: 600, blockSize: 12, random: &random)
        #expect(edges.first == 0 && edges.last == 600)
        let steps = zip(edges, edges.dropFirst()).map { $1 - $0 }
        for step in steps.dropLast() { #expect((8...16).contains(step), "\(step)") }
        #expect(Set(steps).count > 3)
    }

    @Test func everyElementHasItsOwnSecret() {
        let id = UUID()
        let first = ImagePixelation.key(for: id).withUnsafeBytes { Data($0) }
        #expect(ImagePixelation.key(for: id).withUnsafeBytes { Data($0) } == first)
        #expect(ImagePixelation.key(for: UUID()).withUnsafeBytes { Data($0) } != first)
    }

    @Test func transparentPixelsKeepTheirColorsWithinTheAlpha() throws {
        let faded = TestImage.make(width: 20, height: 20) { x, _ in RGBA(r: 255, g: UInt8(x * 12), b: 0, a: 128) }
        let result = try #require(ImagePixelation.pixelated(faded, blockSize: 5, key: key))
        for x in 0..<20 { #expect(TestImage.pixel(result, x, 7).a == 128) }
    }

    private func pixels(_ image: CGImage) -> [UInt32] {
        var result: [UInt32] = []
        for y in 0..<image.height {
            for x in 0..<image.width {
                let p = TestImage.pixel(image, x, y)
                result.append(UInt32(p.r) << 24 | UInt32(p.g) << 16 | UInt32(p.b) << 8 | UInt32(p.a))
            }
        }
        return result
    }
}
