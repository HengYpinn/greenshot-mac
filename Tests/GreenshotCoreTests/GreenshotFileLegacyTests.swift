// SPDX-License-Identifier: GPL-3.0-or-later

import CoreGraphics
import Foundation
import Testing
@testable import GreenshotCore

/// The files of Greenshot for Windows 1.2 - 1.4 in Fixtures (upstream PR #638 test data): one per element type and
/// version, named after what is in them, e.g. "RectangleContainer_lt_100_200_wh_150_80" is one rectangle at 100, 200 of
/// 150 x 80 pixels (upstream's `LegacyElementReaderTests.AssertMatchesFileName`).
struct GreenshotFileLegacyTests {
    static let fixtures = Bundle.module.url(forResource: "Fixtures", withExtension: nil)!

    static func files(_ folder: String, _ fileExtension: String) -> [String] {
        let root = fixtures.appendingPathComponent(folder)
        let enumerator = FileManager.default.enumerator(at: root, includingPropertiesForKeys: nil)
        let urls = (enumerator?.allObjects as? [URL]) ?? []
        return urls.filter { $0.pathExtension == fileExtension }
            .map { String($0.path.dropFirst(fixtures.path.count + 1)) }
            .sorted()
    }

    static let greenshotFiles = files("Greenshotfile", "greenshot")
    static let templateFiles = files("GreenshotTemplate", "gst")

    static func data(_ relativePath: String) throws -> Data {
        try Data(contentsOf: fixtures.appendingPathComponent(relativePath))
    }

    /// The element part of a `.greenshot` fixture.
    static func payload(_ relativePath: String) throws -> (marker: String, payload: Data) {
        let file = try data(relativePath)
        let trailer = try #require(GreenshotFileTrailer.locate(in: file))
        return (trailer.marker, file.subdata(in: trailer.elements))
    }

    static func legacyElements(_ relativePath: String) throws -> [LegacyElement] {
        if relativePath.hasSuffix(".gst") { return try GreenshotLegacyReader.elements(fromPayload: data(relativePath)) }
        return try GreenshotLegacyReader.elements(fromPayload: payload(relativePath).payload)
    }

    /// The first element as this editor's element.
    static func firstAnnotation(_ elements: [LegacyElement]) throws -> Annotation {
        let element = try #require(elements.first)
        return try #require(GreenshotLegacyImport.annotation(element, scale: 1))
    }

