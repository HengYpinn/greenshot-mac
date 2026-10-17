// Greenshot for Mac (Community) - an unofficial macOS port of Greenshot
// Copyright (C) 2026 Greenshot for Mac (Community) contributors
// Based on Greenshot, Copyright (C) 2007-2026 Thomas Braun, Jens Klingen, Robin Krom
// SPDX-License-Identifier: GPL-3.0-or-later

import AppKit
import ImageIO
import UniformTypeIdentifiers

/// The image on a pasteboard: upstream `ClipboardHelper.GetFirstImage` / `ClipboardService.GetImageAsync`
/// (`Greenshot.Base/Core/ClipboardHelper.cs`, `ClipboardService.cs`): copied image files, the image formats in the order
/// upstream prefers them, and the images of copied HTML.
public enum ImagePasteboard {
    /// The image data types in the order they are tried (upstream `ImageFormats`: PNG first, then the bitmap, JPEG,
    /// TIFF and GIF formats); after them any other type ImageIO reads.
    static let preferredTypes: [NSPasteboard.PasteboardType] = [
        .png, NSPasteboard.PasteboardType(UTType.jpeg.identifier), .tiff, NSPasteboard.PasteboardType(UTType.gif.identifier),
    ]

    /// The first image of the pasteboard, at its full resolution with its pixels per point, upright:
    /// 1. copied image files: Finder puts the file's icon on the pasteboard too, which must not win;
    /// 2. image data, best format first;
    /// 3. `data:` images of copied HTML (`<img src="data:...">`); web images need `downloadedHTMLImage`;
    /// 4. whatever `NSImage` makes of the pasteboard.
    public static func image(from pasteboard: NSPasteboard) -> (image: CGImage, scale: CGFloat)? {
        for url in imageFileURLs(on: pasteboard) {
            if let loaded = ImageFileLoader.load(url) { return loaded }
        }
        let readable = Set((CGImageSourceCopyTypeIdentifiers() as? [String]) ?? [])
        let available = pasteboard.types ?? []
        let others = available.filter { readable.contains($0.rawValue) && !preferredTypes.contains($0) }
        for type in preferredTypes + others where available.contains(type) {
            if let data = pasteboard.data(forType: type), let loaded = ImageFileLoader.load(data: data) { return loaded }
        }
        if let html = pasteboard.string(forType: .html) {
            for url in imageURLs(in: html) where url.scheme == "data" {
                if let data = dataURLContents(url), let loaded = ImageFileLoader.load(data: data) { return loaded }
            }
        }
        guard let image = NSImage(pasteboard: pasteboard) else { return nil }
        return bitmap(of: image)
    }

    /// The web images (http, https) of the HTML on the pasteboard, for a download.
    public static func webImageURLs(on pasteboard: NSPasteboard) -> [URL] {
        guard let html = pasteboard.string(forType: .html) else { return [] }
        return imageURLs(in: html).filter { $0.scheme == "http" || $0.scheme == "https" }
    }

    /// The copied files that are images (upstream `GetImageFilenames`, CF_HDROP).
    static func imageFileURLs(on pasteboard: NSPasteboard) -> [URL] {
        let urls = pasteboard.readObjects(forClasses: [NSURL.self], options: [.urlReadingFileURLsOnly: true]) as? [URL] ?? []
        return urls.filter { url in
            let type = (try? url.resourceValues(forKeys: [.contentTypeKey]))?.contentType
                ?? UTType(filenameExtension: url.pathExtension)
            return type?.conforms(to: .image) == true
        }
    }

