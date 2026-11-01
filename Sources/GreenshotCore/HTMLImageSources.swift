// Greenshot for Mac (Community) - an unofficial macOS port of Greenshot
// Copyright (C) 2026 Greenshot for Mac (Community) contributors
// Based on Greenshot, Copyright (C) 2007-2026 Thomas Braun, Jens Klingen, Robin Krom
// SPDX-License-Identifier: GPL-3.0-or-later

import Foundation

/// The `src` values of the `<img>` tags of HTML, in one pass over the bytes. HTML on the clipboard comes from any web
/// page; a regex that looks for the end of every `<img` again made a page of "<img " repeated take minutes (and the
/// clipboard trigger reads it on the main thread), so this scanner goes over each tag once, from its `<img` to its `>`.
enum HTMLImageSources {
    /// What may come right before `src` in a tag.
    enum Boundary {
        /// White space (the HTML paste of the screenshot import).
        case whitespace
        /// Anything but a letter, digit or underscore (a regex word boundary, which also finds `data-src`).
        case wordBoundary
    }

    /// Only this much of the HTML is read; a data URL of a few MB fits.
    static let maxBytes = 8 * 1024 * 1024
    /// A tag (from `<img` to its `>`) longer than this is junk and skipped; the value of `src` is not part of the limit.
    static let maxTagBytes = 4096

    /// The raw (not yet decoded or checked) `src` value of each `<img` tag that has one.
    static func sources(in html: String, boundary: Boundary) -> [String] {
        let bytes = Array(html.utf8.prefix(maxBytes))
        let count = bytes.count
        var results: [String] = []
        var position = 0

        func index(of byte: UInt8, from start: Int) -> Int? {
            guard start < count else { return nil }
            return bytes[start...].firstIndex(of: byte)
        }

        /// The value of the attribute whose `=` is at `equals` and where the tag goes on after it; nil when its quote
        /// is never closed (the rest of the HTML is in it).
        func value(after equals: Int) -> (range: Range<Int>, next: Int)? {
            var at = equals + 1
            while at < count, isSpace(bytes[at]) { at += 1 }
            guard at < count else { return (at..<at, at) }
            let quote = bytes[at]
            if quote == 0x22 || quote == 0x27 {
                guard let end = index(of: quote, from: at + 1) else { return nil }
                return (at + 1..<end, end + 1)
            }
            var end = at
            while end < count, !isSpace(bytes[end]), bytes[end] != 0x3E, bytes[end] != 0x22, bytes[end] != 0x27 { end += 1 }
            return (at..<end, end)
        }

        /// Whether `src` followed by `=` starts at `at`; the place of the `=`.
        func sourceName(at: Int) -> Int? {
            guard at + 3 < count, lowercased(bytes[at]) == 0x73, lowercased(bytes[at + 1]) == 0x72,
                  lowercased(bytes[at + 2]) == 0x63 else { return nil }
            switch boundary {
            case .whitespace: guard isSpace(bytes[at - 1]) else { return nil }
            case .wordBoundary: guard !isWord(bytes[at - 1]) else { return nil }
            }
            var equals = at + 3
            while equals < count, isSpace(bytes[equals]) { equals += 1 }
            return equals < count && bytes[equals] == 0x3D ? equals : nil
        }

        scan: while position + 4 < count {
            guard let lt = index(of: 0x3C, from: position) else { break }
            position = lt + 1
            guard lt + 4 < count, lowercased(bytes[lt + 1]) == 0x69, lowercased(bytes[lt + 2]) == 0x6D,
                  lowercased(bytes[lt + 3]) == 0x67, isSpace(bytes[lt + 4]) || bytes[lt + 4] == 0x2F else { continue }
            // Once over the tag to its `>`, which may also be inside a quoted value: the first `src` value is kept,
            // the values of the other attributes are stepped over.
            var source: Range<Int>?
            var at = lt + 4
            while at < count, bytes[at] != 0x3E {
                let equals: Int
                let isSource: Bool
                if bytes[at] == 0x3D {
                    (equals, isSource) = (at, false)
                } else if source == nil, let found = sourceName(at: at) {
                    (equals, isSource) = (found, true)
                } else {
                    at += 1
                    continue
                }
                guard let value = value(after: equals) else { break scan }
                if isSource, !value.range.isEmpty { source = value.range }
                at = value.next
            }
            guard at < count else { break }
            position = at + 1
            if let source, at - lt - source.count <= maxTagBytes {
                results.append(String(decoding: bytes[source], as: UTF8.self))
            }
        }
        return results
    }

    private static func lowercased(_ byte: UInt8) -> UInt8 { byte >= 0x41 && byte <= 0x5A ? byte + 0x20 : byte }

    private static func isSpace(_ byte: UInt8) -> Bool { byte == 0x20 || (byte >= 0x09 && byte <= 0x0D) }

    private static func isWord(_ byte: UInt8) -> Bool {
        (byte >= 0x30 && byte <= 0x39) || (byte >= 0x41 && byte <= 0x5A) || (byte >= 0x61 && byte <= 0x7A) || byte == 0x5F
            || byte >= 0x80
    }
}
