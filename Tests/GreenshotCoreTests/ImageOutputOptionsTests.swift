// SPDX-License-Identifier: GPL-3.0-or-later

import CoreGraphics
import Foundation
import ImageIO
import Testing
@testable import GreenshotCore

/// The output settings of a save (upstream `SurfaceOutputSettings` and `ImageIO.CreateImageForOutput`).
struct ImageOutputOptionsTests {
    /// 200 colours, opaque.
    let fewColors = TestImage.make(width: 20, height: 10) { x, y in RGBA(r: UInt8(x * 12), g: UInt8(y * 25), b: 40, a: 255) }
    /// 4096 colours, opaque.
    let gradient = TestImage.make(width: 64, height: 64) { x, y in RGBA(r: UInt8(x * 4), g: UInt8(y * 4), b: 99, a: 255) }

    @Test func optionsFromTheSettings() {
        var s = AppSettings()
        s.outputFormat = .gif
        s.jpegQuality = 55
        s.reduceColors = true
        s.reduceColorsTo = 64
        s.autoReduceColors = true
        s.pdf.pageSize = .letter
        let options = ImageOutputOptions(settings: s, scale: 2, title: "Shot")
        #expect(options.format == .gif && options.jpegQuality == 55 && options.scale == 2)
        #expect(options.reduceColors && options.reduceColorsTo == 64 && options.autoReduceColors)
        #expect(options.pdf.pageSize == .letter && options.title == "Shot")
        #expect(ImageOutputOptions(settings: s, format: .png).format == .png)
    }

    @Test func autoReduceWritesAPalettePNGWithTheSamePixels() throws {
        let data = try ImageExporter.data(for: fewColors, options: ImageOutputOptions(format: .png, autoReduceColors: true))
        #expect(pngColorType(data) == 3)
        #expect(pngChunks(data).contains("PLTE"))
        let decoded = try decode(data)
        for (x, y) in [(0, 0), (7, 3), (19, 9)] {
            #expect(TestImage.pixel(decoded, x, y) == TestImage.pixel(fewColors, x, y))
        }
    }

    @Test func autoReduceLeavesManyColoursAndTransparencyAlone() throws {
        let many = try ImageExporter.data(for: gradient, options: ImageOutputOptions(format: .png, autoReduceColors: true))
        #expect(pngColorType(many) != 3)
        let seeThrough = TestImage.make(width: 8, height: 8) { x, _ in x < 4 ? .red : RGBA(r: 0, g: 0, b: 0, a: 0) }
        let transparent = try ImageExporter.data(for: seeThrough, options: ImageOutputOptions(format: .png, autoReduceColors: true))
        #expect(pngColorType(transparent) == 6)
        // Without the setting nothing changes.
        #expect(pngColorType(try ImageExporter.data(for: fewColors, options: ImageOutputOptions(format: .png))) != 3)
    }

    @Test func reduceColorsWritesAPaletteWithAtMostTheCount() throws {
        let options = ImageOutputOptions(format: .png, reduceColors: true, reduceColorsTo: 16)
        let data = try ImageExporter.data(for: gradient, options: options)
        #expect(pngColorType(data) == 3)
        #expect(distinctColors(try decode(data)) <= 16)
        // TIFF gets a palette too.
        let tiff = try ImageExporter.data(for: gradient, options: ImageOutputOptions(format: .tiff, reduceColors: true))
        let tiffSource = try #require(CGImageSourceCreateWithData(tiff as CFData, nil))
        let properties = try #require(CGImageSourceCopyPropertiesAtIndex(tiffSource, 0, nil) as? [CFString: Any])
        #expect((properties[kCGImagePropertyIsIndexed] as? Bool) == true)
    }

    @Test func transparentImagesAreReducedButKeepTheirAlpha() throws {
        let seeThrough = TestImage.make(width: 64, height: 64) { x, y in
            RGBA(r: UInt8(x * 4), g: UInt8(y * 4), b: 99, a: x < 8 ? 0 : 255)
        }
        let data = try ImageExporter.data(for: seeThrough, options: ImageOutputOptions(format: .png, reduceColors: true, reduceColorsTo: 8))
        #expect(pngColorType(data) == 6)
        let decoded = try decode(data)
        #expect(TestImage.pixel(decoded, 2, 2).a == 0)
        #expect(distinctColors(decoded) <= 9)
    }

