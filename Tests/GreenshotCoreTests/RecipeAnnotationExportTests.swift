// Greenshot for Mac (Community) - an unofficial macOS port of Greenshot
// Copyright (C) 2026 Greenshot for Mac (Community) contributors
// Based on Greenshot, Copyright (C) 2007-2026 Thomas Braun, Jens Klingen, Robin Krom
// SPDX-License-Identifier: GPL-3.0-or-later

import CoreGraphics
import Foundation
import Testing
@testable import GreenshotCore

/// Editor elements → recipe annotations → `RecipeAnnotationFactory` gives the elements back (upstream
/// EditorAnnotationImporter.cs).
@Suite struct RecipeAnnotationExportTests {
    private let scale: CGFloat = 2
    private let factory = RecipeAnnotationFactory(imageSize: CGSize(width: 1600, height: 1200), scale: 2)

    private func element(_ kind: AnnotationKind, text: String = "") -> Annotation {
        var style = AnnotationStyle.defaults(for: kind)
        style.lineColor = RGBAColor(red: 0, green: 0, blue: 1)
        style.fillColor = RGBAColor(red: 1, green: 1, blue: 0, alpha: 0.5)
        style.lineWidth = 3
        style.shadow = false
        return Annotation(kind: kind, start: CGPoint(x: 100, y: 60), end: CGPoint(x: 340, y: 160), text: text, style: style)
    }

    private func roundTrip(_ annotation: Annotation) throws -> Annotation {
        let parameters = try #require(RecipeAnnotationExport.parameters(of: annotation, scale: scale))
        guard case .element(let made) = factory.make(AnnotationParameters(parameters)) else {
            Issue.record("No element for \(parameters)")
            return annotation
        }
        return made
    }

    private func close(_ a: CGPoint, _ b: CGPoint) -> Bool { abs(a.x - b.x) <= 2 && abs(a.y - b.y) <= 2 }

