// Greenshot for Mac (Community) - an unofficial macOS port of Greenshot
// Copyright (C) 2026 Greenshot for Mac (Community) contributors
// Based on Greenshot, Copyright (C) 2007-2026 Thomas Braun, Jens Klingen, Robin Krom
// SPDX-License-Identifier: GPL-3.0-or-later

import CoreGraphics
import Foundation
import ImageIO
import Testing
import UniformTypeIdentifiers
import Vision
@testable import GreenshotCore

/// Barcode elements as the editor draws them, read back with the Vision framework.
struct BarcodeElementTests {
    /// The element drawn by `AnnotationRenderer.flatten` on a white image (2 pixels per point).
    static func render(_ spec: BarcodeSpec, size: CGSize? = nil) -> CGImage? {
        var element = Annotation.barcodeElement(spec, at: CGPoint(x: 40, y: 40), scale: 2)
        if let size { element.end = CGPoint(x: 40 + size.width, y: 40 + size.height) }
        let width = Int(element.bounds.maxX) + 40
        let height = Int(element.bounds.maxY) + 40
        guard let context = AnnotationRenderer.makeContext(width: width, height: height) else { return nil }
        context.setFillColor(CGColor(gray: 1, alpha: 1))
        context.fill(CGRect(x: 0, y: 0, width: width, height: height))
        guard let white = context.makeImage() else { return nil }
        return AnnotationRenderer.flatten(base: white, annotations: [element], scale: 2)
    }

    /// What Vision reads in the element; on a miss the picture is written to the temporary folder to look at.
    static func decoded(_ spec: BarcodeSpec, as symbologies: [VNBarcodeSymbology], size: CGSize? = nil) throws -> [String] {
        let image = try #require(render(spec, size: size))
        let request = VNDetectBarcodesRequest()
        request.symbologies = symbologies
        try VNImageRequestHandler(cgImage: image, options: [:]).perform([request])
        let payloads = (request.results ?? []).compactMap(\.payloadStringValue)
        if payloads.isEmpty {
            let url = FileManager.default.temporaryDirectory.appendingPathComponent("barcode-\(spec.symbology.rawValue).png")
            if let destination = CGImageDestinationCreateWithURL(url as CFURL, UTType.png.identifier as CFString, 1, nil) {
                CGImageDestinationAddImage(destination, image, nil)
                CGImageDestinationFinalize(destination)
            }
            print("Vision read nothing in the \(spec.symbology) code; the picture is at \(url.path)")
        }
        return payloads
    }

    static func spec(_ symbology: GreenshotCore.BarcodeSymbology, _ text: String, _ change: (inout BarcodeSpec) -> Void = { _ in }) -> BarcodeSpec {
        var spec = BarcodeSpec()
        spec.symbology = symbology
        spec.text = text
        change(&spec)
        return spec
    }

    // MARK: Round trips

    /// What Vision calls each format (it has no UK Plessey; it reads UPC-A as EAN-13).
    static func vision(_ symbology: GreenshotCore.BarcodeSymbology) -> [VNBarcodeSymbology] {
        switch symbology {
        case .qrCode: return [.qr]
        case .aztec: return [.aztec]
        case .dataMatrix: return [.dataMatrix]
        case .pdf417: return [.pdf417]
        case .code128: return [.code128]
        case .code39: return [.code39]
        case .code93: return [.code93]
        case .ean13, .upcA: return [.ean13]
        case .ean8: return [.ean8]
        case .upcE: return [.upce]
        case .codabar: return [.codabar]
        case .itf: return [.i2of5]
        case .msi: return [.msiPlessey]
        case .plessey: return []
        }
    }