    @Test func gifIsAlwaysReduced() throws {
        let data = try ImageExporter.data(for: gradient, options: ImageOutputOptions(format: .gif, reduceColorsTo: 16))
        #expect(distinctColors(try decode(data)) <= 16)
    }

    @Test func jpegKeepsItsColours() {
        let options = ImageOutputOptions(format: .jpg, reduceColors: true, reduceColorsTo: 2, autoReduceColors: true)
        #expect(ImageExporter.reducedColors(gradient, options: options) === gradient)
        #expect(!ImageFormat.png.usesQuality && ImageFormat.jpg.usesQuality)
    }

    @Test func paletteFilesKeepTheResolution() throws {
        let data = try ImageExporter.data(for: fewColors, options: ImageOutputOptions(format: .png, scale: 2, autoReduceColors: true))
        let source = try #require(CGImageSourceCreateWithData(data as CFData, nil))
        let properties = try #require(CGImageSourceCopyPropertiesAtIndex(source, 0, nil) as? [CFString: Any])
        #expect(try #require(properties[kCGImagePropertyDPIWidth] as? NSNumber).doubleValue.rounded() == 144)
    }

    @Test func softwareTagIsWritten() throws {
        for format in [ImageFormat.png, .jpg, .tiff] {
            let data = try ImageExporter.data(for: fewColors, options: ImageOutputOptions(format: format))
            let source = try #require(CGImageSourceCreateWithData(data as CFData, nil))
            let properties = try #require(CGImageSourceCopyPropertiesAtIndex(source, 0, nil) as? [CFString: Any])
            let png = (properties[kCGImagePropertyPNGDictionary] as? [CFString: Any])?[kCGImagePropertyPNGSoftware] as? String
            let tiff = (properties[kCGImagePropertyTIFFDictionary] as? [CFString: Any])?[kCGImagePropertyTIFFSoftware] as? String
            let software = try #require(png ?? tiff, "\(format)")
            #expect(software.hasPrefix("Greenshot for Mac (Community)"), "\(format)")
        }
    }

    @Test func colorCountStopsEarly() {
        #expect(ImageEffects.colorCount(gradient, atMost: 255) == 256)
        #expect(ImageEffects.colorCount(fewColors, atMost: 255) == 200)
    }

    @Test func indexedNeedsOpaquePixelsAndFewColours() throws {
        #expect(ColorQuantizer.indexed(gradient) == nil)
        let indexed = try #require(ColorQuantizer.indexed(fewColors))
        #expect(indexed.bitsPerPixel == 8 && indexed.colorSpace?.model == .indexed)
        #expect(ColorQuantizer.indexed(TestImage.solid(width: 2, height: 2, RGBA(r: 0, g: 0, b: 0, a: 0))) == nil)
    }

    // MARK: Helpers

    private func decode(_ data: Data) throws -> CGImage {
        try #require(CGImageSourceCreateWithData(data as CFData, nil).flatMap { CGImageSourceCreateImageAtIndex($0, 0, nil) })
    }

    /// The colour type byte of the PNG header (3 is a palette).
    private func pngColorType(_ data: Data) -> UInt8 {
        data.count > 25 ? data[data.startIndex + 25] : 0
    }

    private func pngChunks(_ data: Data) -> [String] {
        let bytes = [UInt8](data)
        var names: [String] = []
        var i = 8
        while i + 8 <= bytes.count {
            let length = Int(bytes[i]) << 24 | Int(bytes[i + 1]) << 16 | Int(bytes[i + 2]) << 8 | Int(bytes[i + 3])
            names.append(String(decoding: bytes[(i + 4)..<(i + 8)], as: UTF8.self))
            i += 12 + length
        }
        return names
    }

    private func distinctColors(_ image: CGImage) -> Int {
        var colors = Set<UInt32>()
        for y in 0..<image.height {
            for x in 0..<image.width {
                let p = TestImage.pixel(image, x, y)
                colors.insert(UInt32(p.r) << 16 | UInt32(p.g) << 8 | UInt32(p.b))
            }
        }
        return colors.count
    }
}
