// Greenshot for Mac (Community) - an unofficial macOS port of Greenshot
// Copyright (C) 2026 Greenshot for Mac (Community) contributors
// Based on Greenshot, Copyright (C) 2007-2026 Thomas Braun, Jens Klingen, Robin Krom
// SPDX-License-Identifier: GPL-3.0-or-later

import CoreGraphics
import Foundation
import Testing
@testable import GreenshotCore

/// SVG pictures (upstream `SvgFileFormatHandler`, `SvgContainer`). Skipped where macOS can't draw SVG.
@Suite(.enabled(if: ElementSvg.isSupported))
struct ElementSvgTests {
    /// A red square on the left, a blue circle on the right: 40 × 20 points.
    static let svg = Data("""
        <?xml version="1.0" encoding="UTF-8"?>
        <svg xmlns="http://www.w3.org/2000/svg" width="40" height="20" viewBox="0 0 40 20">
          <rect x="0" y="0" width="20" height="20" fill="#ff0000"/>
          <circle cx="30" cy="10" r="8" fill="#0000ff"/>
        </svg>
        """.utf8)

    @Test func itsSizeComesFromTheSvg() throws {
        let size = try #require(ElementSvg.size(of: Self.svg))
        #expect(size == CGSize(width: 40, height: 20))
        let viewBoxOnly = Data(#"<svg xmlns="http://www.w3.org/2000/svg" viewBox="0 0 100 50"><rect width="100" height="50"/></svg>"#.utf8)
        let other = try #require(ElementSvg.size(of: viewBoxOnly))
        #expect(other == CGSize(width: 100, height: 50))
    }

    @Test func onlySvgIsTakenForSvg() {
        #expect(ElementSvg.isSVG(Self.svg))
        var withMark = Data([0xEF, 0xBB, 0xBF])
        withMark.append(Self.svg)
        #expect(ElementSvg.isSVG(withMark))
        #expect(!ElementSvg.isSVG(Data("not a picture".utf8)))
        #expect(!ElementSvg.isSVG(Data("<html><body>no svg here</body></html>".utf8)))
        #expect(!ElementSvg.isSVG(Data()))
        #expect(ElementSvg.size(of: Data("<svg".utf8)) == nil)
        let png = TestImage.solid(width: 4, height: 4, .red)
        let pngData = try? ImageExporter.data(for: png, format: .png, scale: 1)
        #expect(pngData.map(ElementSvg.isSVG) == false)
    }

    @Test func anElementIsAsBigAsTheSvgOrFitsTheRoom() throws {
        let element = try #require(Annotation.svg(Self.svg, at: CGPoint(x: 10, y: 5), documentScale: 2))
        #expect(element.kind == .svg)
        #expect(element.bounds == CGRect(x: 10, y: 5, width: 80, height: 40))
        #expect(element.imageData == Self.svg)
        #expect(!element.style.shadow)
        let fitted = try #require(Annotation.svg(Self.svg, at: .zero, documentScale: 2, fitting: CGSize(width: 40, height: 100)))
        #expect(fitted.bounds == CGRect(x: 0, y: 0, width: 40, height: 20))
        #expect(Annotation.svg(Data("nope".utf8), at: .zero, documentScale: 1) == nil)
    }

    @Test func anEnlargedSvgStaysSharp() throws {
        let doc = EditorDocument(image: TestImage.solid(width: 200, height: 100, .white), scale: 1, title: "test")
        var element = try #require(Annotation.svg(Self.svg, at: .zero, documentScale: 1))
        // Four times its size: the square ends at x 80, the circle starts at x 88.
        element.end = CGPoint(x: 160, y: 80)
        doc.add(element)
        let image = doc.flattened()
        #expect(TestImage.pixel(image, 40, 40) == .red)
        #expect(TestImage.pixel(image, 120, 40) == .blue)
        // Drawn from the SVG at this size, the edge of the square is a clean step, not a blurred one.
        #expect(TestImage.pixel(image, 79, 40) == .red)
        #expect(TestImage.pixel(image, 82, 40) == .white)
        #expect(TestImage.pixel(image, 180, 40) == .white)
    }

    @Test func itIsDrawnTheRightWayUp() throws {
        // A green square only in the top left corner.
        let corner = Data(##"<svg xmlns="http://www.w3.org/2000/svg" width="20" height="20"><rect width="5" height="5" fill="#00ff00"/></svg>"##.utf8)
        let doc = EditorDocument(image: TestImage.solid(width: 40, height: 40, .white), scale: 1, title: "test")
        var element = try #require(Annotation.svg(corner, at: .zero, documentScale: 1))
        element.end = CGPoint(x: 40, y: 40)
        doc.add(element)
        let image = doc.flattened()
        let green = RGBA(r: 0, g: 255, b: 0, a: 255)
        #expect(TestImage.pixel(image, 4, 4) == green)
        #expect(TestImage.pixel(image, 4, 35) == .white)
        #expect(TestImage.pixel(image, 35, 4) == .white)
    }

    @Test func itKeepsItsAspectRatioAndCanGoBackToItsSize() throws {
        var element = try #require(Annotation.svg(Self.svg, at: .zero, documentScale: 2))
        #expect(Handle.handles(for: element) == Handle.cornerHandles)
        let dragged = Handle.bottomRight.drag(element, to: CGPoint(x: 160, y: 200))
        #expect(dragged.bounds.width == 2 * dragged.bounds.height)
        element.end = CGPoint(x: 10, y: 10)
        #expect(element.hasDefaultSize)
        let size = try #require(element.defaultSize(documentScale: 2))
        #expect(size == CGSize(width: 80, height: 40))
    }

    @Test func anSvgFileOpensAtTwoPixelsPerPoint() throws {
        let folder = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: folder) }
        let url = folder.appendingPathComponent("drawing.svg")
        try Self.svg.write(to: url)
        let opened = try #require(ImageFileLoader.load(url))
        #expect(opened.scale == 2)
        #expect(opened.image.width == 80)
        #expect(opened.image.height == 40)
        #expect(TestImage.pixel(opened.image, 10, 10) == .red)

        // Not an SVG by its name: ImageIO reads it as before.
        let png = folder.appendingPathComponent("picture.png")
        try ImageExporter.data(for: TestImage.solid(width: 3, height: 3, .blue), format: .png, scale: 1).write(to: png)
        #expect(ElementSvg.rasterizedFile(png) == nil)
        let loaded = try #require(ImageFileLoader.load(png))
        #expect(loaded.image.width == 3)

        // An .svg that isn't one can't be opened.
        let broken = folder.appendingPathComponent("broken.svg")
        try Data("hello".utf8).write(to: broken)
        #expect(ImageFileLoader.load(broken) == nil)

        // Dropped or pasted, the file stays an SVG.
        guard case .svg(let data) = ElementPictures.content(of: url) else {
            Issue.record("an SVG file should be an SVG element")
            return
        }
        #expect(data == Self.svg)
    }

