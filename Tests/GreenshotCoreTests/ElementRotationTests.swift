// Greenshot for Mac (Community) - an unofficial macOS port of Greenshot
// Copyright (C) 2026 Greenshot for Mac (Community) contributors
// Based on Greenshot, Copyright (C) 2007-2026 Thomas Braun, Jens Klingen, Robin Krom
// SPDX-License-Identifier: GPL-3.0-or-later

import CoreGraphics
import Foundation
import Testing
@testable import GreenshotCore

/// The content of pictures, SVGs, emoji and barcodes turns with the image's Rotate (upstream
/// `VectorGraphicsContainer.Transform`, `ImageContainer.Transform`) instead of being squeezed upright into the turned box.
struct ElementRotationTests {
    /// 40 × 20 pixels: red on the left half, blue on the right.
    static let halves = TestImage.make(width: 40, height: 20) { x, _ in x < 20 ? .red : .blue }

    static func document() -> EditorDocument {
        EditorDocument(image: TestImage.solid(width: 100, height: 60, .white), scale: 1, title: "test")
    }

    static func picture(at origin: CGPoint = CGPoint(x: 10, y: 10)) throws -> Annotation {
        try #require(Annotation.picture(halves, pictureScale: 1, at: origin, documentScale: 1))
    }

    static func code128() -> BarcodeSpec {
        var spec = BarcodeSpec()
        spec.symbology = .code128
        spec.text = "GREENSHOT"
        return spec
    }

    @Test func rotateTurnsTheContentOfPicturesSvgsEmojiAndBarcodes() throws {
        let doc = Self.document()
        let picture = try Self.picture()
        let svg = Annotation(kind: .svg, start: CGPoint(x: 0, y: 0), end: CGPoint(x: 40, y: 20), imageData: Data("<svg/>".utf8))
        let emoji = Annotation(kind: .emoji, start: CGPoint(x: 50, y: 0), end: CGPoint(x: 70, y: 20), text: "🙂")
        let barcode = Annotation.barcodeElement(Self.code128(), at: CGPoint(x: 0, y: 30), scale: 0.1)
        let cursor = Annotation(kind: .cursor, start: CGPoint(x: 80, y: 0), end: CGPoint(x: 90, y: 10), imageData: Data())
        let box = Annotation(kind: .rectangle, start: CGPoint(x: 80, y: 30), end: CGPoint(x: 90, y: 40))
        let all = [picture, svg, emoji, barcode, cursor, box]
        doc.add(all)
        func rotations() -> [Int?] { all.map { doc.annotation($0.id)?.rotation } }

        doc.rotateImage(clockwise: true)
        #expect(rotations() == [90, 90, 90, 90, nil, nil])
        doc.rotateImage(clockwise: true)
        #expect(rotations() == [180, 180, 180, 180, nil, nil])
        doc.rotateImage(clockwise: false)
        doc.rotateImage(clockwise: false)
        #expect(rotations() == [nil, nil, nil, nil, nil, nil])
        doc.rotateImage(clockwise: false)
        #expect(rotations() == [270, 270, 270, 270, nil, nil])
    }

    @Test func fourTurnsAreNoTurn() throws {
        let doc = Self.document()
        let picture = try Self.picture()
        doc.add(picture)
        for _ in 0..<4 { doc.rotateImage(clockwise: true) }
        let back = try #require(doc.annotation(picture.id))
        #expect(back == picture)
        #expect(back.rotation == nil)
    }

    @Test func anglesBecomeQuarterTurns() {
        #expect(Annotation.normalizedRotation(0) == nil)
        #expect(Annotation.normalizedRotation(90) == 90)
        #expect(Annotation.normalizedRotation(-90) == 270)
        #expect(Annotation.normalizedRotation(-270) == 90)
        #expect(Annotation.normalizedRotation(-180) == 180)
        #expect(Annotation.normalizedRotation(450) == 90)
        #expect(Annotation.normalizedRotation(360) == nil)
        #expect(Annotation.normalizedRotation(44) == nil)
        #expect(Annotation.normalizedRotation(46) == 90)
        // Any number from a file works without overflowing.
        // Int.min % 360 is -8, Int.max % 360 is 7: both round to no turn.
        #expect(Annotation.normalizedRotation(Int.min) == nil)
        #expect(Annotation.normalizedRotation(Int.max) == nil)
        var odd = Annotation(kind: .svg, start: .zero, end: CGPoint(x: 10, y: 10))
        odd.rotation = 1_000_000_000
        // 1e9 % 360 = 280: nearest quarter is 270.
        #expect(odd.contentQuarterTurns == 3)
    }

    @Test func theContentBoxIsTheUnturnedBoxAroundTheSameCentre() throws {
        var a = Annotation(kind: .image, start: CGPoint(x: 30, y: 10), end: CGPoint(x: 50, y: 50))
        #expect(a.contentBounds == a.bounds)
        a.rotation = 90
        #expect(a.isQuarterTurned)
        #expect(a.contentBounds == CGRect(x: 20, y: 20, width: 40, height: 20))
        a.rotation = 180
        #expect(a.contentBounds == a.bounds)
    }

