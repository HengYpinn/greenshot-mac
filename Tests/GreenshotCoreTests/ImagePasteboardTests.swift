// SPDX-License-Identifier: GPL-3.0-or-later

import AppKit
import Foundation
import Testing
@testable import GreenshotCore

/// The image on the clipboard (upstream `ClipboardHelper.GetFirstImage`, `GetHtmlImageUrls`). Each test uses its own
/// named pasteboard, never the user's clipboard.
@MainActor
struct ImagePasteboardTests {
    private func withPasteboard(_ body: (NSPasteboard) throws -> Void) rethrows {
        let pasteboard = NSPasteboard(name: NSPasteboard.Name("greenshot-tests-\(UUID().uuidString)"))
        defer { pasteboard.releaseGlobally() }
        pasteboard.clearContents()
        try body(pasteboard)
    }

    @Test func aCopiedFileWinsOverItsIcon() throws {
        let url = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString + ".png")
        defer { try? FileManager.default.removeItem(at: url) }
        try ImageExporter.write(TestImage.solid(width: 30, height: 20, .blue), to: url, format: .png)
        try withPasteboard { pasteboard in
            // Finder puts the file and its icon on the pasteboard.
            let icon = try ImageExporter.data(for: TestImage.solid(width: 64, height: 64, .red), format: .tiff)
            let item = NSPasteboardItem()
            item.setString(url.absoluteString, forType: .fileURL)
            item.setData(icon, forType: .tiff)
            pasteboard.writeObjects([item])
            let image = try #require(ImagePasteboard.image(from: pasteboard)).image
            #expect(image.width == 30 && image.height == 20)
            #expect(TestImage.pixel(image, 3, 3) == .blue)
        }
    }

    @Test func pngWinsOverTiffAndKeepsTheScale() throws {
        try withPasteboard { pasteboard in
            let item = NSPasteboardItem()
            item.setData(try ImageExporter.data(for: TestImage.solid(width: 8, height: 8, .red), format: .tiff), forType: .tiff)
            item.setData(try ImageExporter.data(for: TestImage.solid(width: 10, height: 6, .blue), format: .png, scale: 2), forType: .png)
            pasteboard.writeObjects([item])
            let loaded = try #require(ImagePasteboard.image(from: pasteboard))
            #expect(loaded.image.width == 10 && loaded.scale == 2)
        }
    }

    @Test func aDataImageInCopiedHTMLOpens() throws {
        let png = try ImageExporter.data(for: TestImage.solid(width: 5, height: 4, .red), format: .png)
        try withPasteboard { pasteboard in
            pasteboard.setString("<p>Hello <img alt='x' src=\"data:image/png;base64,\(png.base64EncodedString())\"></p>", forType: .html)
            let image = try #require(ImagePasteboard.image(from: pasteboard)).image
            #expect(image.width == 5 && image.height == 4)
            #expect(ImagePasteboard.webImageURLs(on: pasteboard).isEmpty)
        }
    }

    @Test func webImagesOfCopiedHTML() throws {
        try withPasteboard { pasteboard in
            pasteboard.setString("<img src='https://example.com/a.png'><IMG SRC=http://example.com/b.jpg>", forType: .html)
            #expect(ImagePasteboard.webImageURLs(on: pasteboard).map(\.absoluteString)
                == ["https://example.com/a.png", "http://example.com/b.jpg"])
        }
    }

    @Test func imageURLsResolveOnlyAgainstWebPages() {
        let html = #"<img src="pic.png?a=1&amp;b=2"> <img src='/root.png'> <img src="file:///etc/x.png"> <img data-src="no">"#
        let web = ImagePasteboard.imageURLs(in: html, base: URL(string: "https://example.com/blog/post.html"))
        #expect(web.map(\.absoluteString) == ["https://example.com/blog/pic.png?a=1&b=2", "https://example.com/root.png"])
        #expect(ImagePasteboard.imageURLs(in: html, base: URL(string: "file:///Users/me/page.html")).isEmpty)
        #expect(ImagePasteboard.imageURLs(in: html).isEmpty)
    }

    @Test func entitiesAndDataURLs() {
        #expect(ImagePasteboard.decodeEntities("a&amp;b&#39;c&#x41;&lt;&unknown;&") == "a&b'cA<&unknown;&")
        #expect(ImagePasteboard.dataURLContents(URL(string: "data:text/plain;base64,SGk=")!) == Data("Hi".utf8))
        #expect(ImagePasteboard.dataURLContents(URL(string: "data:,a%20b")!) == Data("a b".utf8))
    }

    @Test func nothingOnThePasteboard() {
        withPasteboard { pasteboard in
            pasteboard.setString("just text", forType: .string)
            #expect(ImagePasteboard.image(from: pasteboard) == nil)
        }
    }
}
