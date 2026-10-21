// Greenshot for Mac (Community) - an unofficial macOS port of Greenshot
// Copyright (C) 2026 Greenshot for Mac (Community) contributors
// Based on Greenshot, Copyright (C) 2007-2026 Thomas Braun, Jens Klingen, Robin Krom
// SPDX-License-Identifier: GPL-3.0-or-later

import CoreGraphics
import Foundation
import Testing
@testable import GreenshotCore

/// The pointer pictures of the app: an arrow and a hand, 12 x 16.
struct RecipeTestCursors: RecipeCursorImageProviding {
    func cursorImage(named preset: String) async -> (image: CGImage, hotSpot: CGPoint)? {
        guard preset == "Arrow" || preset == "Hand" else { return nil }
        return (TestImage.solid(width: 12, height: 16, .black), CGPoint(x: 1, y: 1))
    }
}

/// Upstream AnnotationStep: the element types, the placement (ApplyPositioning) and the step itself.
@Suite struct RecipeAnnotationStepTests {
    /// The element of one annotation on a 400 x 300 point capture.
    func element(_ parameters: JSONObject, scale: CGFloat = 1, cursor: (image: CGImage, hotSpot: CGPoint)? = nil) -> Annotation? {
        let factory = RecipeAnnotationFactory(imageSize: CGSize(width: 400 * scale, height: 300 * scale), scale: scale)
        if case .element(let element) = factory.make(AnnotationParameters(parameters), cursor: cursor) { return element }
        return nil
    }

    func bounds(_ parameters: JSONObject, scale: CGFloat = 1) -> CGRect? {
        element(parameters, scale: scale)?.bounds
    }

    // MARK: Placement

    @Test func anchoredToTheBottomRightWithMarginAndOffset() throws {
        let banner: JSONObject = ["type": .string("Rectangle"), "horizontalAnchor": .string("Right"), "verticalAnchor": .string("Bottom"),
                                  "width": .number(220), "height": .number(32), "offsetX": .number(-12), "offsetY": .number(-12),
                                  "fillColor": .string("rgba(20, 20, 20, 180)"), "lineColor": .string("#0078D7"),
                                  "lineThickness": .number(2), "shadow": .bool(true)]
        let rectangle = try #require(element(banner))
        #expect(rectangle.kind == .rectangle)
        #expect(rectangle.bounds == CGRect(x: 158, y: 246, width: 220, height: 32))
        #expect(abs(rectangle.style.fillColor.alpha - 180.0 / 255) < 0.001)
        #expect(rectangle.style.lineColor == RGBAColor(red: 0, green: 0x78 / 255.0, blue: 0xD7 / 255.0))
        #expect(rectangle.style.lineWidth == 2)
        // Points times the pixels per point on a Retina capture.
        #expect(bounds(banner, scale: 2) == CGRect(x: 316, y: 492, width: 440, height: 64))
    }

    @Test func centeredAndMargins() {
        let center: JSONObject = ["HorizontalAnchor": .string("Center"), "VerticalAnchor": .string("Center"), "Width": .number(100),
                                  "Height": .number(50), "OffsetY": .number(5)]
        #expect(bounds(center) == CGRect(x: 150, y: 130, width: 100, height: 50))
        let topLeft: JSONObject = ["HorizontalAnchor": .string("Left"), "VerticalAnchor": .string("Top"), "Width": .number(10),
                                   "Height": .number(10), "MarginLeft": .number(4)]
        #expect(bounds(topLeft) == CGRect(x: 4, y: 10, width: 10, height: 10))
        let unanchored: JSONObject = ["Width": .number(10), "Height": .number(10)]
        #expect(bounds(unanchored) == CGRect(x: 0, y: 0, width: 10, height: 10))
    }

    @Test func explicitEdges() {
        let fromRight: JSONObject = ["Right": .number(20), "Bottom": .number(5), "Width": .number(50), "Height": .number(10)]
        #expect(bounds(fromRight) == CGRect(x: 330, y: 285, width: 50, height: 10))
        // Anchored right with Left given: no margin (upstream); anchored bottom with Top given: Top.
        let mixed: JSONObject = ["HorizontalAnchor": .string("Right"), "Left": .number(7), "VerticalAnchor": .string("Bottom"),
                                 "Top": .number(40), "Width": .number(50), "Height": .number(10)]
        #expect(bounds(mixed) == CGRect(x: 350, y: 40, width: 50, height: 10))
        let left: JSONObject = ["Left": .number(12), "Top": .number(8), "Size": .number(20)]
        #expect(bounds(left) == CGRect(x: 12, y: 8, width: 20, height: 20))
    }