    @Test func hugeSvgsAreDrawnSmaller() {
        let limited = ElementSvg.limited(CGSize(width: 40000, height: 20000))
        #expect(limited.width <= 16384)
        let area: CGFloat = limited.width * limited.height
        #expect(area <= ElementSvg.maxPixels)
        let ratio: CGFloat = limited.width / limited.height
        #expect(abs(ratio - 2) < 0.01)
        #expect(ElementSvg.limited(CGSize(width: 30, height: 10)) == CGSize(width: 30, height: 10))
    }

    @Test func pastedSvgDataStaysAnSvg() {
        guard case .svg = ElementPictures.content(of: Self.svg) else {
            Issue.record("SVG data should be an SVG element")
            return
        }
        guard case .picture = ElementPictures.content(of: (try? ImageExporter.data(for: TestImage.solid(width: 2, height: 2, .red),
                                                                                format: .png, scale: 1)) ?? Data()) else {
            Issue.record("PNG data should be a picture")
            return
        }
    }
}

/// SVGs whose references would make macOS draw far more than the file holds: refused before it draws them.
@Suite(.enabled(if: ElementSvg.isSupported))
struct ElementSvgReferenceTests {
    static let svgStart = #"<svg xmlns="http://www.w3.org/2000/svg" xmlns:xlink="http://www.w3.org/1999/xlink" width="100" height="100">"#

    /// `levels` groups, each drawing the one before it ten times with `<use>`: 10^levels rectangles from a few hundred
    /// bytes per level.
    static func useChain(_ levels: Int, element: String = "use", link: String = "href", id: String = "id", hash: String = "#") -> String {
        var defs = "<rect \(id)=\"r0\" width=\"10\" height=\"10\"/>"
        for level in 1...levels {
            defs += "<g \(id)=\"r\(level)\">" + String(repeating: "<\(element) \(link)=\"\(hash)r\(level - 1)\"/>", count: 10) + "</g>"
        }
        return Self.svgStart + "<defs>\(defs)</defs><\(element) \(link)=\"\(hash)r\(levels)\"/></svg>"
    }

