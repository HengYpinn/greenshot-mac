// Greenshot for Mac (Community) - an unofficial macOS port of Greenshot
// Copyright (C) 2026 Greenshot for Mac (Community) contributors
// Based on Greenshot, Copyright (C) 2007-2026 Thomas Braun, Jens Klingen, Robin Krom
// SPDX-License-Identifier: GPL-3.0-or-later

import Foundation

/// Filters the log on a search text, per log entry instead of per line: an entry starts with the date of the log
/// layout (`2026-10-16 ...`), the lines after it (e.g. an error) belong to it. Port of upstream
/// `Greenshot/SelfService/LogSearch.cs`.
public enum LogSearch {
    /// The longest search text a `greenshotmac://log?search=` link may bring (upstream
    /// `IpcSecurityDispatcher.MaxLogSearchLength`).
    public static let maxLinkSearchLength = 200

    public struct Result: Equatable, Sendable {
        /// The entries that contain the search text, in their order; the log as it is without a search text.
        public var text: String
        /// The number of entries that contain the text.
        public var matchCount: Int
        /// The number of entries in the log.
        public var entryCount: Int

        public init(text: String, matchCount: Int, entryCount: Int) {
            self.text = text
            self.matchCount = matchCount
            self.entryCount = entryCount
        }
    }

    /// The log entries that contain `search` (ignoring case), in their original order. An empty or nil search returns
    /// the log as it is, with no counts.
    public static func filter(_ log: String, search: String?) -> Result {
        guard let search, !search.isEmpty else { return Result(text: log, matchCount: 0, entryCount: 0) }
        let bytes = Array(log.utf8)
        var result = ""
        var matches = 0
        var entries = 0
        var entryStart = 0
        var lineStart = 0
        while lineStart < bytes.count {
            let lineEnd = bytes[lineStart...].firstIndex(of: 0x0A)
            let nextLineStart = lineEnd.map { $0 + 1 } ?? bytes.count
            if nextLineStart >= bytes.count || startsEntry(bytes, at: nextLineStart) {
                if nextLineStart > entryStart {
                    entries += 1
                    let entry = String(decoding: bytes[entryStart..<nextLineStart], as: UTF8.self)
                    if entry.range(of: search, options: .caseInsensitive) != nil {
                        matches += 1
                        result += entry
                        if bytes[nextLineStart - 1] != 0x0A { result += "\n" }
                    }
                }
                entryStart = nextLineStart
            }
            lineStart = nextLineStart
        }
        return Result(text: result, matchCount: matches, entryCount: entries)
    }

    /// The search text of a link as the log viewer uses it: at most `maxLinkSearchLength` characters, trimmed, unsafe
    /// characters escaped like the log shows them (upstream `ShowForLink` and the dispatcher's limit).
    public static func linkSearchText(_ raw: String?) -> String {
        guard let raw else { return "" }
        let limited = LogSanitizer.prefix(raw, utf16Length: maxLinkSearchLength)
        return LogSanitizer.escapeUnsafeCharacters(limited.trimmingCharacters(in: .whitespacesAndNewlines))
    }

    /// The text of the entries counted for "N of M log entries contain ..." (upstream `logviewer_search_matches`).
    public static func matchesText(_ result: Result, search: String) -> String {
        String(localized: "\(LogSanitizer.groupedNumber(result.matchCount)) of \(LogSanitizer.groupedNumber(result.entryCount)) log entries contain \u{201C}\(search)\u{201D}",
               comment: "Log viewer: matching entries of all entries, and the search text")
    }

    /// True when the line at `index` starts with a date like 2026-10-16.
    static func startsEntry(_ bytes: [UInt8], at index: Int) -> Bool {
        guard index + 10 <= bytes.count else { return false }
        for offset in 0..<10 {
            let byte = bytes[index + offset]
            let ok = offset == 4 || offset == 7 ? byte == UInt8(ascii: "-") : (UInt8(ascii: "0")...UInt8(ascii: "9")).contains(byte)
            if !ok { return false }
        }
        return true
    }
}