    /// The image sources of `<img>` tags (upstream `GetHtmlImageUrls`): http, https and data URLs. A relative source is
    /// resolved against `base` only when that is a web page, so it can never become a file URL.
    public static func imageURLs(in html: String, base: URL? = nil) -> [URL] {
        let pattern = #"<img\b[^>]*?\ssrc\s*=\s*(?:"([^"]*)"|'([^']*)'|([^\s>"']+))"#
        guard let expression = try? NSRegularExpression(pattern: pattern, options: [.caseInsensitive]) else { return [] }
        let isWebPage = base?.scheme == "http" || base?.scheme == "https"
        var urls: [URL] = []
        for match in expression.matches(in: html, range: NSRange(html.startIndex..., in: html)) {
            let value = (1...3).lazy.compactMap { index -> String? in
                let range = match.range(at: index)
                guard range.location != NSNotFound, let swiftRange = Range(range, in: html) else { return nil }
                return String(html[swiftRange])
            }.first
            let source = decodeEntities(value ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
            guard !source.isEmpty else { continue }
            if let url = URL(string: source), let scheme = url.scheme?.lowercased() {
                if ["http", "https", "data"].contains(scheme) { urls.append(url) }
            } else if isWebPage, let base, let url = URL(string: source, relativeTo: base)?.absoluteURL {
                urls.append(url)
            }
        }
        return urls
    }

    /// The bytes of a `data:` URL (base64 or percent-encoded).
    static func dataURLContents(_ url: URL) -> Data? {
        let text = url.absoluteString
        guard text.hasPrefix("data:"), let comma = text.firstIndex(of: ",") else { return nil }
        let header = text[text.index(text.startIndex, offsetBy: 5)..<comma]
        let payload = String(text[text.index(after: comma)...])
        if header.hasSuffix(";base64") {
            return Data(base64Encoded: payload.removingPercentEncoding ?? payload, options: .ignoreUnknownCharacters)
        }
        return payload.removingPercentEncoding.map { Data($0.utf8) }
    }

    /// Downloads an image (upstream `NetworkHelper.DownloadImageAsync`): nil when the server doesn't answer with an
    /// image within the timeout, or it is bigger than 50 MB.
    public static func downloadImage(from url: URL, session: URLSession = .shared) async -> (image: CGImage, scale: CGFloat)? {
        guard url.scheme == "http" || url.scheme == "https" else { return nil }
        var request = URLRequest(url: url, timeoutInterval: 15)
        request.setValue("image/*", forHTTPHeaderField: "Accept")
        guard let (data, response) = try? await session.data(for: request),
              (response as? HTTPURLResponse).map({ (200..<300).contains($0.statusCode) }) ?? true,
              data.count <= 50 * 1024 * 1024 else { return nil }
        return ImageFileLoader.load(data: data)
    }

    /// The biggest bitmap of an image, with its pixels per point.
    public static func bitmap(of image: NSImage) -> (image: CGImage, scale: CGFloat)? {
        let best = image.representations
            .compactMap { $0 as? NSBitmapImageRep }
            .max { $0.pixelsWide < $1.pixelsWide }
        if let best, let cgImage = best.cgImage {
            let scale = best.size.width > 0 ? CGFloat(best.pixelsWide) / best.size.width : 1
            return (cgImage, max(scale.rounded(), 1))
        }
        var rect = CGRect(origin: .zero, size: image.size)
        guard let cgImage = image.cgImage(forProposedRect: &rect, context: nil, hints: nil) else { return nil }
        return (cgImage, 1)
    }

    /// `&amp;`, `&quot;`, `&#39;`, `&lt;`, `&gt;` and numeric entities (upstream `WebUtility.HtmlDecode`).
    static func decodeEntities(_ text: String) -> String {
        guard text.contains("&") else { return text }
        var result = ""
        var rest = Substring(text)
        while let amp = rest.firstIndex(of: "&") {
            result += rest[..<amp]
            guard let semicolon = rest[amp...].firstIndex(of: ";"), rest.distance(from: amp, to: semicolon) <= 10 else {
                result += "&"
                rest = rest[rest.index(after: amp)...]
                continue
            }
            let name = String(rest[rest.index(after: amp)..<semicolon])
            let named = ["amp": "&", "quot": "\"", "apos": "'", "lt": "<", "gt": ">"]
            if let value = named[name] {
                result += value
            } else if name.hasPrefix("#"), let code = name.dropFirst().lowercased().hasPrefix("x")
                        ? UInt32(name.dropFirst(2), radix: 16) : UInt32(name.dropFirst()),
                      let scalar = Unicode.Scalar(code) {
                result.unicodeScalars.append(scalar)
            } else {
                result += rest[amp...semicolon]
            }
            rest = rest[rest.index(after: semicolon)...]
        }
        return result + rest
    }
}
