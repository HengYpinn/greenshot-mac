// SPDX-License-Identifier: GPL-3.0-or-later

import CoreGraphics
import Foundation
import ImageIO
import Testing
@testable import GreenshotCore

/// Pictures from anywhere are checked by the size their header claims before they are decoded: a PNG of 1.5 MB can claim
/// 40000 x 40000 pixels (6.4 GB), a JPEG with an EXIF turn makes a second full-size bitmap.
struct ImagePixelLimitTests {
    /// SOI, SOF0 (precision 8, `width` x `height`, one component), EOI.
    static func jpegClaiming(width: UInt16, height: UInt16) -> Data {
        Data([0xFF, 0xD8, 0xFF, 0xC0, 0x00, 0x0B, 0x08, UInt8(height >> 8), UInt8(height & 0xFF), UInt8(width >> 8),
              UInt8(width & 0xFF), 0x01, 0x01, 0x11, 0x00, 0xFF, 0xD9])
    }

    @Test func aHeaderClaimingSixtyThousandSquareIsNotLoaded() {
        let data = Self.jpegClaiming(width: 60000, height: 60000)
        #expect(ImageFileLoader.load(data: data) == nil)
        #expect(ElementPictures.content(of: data) == nil)
        #expect(ElementPictures.load(data: data) == nil)
    }

    @Test func aHeaderClaimingTooManyPixelsWithinTheSideLimitIsNotLoaded() {
        let data = Self.jpegClaiming(width: 30000, height: 30000)
        #expect(ImageFileLoader.load(data: data) == nil)
        #expect(ElementPictures.content(of: data) == nil)
    }

    @Test func theLimitIsCheckedWithoutOverflow() {
        #expect(!ImageFileLoader.isAcceptable(width: Int.max, height: Int.max))
        #expect(!ImageFileLoader.isAcceptable(width: 0, height: 10))
        #expect(!ImageFileLoader.isAcceptable(width: -1, height: 10))
        #expect(ImageFileLoader.isAcceptable(width: 11648, height: 8736))
    }

    @Test func aFileWithAHugeHeaderIsNotLoaded() throws {
        let url = FileManager.default.temporaryDirectory.appendingPathComponent("huge-\(UUID().uuidString).jpg")
        try Self.jpegClaiming(width: 60000, height: 60000).write(to: url)
        defer { try? FileManager.default.removeItem(at: url) }
        #expect(ImageFileLoader.load(url) == nil)
        #expect(ElementPictures.content(of: url) == nil)
    }

    @Test func aSmallPictureStillLoads() throws {
        let data = try ImageWebPEncoder.encode(TestImage.solid(width: 16, height: 8, .blue))
        let loaded = try #require(ImageFileLoader.load(data: data))
        #expect(loaded.image.width == 16)
        #expect(ElementPictures.content(of: data) != nil)
    }

    @Test func aDownloadWithAHugeHeaderIsNotLoaded() async {
        let configuration = URLSessionConfiguration.ephemeral
        configuration.protocolClasses = [HugeImageServer.self]
        let session = URLSession(configuration: configuration)
        let url = URL(string: "https://example.com/bomb.jpg")!
        #expect(await ImagePasteboard.downloadImage(from: url, session: session) == nil)
        #expect(await CanvasDownloadProbe.picture(from: url, session: session) == nil)
    }
}

/// What the editor does with a downloaded picture, from `CanvasDownload` (which is in the app target).
private enum CanvasDownloadProbe {
    static func picture(from url: URL, session: URLSession) async -> ElementPicture? {
        let data = await ImageDownload.data(from: url, session: session)
        return data.flatMap(ElementPictures.content(of:))
    }
}

/// Answers every request with a JPEG header that claims 60000 x 60000 pixels.
final class HugeImageServer: URLProtocol {
    override class func canInit(with request: URLRequest) -> Bool { true }
    override class func canonicalRequest(for request: URLRequest) -> URLRequest { request }

    override func startLoading() {
        guard let url = request.url, let client else { return }
        let response = HTTPURLResponse(url: url, statusCode: 200, httpVersion: "HTTP/1.1", headerFields: [:])!
        client.urlProtocol(self, didReceive: response, cacheStoragePolicy: .notAllowed)
        client.urlProtocol(self, didLoad: ImagePixelLimitTests.jpegClaiming(width: 60000, height: 60000))
        client.urlProtocolDidFinishLoading(self)
    }

    override func stopLoading() {}
}

/// An image element's bytes (from a .greenshot file or pasted elements) are checked the same way before the renderer
/// decodes them.
struct AnnotationPicturePixelLimitTests {
    @Test func anElementPictureClaimingFortyThousandSquareIsNotDecoded() {
        let data = BrowserImportDecoderTests.pngHeader(width: 40000, height: 40000)
        let element = Annotation(kind: .image, start: .zero, end: CGPoint(x: 10, y: 10), imageData: data)
        #expect(AnnotationRenderer.picture(of: element) == nil)
    }

    @Test func aRealPictureWiderThanTheSideLimitIsNotDecoded() {
        // A complete PNG ImageIO would decode: one pixel wider than `ImageFileLoader.maxSide`, two rows high.
        let data = BrowserImportDecoderTests.encoded("public.png", width: ImageFileLoader.maxSide + 1, height: 2)
        let element = Annotation(kind: .image, start: .zero, end: CGPoint(x: 10, y: 10), imageData: data)
        #expect(AnnotationRenderer.picture(of: element) == nil)
    }

    @Test func theLoadersRefuseARealPictureWiderThanTheSideLimit() {
        let data = BrowserImportDecoderTests.encoded("public.png", width: ImageFileLoader.maxSide + 1, height: 2)
        #expect(ImageFileLoader.load(data: data) == nil)
        #expect(ElementPictures.content(of: data) == nil)
    }

    @Test func aSmallElementPictureIsStillDecoded() {
        let data = BrowserImportDecoderTests.encoded("public.png")
        let element = Annotation(kind: .image, start: .zero, end: CGPoint(x: 10, y: 10), imageData: data)
        #expect(AnnotationRenderer.picture(of: element) != nil)
    }
}
