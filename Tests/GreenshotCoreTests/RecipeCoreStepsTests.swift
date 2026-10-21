// Greenshot for Mac (Community) - an unofficial macOS port of Greenshot
// Copyright (C) 2026 Greenshot for Mac (Community) contributors
// Based on Greenshot, Copyright (C) 2007-2026 Thomas Braun, Jens Klingen, Robin Krom
// SPDX-License-Identifier: GPL-3.0-or-later

import AppKit
import Foundation
import Testing
@testable import GreenshotCore

/// Runs one node of a core step on a capture.
enum RecipeStepHarness {
    static func run(_ node: RecipeNode, image: CGImage, scale: CGFloat = 1, annotations: [Annotation] = [],
                    environment: FixedRecipeEnvironment = FixedRecipeEnvironment(),
                    clipboard: (any RecipeClipboardWriting)? = nil,
                    cursorImages: (any RecipeCursorImageProviding)? = nil,
                    variables: [String: JSONValue] = [:]) async -> RecipeFlowContext {
        var recipe = CaptureRecipe(id: "steps_test", name: "Steps Test")
        recipe.nodes = [node]
        recipe.flow.startNodes = [node.id]
        let context = RecipeFlowContext(recipe: recipe, environment: environment)
        var payload = RecipePayload(image: image, scale: scale, title: "Steps")
        payload.annotations = annotations
        context.payload = payload
        for (name, value) in variables { context[variable: name] = value }
        let registry = RecipeStepRegistry()
        registry.registerCoreExecutors(clipboard: clipboard, cursorImages: cursorImages)
        await RecipeFlowEngine(steps: registry, recipeLookup: { _ in nil }).execute(context)
        return context
    }

    /// A white image with black text drawn on it (like RecognitionTests).
    static func textImage(_ text: String, width: Int = 700, height: Int = 120) -> CGImage {
        let rep = NSBitmapImageRep(bitmapDataPlanes: nil, pixelsWide: width, pixelsHigh: height, bitsPerSample: 8,
                                   samplesPerPixel: 4, hasAlpha: true, isPlanar: false, colorSpaceName: .deviceRGB,
                                   bytesPerRow: 0, bitsPerPixel: 0)!
        NSGraphicsContext.saveGraphicsState()
        NSGraphicsContext.current = NSGraphicsContext(bitmapImageRep: rep)
        NSColor.white.setFill()
        NSRect(x: 0, y: 0, width: width, height: height).fill()
        let attributes: [NSAttributedString.Key: Any] = [.font: NSFont.systemFont(ofSize: 40), .foregroundColor: NSColor.black]
        NSAttributedString(string: text, attributes: attributes).draw(at: NSPoint(x: 20, y: 35))
        NSGraphicsContext.restoreGraphicsState()
        return rep.cgImage!
    }

    static func box(_ x: CGFloat, _ y: CGFloat, _ width: CGFloat, _ height: CGFloat) -> Annotation {
        Annotation(kind: .rectangle, start: CGPoint(x: x, y: y), end: CGPoint(x: x + width, y: y + height))
    }
}

extension RecipeFlowContext {
    /// Whether a line of the execution log (after its time) is `message`.
    func logged(_ message: String) -> Bool {
        executionLog.contains { $0.hasSuffix("] " + message) }
    }

    /// Whether a line of the execution log contains `fragment`.
    func logMentions(_ fragment: String) -> Bool {
        executionLog.contains { $0.contains(fragment) }
    }
}

/// What BarcodeScan copies.
final class RecipeTestClipboard: RecipeClipboardWriting, @unchecked Sendable {
    private let lock = NSLock()
    private var copied: [String] = []

    var texts: [String] { lock.withLock { copied } }
    func copy(text: String) async { lock.withLock { copied.append(text) } }
}

/// The Effect, Processors, TextEffect and BarcodeScan steps.
@Suite struct RecipeCoreStepsTests {
    func effect(_ parameters: JSONObject) -> RecipeNode {
        RecipeNode(id: "effect", stepType: "Effect", parameters: parameters)
    }

    // MARK: Effect

    @Test func borderGrowsByItsWidthInPoints() async throws {
        let node = effect(["Effect": .string("Border"), "Width": .number(2), "Color": .string("#FF0000")])
        let context = await RecipeStepHarness.run(node, image: TestImage.solid(width: 10, height: 10, .white), scale: 2,
                                                  annotations: [RecipeStepHarness.box(1, 1, 2, 2)])
        let payload = try #require(context.payload)
        #expect(payload.image.width == 18)
        #expect(payload.image.height == 18)
        #expect(TestImage.pixel(payload.image, 0, 9).isClose(to: .red))
        #expect(TestImage.pixel(payload.image, 9, 9).isClose(to: .white))
        let moved = try #require(payload.annotations.first)
        #expect(moved.start == CGPoint(x: 5, y: 5))
    }