    @Test func filesWithoutTheTurnStillLoad() throws {
        let plain = try Self.picture()
        let json = try JSONEncoder().encode(plain)
        let text = try #require(String(data: json, encoding: .utf8))
        #expect(!text.contains("rotation"))
        let decoded = try JSONDecoder().decode(Annotation.self, from: json)
        #expect(decoded.rotation == nil)
        var turned = plain
        turned.rotation = 270
        let again = try JSONDecoder().decode(Annotation.self, from: try JSONEncoder().encode(turned))
        #expect(again.rotation == 270)
    }

    /// The picture's left half (red) is on top after a clockwise turn and at the bottom after a counter-clockwise one;
    /// upright and squeezed, red would stay on the left.
    @Test func aTurnedPictureIsDrawnTurned() throws {
        for clockwise in [true, false] {
            let doc = Self.document()
            doc.add(try Self.picture())
            doc.rotateImage(clockwise: clockwise)
            let image = doc.flattened()
            let element = try #require(doc.annotations.first)
            // The 40 × 20 box at (10, 10) becomes a 20 × 40 box.
            #expect(element.bounds.size == CGSize(width: 20, height: 40))
            let left = Int(element.bounds.minX) + 4
            let right = Int(element.bounds.maxX) - 4
            let top = Int(element.bounds.minY) + 4
            let bottom = Int(element.bounds.maxY) - 4
            let upper: RGBA = clockwise ? .red : .blue
            let lower: RGBA = clockwise ? .blue : .red
            #expect(TestImage.pixel(image, left, top).isClose(to: upper))
            #expect(TestImage.pixel(image, right, top).isClose(to: upper))
            #expect(TestImage.pixel(image, left, bottom).isClose(to: lower))
            #expect(TestImage.pixel(image, right, bottom).isClose(to: lower))
        }
    }

    /// After two turns the picture is upside down: red (its left half) on the right.
    @Test func aPictureTurnedTwiceIsUpsideDown() throws {
        let doc = Self.document()
        doc.add(try Self.picture())
        doc.rotateImage(clockwise: true)
        doc.rotateImage(clockwise: true)
        let element = try #require(doc.annotations.first)
        #expect(element.rotation == 180)
        #expect(element.bounds.size == CGSize(width: 40, height: 20))
        let image = doc.flattened()
        let middle = Int(element.bounds.midY)
        #expect(TestImage.pixel(image, Int(element.bounds.minX) + 4, middle).isClose(to: .blue))
        #expect(TestImage.pixel(image, Int(element.bounds.maxX) - 4, middle).isClose(to: .red))
    }

    /// Rotating the document and then drawing it gives the same picture as drawing it and then rotating the result.
    @Test func turningTheDocumentMatchesTurningTheDrawing() throws {
        var elements = [try Self.picture(), Annotation.barcodeElement(Self.code128(), at: CGPoint(x: 0, y: 34), scale: 0.2)]
        if ElementSvg.isSupported, let svg = Annotation.svg(ElementSvgTests.svg, at: CGPoint(x: 55, y: 5), documentScale: 1) {
            elements.append(svg)
        }
        for clockwise in [true, false] {
            let doc = Self.document()
            doc.add(elements)
            let expected = try #require(ImageOperations.rotate(doc.flattened(), clockwise: clockwise))
            doc.rotateImage(clockwise: clockwise)
            let turned = doc.flattened()
            #expect(turned.width == expected.width)
            #expect(turned.height == expected.height)
            var different = 0
            for y in 0..<turned.height {
                for x in 0..<turned.width where !TestImage.pixel(turned, x, y).isClose(to: TestImage.pixel(expected, x, y), tolerance: 40) {
                    different += 1
                }
            }
            // A few edge pixels may be smoothed differently.
            #expect(different < 30)
        }
    }

    @Test(.enabled(if: ElementSvg.isSupported))
    func aTurnedSvgIsDrawnTurnedAndSharp() throws {
        let doc = Self.document()
        let svg = try #require(Annotation.svg(ElementSvgTests.svg, at: CGPoint(x: 10, y: 10), documentScale: 1))
        doc.add(svg)
        doc.rotateImage(clockwise: true)
        let element = try #require(doc.annotations.first)
        #expect(element.bounds == CGRect(x: 30, y: 10, width: 20, height: 40))
        let image = doc.flattened()
        // The red square (left in the SVG) is on top; the blue circle's centre (30, 10) lands at (40, 40).
        #expect(TestImage.pixel(image, 40, 20).isClose(to: .red))
        #expect(TestImage.pixel(image, 40, 40).isClose(to: .blue))
        #expect(TestImage.pixel(image, 33, 45).isClose(to: .white, tolerance: 12))
    }

