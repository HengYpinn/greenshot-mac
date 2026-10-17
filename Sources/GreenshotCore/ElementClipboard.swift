// Greenshot for Mac (Community) - an unofficial macOS port of Greenshot
// Copyright (C) 2026 Greenshot for Mac (Community) contributors
// Based on Greenshot, Copyright (C) 2007-2026 Thomas Braun, Jens Klingen, Robin Krom
// SPDX-License-Identifier: GPL-3.0-or-later

import CoreGraphics
import Foundation

/// What a paste into the editor makes of clipboard content that isn't elements or an image (upstream
/// `Surface.PasteElementFromClipboard` and `ClipboardHelper.GetHtmlImageUrls`).
public enum ElementClipboard {
    /// A text element for pasted text, its top left at `origin` (upstream `AddTextContainer` with a sans-serif 12 px
    /// font, black text, a 2 px frame, no shadow, no fill, then `FitToText`). The other properties come from `base`,
    /// the remembered text style. Upstream's text sizes are pixels, which are points here. The box is as big as the
    /// text, at most `maxWidth` pixels wide (the text wraps then).
    public static func textElement(_ text: String, at origin: CGPoint, base: AnnotationStyle, scale: CGFloat,
                                   maxWidth: CGFloat) -> Annotation {
        var style = base
        style.fontFamily = ""
        style.fontSize = 12
        style.bold = false
        style.italic = false
        style.shadow = false
        style.lineWidth = 2
        style.lineColor = .black
        style.fillColor = .clear
        let size = AnnotationRenderer.textBoxSize(text, style: style, scale: scale, maxWidth: maxWidth)
        return Annotation(kind: .text, start: origin, end: CGPoint(x: origin.x + size.width, y: origin.y + size.height),
                          text: text, style: style)
    }

    private static let imageSource = try? NSRegularExpression(
        pattern: #"<img\b[^>]*?\bsrc\s*=\s*(?:"([^"]*)"|'([^']*)'|([^\s"'>]+))"#, options: [.caseInsensitive])

    /// The images of pasted HTML, in their order (upstream `ClipboardHelper.GetHtmlImageUrls`): absolute http(s) and
    /// data URLs; a relative one only with a web page `baseURL` to resolve it against (never a file URL).
    public static func htmlImageURLs(in html: String, baseURL: URL? = nil) -> [URL] {
        guard let imageSource else { return [] }
        let range = NSRange(html.startIndex..., in: html)
        let webBase = baseURL.flatMap { ["http", "https"].contains($0.scheme?.lowercased() ?? "") ? $0 : nil }
        var urls: [URL] = []
        for match in imageSource.matches(in: html, range: range) {
            guard let raw = (1...3).lazy.compactMap({ index -> String? in
                let group = match.range(at: index)
                guard group.location != NSNotFound, let swiftRange = Range(group, in: html) else { return nil }
                return String(html[swiftRange])
            }).first else { continue }
            let source = decodeEntities(raw).trimmingCharacters(in: .whitespacesAndNewlines)
            guard !source.isEmpty else { continue }
            if let url = URL(string: source), let scheme = url.scheme?.lowercased() {
                if ["http", "https", "data"].contains(scheme) { urls.append(url) }
                continue
            }
            if let webBase, let resolved = URL(string: source, relativeTo: webBase)?.absoluteURL {
                urls.append(resolved)
            }
        }
        return urls
    }

    /// The HTML character references that appear in attribute values.
    static func decodeEntities(_ text: String) -> String {
        guard text.contains("&") else { return text }
        var result = text
        for (entity, character) in [("&quot;", "\""), ("&#39;", "'"), ("&#x27;", "'"), ("&apos;", "'"), ("&lt;", "<"),
                                    ("&gt;", ">"), ("&amp;", "&")] {
            result = result.replacingOccurrences(of: entity, with: character, options: .caseInsensitive)
        }
        return result
    }
}
