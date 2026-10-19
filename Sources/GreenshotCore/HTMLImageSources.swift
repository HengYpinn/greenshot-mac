// Greenshot for Mac (Community) - an unofficial macOS port of Greenshot
// Copyright (C) 2026 Greenshot for Mac (Community) contributors
// Based on Greenshot, Copyright (C) 2007-2026 Thomas Braun, Jens Klingen, Robin Krom
// SPDX-License-Identifier: GPL-3.0-or-later

import Foundation

/// The `src` values of the `<img>` tags of HTML, in one pass over the bytes. HTML on the clipboard comes from any web
/// page; a regex that looks for the end of every `<img` again made a page of "<img " repeated take minutes (and the
/// clipboard trigger reads it on the main thread), so this scanner never looks at a byte twice.
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
        // The next ">" (and quote) at or after the position asked for: searched once, then kept; they only move forward.
        var tagEnd = -1
        var noMoreDouble = false
        var noMoreSingle = false

        func index(of byte: UInt8, from start: Int) -> Int? {
            guard start < count else { return nil }
            return bytes[start...].firstIndex(of: byte)
        }

        while position + 4 < count {
            guard let lt = index(of: 0x3C, from: position) else { break }
            position = lt + 1
            guard lt + 4 < count, lowercased(bytes[lt + 1]) == 0x69, lowercased(bytes[lt + 2]) == 0x6D,
                  lowercased(bytes[lt + 3]) == 0x67, isSpace(bytes[lt + 4]) || bytes[lt + 4] == 0x2F else { continue }
            if tagEnd < lt {
                guard let found = index(of: 0x3E, from: lt) else { break }
                tagEnd = found
            }
            if tagEnd - lt > maxTagBytes {
                position = tagEnd + 1
                continue
            }
            // The first `src=` inside the tag.
            var cursor = lt + 4
            while cursor + 3 < tagEnd {
                defer { cursor += 1 }
                guard lowercased(bytes[cursor]) == 0x73, lowercased(bytes[cursor + 1]) == 0x72, lowercased(bytes[cursor + 2]) == 0x63
                else { continue }
                let before = bytes[cursor - 1]
                switch boundary {
                case .whitespace: guard isSpace(before) else { continue }
                case .wordBoundary: guard !isWord(before) else { continue }
                }
                var at = cursor + 3
                while at < count, isSpace(bytes[at]) { at += 1 }
                guard at < count, bytes[at] == 0x3D else { continue }
                at += 1
                while at < count, isSpace(bytes[at]) { at += 1 }
                guard at < count else { break }
                let quote = bytes[at]
                var valueEnd: Int?
                var valueStart = at
                if quote == 0x22 || quote == 0x27 {
                    valueStart = at + 1
                    if quote == 0x22, !noMoreDouble {
                        valueEnd = index(of: quote, from: valueStart)
                        noMoreDouble = valueEnd == nil
                    } else if quote == 0x27, !noMoreSingle {
                        valueEnd = index(of: quote, from: valueStart)
                        noMoreSingle = valueEnd == nil
                    }
                    guard let end = valueEnd else { continue }
                    results.append(String(decoding: bytes[valueStart..<end], as: UTF8.self))
                    position = end + 1
                } else {
                    var end = at
                    while end < count, !isSpace(bytes[end]), bytes[end] != 0x3E, bytes[end] != 0x22, bytes[end] != 0x27 { end += 1 }
                    guard end > at else { continue }
                    results.append(String(decoding: bytes[at..<end], as: UTF8.self))
                    position = end
                }
                tagEnd = -1
                break
            }
            if tagEnd >= 0 { position = tagEnd + 1 }
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
