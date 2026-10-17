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