    // MARK: Types

    @Test func shapesAndFilters() throws {
        let arrow = try #require(element(["Type": .string("Arrow"), "ArrowHeads": .string("BOTH"), "Width": .number(50), "Height": .number(20)]))
        #expect(arrow.kind == .arrow)
        #expect(arrow.style.arrowHeads == .both)
        #expect(arrow.start == .zero)
        #expect(arrow.end == CGPoint(x: 50, y: 20))
        #expect(element(["Type": .string("Arrow")])?.style.arrowHeads == .end)
        #expect(RecipeAnnotationFactory.arrowHeads("START_POINT") == .start)
        let ellipse = try #require(element(["Type": .string("ellipse"), "LineColor": .string("#0000FF"), "Shadow": .bool(false)]))
        #expect(ellipse.kind == .ellipse)
        #expect(ellipse.style.lineColor == .blue)
        #expect(!ellipse.style.shadow)
        let blur = try #require(element(["Type": .string("Blur"), "BlurRadius": .number(4)]))
        #expect(blur.kind == .obfuscate)
        #expect(blur.style.obfuscateMode == .blur)
        #expect(blur.style.blurRadius == 4)
        #expect(element(["Type": .string("Pixelize")])?.style.pixelSize == 5)
        let highlight = try #require(element(["Type": .string("Highlight"), "FillColor": .string("Lime")]))
        #expect(highlight.style.highlightMode == .text)
        #expect(highlight.style.fillColor == RGBAColor(red: 0, green: 1, blue: 0))
        let magnify = try #require(element(["Type": .string("Magnify"), "MagnificationFactor": .number(3)]))
        #expect(magnify.style.highlightMode == .magnify)
        #expect(magnify.style.magnification == 3)
        // An unknown type is a rectangle, like upstream.
        #expect(element(["Type": .string("Sparkle")])?.kind == .rectangle)
    }

    @Test func textAndSpeechBubbles() throws {
        let fitted = try #require(element(["Type": .string("Text"), "Text": .string("Hello"), "TextAlign": .string("Left")]))
        #expect(fitted.kind == .text)
        #expect(fitted.text == "Hello")
        #expect(fitted.style.horizontalAlignment == .left)
        #expect(fitted.style.fontSize == 12)
        #expect(fitted.bounds.width > 10)
        #expect(fitted.bounds.height > 10)
        let sized = try #require(element(["Type": .string("Text"), "Text": .string("Hello"), "Width": .number(200), "Height": .number(30)]))
        #expect(sized.bounds.size == CGSize(width: 200, height: 30))
        #expect(sized.style.horizontalAlignment == .center)
        let frame: JSONObject = ["Type": .string("Speechbubble"), "Text": .string("Hi"), "Left": .number(100), "Top": .number(100),
                                 "Width": .number(80), "Height": .number(40)]
        let bubble = try #require(element(frame))
        #expect(bubble.kind == .speechBubble)
        #expect(bubble.style.bold)
        #expect(bubble.tail == CGPoint(x: 85, y: 165))
        var right = frame
        right["TailDirection"] = .string("BottomRight")
        #expect(element(right)?.tail == CGPoint(x: 195, y: 165))
        var fixed = frame
        fixed["TailX"] = .number(10)
        fixed["TailY"] = .number(20)
        #expect(element(fixed, scale: 2)?.tail == CGPoint(x: 20, y: 40))
    }

    /// TailX and TailY that don't convert fall back to 20 points left of the box and 25 below it (upstream
    /// `GetInt(p, "TailX", bLeft - 20)`), in whole points. A box beyond Int's range gets it without the `Int()` that
    /// stopped the app (see elementsAFileWouldLeaveOutAreSkipped).
    @Test func theTailFallbackBesideAnyBox() throws {
        let centered: JSONObject = ["Type": .string("SpeechBubble"), "Text": .string("Hi"), "HorizontalAnchor": .string("Center"),
                                    "Width": .number(81), "Height": .number(40), "TailX": .null, "TailY": .string("below")]
        let near = try #require(element(centered))
        // The box starts at 159.5: whole points toward zero, like upstream's int bounds.
        #expect(near.tail == CGPoint(x: 139, y: 65))
    }