    /// `levels` patterns (or masks), each with ten rectangles painted with the one before it by `paint`.
    static func paintChain(_ levels: Int, element: String = "pattern", style: String = "", paint: (Int) -> String) -> String {
        let open = element.lowercased() == "pattern" ? #" width="10" height="10" patternUnits="userSpaceOnUse""# : ""
        var defs = "<\(element) id=\"p0\"\(open)><rect width=\"1\" height=\"1\" fill=\"white\"/></\(element)>"
        for level in 1...levels {
            defs += "<\(element) id=\"p\(level)\"\(open)>"
                + (0..<10).map { "<rect x=\"\($0)\" width=\"1\" height=\"10\" \(paint(level))/>" }.joined()
                + "</\(element)>"
        }
        let use = element.lowercased() == "pattern" ? "fill=\"url(#p\(levels))\"" : "mask=\"url(#p\(levels))\""
        return Self.svgStart + "<style>\(style)</style><defs>\(defs)</defs><rect width=\"100\" height=\"100\" \(use)/></svg>"
    }

    @Test func anSvgThatDrawsItsPartsAMillionTimesIsRefused() throws {
        // 1.3 KB: drawing it took seconds, and an element showing it was drawn again at every change.
        let bomb = Data(Self.useChain(6).utf8)
        let clock = ContinuousClock()
        let start = clock.now
        #expect(ElementSvg.size(of: bomb) == nil)
        #expect(ElementPictures.content(of: bomb) == nil)
        let element = Annotation(kind: .svg, start: .zero, end: CGPoint(x: 50, y: 50), imageData: bomb)
        let file = try GreenshotFile.Contents(image: TestImage.solid(width: 60, height: 60, .white), scale: 1, elements: [element]).encoded()
        let read = try #require(GreenshotFile.read(file))
        _ = AnnotationRenderer.flatten(base: read.image, annotations: read.elements, scale: 1)
        #expect(clock.now - start < .seconds(1))
    }