    @Test(arguments: [AnnotationKind.rectangle, .ellipse, .line, .arrow, .text, .speechBubble, .highlight, .obfuscate])
    func boxesComeBack(kind: AnnotationKind) throws {
        let original = element(kind, text: kind.hasEditableText ? "Hello" : "")
        let made = try roundTrip(original)
        #expect(made.kind == original.kind)
        #expect(close(made.start, original.start), "\(made.start)")
        #expect(close(made.end, original.end), "\(made.end)")
        if kind.hasEditableText { #expect(made.text == "Hello") }
        if kind == .rectangle {
            #expect(made.style.lineColor == original.style.lineColor)
            #expect(made.style.lineWidth == 3)
            #expect(!made.style.shadow)
            let alpha = made.style.fillColor.alpha
            #expect(abs(alpha - 0.5) < 0.01)
        }
    }

    @Test func blurPixelizeMagnify() throws {
        var blur = element(.obfuscate)
        blur.style.obfuscateMode = .blur
        blur.style.blurRadius = 7
        let made = try roundTrip(blur)
        #expect(made.style.obfuscateMode == .blur)
        #expect(made.style.blurRadius == 7)
        var magnify = element(.highlight)
        magnify.style.highlightMode = .magnify
        magnify.style.magnification = 3
        let parameters = try #require(RecipeAnnotationExport.parameters(of: magnify, scale: scale))
        #expect(parameters.string("Type") == "Magnify")
        #expect(try roundTrip(magnify).style.magnification == 3)
    }

    @Test func arrowHeadsAndFreehand() throws {
        var arrow = element(.arrow)
        arrow.style.arrowHeads = .both
        #expect(try roundTrip(arrow).style.arrowHeads == .both)
        let path = [CGPoint(x: 10, y: 10), CGPoint(x: 50, y: 30), CGPoint(x: 90, y: 10)]
        let freehand = Annotation(kind: .freehand, start: path[0], end: path[2], points: path)
        let parameters = try #require(RecipeAnnotationExport.parameters(of: freehand, scale: scale))
        #expect(parameters.string("Points") == "5,5;25,15;45,5")
        #expect(try roundTrip(freehand).points == path)
    }

    @Test func speechBubbleTail() throws {
        var bubble = element(.speechBubble, text: "Look")
        bubble.tail = CGPoint(x: 60, y: 260)
        let made = try roundTrip(bubble)
        let tail = try #require(made.tail)
        #expect(close(tail, CGPoint(x: 60, y: 260)))
    }

    @Test func barcodeSpecRoundTrip() throws {
        for type in QRPayloadType.allCases {
            var spec = BarcodeSpec()
            spec.qrType = type
            spec.text = "hello"
            spec.wifiSSID = "net"
            spec.wifiEncryption = .wep
            spec.vCardFirstName = "Ann"
            spec.epcIBAN = "DE00"
            spec.emailTo = "a@example.com"
            spec.eventTitle = "Meet"
            spec.phoneNumber = "123"
            spec.smsMessage = "hi"
            spec.latitude = "52.5"
            spec.roundedDots = true
            spec.margin = 3
            spec.foreground = RGBAColor(red: 0, green: 0.2, blue: 0.4)
            let back = RecipeAnnotationExport.spec(of: RecipeAnnotationExport.parameters(of: spec))
            #expect(back.qrType == type)
            #expect(back.roundedDots)
            #expect(back.margin == 3)
            switch type {
            case .text: #expect(back.text == "hello")
            case .wifi: #expect(back.wifiSSID == "net" && back.wifiEncryption == .wep)
            case .vCard: #expect(back.vCardFirstName == "Ann")
            case .epcTransfer: #expect(back.epcIBAN == "DE00")
            case .email: #expect(back.emailTo == "a@example.com")
            case .calendarEvent: #expect(back.eventTitle == "Meet")
            case .phone: #expect(back.phoneNumber == "123")
            case .sms: #expect(back.smsMessage == "hi")
            case .geo: #expect(back.latitude == "52.5")
            }
        }
        var code = BarcodeSpec()
        code.symbology = .code128
        code.text = "ABC-123"
        let parameters = RecipeAnnotationExport.parameters(of: code)
        #expect(parameters.string("Format") == "CODE_128")
        #expect(RecipeAnnotationExport.spec(of: parameters).symbology == .code128)
        #expect(RecipeAnnotationExport.spec(of: parameters).text == "ABC-123")
    }

    @Test func applyingASpecDropsOtherTypesFields() {
        var spec = BarcodeSpec()
        spec.qrType = .phone
        spec.phoneNumber = "555"
        let before: JSONObject = ["Type": .string("QRCode"), "QrType": .string("WiFi"), "WifiSsid": .string("old"), "OffsetX": .number(4)]
        let after = RecipeAnnotationExport.applying(spec, to: before)
        #expect(after["WifiSsid"] == nil)
        #expect(after.string("PhoneNumber") == "555")
        #expect(after.string("QrType") == "Phone")
        #expect(after.int("OffsetX") == 4)
    }

    @Test func picturesAreEmbeddedOrSaved() throws {
        let image = TestImage.solid(width: 8, height: 8, .red)
        let picture = try #require(Annotation.picture(image, pictureScale: 1, at: CGPoint(x: 20, y: 20), documentScale: scale))
        let items = RecipeAnnotationExport.items(of: [picture, element(.rectangle)], scale: scale)
        #expect(items.map(\.type) == ["Image", "Rectangle"])
        let pictureItem = items[0]
        #expect(pictureItem.canSaveAsFile)
        #expect(pictureItem.parameters.string("ImageData") != nil)
        let embedded = RecipeAnnotationExport.annotations(of: items, storage: .embed) { _, _ in }
        #expect(embedded[0].objectValue?.string("ImageData") != nil)
        var written: [String] = []
        let folder = URL(fileURLWithPath: "/tmp/assets")
        let saved = RecipeAnnotationExport.annotations(of: items, storage: .saveToFile(folder: folder, prefix: "my recipe")) { _, url in
            written.append(url.lastPathComponent)
        }
        #expect(written == ["my recipe_image_1.png"])
        #expect(saved[0].objectValue?.string("FilePath") == "/tmp/assets/my recipe_image_1.png")
        #expect(saved[0].objectValue?["ImageData"] == nil)
        // A file that can't be written stays embedded.
        struct Refused: Error {}
        let failed = RecipeAnnotationExport.annotations(of: items, storage: .saveToFile(folder: folder, prefix: "p")) { _, _ in throw Refused() }
        #expect(failed[0].objectValue?.string("ImageData") != nil)
        // The picture comes back from the factory.
        let made = try roundTrip(picture)
        #expect(made.kind == .image)
    }

    @Test func namesSortsAndUnusableKinds() {
        #expect(RecipeAnnotationExport.assetFileName(prefix: "a/b", type: "Svg", index: 3, fileExtension: ".svg") == "a_b_svg_3.svg")
        #expect(RecipeAnnotationExport.assetFileName(prefix: "", type: "Image", index: 1, fileExtension: ".png") == "asset_image_1.png")
        let items = RecipeAnnotationExport.items(of: [element(.text, text: "b"), element(.arrow), element(.text, text: "a"),
                                                      Annotation(kind: .cutMark, start: .zero, end: .zero)], scale: scale)
        #expect(items.count == 3)
        #expect(RecipeAnnotationExport.sortedAlphabetically(items).map(\.description) == ["Arrow", "Text: a", "Text: b"])
        #expect(RecipeAnnotationExport.format(.clear) == "transparent")
        #expect(RecipeAnnotationExport.format(RGBAColor(red: 1, green: 0, blue: 0)) == "#FF0000")
        #expect(RecipeAnnotationExport.format(RGBAColor(red: 0, green: 0, blue: 0, alpha: 0.5)) == "#80000000")
    }
}