    @Test func rotateTurnsByQuarters() async throws {
        let halves = TestImage.make(width: 20, height: 10) { x, _ in x < 10 ? .red : .blue }
        let quarter = await RecipeStepHarness.run(effect(["Effect": .string("Rotate"), "Angle": .number(90)]), image: halves)
        let turned = try #require(quarter.payload)
        #expect(turned.image.width == 10)
        #expect(turned.image.height == 20)
        let half = await RecipeStepHarness.run(effect(["Effect": .string("Rotate"), "Angle": .number(180)]), image: halves)
        let upsideDown = try #require(half.payload)
        #expect(upsideDown.image.width == 20)
        #expect(TestImage.pixel(upsideDown.image, 0, 0).isClose(to: .blue))
        let back = await RecipeStepHarness.run(effect(["Effect": .string("Rotate"), "Angle": .number(270)]), image: halves)
        #expect(back.payload?.image.height == 20)
    }

    @Test func anEffectThatCannotBeAppliedIsLogged() async throws {
        let context = await RecipeStepHarness.run(effect(["Effect": .string("Rotate"), "Angle": .number(45)]),
                                                  image: TestImage.solid(width: 20, height: 10, .white))
        #expect(!context.isAborted)
        #expect(context.payload?.image.width == 20)
        #expect(context.logged("Warning: the effect 'Rotate' could not be applied."))
        let unknown = await RecipeStepHarness.run(effect(["Effect": .string("Sparkle")]), image: TestImage.solid(width: 4, height: 4, .white))
        #expect(unknown.logMentions("could not be applied"))
    }

    @Test func resizeByPercentageOrPoints() async throws {
        let image = TestImage.solid(width: 20, height: 10, .white)
        let percent = await RecipeStepHarness.run(effect(["Effect": .string("Resize"), "Percentage": .number(50)]), image: image)
        #expect(percent.payload?.image.width == 10)
        #expect(percent.payload?.image.height == 5)
        let points = await RecipeStepHarness.run(effect(["Effect": .string("Resize"), "Width": .number(5)]), image: image, scale: 2)
        #expect(points.payload?.image.width == 10)
        #expect(points.payload?.image.height == 5)
        let free = await RecipeStepHarness.run(effect(["Effect": .string("Resize"), "Width": .number(8), "Height": .number(8),
                                                       "MaintainAspectRatio": .bool(false)]), image: image)
        #expect(free.payload?.image.width == 8)
        #expect(free.payload?.image.height == 8)
    }

    @Test func resizeCanvasAddsMarginsAndMovesElements() async throws {
        let node = effect(["Effect": .string("ResizeCanvas"), "Margin": .number(3), "BackgroundColor": .string("#0000FF")])
        let context = await RecipeStepHarness.run(node, image: TestImage.solid(width: 10, height: 10, .white),
                                                  annotations: [RecipeStepHarness.box(1, 1, 4, 4)])
        let payload = try #require(context.payload)
        #expect(payload.image.width == 16)
        #expect(TestImage.pixel(payload.image, 0, 0).isClose(to: .blue))
        #expect(payload.annotations.first?.start == CGPoint(x: 4, y: 4))
    }

    /// "nan" is a Double for the recipe's parameters (`Double("nan")`); Adjust leaves the image as it is.
    @Test func adjustWithNanLeavesTheImage() async throws {
        let node = effect(["Effect": .string("Adjust"), "Brightness": .string("nan"), "Gamma": .string("NaN")])
        let context = await RecipeStepHarness.run(node, image: TestImage.solid(width: 4, height: 4, .red))
        #expect(context.logged("Applied effect 'Adjust'"))
        let payload = try #require(context.payload)
        #expect(TestImage.pixel(payload.image, 1, 1) == .red)
    }

