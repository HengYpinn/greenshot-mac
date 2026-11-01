// Greenshot for Mac (Community) - an unofficial macOS port of Greenshot
// Copyright (C) 2026 Greenshot for Mac (Community) contributors
// Based on Greenshot, Copyright (C) 2007-2026 Thomas Braun, Jens Klingen, Robin Krom
// SPDX-License-Identifier: GPL-3.0-or-later

import CoreGraphics
import Foundation
import ImageIO
import Testing
import UniformTypeIdentifiers
@testable import GreenshotCore

/// Pasted text, the pictures of pasted HTML and multi-size picture files (upstream `Surface.PasteElementFromClipboard`,
/// `ClipboardHelper.GetHtmlImageUrls`, `IconContainer`).
struct ElementClipboardTests {
    @Test func pastedTextGetsUpstreamsTextStyle() {
        var remembered = AnnotationStyle.defaults(for: .text)
        remembered.fontSize = 40
        remembered.bold = true
        remembered.shadow = true
        remembered.fillColor = .yellow
        remembered.horizontalAlignment = .left
        let a = ElementClipboard.textElement("Hello", at: CGPoint(x: 10, y: 20), base: remembered, scale: 2, maxWidth: 1000)
        #expect(a.kind == .text && a.text == "Hello")
        #expect(a.style.lineColor == .black && a.style.lineWidth == 2 && !a.style.shadow && a.style.fillColor == .clear)
        #expect(a.style.fontSize == 12 && !a.style.bold && !a.style.italic && a.style.fontFamily.isEmpty)
        // What upstream doesn't set comes from the remembered style.
        #expect(a.style.horizontalAlignment == .left)
        #expect(a.bounds.origin == CGPoint(x: 10, y: 20))
    }

    @Test func thePastedBoxFitsTheText() {
        let style = AnnotationStyle.defaults(for: .text)
        let short = ElementClipboard.textElement("Hi", at: .zero, base: style, scale: 1, maxWidth: 1000).bounds
        let long = ElementClipboard.textElement("Hi there, a longer line", at: .zero, base: style, scale: 1, maxWidth: 1000).bounds
        let twoLines = ElementClipboard.textElement("Hi\nthere", at: .zero, base: style, scale: 1, maxWidth: 1000).bounds
        #expect(long.width > short.width && long.height == short.height)
        #expect(twoLines.height > short.height * 1.5)
        // The text inside fits in one line: drawing it into the box doesn't wrap.
        let a = ElementClipboard.textElement("Hi there, a longer line", at: .zero, base: style, scale: 1, maxWidth: 1000)
        let frame = AnnotationRenderer.textFrame(a.text, style: a.style, in: AnnotationRenderer.textRect(for: a, scale: 1), scale: 1)
        #expect(frame.height < twoLines.height - 10)
        // A long text wraps at the image's width.
        let wrapped = ElementClipboard.textElement(String(repeating: "word ", count: 200), at: .zero, base: style, scale: 1,
                                                   maxWidth: 300).bounds
        #expect(wrapped.width <= 300 && wrapped.height > 100)
    }