    static func matchesFileName(_ relativePath: String, _ elements: [LegacyElement]) {
        let name = ((relativePath as NSString).lastPathComponent as NSString).deletingPathExtension
        for element in elements {
            #expect(GreenshotLegacyImport.annotation(element, scale: 1) != nil || element.typeName == "CursorContainer",
                    "\(element.typeName) in \(relativePath)")
        }
        if name.hasPrefix("Surface_with_Image") {
            #expect(elements.isEmpty)
            return
        }
        let parts = name.split(separator: "_")
        if name.hasPrefix("Surface_with_") {
            #expect(elements.count == Int(parts[2]))
            return
        }
        for element in elements {
            #expect(element.typeName == String(parts[0]))
        }
        if let lt = parts.firstIndex(of: "lt"), let wh = parts.firstIndex(of: "wh"), wh == lt + 3, parts.count == wh + 3 {
            #expect(elements.count == 1)
            let element = elements.first
            #expect(element?.left == Int(parts[lt + 1]))
            #expect(element?.top == Int(parts[lt + 2]))
            #expect(element?.width == Int(parts[wh + 1]))
            #expect(element?.height == Int(parts[wh + 2]))
        }
    }

    @Test func fixturesArePresent() {
        #expect(Self.greenshotFiles.count >= 20)
        #expect(Self.templateFiles.count >= 25)
    }

    @Test(arguments: greenshotFiles) func greenshotFileElementsMatchTheName(_ relativePath: String) throws {
        let (marker, payload) = try Self.payload(relativePath)
        let folder = ((relativePath as NSString).deletingLastPathComponent as NSString).lastPathComponent
        let version = folder.replacingOccurrences(of: "File_Version_1.", with: "01.")
        #expect(marker == "Greenshot" + version)
        Self.matchesFileName(relativePath, try GreenshotLegacyReader.elements(fromPayload: payload))
    }

    @Test(arguments: templateFiles) func templateElementsMatchTheName(_ relativePath: String) throws {
        Self.matchesFileName(relativePath, try Self.legacyElements(relativePath))
    }

    // MARK: Fields and content

    @Test(arguments: ["1.02", "1.03"]) func rectangleWithKnownColors(_ version: String) throws {
        let elements = try Self.legacyElements("Greenshotfile/File_Version_\(version)/RectangleContainer_lt_100_200_wh_150_80.greenshot")
        let element = try #require(elements.first)
        guard case .color(let line)? = element.field("LINE_COLOR"), case .color(let fill)? = element.field("FILL_COLOR") else {
            Issue.record("no colors")
            return
        }
        #expect(line.isKnownColor)
        #expect(line.knownColor == 141)
        #expect(fill.knownColor == 27)
        let rectangle = try #require(GreenshotLegacyImport.annotation(element, scale: 1))
        #expect(rectangle.kind == .rectangle)
        #expect(rectangle.style.lineColor == RGBAColor.red)
        #expect(rectangle.style.fillColor.alpha == 0)
        #expect(rectangle.bounds == CGRect(x: 100, y: 200, width: 150, height: 80))
    }

    @Test(arguments: ["1.02", "1.03"]) func textAndFont(_ version: String) throws {
        let elements = try Self.legacyElements("Greenshotfile/File_Version_\(version)/TextContainer_lt_300_200_wh_300_100.greenshot")
        let text = try Self.firstAnnotation(elements)
        #expect(text.kind == .text)
        #expect(text.text == "Hello Greenshot")
        #expect(text.style.fontFamily == "Arial")
        #expect(text.style.fontSize > 5)
    }

    @Test(arguments: ["1.02", "1.03"]) func speechBubbleTail(_ version: String) throws {
        let elements = try Self.legacyElements("GreenshotTemplate/File_Version_\(version)/SpeechbubbleContainer_lt_200_200_wh_150_80.gst")
        let bubble = try Self.firstAnnotation(elements)
        #expect(bubble.kind == .speechBubble)
        #expect(bubble.text == "Point on 100x300")
        #expect(bubble.tail == CGPoint(x: 100, y: 300))
    }

    @Test(arguments: ["GreenshotTemplate/File_Version_1.02/StepLabelContainer_lt_200_200_lt_500_300.gst",
                      "Greenshotfile/File_Version_1.03/StepLabelContainer_lt_200_200_lt_500_300.greenshot",
                      "Greenshotfile/File_Version_1.04/StepLabelContainer_lt_200_200_lt_500_300.greenshot"])
    func stepLabels(_ path: String) throws {
        let result = GreenshotLegacyImport.convert(try Self.legacyElements(path), scale: 1)
        #expect(result.elements.map(\.kind) == [.counter, .counter])
        #expect(result.counterStart == 1)
        #expect(result.unreadable.isEmpty)
    }

    @Test(arguments: ["1.02", "1.03"]) func freehandPointsAreMovedByTheElement(_ version: String) throws {
        let elements = try Self.legacyElements("GreenshotTemplate/File_Version_\(version)/FreehandContainer_with_4_points.gst")
        let element = try #require(elements.first)
        guard case .freehand(let points) = element.content else {
            Issue.record("no points")
            return
        }
        #expect(points.count == 4)
        #expect(points.first == CGPoint(x: 240, y: 171))
        let freehand = try #require(GreenshotLegacyImport.annotation(element, scale: 1))
        let first = try #require(freehand.points.first)
        #expect(first == CGPoint(x: 240 + element.left, y: 171 + element.top))
    }

    @Test(arguments: ["1.02", "1.03"]) func highlightTakesTheColorOfItsFilter(_ version: String) throws {
        let elements = try Self.legacyElements("GreenshotTemplate/File_Version_\(version)/HighlightContainer_TextFilter_lt_310_70_wh_195_60.gst")
        let element = try #require(elements.first)
        #expect(element.filters.map(\.name) == ["HighlightFilter"])
        let highlight = try #require(GreenshotLegacyImport.annotation(element, scale: 1))
        #expect(highlight.style.highlightMode == .text)
        #expect(highlight.style.fillColor.alpha > 0)
    }

    @Test(arguments: ["1.02", "1.03"]) func obfuscateWithBlur(_ version: String) throws {
        let elements = try Self.legacyElements("GreenshotTemplate/File_Version_\(version)/ObfuscateContainer_BlurFilter_lt_130_70_wh_180_70.gst")
        let element = try #require(elements.first)
        #expect(element.filters.map(\.name) == ["BlurFilter"])
        let obfuscate = try #require(GreenshotLegacyImport.annotation(element, scale: 1))
        #expect(obfuscate.style.obfuscateMode == .blur)
    }

    @Test(arguments: ["ImageContainer_lt_300_200_wh_100_100", "IconContainer_lt_400_200_wh_32_32",
                      "MetafileContainer_lt_300_200_wh_120_100"])
    func picturesBecomePNGImages(_ name: String) throws {
        let elements = try Self.legacyElements("GreenshotTemplate/File_Version_1.03/\(name).gst")
        let picture = try Self.firstAnnotation(elements)
        #expect(picture.kind == .image)
        let data = try #require(picture.imageData)
        #expect(data.starts(with: [0x89, 0x50, 0x4E, 0x47]))
    }

    @Test func svgKeepsItsSource() throws {
        let elements = try Self.legacyElements("Greenshotfile/File_Version_1.03/SvgContainer_lt_300_200_wh_120_100.greenshot")
        let svg = try Self.firstAnnotation(elements)
        #expect(svg.kind == .svg)
        let source = String(decoding: try #require(svg.imageData), as: UTF8.self)
        #expect(source.contains("<svg"))
    }

    @Test func emoji() throws {
        let elements = try Self.legacyElements("Greenshotfile/File_Version_1.04/EmojiContainer_lt_100_200_wh_64_64.greenshot")
        let emoji = try Self.firstAnnotation(elements)
        #expect(emoji.kind == .emoji)
        #expect(emoji.text == "\u{1F49A}")
    }

    @Test func cursorOf14HasItsPicture() throws {
        let elements = try Self.legacyElements("Greenshotfile/File_Version_1.04/CursorContainer_lt_600_100_wh_64_64.greenshot")
        let cursor = try Self.firstAnnotation(elements)
        #expect(cursor.kind == .cursor)
        #expect(cursor.imageData?.starts(with: [0x89, 0x50, 0x4E, 0x47]) == true)
    }

    @Test func surfaceWithManyElements() throws {
        let (_, payload) = try Self.payload("Greenshotfile/File_Version_1.03/Surface_with_14_different_DrawableContainer.greenshot")
        let result = try GreenshotLegacyImport.read(payload: payload, scale: 1)
        #expect(result.elements.count == 14)
        #expect(result.unreadable.isEmpty)
    }

    // MARK: Whole files

    @Test func backgroundOfAnEmptyFile() throws {
        let contents = try #require(GreenshotFile.read(Self.data("Greenshotfile/File_Version_1.03/Surface_with_Image_800x400.greenshot")))
        #expect(contents.image.width == 800)
        #expect(contents.image.height == 400)
        #expect(contents.scale == 1)
        #expect(contents.elements.isEmpty)
        #expect(contents.origin == .windows(marker: "Greenshot01.03"))
        #expect(!contents.elementsFailed)
        #expect(contents.savesToNewFile)
    }

    @Test func wholeFileWithElements() throws {
        let contents = try #require(GreenshotFile.read(Self.data("Greenshotfile/File_Version_1.04/Surface_with_11_different_DrawableContainer.greenshot")))
        #expect(contents.elements.count == 11)
        #expect(contents.unreadable.isEmpty)
    }

    // MARK: Files from anywhere

    @Test func garbageIsAnError() {
        let garbage = Data((0..<200).map { UInt8(truncatingIfNeeded: $0 * 7) })
        #expect(throws: (any Error).self) { try GreenshotLegacyReader.elements(fromPayload: garbage) }
    }

    @Test func truncatedPayloadIsAnError() throws {
        let template = try Self.data("GreenshotTemplate/File_Version_1.03/TextContainer_lt_300_200_wh_300_100.gst")
        let half = template.prefix(template.count / 2)
        #expect(throws: (any Error).self) { try GreenshotLegacyReader.elements(fromPayload: half) }
    }

    @Test func everyCutOfAPayloadFailsCleanly() throws {
        let template = try Self.data("GreenshotTemplate/File_Version_1.02/ArrowContainer_lt_100_200_wh_400_100.gst")
        for length in stride(from: 0, to: template.count, by: 37) {
            _ = try? GreenshotLegacyReader.elements(fromPayload: template.prefix(length))
        }
    }

    @Test func flippedBytesNeverTrap() throws {
        let template = try Self.data("GreenshotTemplate/File_Version_1.03/RectangleContainer_lt_100_200_wh_150_80.gst")
        for index in stride(from: 17, to: template.count, by: 23) {
            var damaged = template
            damaged[index] ^= 0xFF
            _ = try? GreenshotLegacyReader.elements(fromPayload: damaged)
        }
    }

    @Test func foreignTypeIsSkippedAndNamed() throws {
        let payload = NRBFTestStream.list(of: "Evil.Payload")
        let elements = try GreenshotLegacyReader.elements(fromPayload: payload)
        #expect(elements.map(\.typeName) == ["Payload"])
        let result = GreenshotLegacyImport.convert(elements, scale: 1)
        #expect(result.elements.isEmpty)
        #expect(result.unreadable == ["Payload"])
    }

    @Test func hugeLengthIsRefused() {
        var payload = NRBFTestStream.header()
        payload.append(contentsOf: [15]) // ArraySinglePrimitive
        payload.append(contentsOf: NRBFTestStream.int32(1))
        payload.append(contentsOf: NRBFTestStream.int32(Int32.max))
        payload.append(2) // bytes
        #expect(throws: (any Error).self) { try NRBFDecoder.decode(payload) }
    }

    @Test func deepNestingIsRefused() {
        // A class whose only member is the same class, inline, 200 times.
        var payload = NRBFTestStream.header()
        payload.append(contentsOf: NRBFTestStream.bytes([12], NRBFTestStream.int32(2), NRBFTestStream.string("Lib")))
        payload.append(contentsOf: NRBFTestStream.bytes([5], NRBFTestStream.int32(1), NRBFTestStream.string("Nested"),
                                                        NRBFTestStream.int32(1), NRBFTestStream.string("child"), [2],
                                                        NRBFTestStream.int32(2)))
        for id in 2...200 {
            payload.append(contentsOf: NRBFTestStream.bytes([1], NRBFTestStream.int32(Int32(id)),
                                                            NRBFTestStream.int32(1)))
        }
        #expect(throws: NRBFError.tooDeep) { try NRBFDecoder.decode(payload) }
    }

    // MARK: Mapping

    @Test func cutMarkAcrossAVerticalCut() throws {
        var element = LegacyElement(typeName: "CutMarkContainer", left: 300, top: 0, width: 40, height: 400)
        element.content = .cutMark(horizontal: false, seed: -5, shadow: .init(darkness: 0.5, size: 9, offsetX: 2, offsetY: 3))
        element.fields = [LegacyField(name: "CUT_MARK_STYLE", value: .enumeration(type: "CutMarkStyle", value: 2)),
                          LegacyField(name: "TOOTH_HEIGHT", value: .number(24))]
        let mark = try #require(GreenshotLegacyImport.annotation(element, scale: 2))
        #expect(mark.kind == .cutMark)
        #expect(mark.verticalCut == true)
        #expect(mark.seed == UInt64(bitPattern: -5))
        #expect(mark.style.cutMarkStyle == .zigZag)
        #expect(mark.style.toothHeight == 12)
        #expect(mark.cutEdges?.shadowSize == 9)
        #expect(mark.cutEdges?.shadowDarkness == 0.5)
    }

    @Test func tornEdgeSidesAndMargins() throws {
        var element = LegacyElement(typeName: "TornEdgeContainer", left: 0, top: 0, width: 820, height: 420)
        element.content = .tornEdge(seed: 7, edges: [true, false, true, false], margins: [10, 0, 10, 0],
                                    shadow: .init(darkness: 0.6, size: 7, offsetX: -1, offsetY: -1))
        let torn = try #require(GreenshotLegacyImport.annotation(element, scale: 1))
        let layout = try #require(torn.cutEdges)
        #expect(torn.kind == .tornEdge)
        #expect(layout.top)
        #expect(!layout.right)
        #expect(layout.marginTop == 10)
        #expect(layout.marginLeft == 0)
    }

    @Test func sizesInPixelsBecomePoints() throws {
        var element = LegacyElement(typeName: "LineContainer", left: 10, top: 20, width: 100, height: -10)
        element.fields = [LegacyField(name: "LINE_THICKNESS", value: .number(4)),
                          LegacyField(name: "ARROWHEADS", value: .enumeration(type: "ArrowContainer+ArrowHeadCombination", value: 3))]
        let line = try #require(GreenshotLegacyImport.annotation(element, scale: 2))
        #expect(line.style.lineWidth == 2)
        #expect(line.start == CGPoint(x: 10, y: 20))
        #expect(line.end == CGPoint(x: 110, y: 10))
    }

    /// Upstream's font sizes are pixels (`GraphicsUnit.Pixel`) and a Windows pixel is a point here: the defaults are
    /// upstream's numbers, and a file's text keeps its size.
    @Test func textSizesArePixelsOfWindows() throws {
        let text = AnnotationStyle.defaults(for: .text)
        let bubble = AnnotationStyle.defaults(for: .speechBubble)
        let counter = AnnotationStyle.defaults(for: .counter)
        #expect(text.fontSize == 11)
        #expect(bubble.fontSize == 20)
        // A counter's font size is the radius of a new one: upstream's step labels start 30 × 30.
        #expect(counter.fontSize == 15)

        var sized = LegacyElement(typeName: "TextContainer", left: 0, top: 0, width: 100, height: 40)
        sized.fields = [LegacyField(name: "FONT_SIZE", value: .number(11))]
        let imported = try #require(GreenshotLegacyImport.annotation(sized, scale: 1))
        #expect(imported.style.fontSize == text.fontSize)
        let unsized = LegacyElement(typeName: "SpeechbubbleContainer", left: 0, top: 0, width: 100, height: 40)
        let defaulted = try #require(GreenshotLegacyImport.annotation(unsized, scale: 1))
        #expect(defaulted.style.fontSize == bubble.fontSize)
    }

    @Test func countersAreOrderedByTheirNumbers() {
        func label(_ number: Int, left: Int) -> LegacyElement {
            var element = LegacyElement(typeName: "StepLabelContainer", left: left, top: 0, width: 30, height: 30)
            element.content = .stepLabel(number: number, counterStart: 3)
            return element
        }
        let rectangle = LegacyElement(typeName: "RectangleContainer", left: 0, top: 0, width: 5, height: 5)
        let result = GreenshotLegacyImport.convert([label(2, left: 200), rectangle, label(1, left: 100)], scale: 1)
        #expect(result.elements.map(\.kind) == [.counter, .rectangle, .counter])
        #expect(result.elements.first?.start.x == 100)
        #expect(result.elements.last?.start.x == 200)
        #expect(result.counterStart == 3)
    }

    @Test func knownColors() {
        #expect(LegacyKnownColors.table.count == 175)
        #expect(LegacyKnownColors.argb(knownColor: 141) == 0xFFFF_0000)
        #expect(LegacyKnownColors.argb(knownColor: 27) == 0x00FF_FFFF)
        #expect(LegacyKnownColors.argb(knownColor: 59) == 0xFF8B_0000) // DarkRed, upstream's counter color
        #expect(LegacyKnownColors.argb(knownColor: 68) == 0xFF69_6969) // DimGray, the cut mark color
        #expect(LegacyKnownColors.argb(named: "yellow") == 0xFFFF_FF00)
        #expect(LegacyKnownColors.argb(knownColor: 0) == nil)
    }

    @Test func argbColors() {
        let color = LegacyColor(value: 0x80FF_8000, knownColor: 0, state: 2, name: nil)
        let rgba = GreenshotLegacyImport.rgba(color)
        let half: Double = 128.0 / 255.0
        let greenError: Double = abs(rgba.green - half)
        let alphaError: Double = abs(rgba.alpha - half)
        #expect(rgba.red == 1)
        #expect(greenError < 0.001)
        #expect(rgba.blue == 0)
        #expect(alphaError < 0.001)
    }
}

