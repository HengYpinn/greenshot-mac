// Greenshot for Mac (Community) - an unofficial macOS port of Greenshot
// Copyright (C) 2026 Greenshot for Mac (Community) contributors
// SPDX-License-Identifier: GPL-3.0-or-later

import CoreGraphics
import Foundation
import Testing
@testable import GreenshotCore

/// HDR screens (CAP-120): upstream's `HdrToneMapperTests` in EDR units. Upstream uses an SDR white of 200 nits and a
/// display of 1000 nits: here SDR white is 1 and the display's headroom 5.
struct CaptureHDRTests {
    private let display: Float = 5

    /// A float picture in extended linear sRGB (or `space`); each value fills a 2 × 2 block, so the measurement (every
    /// second pixel of every second row) sees each of them.
    private func hdrImage(_ pixels: [(Float, Float, Float)], space name: CFString = CGColorSpace.extendedLinearSRGB) -> CGImage {
        let width = pixels.count * 2
        let height = 2
        var floats = [Float](repeating: 0, count: width * height * 4)
        for (index, pixel) in pixels.enumerated() {
            for row in 0..<2 {
                for column in 0..<2 {
                    let i = (row * width + index * 2 + column) * 4
                    floats[i] = pixel.0
                    floats[i + 1] = pixel.1
                    floats[i + 2] = pixel.2
                    floats[i + 3] = 1
                }
            }
        }
        let info = CGImageAlphaInfo.premultipliedLast.rawValue | CGBitmapInfo.floatComponents.rawValue
            | CGBitmapInfo.byteOrder32Little.rawValue
        let space = CGColorSpace(name: name)!
        return floats.withUnsafeMutableBytes { bytes in
            let context = CGContext(data: bytes.baseAddress, width: width, height: height, bitsPerComponent: 32,
                                    bytesPerRow: width * 16, space: space, bitmapInfo: info)!
            return context.makeImage()!
        }
    }

    /// The pixel of value number `index` after tone mapping.
    private func pixel(_ image: CGImage, _ index: Int) -> RGBA {
        TestImage.pixel(image, index * 2, 0)
    }

    private func grey(_ value: Float) -> (Float, Float, Float) { (value, value, value) }

    @Test(arguments: [
        (Float(4), Float(0.5), Float(4)), // mostly highlights: the brightest pixel becomes white
        (10, 0.5, 5), // brighter than the display: the display's peak becomes white
        (4, 0.01, 1), // a small highlight on an SDR desktop: SDR white stays white
        (1, 0.5, 1), // SDR only
        (4, 0.06, 2.5), // in between
    ])
    func theWhiteLevelFollowsTheHighlights(peak: Float, share: Float, expected: Float) {
        let white = CaptureHDR.whiteLevel(peak: peak, displayPeak: display, highlightShare: share)
        #expect(abs(white - expected) < 0.01)
    }

    @Test func anImplausibleDisplayPeakIsIgnored() {
        let white = CaptureHDR.whiteLevel(peak: 4, displayPeak: 0.5, highlightShare: 0.5)
        #expect(abs(white - 4) < 0.01)
    }

    @Test func theCurveOnlyCompressesHighlights() {
        #expect(CaptureHDR.compress(0.5, peak: 4) == 0.5)
        #expect(CaptureHDR.compress(CaptureHDR.knee, peak: 4) == CaptureHDR.knee)
        #expect(CaptureHDR.compress(4, peak: 4) == 1)
        #expect(CaptureHDR.compress(9, peak: 4) == 1)
        // No bend at the knee: just above it the curve still rises like the values.
        let step: Float = 0.0001
        let rise = CaptureHDR.compress(CaptureHDR.knee + step, peak: 4) - CaptureHDR.knee
        #expect(abs(rise - step) < step / 50)
        var previous: Float = 0
        for value in stride(from: Float(0), through: 5, by: 0.05) {
            let mapped = CaptureHDR.compress(value, peak: 4)
            #expect(mapped >= previous)
            previous = mapped
        }
        // Without highlights only what is above white is cut.
        #expect(CaptureHDR.compress(1.2, peak: 1) == 1)
    }

