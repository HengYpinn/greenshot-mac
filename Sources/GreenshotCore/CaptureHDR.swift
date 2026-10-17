// Greenshot for Mac (Community) - an unofficial macOS port of Greenshot
// Copyright (C) 2026 Greenshot for Mac (Community) contributors
// Based on Greenshot, Copyright (C) 2007-2026 Thomas Braun, Jens Klingen, Robin Krom
// SPDX-License-Identifier: GPL-3.0-or-later

import CoreGraphics
import Foundation

/// The brightest value of an HDR picture and the share of its pixels brighter than SDR white (upstream
/// `HdrContent.Measure`). Values in EDR units: SDR white is 1.0.
public struct HDRMeasurement: Equatable, Sendable {
    public var peak: Float
    public var highlightShare: Float

    public init(peak: Float, highlightShare: Float) {
        self.peak = peak
        self.highlightShare = highlightShare
    }

    /// Something on the picture is brighter than SDR white: an HDR video, photo or game.
    public var hasHDRContent: Bool { peak > CaptureHDR.sdrMargin }
}

/// HDR screens: a picture of an HDR display tone mapped into an 8-bit sRGB screenshot, so the bright parts of HDR content
/// keep their detail instead of being cut off (upstream 1.4, `Greenshot.Base/Native/HdrContent.cs` and
/// `HdrToneMapper.cs`). Pictures without HDR content aren't tone mapped at all: the app keeps the SDR picture
/// ScreenCaptureKit took, so their colours stay exactly as before.
///
/// macOS counts in EDR units, SDR white = 1.0, so upstream's nits become ratios: upstream's white level of 200 nits
/// with a peak of 800 nits is a white level of 1 with a peak of 4 here.
public enum CaptureHDR {
    /// Share of pixels brighter than SDR white up to which SDR white stays white, and from which the peak becomes white
    /// (upstream `FewHighlights`, `MostlyHighlights`).
    public static let fewHighlights: Float = 0.02
    public static let mostlyHighlights: Float = 0.10
    /// A value within this factor of SDR white is SDR; the margin covers half-float rounding (upstream `SdrMargin`).
    public static let sdrMargin: Float = 1.01
    /// In units of the white level, values up to the knee stay as they are; above it the highlights are compressed so the
    /// peak becomes white (upstream lets Direct2D's `HdrToneMap` in HDR mode do this).
    public static let knee: Float = 0.9

    /// The brightness (EDR units) that becomes white (upstream `HdrContent.WhiteLevelInNits`). Few highlights: SDR white
    /// stays white; mostly highlights: the peak becomes white, like the Xbox Game Bar; in between it blends by the share
    /// of highlights. `displayPeak` is the display's headroom; an implausible one (below SDR white, 0 when unknown) is
    /// ignored.
    public static func whiteLevel(peak: Float, displayPeak: Float, highlightShare: Float) -> Float {
        let limited = displayPeak > 1 && displayPeak <= 10_000 / 80 ? min(peak, displayPeak) : peak
        guard limited > sdrMargin else { return 1 }
        let darken = min(max((highlightShare - fewHighlights) / (mostlyHighlights - fewHighlights), 0), 1)
        return 1 + (limited - 1) * darken
    }

    /// The highlight curve for the largest colour channel, in units of the white level: unchanged up to `knee`, `peak`
    /// becomes 1, smooth (no bend at the knee) and never darker for a brighter value. Without highlights above white
    /// (`peak` ≤ 1) only what is brighter than white is cut.
    public static func compress(_ value: Float, peak: Float) -> Float {
        guard peak > 1 else { return min(value, 1) }
        guard value > knee else { return value }
        guard value < peak else { return 1 }
        let a = (peak - knee) / (1 - knee)
        let t = (value - knee) / (peak - knee)
        return knee + (1 - knee) * a * t / (1 + (a - 1) * t)
    }

    // MARK: Pictures

    /// The pictures of one display tone mapped with the same white level, the first one (without the mouse pointer)
    /// measured; nil when it has no HDR content (keep the SDR pictures then) or something failed.
    public static func toneMapped(_ pictures: [CGImage], displayPeak: Float) -> (images: [CGImage], measurement: HDRMeasurement,
                                                                              whiteLevel: Float)? {
        guard let first = pictures.first, let measurement = measure(first), measurement.hasHDRContent else { return nil }
        let white = whiteLevel(peak: measurement.peak, displayPeak: displayPeak, highlightShare: measurement.highlightShare)
        let mapped = pictures.compactMap { toneMap($0, whiteLevel: white, peak: measurement.peak) }
        guard mapped.count == pictures.count else { return nil }
        return (mapped, measurement, white)
    }

    /// The rows drawn into a float buffer at a time: about 24 MB for a 6K display instead of 330 MB for all of it.
    static let bandHeight = 256

    /// Measures every second pixel of every second row (upstream: enough for these two numbers, a quarter of the work).
    public static func measure(_ image: CGImage) -> HDRMeasurement? {
        var peak: Float = 0
        var brighter = 0
        var counted = 0
        let done = forEachBand(of: image) { buffer, width, rows in
            let part = measure(buffer, width: width, height: rows)
            peak = max(peak, part.peak)
            brighter += part.brighter
            counted += part.counted
        }
        guard done else { return nil }
        return HDRMeasurement(peak: peak, highlightShare: counted > 0 ? Float(brighter) / Float(counted) : 0)
    }