    @Test func resetSizeKeepsAQuarterTurnedPictureOnItsSide() throws {
        var picture = try Self.picture()
        let upright = try #require(picture.defaultSize(documentScale: 1))
        #expect(upright == CGSize(width: 40, height: 20))
        picture.rotation = 90
        let turned = try #require(picture.defaultSize(documentScale: 1))
        #expect(turned == CGSize(width: 20, height: 40))
        picture.rotation = 180
        let halfway = try #require(picture.defaultSize(documentScale: 1))
        #expect(halfway == CGSize(width: 40, height: 20))

        let doc = Self.document()
        doc.add(try Self.picture())
        doc.rotateImage(clockwise: true)
        let id = try #require(doc.annotations.first?.id)
        let element = try #require(doc.annotation(id))
        doc.update(element.withBounds(CGRect(x: 5, y: 5, width: 30, height: 30)))
        doc.resetSize([id])
        let reset = try #require(doc.annotation(id))
        #expect(reset.bounds == CGRect(x: 5, y: 5, width: 20, height: 40))
    }

    @Test func editingATurnedBarcodeKeepsItOnItsSide() throws {
        var qr = BarcodeSpec()
        qr.text = "https://getgreenshot.org"
        var element = Annotation.barcodeElement(qr, at: CGPoint(x: 10, y: 20), scale: 1)
        // Upright: switching to a bar code gives its default size, 330 × 100.
        let upright = element.withEditedBarcode(Self.code128(), scale: 1)
        #expect(upright.bounds == CGRect(x: 10, y: 20, width: 330, height: 100))
        #expect(upright.barcode == Self.code128())
        // On its side, the bar code lies on its side too.
        element.rotation = 90
        let turned = element.withEditedBarcode(Self.code128(), scale: 1)
        #expect(turned.bounds == CGRect(x: 10, y: 20, width: 100, height: 330))
        #expect(turned.rotation == 90)
        // A bar code edited to another bar code keeps its box, turned or not.
        var linear = Annotation.barcodeElement(Self.code128(), at: CGPoint(x: 0, y: 0), scale: 1)
        linear.rotation = 270
        linear.end = CGPoint(x: 100, y: 330)
        var other = Self.code128()
        other.text = "OTHER"
        let edited = linear.withEditedBarcode(other, scale: 1)
        #expect(edited.bounds == linear.bounds)
    }

    /// JSON of `annotation` with its "rotation" written as `value` (raw JSON text).
    static func json(_ annotation: Annotation, rotation value: String) throws -> Data {
        var object = try #require(try JSONSerialization.jsonObject(with: JSONEncoder().encode(annotation)) as? [String: Any])
        object["rotation"] = try JSONSerialization.jsonObject(with: Data(value.utf8), options: .fragmentsAllowed)
        return try JSONSerialization.data(withJSONObject: object)
    }

    @Test func aTurnThatIsNoWholeNumberStillLoads() throws {
        let picture = try Self.picture()
        let cases: [(String, Int?)] = [("90.5", 90), ("44.6", nil), ("135.2", 180), ("-90.0", 270), ("-45", nil),
                                      ("1e300", nil), ("\"90\"", nil), ("null", nil), ("270", 270), ("450", 90)]
        for (value, expected) in cases {
            let decoded = try JSONDecoder().decode(Annotation.self, from: try Self.json(picture, rotation: value))
            #expect(decoded.rotation == expected, "rotation \(value)")
            #expect(decoded.imageData == picture.imageData)
        }
    }

    @Test func everyFieldSurvivesTheRoundTrip() throws {
        var a = Annotation(kind: .barcode, start: CGPoint(x: 1, y: 2), end: CGPoint(x: 30, y: 40),
                           points: [CGPoint(x: 3, y: 4)], text: "t", tail: CGPoint(x: 5, y: 6), imageData: Data([1, 2, 3]))
        a.seed = 42
        a.verticalCut = true
        a.cutEdges = CutEdgeLayout(top: false, marginTop: 3)
        a.barcode = Self.code128()
        a.rotation = 270
        a.style.lineWidth = 7
        let decoded = try JSONDecoder().decode(Annotation.self, from: try JSONEncoder().encode(a))
        #expect(decoded == a)
    }

    @Test func kindsWhoseContentDoesNotTurnIgnoreATurn() throws {
        // A file may carry a turn on any element; only pictures, SVGs, emoji and barcodes turn their content.
        for kind in [AnnotationKind.cursor, .text, .rectangle, .highlight] {
            var a = Annotation(kind: kind, start: CGPoint(x: 10, y: 10), end: CGPoint(x: 50, y: 30))
            a.rotation = 90
            #expect(a.contentQuarterTurns == 0)
            #expect(!a.isQuarterTurned)
            #expect(a.contentBounds == a.bounds)
        }
        var pointer = try Self.picture()
        pointer.kind = .cursor
        pointer.rotation = 90
        let size = try #require(pointer.defaultSize(documentScale: 1))
        #expect(size == CGSize(width: 40, height: 20))
    }
}
