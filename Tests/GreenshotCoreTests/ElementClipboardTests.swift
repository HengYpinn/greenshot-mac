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
        #expect(a.style.fontSize == 16 && !a.style.bold && !a.style.italic && a.style.fontFamily.isEmpty)
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

    @Test func aRetinaPictureKeepsItsScale() throws {
        let data = try ImageExporter.data(for: TestImage.solid(width: 8, height: 8, .red), format: .png, scale: 2)
        let picture = try #require(ElementPictures.load(data: data))
        #expect(picture.image.width == 8 && picture.scale == 2)
        #expect(ElementPictures.load(data: Data("not a picture".utf8)) == nil)
    }
}