    /// The measurement of premultiplied RGBA floats, `width` pixels per row: NaN and infinite values skipped, colours
    /// unpremultiplied.
    static func measure(_ pixels: UnsafeMutableBufferPointer<Float>, width: Int, height: Int) -> (peak: Float, brighter: Int, counted: Int) {
        var peak: Float = 0
        var brighter = 0
        var counted = 0
        let sdrWhite = sdrMargin
        for row in stride(from: 0, to: height, by: 2) {
            for x in stride(from: 0, to: width, by: 2) {
                let i = (row * width + x) * 4
                var value = max(pixels[i], max(pixels[i + 1], pixels[i + 2]))
                let alpha = pixels[i + 3]
                if alpha > 0.0001 && alpha < 1 { value /= alpha }
                // NaN fails the comparison.
                guard value.isFinite, value >= 0 else { continue }
                counted += 1
                peak = max(peak, value)
                if value > sdrWhite { brighter += 1 }
            }
        }
        return (peak, brighter, counted)
    }

    /// The picture with white level `whiteLevel` and the highlights up to `peak` compressed, as 8-bit sRGB.
    public static func toneMap(_ image: CGImage, whiteLevel: Float, peak: Float) -> CGImage? {
        guard let space = CGColorSpace(name: CGColorSpace.sRGB),
              let output = CGContext(data: nil, width: image.width, height: image.height, bitsPerComponent: 8, bytesPerRow: 0,
                                     space: space, bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue)
        else { return nil }
        let relativePeak = peak / whiteLevel
        var top = 0
        let done = forEachBand(of: image) { buffer, width, rows in
            // The rows of a band in parallel: each row is its own part of the buffer.
            if let base = buffer.baseAddress {
                DispatchQueue.concurrentPerform(iterations: rows) { row in
                    map(UnsafeMutableBufferPointer(start: base + row * width * 4, count: width * 4), count: width,
                        whiteLevel: whiteLevel, peak: relativePeak)
                }
            }
            if let band = bandImage(buffer, width: width, height: rows) {
                // The output's origin is at the bottom left.
                output.draw(band, in: CGRect(x: 0, y: image.height - top - rows, width: width, height: rows))
            }
            top += rows
        }
        return done ? output.makeImage() : nil
    }

    /// Divides by the white level and compresses the highlights, keeping each pixel's hue (all channels scaled by the
    /// curve of the largest one: an orange highlight stays orange instead of turning yellow).
    static func map(_ pixels: UnsafeMutableBufferPointer<Float>, count: Int, whiteLevel: Float, peak: Float) {
        let scale = 1 / whiteLevel
        for p in 0..<count {
            let i = p * 4
            let r = pixels[i] * scale
            let g = pixels[i + 1] * scale
            let b = pixels[i + 2] * scale
            let alpha = pixels[i + 3]
            var largest = max(r, max(g, b))
            if alpha > 0.0001 && alpha < 1 { largest /= alpha }
            var factor: Float = 1
            if largest.isFinite, largest > knee {
                factor = compress(largest, peak: peak) / largest
            }
            pixels[i] = r * factor
            pixels[i + 1] = g * factor
            pixels[i + 2] = b * factor
        }
    }

    private static let workingSpace = CGColorSpace(name: CGColorSpace.extendedLinearSRGB)
    private static let floatInfo = CGImageAlphaInfo.premultipliedLast.rawValue | CGBitmapInfo.floatComponents.rawValue
        | CGBitmapInfo.byteOrder32Little.rawValue

    /// Calls `body` with each band of `image` (top to bottom) as premultiplied RGBA floats in extended linear sRGB: SDR
    /// white is 1, HDR highlights above, colours outside sRGB below 0 or above 1. False when the buffer can't be made.
    private static func forEachBand(of image: CGImage, _ body: (UnsafeMutableBufferPointer<Float>, Int, Int) -> Void) -> Bool {
        let width = image.width
        let height = image.height
        guard width > 0, height > 0, let space = workingSpace else { return false }
        let rowsPerBand = min(bandHeight, height)
        var buffer = [Float](repeating: 0, count: width * rowsPerBand * 4)
        return buffer.withUnsafeMutableBufferPointer { pixels -> Bool in
            var top = 0
            while top < height {
                let rows = min(rowsPerBand, height - top)
                guard let context = CGContext(data: pixels.baseAddress, width: width, height: rows, bitsPerComponent: 32,
                                              bytesPerRow: width * 16, space: space, bitmapInfo: floatInfo),
                      let band = image.cropping(to: CGRect(x: 0, y: top, width: width, height: rows))
                else { return false }
                context.clear(CGRect(x: 0, y: 0, width: width, height: rows))
                context.draw(band, in: CGRect(x: 0, y: 0, width: width, height: rows))
                body(UnsafeMutableBufferPointer(rebasing: pixels[0..<(width * rows * 4)]), width, rows)
                top += rows
            }
            return true
        }
    }

    /// A band of floats as a picture, to draw into the 8-bit result (Core Graphics converts to sRGB and rounds).
    private static func bandImage(_ pixels: UnsafeMutableBufferPointer<Float>, width: Int, height: Int) -> CGImage? {
        guard let space = workingSpace,
              let context = CGContext(data: pixels.baseAddress, width: width, height: height, bitsPerComponent: 32,
                                      bytesPerRow: width * 16, space: space, bitmapInfo: floatInfo)
        else { return nil }
        return context.makeImage()
    }
}