    /// Format, text, and what Vision reads: with the check digit, UPC-A as EAN-13, Codabar with its guards.
    static let readable: [(GreenshotCore.BarcodeSymbology, String, String)] = [
        (.qrCode, "https://getgreenshot.org", "https://getgreenshot.org"),
        (.aztec, "Greenshot for Mac", "Greenshot for Mac"),
        (.pdf417, "Greenshot PDF-417 1234567890", "Greenshot PDF-417 1234567890"),
        (.code128, "Greenshot-128", "Greenshot-128"),
        (.ean13, "590123412345", "5901234123457"),
        (.ean8, "9638507", "96385074"),
        (.upcA, "03600029145", "0036000291452"),
        (.upcE, "0425261", "04252614"),
        (.code39, "HELLO-39", "HELLO-39"),
        (.code93, "TEST93", "TEST93"),
        (.codabar, "12345", "A12345A"),
        (.codabar, "b40156d", "B40156D"),
        (.itf, "12345678", "12345678"),
        (.msi, "1234567", "12345674"),
    ]

    @Test(arguments: readable)
    func visionReadsTheElement(_ symbology: GreenshotCore.BarcodeSymbology, _ text: String, _ expected: String) throws {
        let payloads = try Self.decoded(Self.spec(symbology, text), as: Self.vision(symbology))
        #expect(payloads == [expected], "\(symbology)")
    }

    @Test func visionReadsFullASCII() throws {
        let code39 = try Self.decoded(Self.spec(.code39, "Hello, world!"), as: [.code39FullASCII])
        #expect(code39 == ["Hello, world!"])
        let code93 = try Self.decoded(Self.spec(.code93, "Hello, world!"), as: [.code93i])
        #expect(code93 == ["Hello, world!"])
    }

    @Test func roundDotsColoursAndMarginsStillRead() throws {
        let rounded = Self.spec(.qrCode, "https://getgreenshot.org") { $0.roundedDots = true }
        #expect(try Self.decoded(rounded, as: [.qr]) == ["https://getgreenshot.org"])
        let coloured = Self.spec(.qrCode, "colours") {
            $0.foreground = RGBAColor(red: 0, green: 0, blue: 0.5)
            $0.background = .yellow
            $0.margin = 4
        }
        #expect(try Self.decoded(coloured, as: [.qr]) == ["colours"])
        let tight = Self.spec(.aztec, "no margin") { $0.margin = 0; $0.roundedDots = true }
        #expect(try Self.decoded(tight, as: [.aztec]) == ["no margin"])
        let wide = Self.spec(.ean13, "4006381333931") { $0.margin = 10 }
        #expect(try Self.decoded(wide, as: [.ean13]) == ["4006381333931"])
    }

    /// Text beyond ASCII: UTF-8 in QR codes, UTF-8 with its ECI in Data Matrix, ISO 8859-1 in Aztec and PDF-417.
    @Test(arguments: [GreenshotCore.BarcodeSymbology.qrCode, .dataMatrix, .aztec, .pdf417])
    func accentsReadBack(_ symbology: GreenshotCore.BarcodeSymbology) throws {
        let spec = Self.spec(symbology, "Grüße, café")
        let payloads = try Self.decoded(spec, as: Self.vision(symbology), size: CGSize(width: 400, height: 400))
        #expect(payloads == ["Grüße, café"], "\(symbology)")
        #expect(spec.characterSetWarning == nil)
        let japanese = Self.spec(symbology, "日本語")
        #expect((japanese.characterSetWarning != nil) == (symbology == .aztec || symbology == .pdf417))
    }

    @Test func aWifiCodeReadsAsItsPayload() throws {
        var wifi = Self.spec(.qrCode, "")
        wifi.qrType = .wifi
        wifi.wifiSSID = "Home"
        wifi.wifiPassword = "secret"
        #expect(try Self.decoded(wifi, as: [.qr]) == ["WIFI:S:Home;T:WPA;P:secret;;"])
    }

    // MARK: Core Image