    @Test func measuringFindsThePeakAndTheShareOfHighlights() throws {
        // A red twice as bright as SDR red has less luminance than SDR white: no highlight, but the largest channel.
        let image = hdrImage([grey(1), grey(0.5), grey(4), (2, 0, 0)])
        let measurement = try #require(CaptureHDR.measure(image))
        #expect(abs(measurement.peak - 4) < 0.01)
        #expect(abs(measurement.highlightShare - 0.25) < 0.01)
        #expect(abs(measurement.channelPeak - 4) < 0.01)
        #expect(measurement.hasHDRContent)
    }

    @Test func aWideGamutColourAtSDRBrightnessIsNoHDRContent() throws {
        // A saturated Display P3 red at SDR level: its red channel is about 1.22 in extended sRGB, its luminance below 1.
        var pixels = [(Float, Float, Float)](repeating: grey(1), count: 50)
        pixels[0] = (1, 0, 0)
        let image = hdrImage(pixels, space: CGColorSpace.extendedLinearDisplayP3)
        let measurement = try #require(CaptureHDR.measure(image))
        #expect(measurement.channelPeak > 1.2)
        #expect(!measurement.hasHDRContent)
        #expect(CaptureHDR.toneMapped([image], displayPeak: display) == nil)
    }

    @Test func sdrContentIsNotToneMapped() throws {
        let image = hdrImage([grey(1), grey(0.2), grey(0), (1, 0, 0)])
        let measurement = try #require(CaptureHDR.measure(image))
        #expect(!measurement.hasHDRContent)
        #expect(CaptureHDR.toneMapped([image], displayPeak: display) == nil)
    }

    @Test func theMeasurementSkipsBrokenValuesAndUnpremultiplies() {
        // 4 × 2 pixels, the measurement reads (0, 0) and (2, 0).
        var floats: [Float] = [.nan, 0, 0, 1, 0, 0, 0, 1, 0.5, 0.5, 0.5, 0.5, 0, 0, 0, 1]
        floats += [Float](repeating: 0, count: 16)
        let part = floats.withUnsafeMutableBufferPointer { CaptureHDR.measure($0, width: 4, height: 2) }
        #expect(part.counted == 1)
        #expect(abs(part.peak - 1) < 0.001)
        #expect(part.channelPeak == 1)
        #expect(part.brighter == 0)
    }

    @Test func mostlyHighlightsAreScaledWithTheirHue() throws {
        // Half of the picture is an orange highlight (luminance 2.28): it becomes the white level, SDR white turns grey.
        // Upstream measures the largest channel (4) and makes SDR white darker still (130–145).
        let image = hdrImage([grey(1), (4, 2, 0)])
        let result = try #require(CaptureHDR.toneMapped([image], displayPeak: display))
        let white = pixel(result.images[0], 0)
        let orange = pixel(result.images[0], 1)
        #expect((172...182).contains(white.r))
        #expect(orange.r >= 250)
        #expect((180...196).contains(orange.g))
        #expect(orange.b <= 5)
    }

    @Test func brighterValuesAreNeverDarker() throws {
        let values: [Float] = [0, 0.1, 0.25, 0.5, 0.75, 1, 1.5, 2, 3, 5]
        let result = try #require(CaptureHDR.toneMapped([hdrImage(values.map(grey))], displayPeak: display))
        #expect(pixel(result.images[0], 0).r == 0)
        for index in 1..<values.count {
            let before = pixel(result.images[0], index - 1).r
            let now = pixel(result.images[0], index).r
            #expect(now >= before, "\(values[index]) × SDR white became darker than \(values[index - 1])")
        }
    }

