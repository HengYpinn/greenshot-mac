// SPDX-License-Identifier: GPL-3.0-or-later

import CoreGraphics
import Foundation
import ImageIO
import PDFKit
import Testing
@testable import GreenshotCore

/// The formats written without ImageIO: TGA, PBM, ICO (upstream `ImageSharpFileFormatHandler`,
/// `IconFileFormatHandler`) and PDF (the PDF plugin's `PdfFileFormatHandler`).
struct ImageFormatsTests {
    /// Left half red, right half half-transparent blue, one green pixel: runs and single pixels.
    let image = TestImage.make(width: 10, height: 4) { x, y in
        if x == 3 && y == 1 { return RGBA(r: 0, g: 255, b: 0, a: 255) }
        return x < 5 ? .red : RGBA(r: 0, g: 0, b: 128, a: 128)
    }

    @Test func extensionsTypesAndNames() {
        #expect(ImageFormat(fileExtension: "ICO") == .ico)
        #expect(ImageFormat(fileExtension: "tga") == .tga)
        #expect(ImageFormat(fileExtension: "pbm") == .pbm)
        #expect(ImageFormat(fileExtension: "pdf") == .pdf)
        #expect(ImageFormat.tga.utType.identifier == "com.truevision.tga-image")
        #expect(ImageFormat.pbm.utType.conforms(to: .image) && ImageFormat.ico.utType.conforms(to: .image))
        #expect(ImageFormat.pdf.mimeType == "application/pdf" && ImageFormat.tga.mimeType == "image/x-tga")
        for format in ImageFormat.allCases {
            #expect(ImageFormat(fileExtension: format.fileExtension) == format)
            #expect(!format.displayName.isEmpty)
        }
    }

    @Test func tgaIsRunLengthEncoded32BitTopDown() throws {
        let data = try ImageExporter.data(for: image, format: .tga)
        let bytes = [UInt8](data)
        #expect(bytes[2] == 10)
        #expect(bytes[12] == 10 && bytes[13] == 0 && bytes[14] == 4 && bytes[15] == 0)
        #expect(bytes[16] == 32 && bytes[17] == 0x28)
        // First row: a run of 5 red pixels (B G R A), then 5 blue ones with straight alpha.
        let redRun: [UInt8] = [0x84, 0, 0, 255, 255]
        let blueRun: [UInt8] = [0x84, 255, 0, 0, 128]
        #expect(Array(bytes[18..<23]) == redRun)
        #expect(Array(bytes[23..<28]) == blueRun)
        #expect(String(decoding: bytes.suffix(18).prefix(17), as: UTF8.self) == "TRUEVISION-XFILE.")
        let decoded = try decode(data)
        #expect(decoded.width == 10 && decoded.height == 4)
        #expect(TestImage.pixel(decoded, 0, 0) == .red)
        #expect(TestImage.pixel(decoded, 3, 1) == RGBA(r: 0, g: 255, b: 0, a: 255))
        #expect(TestImage.pixel(decoded, 8, 3).isClose(to: RGBA(r: 0, g: 0, b: 128, a: 128), tolerance: 2))
    }

    @Test func tgaRunsAndRawStretchesStayWithinARow() {
        var data = Data()
        let pixels: [UInt32] = [1, 2, 3, 3, 3, 4] + [UInt32](repeating: 9, count: 130)
        ImageFormatEncoders.appendRunLengthRow(pixels, from: 0, count: 6, to: &data)
        // Raw 1, 2; run of three 3s; raw 4.
        #expect(data.count == 1 + 8 + 1 + 4 + 1 + 4)
        #expect(data[0] == 0x01 && data[9] == 0x82 && data[14] == 0x00)
        var long = Data()
        ImageFormatEncoders.appendRunLengthRow(pixels, from: 6, count: 130, to: &long)
        // 130 equal pixels: a run of 128 and a run of 2.
        #expect(long.count == 10 && long[0] == 0xFF && long[5] == 0x81)
    }

    @Test func pbmIsABinaryPixmapOnWhite() throws {
        let data = try ImageExporter.data(for: image, format: .pbm)
        let header = Data("P6\n10 4\n255\n".utf8)
        #expect(data.prefix(header.count) == header)
        #expect(data.count == header.count + 10 * 4 * 3)
        // The half-transparent blue on white.
        let i = header.count + 9 * 3
        #expect(abs(Int(data[i]) - 127) <= 2 && abs(Int(data[i + 2]) - 255) <= 2)
        let decoded = try decode(data)
        #expect(decoded.width == 10 && TestImage.pixel(decoded, 1, 1) == .red)
    }

    @Test(arguments: [(10, 10, 16), (40, 30, 48), (32, 32, 32), (1280, 800, 256)])
    func icoPicksTheBestSize(width: Int, height: Int, side: Int) throws {
        let source = TestImage.solid(width: width, height: height, .blue)
        let data = try ImageExporter.data(for: source, format: .ico)
        let bytes = [UInt8](data)
        let directory: [UInt8] = [0, 0, 1, 0, 1, 0]
        let pngSignature: [UInt8] = [0x89, 0x50, 0x4E, 0x47]
        let storedSide: Int = side == 256 ? 0 : side
        #expect(Array(bytes[0..<6]) == directory)
        #expect(Int(bytes[6]) == storedSide && bytes[6] == bytes[7])
        #expect(Array(bytes[22..<26]) == pngSignature)
        let decoded = try decode(data)
        #expect(decoded.width == side && decoded.height == side)
        // Fitted and centered on transparency.
        #expect(TestImage.pixel(decoded, side / 2, side / 2) == .blue)
        if width != height { #expect(TestImage.pixel(decoded, side / 2, 0).a == 0) }
    }

    @Test func pdfHasOnePageLaidOutByTheSettings() throws {
        var pdf = PDFSettings()
        pdf.pageSize = .a4
        let options = ImageOutputOptions(format: .pdf, scale: 2, pdf: pdf, title: "Report")
        let data = try ImageExporter.data(for: image, options: options)
        #expect(data.prefix(4) == Data("%PDF".utf8))
        let document = try #require(PDFDocument(data: data))
        #expect(document.pageCount == 1)
        let page = try #require(document.page(at: 0)).bounds(for: .mediaBox)
        #expect(abs(page.width - 595.3) < 1 && abs(page.height - 841.9) < 1)
        #expect(document.documentAttributes?[PDFDocumentAttribute.titleAttribute] as? String == "Report")
    }

    @Test func writingAPDFTakesTheFileNameAsTitle() throws {
        let url = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString).appendingPathComponent("Shot 1.pdf")
        defer { try? FileManager.default.removeItem(at: url.deletingLastPathComponent()) }
        try ImageExporter.write(image, to: url, options: ImageOutputOptions(format: .pdf))
        let document = try #require(PDFDocument(url: url))
        #expect(document.documentAttributes?[PDFDocumentAttribute.titleAttribute] as? String == "Shot 1")
    }

    @Test func newFormatsOpenAgain() throws {
        for format in [ImageFormat.tga, .pbm, .ico] {
            let url = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString + "." + format.fileExtension)
            defer { try? FileManager.default.removeItem(at: url) }
            try ImageExporter.write(image, to: url, format: format)
            #expect(ImageFileLoader.load(url) != nil, "\(format)")
        }
    }

    private func decode(_ data: Data) throws -> CGImage {
        try #require(CGImageSourceCreateWithData(data as CFData, nil).flatMap { CGImageSourceCreateImageAtIndex($0, 0, nil) })
    }
}