    @Test func patternsMasksStyleSheetsAndInnerPicturesCount() {
        let attribute = Self.paintChain(5) { "fill=\"url(#p\($0 - 1))\"" }
        let styleAttribute = Self.paintChain(5) { "style=\"fill: url('#p\($0 - 1)')\"" }
        let styleSheet = Self.paintChain(5, style: (1...5).map { ".c\($0) { fill: url(#p\($0 - 1)) }" }.joined()) { "class=\"c\($0)\"" }
        let masks = Self.paintChain(5, element: "mask") { "fill=\"white\" mask=\"url(#p\($0 - 1))\"" }
        let symbols = Self.useChain(5, link: "xlink:href")
        // An SVG picture inside the SVG, drawn ten times.
        let inner = Data(Self.useChain(4).utf8).base64EncodedString()
        let picture = Self.svgStart + "<defs><image id=\"i\" width=\"10\" height=\"10\" href=\"data:image/svg+xml;base64,\(inner)\"/></defs>"
            + String(repeating: "<use href=\"#i\"/>", count: 10) + "</svg>"
        // macOS takes the last of `href` and `xlink:href`; the parser doesn't say which comes first.
        let chain = Self.useChain(5)
        let both = chain.replacingOccurrences(of: ##"<use href="#r5"/>"##, with: ##"<use href="#r5" xlink:href="#r0"/>"##)
        let bothTurned = chain.replacingOccurrences(of: ##"<use href="#r5"/>"##, with: ##"<use href="#r0" xlink:href="#r5"/>"##)
        let bombs = ["attribute": attribute, "style attribute": styleAttribute, "style sheet": styleSheet, "masks": masks,
                     "symbols": symbols, "inner picture": picture, "both links": both, "both links turned": bothTurned]
        for (name, svg) in bombs {
            #expect(ElementSvg.size(of: Data(svg.utf8)) == nil, "\(name)")
        }
    }

    @Test func namesAreComparedLikeMacOSDoes() {
        // macOS takes element and attribute names in any case, `xml:id` for an id, and a link without its "#".
        let bombs = ["Use": Self.useChain(6, element: "Use"), "USE": Self.useChain(6, element: "USE"),
                     "HREF": Self.useChain(6, link: "HREF"), "XLINK:HREF": Self.useChain(6, link: "XLINK:HREF"),
                     "ID": Self.useChain(6, id: "ID"), "xml:id": Self.useChain(6, id: "xml:id"),
                     "no #": Self.useChain(6, hash: ""),
                     "PATTERN": Self.paintChain(5, element: "PATTERN") { "fill=\"url(#p\($0 - 1))\"" },
                     "MASK": Self.paintChain(5, element: "MASK") { "fill=\"white\" mask=\"url(#p\($0 - 1))\"" },
                     "STYLE": Self.paintChain(5, style: (1...5).map { ".c\($0) { fill: url(#p\($0 - 1)) }" }.joined()) { "class=\"c\($0)\"" }
                        .replacingOccurrences(of: "<style>", with: "<STYLE>").replacingOccurrences(of: "</style>", with: "</STYLE>")]
        for (name, svg) in bombs {
            #expect(!ElementSvg.hasLimitedReferences(Data(svg.utf8)), "\(name)")
        }
    }

    @Test func innerPicturesCountWhateverTypeTheySay() throws {
        // macOS looks at what an inner picture holds, not at the type its URL says.
        let inner = Self.useChain(4)
        let commented = Data(("<!--" + String(repeating: "x", count: 5000) + "-->" + inner).utf8)
        let utf16 = try #require(inner.data(using: .utf16))
        let urls = ["png type, comment first": "data:image/png;base64," + commented.base64EncodedString(),
                    "png type, UTF-16": "data:image/png;base64," + utf16.base64EncodedString(),
                    "no type, comment first": "data:," + (String(decoding: commented, as: UTF8.self)
                        .addingPercentEncoding(withAllowedCharacters: .alphanumerics) ?? "")]
        for (name, url) in urls {
            let svg = Self.svgStart + "<defs><image id=\"i\" width=\"10\" height=\"10\" href=\"\(url)\"/></defs>"
                + String(repeating: "<use href=\"#i\"/>", count: 10) + "</svg>"
            #expect(!ElementSvg.hasLimitedReferences(Data(svg.utf8)), "\(name)")
        }
        // SVG pictures in SVG pictures, six deep.
        var nested = Self.svgStart + "<rect width=\"1\" height=\"1\"/></svg>"
        for _ in 1...6 {
            nested = Self.svgStart + "<image href=\"data:image/svg+xml;base64,\(Data(nested.utf8).base64EncodedString())\"/></svg>"
        }
        #expect(!ElementSvg.hasLimitedReferences(Data(nested.utf8)))
        // A real picture inside the SVG is fine.
        let png = try ImageExporter.data(for: TestImage.solid(width: 2, height: 2, .red), format: .png, scale: 1)
        let picture = Self.svgStart + "<image width=\"10\" height=\"10\" href=\"data:image/png;base64,\(png.base64EncodedString())\"/></svg>"
        #expect(ElementSvg.hasLimitedReferences(Data(picture.utf8)))
    }

    @Test func entitiesAreRefused() {
        // An entity of 3.8 KB in 100,000 attributes made the count itself take seconds; drawing programs don't
        // write entities.
        let entity = String(repeating: "x", count: 3800)
        let svg = "<?xml version=\"1.0\"?><!DOCTYPE svg [<!ENTITY b \"\(entity)\">]>" + Self.svgStart
            + String(repeating: "<g class=\"&b;\"/>", count: 100_000) + "</svg>"
        let clock = ContinuousClock()
        let start = clock.now
        #expect(!ElementSvg.hasLimitedReferences(Data(svg.utf8)))
        #expect(clock.now - start < .seconds(1))
        let small = #"<!DOCTYPE svg [<!ENTITY ns_svg "http://www.w3.org/2000/svg">]>"#
            + #"<svg xmlns="&ns_svg;" width="100" height="100"><rect width="10" height="10"/></svg>"#
        #expect(!ElementSvg.hasLimitedReferences(Data(small.utf8)))
    }

    @Test func theVerdictIsKept() {
        let svg = Data(Self.useChain(3).utf8)
        #expect(ElementSvg.knownVerdict(svg) == nil)
        #expect(ElementSvg.drawnElements(svg) != nil)
        #expect(ElementSvg.knownVerdict(svg) == true)
    }

    @Test func bigStyleSheetsAreCountedQuickly() {
        // A rule for each of 5,000 classes, 20,000 shapes: looking for the shapes of each rule in turn took minutes.
        let shapes = (0..<20_000).map { "<rect class=\"c\($0 % 5000)\" width=\"1\" height=\"1\"/>" }.joined()
        let gradients = (0..<5000).map { ".c\($0){fill:url(#g)}" }.joined()
        let patterns = (0..<5000).map { ".c\($0){fill:url(#p)}" }.joined()
        let defs = #"<linearGradient id="g"><stop offset="0"/></linearGradient><pattern id="p" width="2" height="2"><rect width="1" height="1"/><rect x="1" width="1" height="1"/></pattern>"#
        let clock = ContinuousClock()
        let start = clock.now
        // Gradients add nothing; 20,000 shapes each drawing the pattern's content is more than the limit.
        let gradientsFit = ElementSvg.hasLimitedReferences(Data((Self.svgStart + "<style>\(gradients)</style>\(defs)\(shapes)</svg>").utf8))
        let patternsFit = ElementSvg.hasLimitedReferences(Data((Self.svgStart + "<style>\(patterns)</style>\(defs)\(shapes)</svg>").utf8))
        #expect(gradientsFit)
        #expect(!patternsFit)
        #expect(clock.now - start < .seconds(1))
    }

    @Test func aStyleSheetPaintingItsOwnMaskIsFine() {
        // A rule for every `.icon path` reaches the mask and its content too: painting an element with itself or with
        // a pattern or mask it is in is skipped when it is drawn, so it isn't a circle.
        let svg = #"<svg xmlns="http://www.w3.org/2000/svg" width="10" height="10"><style>.icon path{mask:url(#m)}</style>"#
            + #"<mask id="m"><rect width="10" height="10" fill="white"/></mask><g class="icon"><path d="M0 0h10v10z"/></g></svg>"#
        #expect(ElementSvg.size(of: Data(svg.utf8)) == CGSize(width: 10, height: 10))
        let pattern = Self.svgStart + #"<pattern id="p" width="10" height="10"><rect width="5" height="5" fill="url(#p)"/></pattern>"#
            + #"<rect width="100" height="100" fill="url(#p)"/></svg>"#
        #expect(ElementSvg.size(of: Data(pattern.utf8)) == CGSize(width: 100, height: 100))
    }

    @Test func referencesInACircleAreRefused() {
        // Two groups drawing each other made macOS crash.
        let pair = Self.svgStart + ##"<g id="a"><rect width="1" height="1"/><use href="#b"/></g><g id="b"><use href="#a"/></g></svg>"##
        #expect(ElementSvg.size(of: Data(pair.utf8)) == nil)
        let itself = Self.svgStart + ##"<g id="a"><rect width="1" height="1"/><use href="#a"/></g></svg>"##
        #expect(ElementSvg.size(of: Data(itself.utf8)) == nil)
        // Two patterns painting each other's content.
        let patterns = Self.svgStart + #"<pattern id="p" width="10" height="10"><rect width="5" height="5" fill="url(#q)"/></pattern>"#
            + #"<pattern id="q" width="10" height="10"><rect width="5" height="5" fill="url(#p)"/></pattern>"#
            + #"<rect width="100" height="100" fill="url(#p)"/></svg>"#
        #expect(ElementSvg.size(of: Data(patterns.utf8)) == nil)
    }

    @Test func ordinaryReferencesStayFine() throws {
        // An icon sheet drawing a symbol 300 times, 10,000 rectangles from four levels of `<use>`.
        let symbol = #"<symbol id="s"><path d="M0 0h1v1z"/><path d="M1 1h1v1z"/><circle r="1"/></symbol>"#
        let sheet = Self.svgStart + "<defs>\(symbol)</defs>" + String(repeating: ##"<use xlink:href="#s"/>"##, count: 300) + "</svg>"
        // A drawing exported with a style sheet: 3,000 shapes filled with a gradient and a pattern of their class.
        let styled = Self.svgStart + "<style>.st0{fill:url(#g)} .st1{fill:url(#p)}</style>"
            + #"<linearGradient id="g"><stop offset="0" stop-color="red"/><stop offset="1" stop-color="blue"/></linearGradient>"#
            + #"<pattern id="p" width="4" height="4" patternUnits="userSpaceOnUse"><rect width="2" height="2"/></pattern>"#
            + String(repeating: #"<rect class="st0" width="1" height="1"/>"#, count: 3000)
            + String(repeating: #"<rect class="st1" width="1" height="1"/>"#, count: 3000) + "</svg>"
        let doctype = #"<?xml version="1.0"?><!DOCTYPE svg PUBLIC "-//W3C//DTD SVG 1.1//EN" "http://www.w3.org/Graphics/SVG/1.1/DTD/svg11.dtd">"#
            + #"<svg xmlns="http://www.w3.org/2000/svg" width="100" height="100"><rect width="10" height="10"/></svg>"#
        for svg in [sheet, styled, Self.useChain(4), doctype] {
            #expect(ElementSvg.size(of: Data(svg.utf8)) == CGSize(width: 100, height: 100))
        }
    }
}
