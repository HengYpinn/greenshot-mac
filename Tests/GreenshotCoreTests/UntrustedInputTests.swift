// SPDX-License-Identifier: GPL-3.0-or-later

import CoreGraphics
import Foundation
import Testing
@testable import GreenshotCore

/// Element files, pasted elements, pasted HTML and window titles come from outside the app: they must not crash it,
/// fill its memory or steer where files go.
struct UntrustedInputTests {
    @Test func absurdSizesInAnElementFileAreLimited() throws {
        let element = Annotation(kind: .obfuscate, start: CGPoint(x: 1, y: 1), end: CGPoint(x: 5, y: 5))
        var json = String(decoding: try ElementTransfer(elements: [element], scale: 1).encoded(), as: UTF8.self)
        json = json.replacingOccurrences(of: "\"pixelSize\":5", with: "\"pixelSize\":1e300")
        json = json.replacingOccurrences(of: "\"blurRadius\":6", with: "\"blurRadius\":-1e300")
        #expect(json.contains("1e300"))
        let transfer = try #require(ElementTransfer.decode(Data(json.utf8)))
        let style = try #require(transfer.elements.first?.style)
        #expect(style.pixelSize == 100)
        #expect(style.blurRadius == 0)
        // Rendering it must not trap.
        let image = TestImage.solid(width: 8, height: 8, .blue)
        _ = AnnotationRenderer.flatten(base: image, annotations: transfer.elements, scale: 1)
    }

    @Test func pixelateWithAnInfiniteBlockSizeDoesNotTrap() {
        let image = TestImage.solid(width: 8, height: 8, .blue)
        #expect(ImagePixelation.pixelated(image, blockSize: .infinity, element: UUID()) != nil)
        #expect(ImagePixelation.pixelated(image, blockSize: .nan, element: UUID()) != nil)
    }

    @Test func downloadsStopAtTheLimitWithOrWithoutALength() async {
        let configuration = URLSessionConfiguration.ephemeral
        configuration.protocolClasses = [EndlessServer.self]
        let session = URLSession(configuration: configuration)
        #expect(await ImageDownload.data(from: URL(string: "https://example.com/declared")!, session: session, maxBytes: 1000) == nil)
        #expect(await ImageDownload.data(from: URL(string: "https://example.com/undeclared")!, session: session, maxBytes: 1000) == nil)
        #expect(await ImageDownload.data(from: URL(string: "https://example.com/small")!, session: session, maxBytes: 1000)?.count == 10)
        #expect(await ImageDownload.data(from: URL(string: "file:///etc/hosts")!, session: session) == nil)
    }

    @Test func aTitleOfDotsCannotLeaveTheFolder() {
        #expect(FilenamePattern.makeFilenameSafe("..") == "_")
        #expect(FilenamePattern.makeFilenameSafe(".") == "_")
        #expect(FilenamePattern.makeFilenameSafe("...") == "...")
        let context = FilenamePattern.Context(captureTime: Date(timeIntervalSince1970: 0), title: "..")
        let name = FilenamePattern.fileName("${title}/x", context: context)
        #expect(!name.split(separator: "/").contains(".."))
    }

    @Test func aProgramThatLooksLikeAnOptionIsRefused() {
        #expect(ExternalCommandLine.program("-S x") == nil)
        #expect(ExternalCommandLine.program("${title}", fill: { _ in "--output=/tmp/x" }) == nil)
        #expect(ExternalCommandLine.program("/usr/bin/open") != nil)
    }

    @Test func webPStopsWhereDecodersStop() throws {
        #expect(throws: (any Error).self) { try ImageWebPEncoder.encode(TestImage.solid(width: 16384, height: 1, .blue)) }
        let data = try ImageWebPEncoder.encode(TestImage.solid(width: 16383, height: 1, .blue))
        #expect(ImageFileLoader.load(data: data)?.image.width == 16383)
    }
}

/// Streams 2000 bytes, once with a Content-Length and once without; "small" answers 10 bytes.
final class EndlessServer: URLProtocol {
    override class func canInit(with request: URLRequest) -> Bool { true }
    override class func canonicalRequest(for request: URLRequest) -> URLRequest { request }

    override func startLoading() {
        guard let url = request.url, let client else { return }
        let small = url.lastPathComponent == "small"
        var headers: [String: String] = [:]
        if url.lastPathComponent == "declared" { headers["Content-Length"] = "2000" }
        let response = HTTPURLResponse(url: url, statusCode: 200, httpVersion: "HTTP/1.1", headerFields: headers)!
        client.urlProtocol(self, didReceive: response, cacheStoragePolicy: .notAllowed)
        if small {
            client.urlProtocol(self, didLoad: Data(repeating: 1, count: 10))
        } else {
            for _ in 0..<20 { client.urlProtocol(self, didLoad: Data(repeating: 1, count: 100)) }
        }
        client.urlProtocolDidFinishLoading(self)
    }

    override func stopLoading() {}
}