    /// An element further away than a `.greenshot` file takes back (`Annotation.maxCoordinate`) was made, then left out
    /// as "Damaged element" when the saved file was reopened: it is skipped with the reason instead. Making it doesn't
    /// stop the app either (the speech bubble's tail fallback beside a box beyond Int's range).
    @Test func elementsAFileWouldLeaveOutAreSkipped() throws {
        let factory = RecipeAnnotationFactory(imageSize: CGSize(width: 800, height: 600), scale: 2)
        let far: [JSONObject] = [
            ["Type": .string("Rectangle"), "Left": .number(2_000_000), "Width": .number(10), "Height": .number(10)],
            ["Type": .string("SpeechBubble"), "Text": .string("Hi"), "Left": .number(9e18), "OffsetX": .number(9e18),
             "Top": .number(-9e18), "OffsetY": .number(-9e18), "Width": .number(80), "Height": .number(40),
             "TailX": .null, "TailY": .null],
            ["Type": .string("SpeechBubble"), "Text": .string("Hi"), "Width": .number(80), "Height": .number(40),
             "TailOffsetX": .number(9e18)],
            ["Type": .string("Freehand"), "Points": .string("0,0;5000000,5")]
        ]
        let image = TestImage.solid(width: 800, height: 600, .white)
        var skipped = 0
        for parameters in far {
            switch factory.make(AnnotationParameters(parameters)) {
            case .element(let element):
                let read = try #require(GreenshotFile.read(try GreenshotFile.Contents(image: image, scale: 2, elements: [element]).encoded()))
                #expect(read.elements.count == 1, "\(parameters)")
            case .skipped(let reason):
                #expect(reason.contains("too far"))
                skipped += 1
            case .crop:
                Issue.record("A crop for \(parameters)")
            }
        }
        #expect(skipped == far.count)
    }

    @Test func countersAndEmoji() throws {
        let counter = try #require(element(["Type": .string("StepLabel")]))
        #expect(counter.kind == .counter)
        #expect(counter.bounds.size == CGSize(width: 30, height: 30))
        #expect(counter.style.fillColor == .darkRed)
        // A counter stays round.
        let wide = try #require(element(["Type": .string("StepLabel"), "Width": .number(50), "Height": .number(40)]))
        #expect(wide.bounds.size == CGSize(width: 40, height: 40))
        let emoji = try #require(element(["Type": .string("Emoji"), "Emoji": .string("x"), "Size": .number(32)]))
        #expect(emoji.kind == .emoji)
        #expect(emoji.text == "x")
        #expect(emoji.bounds.size == CGSize(width: 32, height: 32))
    }