    /// Sizes far beyond any image (a percentage of "inf" or 1e300, margins of 5e18, a border or shadow of 4.7e18 points on a
    /// Retina capture) can't be applied: logged, and the flow goes on, instead of stopping the app.
    @Test func effectsWithSizesBeyondAnyImage() async throws {
        let huge = JSONValue.number(4.7e18)
        let cases: [JSONObject] = [
            ["Effect": .string("Resize"), "Percentage": .string("inf")],
            ["Effect": .string("Resize"), "Percentage": .number(1e300)],
            ["Effect": .string("ResizeCanvas"), "Left": .number(5e18), "Right": .number(5e18)],
            ["Effect": .string("ResizeCanvas"), "Left": .number(-5e18)],
            ["Effect": .string("Border"), "Width": huge],
            ["Effect": .string("DropShadow"), "ShadowSize": huge],
            ["Effect": .string("DropShadow"), "ShadowOffsetX": huge],
            ["Effect": .string("TornEdge"), "ShadowSize": huge]
        ]
        for parameters in cases {
            let context = await RecipeStepHarness.run(effect(parameters), image: TestImage.solid(width: 4, height: 4, .white), scale: 2)
            #expect(context.logMentions("could not be applied"), "\(parameters)")
            #expect(context.payload?.image.width == 4)
        }
        // Teeth bigger than the image tear it all off, but they are drawn.
        let teeth: JSONObject = ["Effect": .string("TornEdge"), "ToothHeight": huge, "HorizontalToothRange": huge, "VerticalToothRange": huge]
        let torn = await RecipeStepHarness.run(effect(teeth), image: TestImage.solid(width: 4, height: 4, .white), scale: 2)
        #expect(torn.logged("Applied effect 'TornEdge'"))
    }

    @Test func colorEffects() async throws {
        let inverted = await RecipeStepHarness.run(effect(["Effect": .string("Invert")]), image: TestImage.solid(width: 4, height: 4, .white))
        let black = try #require(inverted.payload?.image)
        #expect(TestImage.pixel(black, 1, 1).isClose(to: .black))
        let gray = await RecipeStepHarness.run(effect(["Effect": .string("Grayscale")]), image: TestImage.solid(width: 4, height: 4, .red))
        let grayImage = try #require(gray.payload?.image)
        let pixel = TestImage.pixel(grayImage, 1, 1)
        #expect(abs(Int(pixel.r) - Int(pixel.g)) <= 2)
        #expect(abs(Int(pixel.g) - Int(pixel.b)) <= 2)
    }

    // MARK: Processors

    @Test func processorsRunOCRWhenAsked() async throws {
        let node = RecipeNode(id: "ocr", stepType: "Processors", parameters: ["ProcessorMode": .string("OCR")])
        let context = await RecipeStepHarness.run(node, image: RecipeStepHarness.textImage("Invoice 4711"))
        let text = context[variable: "OcrText"]?.asString ?? ""
        #expect(text.contains("4711"))
        #expect(context[variable: "CommandResult"]?.asString == text)
        #expect(context.payload?.extractedText == text)
    }

    @Test func processorsWithoutAModeFollowTheSettings() async throws {
        let node = RecipeNode(id: "ocr", stepType: "Processors")
        let image = RecipeStepHarness.textImage("Invoice 4711")
        let off = await RecipeStepHarness.run(node, image: image)
        #expect(off[variable: "OcrText"] == nil)
        #expect(off.logged("Processors: nothing to run."))
        var environment = FixedRecipeEnvironment()
        environment.config["alwaysrunocroncapture"] = .bool(true)
        let on = await RecipeStepHarness.run(node, image: image, environment: environment)
        let text = on[variable: "OcrText"]?.asString ?? ""
        #expect(text.contains("4711"))
    }

    /// The app's settings reach the steps under their own names (Processors and TextEffect read these two).
    @Test func ocrSettingsReachTheSteps() {
        var settings = AppSettings()
        settings.alwaysRunOCROnCapture = true
        settings.ocrLanguage = "de-DE"
        let environment = SystemRecipeEnvironment(settings: settings)
        #expect(environment.configValue("alwaysRunOCROnCapture") == .bool(true))
        #expect(environment.configValue("ocrLanguage") == .string("de-DE"))
    }

    // MARK: TextEffect

    /// "Call 555-1234 now" with three words.
    static let line = RecognizedLine(text: "Call 555-1234 now", bounds: CGRect(x: 0, y: 0, width: 200, height: 20), words: [
        RecognizedWord(text: "Call", bounds: CGRect(x: 0, y: 0, width: 40, height: 20)),
        RecognizedWord(text: "555-1234", bounds: CGRect(x: 50, y: 0, width: 80, height: 20)),
        RecognizedWord(text: "now", bounds: CGRect(x: 140, y: 0, width: 60, height: 20))
    ])

    func expressions(_ patterns: [String]) -> [NSRegularExpression] {
        patterns.compactMap { try? NSRegularExpression(pattern: $0, options: [.caseInsensitive]) }
    }