    @Test func aSmallHighlightKeepsTheSDRPicture() throws {
        // One highlight among many SDR pixels: SDR white stays the white level, so the exact SDR picture is kept.
        var values = [Float](repeating: 0.5, count: 60)
        values[0] = 0.2
        values[1] = 1
        values[2] = 4
        let image = hdrImage(values.map(grey))
        let measurement = try #require(CaptureHDR.measure(image))
        #expect(measurement.hasHDRContent)
        #expect(CaptureHDR.toneMapped([image], displayPeak: display) == nil)
    }

    @Test func atTheWhiteLevelOfSDRWhiteNothingUpToWhiteChanges() throws {
        // Tone mapped anyway: white stays white, the middle is as Core Graphics converts it, the highlight keeps its hue.
        let image = hdrImage([grey(0.2), grey(1), grey(0.95), (4, 2, 0)])
        let mapped = try #require(CaptureHDR.toneMap(image, whiteLevel: 1, peak: 4))
        #expect(pixel(mapped, 1) == RGBA.white)
        #expect(pixel(mapped, 2) == TestImage.pixel(hdrImageAsSRGB(grey(0.95)), 0, 0))
        #expect(pixel(mapped, 0) == TestImage.pixel(hdrImageAsSRGB(grey(0.2)), 0, 0))
        let orange = pixel(mapped, 3)
        #expect(orange.r == 255)
        #expect((185...190).contains(orange.g))
    }

    @Test func everyPictureOfADisplayGetsTheSameWhiteLevel() throws {
        let plain = hdrImage([grey(1), grey(4)])
        let pointer = hdrImage([grey(1), grey(1)])
        let result = try #require(CaptureHDR.toneMapped([plain, pointer], displayPeak: display))
        #expect(result.images.count == 2)
        #expect(pixel(result.images[0], 0) == pixel(result.images[1], 0))
    }

    @Test func aTallPictureIsMappedBandByBand() throws {
        // More rows than one band: the bands land where they belong.
        let width = 4
        let height = CaptureHDR.bandHeight + 10
        var floats = [Float](repeating: 0, count: width * height * 4)
        for row in 0..<height {
            let value: Float = row < 2 ? 4 : (row >= height - 4 ? 0 : 0.5)
            for x in 0..<width {
                let i = (row * width + x) * 4
                floats[i] = value
                floats[i + 1] = value
                floats[i + 2] = value
                floats[i + 3] = 1
            }
        }
        let info = CGImageAlphaInfo.premultipliedLast.rawValue | CGBitmapInfo.floatComponents.rawValue
            | CGBitmapInfo.byteOrder32Little.rawValue
        let image = floats.withUnsafeMutableBytes { bytes in
            CGContext(data: bytes.baseAddress, width: width, height: height, bitsPerComponent: 32, bytesPerRow: width * 16,
                      space: CGColorSpace(name: CGColorSpace.extendedLinearSRGB)!, bitmapInfo: info)!.makeImage()!
        }
        let mapped = try #require(CaptureHDR.toneMap(image, whiteLevel: 1, peak: 4))
        #expect(TestImage.pixel(mapped, 0, 0).r == 255)
        #expect(TestImage.pixel(mapped, 0, height - 1).r == 0)
        let middle = TestImage.pixel(mapped, 0, CaptureHDR.bandHeight + 2).r
        #expect((185...190).contains(middle))
    }

    /// A one-value picture converted to 8-bit sRGB by Core Graphics alone, for comparison.
    private func hdrImageAsSRGB(_ pixel: (Float, Float, Float)) -> CGImage {
        let source = hdrImage([pixel])
        let context = CGContext(data: nil, width: source.width, height: source.height, bitsPerComponent: 8, bytesPerRow: 0,
                                space: CGColorSpace(name: CGColorSpace.sRGB)!,
                                bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue)!
        context.draw(source, in: CGRect(x: 0, y: 0, width: source.width, height: source.height))
        return context.makeImage()!
    }
}