    @Test func qrCodesAndBarcodes() throws {
        let qr = try #require(element(["Type": .string("QRCode")]))
        #expect(qr.kind == .barcode)
        #expect(qr.bounds.size == CGSize(width: 160, height: 160))
        #expect(qr.barcode?.text == "https://getgreenshot.org")
        #expect(qr.barcode?.symbology == .qrCode)
        let square = try #require(element(["Type": .string("QRCode"), "Width": .number(100), "Height": .number(200)]))
        #expect(square.bounds.size == CGSize(width: 100, height: 100))
        let bar = try #require(element(["Type": .string("Barcode"), "Format": .string("CODE_128"), "Text": .string("ABC"),
                                        "Width": .number(300), "ForeColor": .string("#FF0000")]))
        #expect(bar.bounds.size == CGSize(width: 300, height: 80))
        #expect(bar.barcode?.symbology == .code128)
        #expect(bar.barcode?.text == "ABC")
        #expect(bar.barcode?.foreground == .red)
        let wifi = try #require(element(["Type": .string("QRCode"), "QrType": .string("WiFi"), "WifiSsid": .string("Home"),
                                         "WifiEncryption": .string("nopass")]))
        #expect(wifi.barcode?.qrType == .wifi)
        #expect(wifi.barcode?.wifiSSID == "Home")
        #expect(wifi.barcode?.wifiEncryption == .unencrypted)
    }

    @Test func picturesFreehandAndPointers() throws {
        let png = try ImageExporter.data(for: TestImage.solid(width: 8, height: 4, .red), format: .png)
        let picture = try #require(element(["Type": .string("Image"), "ImageData": .string(png.base64EncodedString())]))
        #expect(picture.kind == .image)
        #expect(picture.bounds.size == CGSize(width: 8, height: 4))
        let locked = try #require(element(["Type": .string("Image"), "ImageData": .string(png.base64EncodedString()),
                                           "Width": .number(16), "LockAspectRatio": .bool(true)]))
        #expect(locked.bounds.size == CGSize(width: 16, height: 8))
        let factory = RecipeAnnotationFactory(imageSize: CGSize(width: 400, height: 300), scale: 1)
        let broken = factory.make(AnnotationParameters(["Type": .string("Image"), "ImageData": .string("***")]))
        var skipped = false
        if case .skipped = broken { skipped = true }
        #expect(skipped)
        let path = try #require(element(["Type": .string("Freehand"), "Points": .string("10,10;20,20|30 15")], scale: 2))
        #expect(path.points == [CGPoint(x: 20, y: 20), CGPoint(x: 40, y: 40), CGPoint(x: 60, y: 30)])
        let arrow = (image: TestImage.solid(width: 12, height: 16, .black), hotSpot: CGPoint(x: 1, y: 1))
        let pointer = try #require(element(["Type": .string("Cursor"), "Left": .number(5)], scale: 2, cursor: arrow))
        #expect(pointer.kind == .cursor)
        #expect(pointer.bounds == CGRect(x: 10, y: 0, width: 24, height: 32))
    }

    @Test func svgKeepsItsAspectRatio() throws {
        guard ElementSvg.isSupported else { return }
        let svg = "<svg xmlns=\"http://www.w3.org/2000/svg\" width=\"40\" height=\"20\"><rect width=\"40\" height=\"20\" fill=\"red\"/></svg>"
        let own = try #require(element(["Type": .string("Svg"), "Content": .string(svg)], scale: 2))
        #expect(own.kind == .svg)
        #expect(own.bounds.size == CGSize(width: 80, height: 40))
        let wider = try #require(element(["Type": .string("Svg"), "Content": .string(svg), "Width": .number(80)]))
        #expect(wider.bounds.size == CGSize(width: 80, height: 40))
    }

    // MARK: The step

    @Test func evaluatesItsParametersOnceWithTheCaptureSize() async throws {
        let node = RecipeNode(id: "stamp", stepType: "Annotation", parameters: [
            "Type": .string("Text"), "Text": .string("Hi ${Greeting}"), "Left": .string("${width - 120}"), "Top": .string("${h / 2}"),
            "Width": .number(100), "Height": .string("${payload.height / 10}")
        ])
        let context = await RecipeStepHarness.run(node, image: TestImage.solid(width: 800, height: 600, .white), scale: 2,
                                                  variables: ["Greeting": .string("${user.username}")])
        let stamp = try #require(context.payload?.annotations.first)
        #expect(stamp.text == "Hi ${user.username}")
        #expect(stamp.bounds == CGRect(x: 560, y: 300, width: 200, height: 60))
    }

    @Test func listOfAnnotationsAndCrop() async throws {
        let node = RecipeNode(id: "marks", stepType: "Annotation", parameters: ["Annotations": .array([
            .object(["Type": .string("Rectangle"), "Left": .number(20), "Top": .number(20), "Width": .number(10), "Height": .number(10)]),
            .string("not an annotation"),
            .object(["Type": .string("Crop"), "Left": .number(10), "Top": .number(10), "Width": .number(50), "Height": .number(40)])
        ])])
        let context = await RecipeStepHarness.run(node, image: TestImage.solid(width: 100, height: 100, .white))
        let payload = try #require(context.payload)
        #expect(payload.image.width == 50)
        #expect(payload.image.height == 40)
        #expect(payload.annotations.count == 1)
        #expect(payload.annotations.first?.start == CGPoint(x: 10, y: 10))
    }

    @Test func pointersComeFromTheApp() async throws {
        let node = RecipeNode(id: "pointer", stepType: "Annotation", parameters: ["Type": .string("Cursor"), "CursorName": .string("Hand")])
        let image = TestImage.solid(width: 100, height: 100, .white)
        let withApp = await RecipeStepHarness.run(node, image: image, cursorImages: RecipeTestCursors())
        let pointer = try #require(withApp.payload?.annotations.first)
        #expect(pointer.kind == .cursor)
        #expect(pointer.bounds.size == CGSize(width: 12, height: 16))
        let without = await RecipeStepHarness.run(node, image: image)
        #expect(without.payload?.annotations.isEmpty == true)
        #expect(without.logged("Warning: pointer pictures are not available here."))
        #expect(!without.isAborted)
    }
}