    /// The quiet zone Core Image draws is removed: the outer rows and columns of what is left have dark modules.
    @Test(arguments: ["A", "Greenshot for Mac (Community)", String(repeating: "0123456789", count: 30)])
    func coreImageBordersAreRemoved(_ text: String) throws {
        for symbology in [GreenshotCore.BarcodeSymbology.qrCode, .pdf417] {
            let matrix = try BarcodeGenerator.matrix(symbology, payload: text)
            let last = matrix.height - 1
            let right = matrix.width - 1
            #expect((0..<matrix.width).contains { matrix[$0, 0] }, "\(symbology) top")
            #expect((0..<matrix.width).contains { matrix[$0, last] }, "\(symbology) bottom")
            #expect((0..<matrix.height).contains { matrix[0, $0] }, "\(symbology) left")
            #expect((0..<matrix.height).contains { matrix[right, $0] }, "\(symbology) right")
        }
        // An Aztec code's centre is its bull's eye: the middle module is dark, and the code is square with odd sides.
        let aztec = try BarcodeGenerator.matrix(.aztec, payload: text)
        #expect(aztec.width == aztec.height)
        #expect(aztec.width % 2 == 1)
        #expect(aztec[aztec.width / 2, aztec.height / 2])
    }

    @Test func qrFinderPatternsAreTopLeftTopRightAndBottomLeft() throws {
        let matrix = try BarcodeGenerator.matrix(.qrCode, payload: "orientation")
        let far = matrix.width - 1
        // A finder pattern's outer ring is dark; the bottom right corner has none.
        #expect(matrix[0, 0])
        #expect(matrix[far, 0])
        #expect(matrix[0, far])
        #expect(matrix[6, 6])
        #expect(!matrix[far - 7, far - 7] || !matrix[far, far] || !matrix[far - 3, far])
        #expect(matrix.width == 21)
    }

    @Test func code128IsOneRowFramedByItsStartAndStop() throws {
        let matrix = try BarcodeGenerator.matrix(.code128, payload: "HELLO128")
        #expect(matrix.height == 1)
        // Start B, 8 characters, check character, each 11 modules, and the 13 module stop.
        #expect(matrix.width == 123)
        #expect(matrix.row(0).hasPrefix("11010010000"))
        #expect(matrix.row(0).hasSuffix("1100011101011"))
    }

    @Test func tooMuchTextIsAnErrorNotACrash() {
        let long = String(repeating: "x", count: BarcodeSpec.maxFieldLength + 1)
        #expect(throws: BarcodeError.tooLong) { try BarcodeGenerator.matrix(.qrCode, payload: long) }
        #expect(throws: BarcodeError.empty) { try BarcodeGenerator.matrix(.aztec, payload: "") }
        #expect(throws: (any Error).self) { try BarcodeGenerator.matrix(.code128, payload: "Grüße") }
    }

    // MARK: Layout and element

    @Test func matrixCodesAreSquareAndCentredBarCodesFill() {
        let square = BarcodeMatrix(width: 21, height: 21, modules: Array(repeating: true, count: 441))
        let layout = BarcodeLayout(matrix: square, margin: 2, is2D: true, in: CGRect(x: 0, y: 0, width: 250, height: 500))
        #expect(layout.moduleWidth == 10)
        #expect(layout.moduleHeight == 10)
        #expect(layout.frame == CGRect(x: 0, y: 125, width: 250, height: 250))
        #expect(layout.origin == CGPoint(x: 20, y: 145))
        let bars = BarcodeMatrix(row: Array(repeating: true, count: 96))
        let wide = BarcodeLayout(matrix: bars, margin: 2, is2D: false, in: CGRect(x: 10, y: 20, width: 500, height: 80))
        #expect(wide.frame == CGRect(x: 10, y: 20, width: 500, height: 80))
        #expect(wide.moduleWidth == 5)
        #expect(wide.moduleHeight == 80)
        #expect(wide.origin == CGPoint(x: 20, y: 20))
    }