/// Hand-made BinaryFormatter streams for the decoder's limits.
enum NRBFTestStream {
    /// The parts one after the other (a `+` chain of byte arrays is too slow for older compilers to type-check).
    static func bytes(_ parts: [UInt8]...) -> [UInt8] {
        parts.flatMap { $0 }
    }

    static func int32(_ value: Int32) -> [UInt8] {
        withUnsafeBytes(of: value.littleEndian) { Array($0) }
    }

    static func string(_ text: String) -> [UInt8] {
        let utf8 = Array(text.utf8)
        precondition(utf8.count < 128)
        return [UInt8(utf8.count)] + utf8
    }

    /// SerializationHeader with root object 1.
    static func header() -> Data {
        Data([0] + int32(1) + int32(-1) + int32(1) + int32(0))
    }

    /// A List<object> (root, id 1) with one instance of `typeName` that has an int member "left".
    static func list(of typeName: String) -> Data {
        var data = header()
        data.append(contentsOf: NRBFTestStream.bytes([12], int32(2), string("Evil, Version=1.0.0.0")))
        // The list: _items (object[]), _size (int).
        data.append(contentsOf: NRBFTestStream.bytes([5], int32(1), string("System.Collections.Generic.List`1"),
                                                     int32(2), string("_items"), string("_size"), [5, 0, 8], int32(2)))
        data.append(contentsOf: [9] + int32(3))   // _items: reference to the array
        data.append(contentsOf: int32(1))         // _size
        // The array (id 3) with one inline instance (id 4).
        data.append(contentsOf: NRBFTestStream.bytes([16], int32(3), int32(1)))
        data.append(contentsOf: NRBFTestStream.bytes([5], int32(4), string(typeName), int32(1), string("left"), [0, 8],
                                                     int32(2)))
        data.append(contentsOf: int32(42))
        data.append(11)
        return data
    }
}