    @Test func imagesOfPastedHTML() {
        let html = """
        <p>Text</p><img alt="x" src="https://example.com/a.png?x=1&amp;y=2"><IMG SRC='http://example.com/b.jpg'>
        <img src=data:image/png;base64,AAAA width=3><img src="/relative.png"><img src="file:///etc/passwd"><img src="">
        """
        let urls = ElementClipboard.htmlImageURLs(in: html).map(\.absoluteString)
        #expect(urls == ["https://example.com/a.png?x=1&y=2", "http://example.com/b.jpg", "data:image/png;base64,AAAA"])
        // A relative one only with a web page to resolve it against, never against a file.
        let resolved = ElementClipboard.htmlImageURLs(in: html, baseURL: URL(string: "https://example.org/page/index.html"))
        #expect(resolved.map(\.absoluteString).contains("https://example.org/relative.png"))
        #expect(!ElementClipboard.htmlImageURLs(in: html, baseURL: URL(fileURLWithPath: "/tmp/x.html"))
            .contains { $0.absoluteString.hasSuffix("relative.png") })
        #expect(ElementClipboard.htmlImageURLs(in: "<p>No pictures</p>").isEmpty)
    }

    @Test func theLargestSizeOfAnIconIsUsed() throws {
        let data = NSMutableData()
        let destination = try #require(CGImageDestinationCreateWithData(data, UTType.ico.identifier as CFString, 2, nil))
        CGImageDestinationAddImage(destination, TestImage.solid(width: 16, height: 16, .red), nil)
        CGImageDestinationAddImage(destination, TestImage.solid(width: 64, height: 64, .blue), nil)
        #expect(CGImageDestinationFinalize(destination))
        let picture = try #require(ElementPictures.load(data: data as Data))
        #expect(picture.image.width == 64 && picture.scale == 1)
    }

    /// A little-endian TIFF of `sizes.count` uncompressed 8-bit gray pages (126 bytes each but the pixels), the
    /// pages chained one after the other.
    static func tiff(pageSizes sizes: [Int]) -> Data {
        func le16(_ value: Int) -> [UInt8] { [UInt8(value & 0xFF), UInt8(value >> 8 & 0xFF)] }
        func le32(_ value: Int) -> [UInt8] { le16(value & 0xFFFF) + le16(value >> 16) }
        var data: [UInt8] = [0x49, 0x49, 42, 0] + le32(8)
        for (index, side) in sizes.enumerated() {
            let ifdOffset = data.count
            let ifdLength = 2 + 9 * 12 + 4
            let pixels = side * side
            let next = index + 1 < sizes.count ? ifdOffset + ifdLength + pixels : 0
            // Width, height, 8 bits, no compression, black is zero, the strip, 1 sample, rows per strip, strip bytes.
            let entries: [(tag: Int, type: Int, value: Int)] = [(256, 4, side), (257, 4, side), (258, 3, 8), (259, 3, 1), (262, 3, 1),
                                                                (273, 4, ifdOffset + ifdLength), (277, 3, 1), (278, 4, side),
                                                                (279, 4, pixels)]
            data += le16(entries.count)
            for entry in entries {
                data += le16(entry.tag) + le16(entry.type) + le32(1)
                data += entry.type == 3 ? le16(entry.value) + [0, 0] : le32(entry.value)
            }
            data += le32(next)
            data += [UInt8](repeating: 0x7F, count: pixels)
        }
        return Data(data)
    }

    @Test func theLargestPageOfATiffIsUsed() throws {
        let picture = try #require(ElementPictures.load(data: Self.tiff(pageSizes: [1, 3, 2])))
        #expect(picture.image.width == 3)
    }

    @Test func onlyTheFirstFramesAreCompared() throws {
        // ImageIO walks the chain of a TIFF's pages again for the size of each one: comparing every page of a file
        // with thousands took minutes. A bigger page after the first `maxComparedFrames` is not looked at.
        let sizes = Array(repeating: 1, count: ImageFileLoader.maxComparedFrames) + [2]
        let picture = try #require(ElementPictures.load(data: Self.tiff(pageSizes: sizes)))
        #expect(picture.image.width == 1)
        let many = Self.tiff(pageSizes: Array(repeating: 1, count: 4000))
        let clock = ContinuousClock()
        let start = clock.now
        let loaded = ElementPictures.load(data: many)
        #expect(loaded != nil)
        #expect(clock.now - start < .seconds(2))
    }

    @Test func aRetinaPictureKeepsItsScale() throws {
        let data = try ImageExporter.data(for: TestImage.solid(width: 8, height: 8, .red), format: .png, scale: 2)
        let picture = try #require(ElementPictures.load(data: data))
        #expect(picture.image.width == 8 && picture.scale == 2)
        #expect(ElementPictures.load(data: Data("not a picture".utf8)) == nil)
    }
}