    @Test func textEffectFindsWordsLinesAndMatchesAcrossWords() {
        let none = TextEffectExecutor.Padding(horizontalPercent: 0, verticalPercent: 0)
        let phone = TextEffectExecutor.matchedBounds([Self.line], expressions(["\\d{3}-\\d{4}"]), scope: "Auto", padding: none)
        #expect(phone == [CGRect(x: 50, y: 0, width: 80, height: 20)])
        let across = TextEffectExecutor.matchedBounds([Self.line], expressions(["call 555"]), scope: "auto", padding: none)
        #expect(across == [CGRect(x: 0, y: 0, width: 130, height: 20)])
        let words = TextEffectExecutor.matchedBounds([Self.line], expressions(["^now$"]), scope: "Word", padding: none)
        #expect(words == [CGRect(x: 140, y: 0, width: 60, height: 20)])
        let lines = TextEffectExecutor.matchedBounds([Self.line], expressions(["now"]), scope: "Line", padding: none)
        #expect(lines == [Self.line.bounds])
        let nothing = TextEffectExecutor.matchedBounds([Self.line], expressions(["secret"]), scope: "Auto", padding: none)
        #expect(nothing.isEmpty)
    }

    @Test func textEffectPadsByPercentAndOffsetsByPoints() {
        let padding = TextEffectExecutor.Padding(horizontalPercent: 10, verticalPercent: 20, offset: CGVector(dx: 4, dy: -2))
        let padded = TextEffectExecutor.padded(CGRect(x: 50, y: 10, width: 100, height: 20), padding)
        #expect(padded == CGRect(x: 49, y: 6, width: 110, height: 24))
        let node = RecipeNode(id: "text", stepType: "TextEffect", parameters: ["Padding": .number(30), "OffsetHorizontal": .number(2)])
        let step = RecipeStepInvocation(node: node, parameters: node.parameters, contract: nil)
        let read = TextEffectExecutor.padding(step, scale: 2)
        #expect(read.horizontalPercent == 30)
        #expect(read.verticalPercent == 30)
        #expect(read.offset == CGVector(dx: 4, dy: 0))
    }

    /// A recipe can give any padding (PaddingHorizontal 9e18): it is limited to `Annotation.maxCoordinate` on each side
    /// instead of an `Int()` that traps.
    @Test func textEffectLimitsAHugePadding() {
        let huge = TextEffectExecutor.Padding(horizontalPercent: 9_000_000_000_000_000_000, verticalPercent: -9_000_000_000_000_000_000)
        let padded = TextEffectExecutor.padded(CGRect(x: 0, y: 0, width: 1000, height: 10), huge)
        #expect(padded.minX == -Annotation.maxCoordinate)
        // The far corner stays within the limit too (see textEffectElementsSurviveASavedFile).
        #expect(padded.width == 2 * Annotation.maxCoordinate)
        #expect(padded.height == 2 * Annotation.maxCoordinate - 10)
        // Whole pixels toward zero, like upstream's `(int)`: 7.5 % of 10 on each side is 0.
        let small = TextEffectExecutor.Padding(horizontalPercent: 15, verticalPercent: -15)
        #expect(TextEffectExecutor.padded(CGRect(x: 0, y: 0, width: 10, height: 10), small) == CGRect(x: 0, y: 0, width: 10, height: 10))
    }

    /// The element over a match stays within the positions a `.greenshot` file takes back (`Annotation.maxCoordinate`):
    /// a huge padding or offset made one the reopened file left out as "Damaged element". It still covers the same part of
    /// the capture.
    @Test func textEffectElementsSurviveASavedFile() throws {
        let node = RecipeNode(id: "text", stepType: "TextEffect", parameters: [:])
        let step = RecipeStepInvocation(node: node, parameters: node.parameters, contract: nil)
        let box = CGRect(x: 10, y: 5, width: 20, height: 10)
        let paddings = [TextEffectExecutor.Padding(horizontalPercent: 9_000_000_000_000_000_000, verticalPercent: 20),
                        TextEffectExecutor.Padding(offset: CGVector(dx: 9e18, dy: -9e18))]
        let elements = paddings.map { TextEffectExecutor.annotation("Redact", box: TextEffectExecutor.padded(box, $0), step) }
        let contents = GreenshotFile.Contents(image: TestImage.solid(width: 40, height: 30, .white), scale: 1, elements: elements)
        let read = try #require(GreenshotFile.read(try contents.encoded()))
        #expect(read.elements.count == 2)
        #expect(read.unreadable.isEmpty)
        #expect(elements[0].bounds.minX <= 0)
        #expect(elements[0].bounds.maxX >= 40)
    }

