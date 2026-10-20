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

    @Test func webImagesOfCopiedHTML() {
        withPasteboard { pasteboard in
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

    @Test func downloadsTheImageOfAWebPage() async throws {
        let configuration = URLSessionConfiguration.ephemeral
        configuration.protocolClasses = [FakeWebServer.self]
        let session = URLSession(configuration: configuration)
        let image = try #require(await ImagePasteboard.downloadImage(from: URL(string: "https://example.com/shot.png")!, session: session))
        #expect(image.image.width == 6 && image.scale == 2)
        #expect(await ImagePasteboard.downloadImage(from: URL(string: "https://example.com/missing.png")!, session: session) == nil)
        #expect(await ImagePasteboard.downloadImage(from: URL(string: "https://example.com/page.html")!, session: session) == nil)
        #expect(await ImagePasteboard.downloadImage(from: URL(string: "file:///etc/hosts")!, session: session) == nil)
    }
}

/// Answers image requests without a network: shot.png is an image, page.html is text, the rest is missing.
final class FakeWebServer: URLProtocol {
    override class func canInit(with request: URLRequest) -> Bool { true }
    override class func canonicalRequest(for request: URLRequest) -> URLRequest { request }

    override func startLoading() {
        guard let url = request.url, let client else { return }
        let path = url.lastPathComponent
        let body: Data
        let status: Int
        switch path {
        case "shot.png":
            body = (try? ImageExporter.data(for: TestImage.solid(width: 6, height: 4, .blue), format: .png, scale: 2)) ?? Data()
            status = 200
        case "page.html":
            body = Data("<html></html>".utf8)
            status = 200
        default:
            body = Data()
            status = 404
        }
        let response = HTTPURLResponse(url: url, statusCode: status, httpVersion: "HTTP/1.1", headerFields: nil)!
        client.urlProtocol(self, didReceive: response, cacheStoragePolicy: .notAllowed)
        client.urlProtocol(self, didLoad: body)
        client.urlProtocolDidFinishLoading(self)
    }

    override func stopLoading() {}
}

/// HTML from the clipboard comes from any web page: finding its images must take time in proportion to its size.
struct HTMLImageSourcesTests {
    @Test func twoMegabytesOfImgStartsAreQuick() {
        let html = String(repeating: "<img ", count: 400_000)
        let clock = ContinuousClock()
        let start = clock.now
        let pasteboardURLs = ImagePasteboard.imageURLs(in: html)
        let elementURLs = ElementClipboard.htmlImageURLs(in: html)
        let elapsed = clock.now - start
        #expect(pasteboardURLs.isEmpty)
        #expect(elementURLs.isEmpty)
        #expect(elapsed < .seconds(2))
    }

    @Test func manyUnclosedQuotesAreQuick() {
        let html = String(repeating: "<img src=\"", count: 200_000) + String(repeating: "<img src='", count: 100_000)
        let clock = ContinuousClock()
        let start = clock.now
        #expect(ImagePasteboard.imageURLs(in: html).isEmpty)
        #expect(clock.now - start < .seconds(2))
    }

    @Test func manyTagsWithoutSourcesAreQuick() {
        let html = String(repeating: "<img alt=x>", count: 200_000) + "<img src=\"https://example.com/a.png\">"
        let clock = ContinuousClock()
        let start = clock.now
        let urls = ImagePasteboard.imageURLs(in: html)
        #expect(urls.map(\.absoluteString) == ["https://example.com/a.png"])
        #expect(clock.now - start < .seconds(2))
    }

    @Test func sourcesInAllThreeQuotingStyles() {
        let html = "<IMG class=a SRC=\"https://e.com/1.png\"><img\nsrc='https://e.com/2.png' alt=x><img src=https://e.com/3.png>"
            + "<img srcset=\"x\"><img data-src=\"https://e.com/4.png\"><p src=\"https://e.com/no.png\">"
        #expect(ImagePasteboard.imageURLs(in: html).map(\.absoluteString)
            == ["https://e.com/1.png", "https://e.com/2.png", "https://e.com/3.png"])
        #expect(ElementClipboard.htmlImageURLs(in: html).map(\.absoluteString)
            == ["https://e.com/1.png", "https://e.com/2.png", "https://e.com/3.png", "https://e.com/4.png"])
    }

    @Test func aValueWithAGreaterThanSignIsKept() {
        let html = "<img alt=x src=\"data:text/plain,a>b\">"
        #expect(ImagePasteboard.imageURLs(in: html).count == 1)
    }
}
