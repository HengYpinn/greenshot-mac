// Greenshot for Mac (Community) - an unofficial macOS port of Greenshot
// Copyright (C) 2026 Greenshot for Mac (Community) contributors
// Based on Greenshot, Copyright (C) 2007-2026 Thomas Braun, Jens Klingen, Robin Krom
// SPDX-License-Identifier: GPL-3.0-or-later

import Foundation

/// Makes text which goes into the log, or is shown from it, harmless: window titles, file names, URLs or clipboard
/// text can contain anything. Port of upstream `Greenshot.Base/Core/LogSanitizer.cs` and the `EntryLayout` of
/// `LogHelper.cs`, which indents every line of an entry after the first one.
public enum LogSanitizer {
    /// The longest log entry which is written as it is, the rest is left out: one entry can't push everything else out
    /// of the log (it rolls over at 1 MB). Counted in UTF-16 units, like upstream's characters.
    public static let maxEntryLength = 64 * 1024

    /// Put in front of every line of an entry after its first one.
    public static let indent = "    "

    /// Control characters and the invisible characters which change how text is shown (e.g. a right-to-left override,
    /// which shows text in a different order than it was written) become `\uXXXX`, so the log shows what really was
    /// there. Line breaks and tabs stay. Returns the same string when there is nothing to escape.
    public static func escapeUnsafeCharacters(_ text: String) -> String {
        guard text.unicodeScalars.contains(where: isUnsafe) else { return text }
        var result = String.UnicodeScalarView()
        for scalar in text.unicodeScalars {
            if isUnsafe(scalar) {
                result.append(contentsOf: "\\u".unicodeScalars)
                result.append(contentsOf: hex4(scalar.value).unicodeScalars)
            } else {
                result.append(scalar)
            }
        }
        return String(result)
    }

    /// The text cut after `maxLength` UTF-16 units, with a note how much was left out. A surrogate pair (e.g. an emoji)
    /// is never cut in half.
    public static func limit(_ text: String, maxLength: Int = maxEntryLength) -> String {
        let total = text.utf16.count
        guard total > maxLength else { return text }
        let head = prefix(text, utf16Length: maxLength)
        let left = total - head.utf16.count
        return head + " ... (\(groupedNumber(left)) more characters)"
    }

    /// Indents every line after the first one; a line break (\r\n, \n or \r) at the very end stays as it is.
    public static func indentFollowingLines(_ entry: String) -> String {
        guard entry.unicodeScalars.contains(where: { $0 == "\n" || $0 == "\r" }) else { return entry }
        let scalars = Array(entry.unicodeScalars)
        var result = String.UnicodeScalarView()
        for index in scalars.indices {
            let scalar = scalars[index]
            result.append(scalar)
            let next = index + 1 < scalars.count ? scalars[index + 1] : nil
            let lineBreak = scalar == "\n" || (scalar == "\r" && next != "\n")
            if lineBreak, next != nil {
                result.append(contentsOf: indent.unicodeScalars)
            }
        }
        return String(result)
    }

    /// A whole formatted entry as it goes into the file (upstream `EntryLayout.Format`): escaped, cut when too long
    /// (still ending with a line break), every line after the first indented. So no text in an entry can look like
    /// the start of another entry, in the file or in the log viewer.
    public static func fileEntry(_ entry: String) -> String {
        var text = escapeUnsafeCharacters(entry)
        if text.utf16.count > maxEntryLength {
            text = limit(text) + "\n"
        }
        return indentFollowingLines(text)
    }

    /// The first UTF-16 units of `text`, one less when the last one would be the first half of a surrogate pair
    /// (upstream `Substring(0, length)` with the same check).
    static func prefix(_ text: String, utf16Length: Int) -> String {
        let utf16 = text.utf16
        guard utf16.count > utf16Length else { return text }
        var length = max(0, utf16Length)
        if length > 0, UTF16.isLeadSurrogate(utf16[utf16.index(utf16.startIndex, offsetBy: length - 1)]) {
            length -= 1
        }
        let end = utf16.index(utf16.startIndex, offsetBy: length)
        return String(utf16[..<end]) ?? String(text.unicodeScalars.prefix(length))
    }

    /// Characters which are escaped: control characters except tab and line breaks, the line and paragraph separators,
    /// and the invisible formatting characters which change the order or the look of text.
    static func isUnsafe(_ scalar: Unicode.Scalar) -> Bool {
        let value = scalar.value
        if value == 0x09 || value == 0x0A || value == 0x0D { return false }
        if value < 0x20 || (0x7F...0x9F).contains(value) { return true }
        switch value {
        case 0x061C, // Arabic letter mark
             0x200B...0x200F, // zero width space, non-joiner, joiner, left-to-right and right-to-left marks
             0x2028, 0x2029, // line and paragraph separators
             0xFEFF: // zero width no-break space (byte order mark)
            return true
        default:
            // Embeddings and overrides (U+202A to U+202E) and isolates (U+2066 to U+2069)
            return (0x202A...0x202E).contains(value) || (0x2066...0x2069).contains(value)
        }
    }

    private static func hex4(_ value: UInt32) -> String {
        let digits = String(value, radix: 16, uppercase: true)
        return String(repeating: "0", count: max(0, 4 - digits.count)) + digits
    }

    /// 1234567 as "1,234,567", like upstream's `{0:N0}` in the invariant culture.
    static func groupedNumber(_ number: Int) -> String {
        let digits = String(abs(number))
        var groups: [Substring] = []
        var end = digits.endIndex
        while end > digits.startIndex {
            let start = digits.index(end, offsetBy: -3, limitedBy: digits.startIndex) ?? digits.startIndex
            groups.insert(digits[start..<end], at: 0)
            end = start
        }
        return (number < 0 ? "-" : "") + groups.joined(separator: ",")
    }
}
