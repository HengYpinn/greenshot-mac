// Greenshot for Mac (Community) - an unofficial macOS port of Greenshot
// Copyright (C) 2026 Greenshot for Mac (Community) contributors
// SPDX-License-Identifier: GPL-3.0-or-later

import Foundation
import Testing
@testable import GreenshotCore

/// Upstream `Greenshot.Tests/Core/LogSanitizerTests.cs` and the EntryLayout tests of `LogSearchTests.cs`.
struct LogSanitizerTests {
    @Test func escapesControlAndInvisibleCharacters() {
        #expect(LogSanitizer.escapeUnsafeCharacters("a\u{0}b") == "a\\u0000b")
        #expect(LogSanitizer.escapeUnsafeCharacters("bell\u{7}") == "bell\\u0007")
        #expect(LogSanitizer.escapeUnsafeCharacters("del\u{7F}c1\u{85}") == "del\\u007Fc1\\u0085")
        #expect(LogSanitizer.escapeUnsafeCharacters("evil\u{202E}txt.exe") == "evil\\u202Etxt.exe")
        #expect(LogSanitizer.escapeUnsafeCharacters("\u{2066}iso\u{2069}") == "\\u2066iso\\u2069")
        #expect(LogSanitizer.escapeUnsafeCharacters("zero\u{200B}width") == "zero\\u200Bwidth")
        #expect(LogSanitizer.escapeUnsafeCharacters("\u{FEFF}bom") == "\\uFEFFbom")
        #expect(LogSanitizer.escapeUnsafeCharacters("line\u{2028}sep") == "line\\u2028sep")
        #expect(LogSanitizer.escapeUnsafeCharacters("arabic\u{061C}mark") == "arabic\\u061Cmark")
    }

    @Test func keepsTabsLineBreaksAndOrdinaryText() {
        let text = "Tab\there\r\nnext line\nÄpfel 😀 中文"
        #expect(LogSanitizer.escapeUnsafeCharacters(text) == text)
        #expect(LogSanitizer.escapeUnsafeCharacters("") == "")
    }

    @Test func limitCutsWithANote() {
        let text = String(repeating: "a", count: 1_300)
        let cut = LogSanitizer.limit(text, maxLength: 100)
        #expect(cut == String(repeating: "a", count: 100) + " ... (1,200 more characters)")
        #expect(LogSanitizer.limit("short", maxLength: 100) == "short")
    }

    @Test func limitDoesNotSplitASurrogatePair() {
        // "😀" is two UTF-16 units; cutting after 3 units would split the second one.
        let text = "a😀😀b"
        let cut = LogSanitizer.limit(text, maxLength: 4)
        #expect(cut.hasPrefix("a😀 ... ("))
        #expect(cut.hasSuffix("(3 more characters)"))
    }

    @Test(arguments: [
        ("one line\n", "one line\n"),
        ("title\n2026-10-16 09:00:00,000 [1] ERROR - fake\n", "title\n    2026-10-16 09:00:00,000 [1] ERROR - fake\n"),
        ("a\r\nb\r\n", "a\r\n    b\r\n"),
        ("a\rb\n", "a\r    b\n"),
        ("no line break", "no line break"),
    ])
    func indentsEveryFollowingLine(entry: String, expected: String) {
        #expect(LogSanitizer.indentFollowingLines(entry) == expected)
    }

    @Test func textInAMessageCantStartAnotherEntry() {
        let raw = LogFile.entry(date: Date(timeIntervalSince1970: 0), thread: "main", level: .info, category: "Capture",
                                message: "Captured window 'Report\n2026-10-16 09:00:00,000 [1] ERROR - [Fake] injected'",
                                error: nil)
        let written = LogSanitizer.fileEntry(raw)
        #expect(written.contains("\n" + LogSanitizer.indent + "2026-10-16 09:00:00,000 [1] ERROR - [Fake] injected"))
        let result = LogSearch.filter(written, search: "injected")
        #expect(result.entryCount == 1)
        #expect(result.matchCount == 1)
    }

    @Test func aTooLongEntryIsCutAndStillEndsTheLine() {
        let raw = String(repeating: "x", count: LogSanitizer.maxEntryLength + 10) + "\n"
        let written = LogSanitizer.fileEntry(raw)
        #expect(written.hasSuffix("(11 more characters)\n"))
        #expect(written.utf16.count < LogSanitizer.maxEntryLength + 40)
    }

    @Test func groupsNumbersLikeTheInvariantCulture() {
        #expect(LogSanitizer.groupedNumber(0) == "0")
        #expect(LogSanitizer.groupedNumber(999) == "999")
        #expect(LogSanitizer.groupedNumber(1_000) == "1,000")
        #expect(LogSanitizer.groupedNumber(1_234_567) == "1,234,567")
    }
}