    @Test func newElementsHaveUpstreamsSizesAndFit() throws {
        let qr = Annotation.barcodeElement(BarcodeSpec(), at: CGPoint(x: 100, y: 100), scale: 2)
        #expect(qr.kind == .barcode)
        #expect(qr.bounds == CGRect(x: 100, y: 100, width: 420, height: 420))
        #expect(qr.barcodeKeepsAspect)
        let ean = Annotation.barcodeElement(Self.spec(.ean13, "590123412345"), at: .zero, scale: 1)
        #expect(ean.bounds.size == CGSize(width: 330, height: 100))
        #expect(!ean.barcodeKeepsAspect)
        let pdf = try #require(Self.spec(.pdf417, "Greenshot").defaultSize as CGSize?)
        #expect(pdf.width == 210)
        #expect(pdf.height < 210)
        let small = Annotation.barcodeElement(BarcodeSpec(), at: .zero, scale: 2, fitting: CGSize(width: 200, height: 300))
        #expect(small.bounds.size == CGSize(width: 200, height: 200))
    }

    @Test func insertedElementsSitNearTheTopLeft() {
        let big = Annotation.insertedBarcode(BarcodeSpec(), imageSize: CGSize(width: 2000, height: 1000), scale: 2)
        #expect(big.bounds == CGRect(x: 100, y: 100, width: 420, height: 420))
        // On a small image the code shrinks to fit and moves into the corner.
        let small = Annotation.insertedBarcode(BarcodeSpec(), imageSize: CGSize(width: 300, height: 200), scale: 1)
        #expect(small.bounds == CGRect(x: 50, y: 0, width: 200, height: 200))
    }

    @Test func handlesFollowTheKindOfCode() {
        let qr = Annotation.barcodeElement(BarcodeSpec(), at: .zero, scale: 1)
        #expect(Handle.handles(for: qr) == Handle.cornerHandles)
        let ean = Annotation.barcodeElement(Self.spec(.ean8, "9638507"), at: .zero, scale: 1)
        #expect(Handle.handles(for: ean) == Handle.boxHandles)
        // Dragging a corner of a QR code keeps it square.
        let dragged = Handle.bottomRight.drag(qr, to: CGPoint(x: 300, y: 250))
        #expect(dragged.bounds.width == dragged.bounds.height)
    }

    @Test func editedElementsKeepTheirPlace() {
        let box = CGRect(x: 50, y: 60, width: 300, height: 300)
        let qr = BarcodeSpec()
        let ean = Self.spec(.ean13, "590123412345")
        // A matrix code keeps its width.
        #expect(qr.editedBox(from: box, old: qr, scale: 2) == box)
        // A bar code keeps its box.
        let bars = CGRect(x: 5, y: 6, width: 400, height: 90)
        #expect(ean.editedBox(from: bars, old: Self.spec(.code39, "A"), scale: 2) == bars)
        // Switching between them takes the new default size.
        #expect(ean.editedBox(from: box, old: qr, scale: 2) == CGRect(x: 50, y: 60, width: 660, height: 200))
        #expect(qr.editedBox(from: bars, old: ean, scale: 1) == CGRect(x: 5, y: 6, width: 210, height: 210))
    }

    @Test func invalidOrMissingSpecsDrawWithoutCrashing() throws {
        let invalid = Self.spec(.ean13, "not digits")
        let picture = try #require(Self.render(invalid))
        #expect(picture.width > 0)
        var bare = Annotation(kind: .barcode, start: .zero, end: CGPoint(x: 50, y: 50))
        bare.barcode = nil
        let base = try #require(Self.render(BarcodeSpec()))
        #expect(AnnotationRenderer.flatten(base: base, annotations: [bare], scale: 1) != nil)
        #expect(throws: (any Error).self) { try AnnotationRenderer.barcodeImage(invalid, size: CGSize(width: 10, height: 10)) }
        let preview = try AnnotationRenderer.barcodeImage(BarcodeSpec(), size: CGSize(width: 210, height: 210))
        #expect(preview.width == 210)
    }
}
