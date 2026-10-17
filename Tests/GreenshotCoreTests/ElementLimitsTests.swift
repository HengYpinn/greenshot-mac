// SPDX-License-Identifier: GPL-3.0-or-later

import CoreGraphics
import Foundation
import Testing
@testable import GreenshotCore

/// Elements from `.greenshot` files, element files and the clipboard with positions that aren't finite or are absurdly
/// far away: left out when they are read, and never trapping when they are drawn or pushed out.
struct ElementLimitsTests {
    static let svg = Data(#"<svg xmlns="http://www.w3.org/2000/svg" width="40" height="20"><rect width="40" height="20" fill="red"/></svg>"#.utf8)

    /// An SVG element ending at 1e300, 1e300: valid JSON, which decoded fine and trapped when it was drawn.
    static let hugeSvg = Annotation(kind: .svg, start: .zero, end: CGPoint(x: 1e300, y: 1e300), imageData: svg)
    static let rectangle = Annotation(kind: .rectangle, start: CGPoint(x: 1, y: 1), end: CGPoint(x: 5, y: 5))

    @Test func theLimitsOfAnElement() {
        #expect(Self.rectangle.hasLimitedGeometry)
        #expect(!Self.hugeSvg.hasLimitedGeometry)
        var far = Self.rectangle
        far.start.x = -1_000_001
        #expect(!far.hasLimitedGeometry)
        var edge = Self.rectangle
        edge.end = CGPoint(x: Annotation.maxCoordinate, y: -Annotation.maxCoordinate)
        #expect(edge.hasLimitedGeometry)
        var tail = Annotation(kind: .speechBubble, start: .zero, end: CGPoint(x: 10, y: 10))
        tail.tail = CGPoint(x: CGFloat.infinity, y: 0)
        #expect(!tail.hasLimitedGeometry)
        let path = Annotation(kind: .freehand, start: .zero, end: .zero, points: [.zero, CGPoint(x: 0, y: CGFloat.nan)])
        #expect(!path.hasLimitedGeometry)
    }

    @Test func aGreenshotFileLeavesThemOut() throws {
        let contents = GreenshotFile.Contents(image: TestImage.solid(width: 8, height: 8, .blue), scale: 1,
                                              elements: [Self.rectangle, Self.hugeSvg])
        let data = try contents.encoded()
        #expect(String(decoding: data, as: UTF8.self).contains("1e+300"))
        let read = try #require(GreenshotFile.read(data))
        #expect(read.elements.map(\.kind) == [.rectangle])
        #expect(read.unreadable == [Annotation.outOfLimitsName])
        let message = try #require(read.openMessage)
        #expect(message.contains("Damaged element"))
        _ = AnnotationRenderer.flatten(base: read.image, annotations: read.elements, scale: 1)
    }

    @Test func pastedElementsAndElementFilesLeaveThemOut() throws {
        let data = try ElementTransfer(elements: [Self.hugeSvg, Self.rectangle], scale: 1).encoded()
        let transfer = try #require(ElementTransfer.decode(data))
        #expect(transfer.elements.map(\.kind) == [.rectangle])
    }

    @Test func aTinyScaleCannotMakePastedElementsHuge() throws {
        // At 1e-300 pixels per point, pasting into a 2× image multiplied the positions by 2e300.
        let json = String(decoding: try ElementTransfer(elements: [Self.rectangle], scale: 1).encoded(), as: UTF8.self)
            .replacingOccurrences(of: "\"scale\":1", with: "\"scale\":1e-300")
        #expect(json.contains("1e-300"))
        let transfer = try #require(ElementTransfer.decode(Data(json.utf8)))
        #expect(transfer.scale == 1)
        let placed = transfer.placed(in: CGSize(width: 100, height: 100), scale: 2, documentID: nil)
        let element = try #require(placed.first)
        #expect(element.hasLimitedGeometry)
    }

    @Test func aHugeElementIsDrawnWithoutTrapping() {
        // The second guard: an element made here (not read from a file) that is huge anyway.
        let image = TestImage.solid(width: 8, height: 8, .blue)
        let infinite = Annotation(kind: .svg, start: .zero, end: CGPoint(x: CGFloat.infinity, y: 10), imageData: Self.svg)
        _ = AnnotationRenderer.flatten(base: image, annotations: [Self.hugeSvg, infinite], scale: 1)
        #expect(ElementSvg.picture(of: infinite, pixelSize: CGSize(width: CGFloat.infinity, height: 10)) == nil)
        #expect(ElementSvg.picture(of: infinite, pixelSize: CGSize(width: CGFloat.nan, height: 10)) == nil)
        #expect(ElementSvg.render(Self.svg, pixelSize: CGSize(width: CGFloat.infinity, height: CGFloat.infinity)) == nil)
        if ElementSvg.isSupported {
            let picture = ElementSvg.picture(of: Self.hugeSvg, pixelSize: CGSize(width: 1e300, height: 1e300))
            #expect(picture.map { $0.width <= 16384 } ?? true)
        }
    }

    @Test func aHugeElementIsNotPushedOut() {
        let document = EditorDocument(image: TestImage.solid(width: 200, height: 100, .white), scale: 1, title: "t", isModified: false)
        let huge = Annotation(kind: .rectangle, start: .zero, end: CGPoint(x: 1e300, y: 1e300))
        let wide = Annotation(kind: .rectangle, start: .zero, end: CGPoint(x: 70_000, y: 10))
        let infinite = Annotation(kind: .rectangle, start: .zero, end: CGPoint(x: CGFloat.infinity, y: 10))
        document.add([huge, wide, infinite])
        for edge in ElementEdge.allCases {
            #expect(!document.pushOut(huge.id, to: edge))
        }
        #expect(!document.pushOut(infinite.id, to: .left))
        #expect(!document.pushOut(infinite.id, to: .right))
        #expect(!document.pushOut(wide.id, to: .right))
        #expect(document.imageSize == CGSize(width: 200, height: 100))
        // Across the cut a wide element is small: pushed out at the bottom, the image grows by 10 pixels.
        #expect(document.pushOut(wide.id, to: .bottom))
        #expect(document.imageSize == CGSize(width: 200, height: 110))
    }

    @Test func aHugeSvgFileOpensWithinTheScaleLimits() throws {
        let folder = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: folder) }
        let url = folder.appendingPathComponent("huge.svg")
        let svg = #"<svg xmlns="http://www.w3.org/2000/svg" width="100000000" height="1"><rect width="10" height="1" fill="red"/></svg>"#
        try Data(svg.utf8).write(to: url)
        guard ElementSvg.isSupported else { return }
        let opened = try #require(ElementSvg.rasterizedFile(url))
        #expect(opened.scale >= ElementSvg.minOpenScale)
        #expect(opened.scale <= ElementSvg.maxOpenScale)
        #expect(opened.image.width <= 16384)
    }
}