    @Test func textEffectElements() {
        let box = CGRect(x: 10, y: 10, width: 50, height: 20)
        let node = RecipeNode(id: "text", stepType: "TextEffect", parameters: ["FillColor": .string("#00FF00"), "BlurRadius": .number(7)])
        let step = RecipeStepInvocation(node: node, parameters: node.parameters, contract: nil)
        let redact = TextEffectExecutor.annotation("Redact", box: box, step)
        #expect(redact.kind == .rectangle)
        #expect(redact.style.fillColor == RGBAColor(red: 0, green: 1, blue: 0))
        #expect(redact.style.lineWidth == 0)
        #expect(!redact.style.shadow)
        #expect(redact.bounds == box)
        let blur = TextEffectExecutor.annotation("blur", box: box, step)
        #expect(blur.style.obfuscateMode == .blur)
        #expect(blur.style.blurRadius == 7)
        let pixelize = TextEffectExecutor.annotation("Pixelize", box: box, step)
        #expect(pixelize.style.obfuscateMode == .pixelate)
        #expect(pixelize.style.pixelSize == 5)
        let magnify = TextEffectExecutor.annotation("Magnify", box: box, step)
        #expect(magnify.style.highlightMode == .magnify)
        #expect(TextEffectExecutor.patterns(.string("a,b")) == ["a,b"])
        #expect(TextEffectExecutor.patterns(.array([.string("x"), .string(" "), .string("x"), .string("y")])) == ["x", "y"])
    }

    @Test func textEffectCoversTheMatchesFoundByOCR() async throws {
        let image = RecipeStepHarness.textImage("Order 4711 shipped")
        let node = RecipeNode(id: "redact", stepType: "TextEffect", parameters: ["Patterns": .array([.string("\\d{4}")]),
                                                                             "Effect": .string("Redact")])
        let context = await RecipeStepHarness.run(node, image: image)
        let payload = try #require(context.payload)
        #expect(payload.annotations.count == 1)
        let element = try #require(payload.annotations.first)
        #expect(element.kind == .rectangle)
        #expect(element.style.fillColor == .black)
        // The number, not the whole line.
        #expect(element.bounds.width < 300)
        #expect(element.bounds.minX > 60)
        let missing = RecipeNode(id: "none", stepType: "TextEffect", parameters: ["Patterns": .array([.string("secret")])])
        let nothing = await RecipeStepHarness.run(missing, image: image)
        #expect(nothing.payload?.annotations.isEmpty == true)
        #expect(nothing.logged("TextEffectStep found 0 pattern matches."))
    }

    @Test func textEffectSkipsInvalidPatterns() async {
        let node = RecipeNode(id: "bad", stepType: "TextEffect", parameters: ["Patterns": .array([.string("(")])])
        let context = await RecipeStepHarness.run(node, image: TestImage.solid(width: 20, height: 20, .white))
        #expect(!context.isAborted)
        #expect(context.logMentions("Warning: Invalid regex pattern '('"))
    }

    // MARK: BarcodeScan

    @Test func barcodeScanReadsAQRCode() async throws {
        var spec = BarcodeSpec()
        spec.margin = 4
        let code = try AnnotationRenderer.barcodeImage(spec, size: CGSize(width: 240, height: 240))
        let clipboard = RecipeTestClipboard()
        let node = RecipeNode(id: "scan", stepType: "BarcodeScan", parameters: ["CopyToClipboard": .bool(true), "SetVariable": .string("Link")])
        let context = await RecipeStepHarness.run(node, image: code, clipboard: clipboard)
        #expect(context[variable: "Zxing.DecodedText"] == .string("https://getgreenshot.org"))
        #expect(context[variable: "Barcode.Format"] == .string("QR_CODE"))
        #expect(context[variable: "Link"] == .string("https://getgreenshot.org"))
        #expect(context.payload?.extractedText == "https://getgreenshot.org")
        #expect(clipboard.texts == ["https://getgreenshot.org"])
    }

    @Test func barcodeScanWithoutACode() async {
        let node = RecipeNode(id: "scan", stepType: "BarcodeScan")
        let context = await RecipeStepHarness.run(node, image: TestImage.solid(width: 40, height: 40, .white))
        #expect(context[variable: "Zxing.DecodedText"] == nil)
        #expect(context.logged("BarcodeScan: no QR codes or barcodes found."))
        #expect(BarcodeScanExecutor.zxingFormat("Code128") == "CODE_128")
        #expect(BarcodeScanExecutor.zxingFormat("EAN13") == "EAN_13")
    }
}
