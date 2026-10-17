// Greenshot for Mac (Community) - an unofficial macOS port of Greenshot
// Copyright (C) 2026 Greenshot for Mac (Community) contributors
// SPDX-License-Identifier: GPL-3.0-or-later

import Foundation
import Testing
@testable import GreenshotCore

/// Upstream `Greenshot.Tests/SelfService/LogSearchTests.cs`.
struct LogSearchTests {
    static let log =
        "2026-10-16 09:00:00,000 [1] INFO  - [Startup] Greenshot started\n" +
        "2026-10-16 09:00:01,000 [1] WARN  - [Capture] Capture failed\n" +
        "System.InvalidOperationException: HDR texture lost\n" +
        "   at Greenshot.Capture()\n" +
        "2026-10-16 09:00:02,000 [1] INFO  - [Capture] HDR tone mapping 2560x1440\n" +
        "2026-10-16 09:00:03,000 [1] INFO  - [Startup] Ready"

    @Test func keepsWholeEntriesWithTheirErrorLines() {
        let result = LogSearch.filter(Self.log, search: "texture")
        #expect(result.matchCount == 1)
        #expect(result.entryCount == 4)
        #expect(result.text == "2026-10-16 09:00:01,000 [1] WARN  - [Capture] Capture failed\n" +
            "System.InvalidOperationException: HDR texture lost\n" +
            "   at Greenshot.Capture()\n")
    }

    @Test func ignoresCaseAndKeepsTheOrder() throws {
        let result = LogSearch.filter(Self.log, search: "hdr")
        #expect(result.matchCount == 2)
        let failed = try #require(result.text.range(of: "Capture failed"))
        let mapping = try #require(result.text.range(of: "HDR tone mapping"))
        #expect(failed.lowerBound < mapping.lowerBound)
        #expect(!result.text.contains("[Startup]"))
    }

    @Test func lastEntryWithoutNewlineEndsWithOne() {
        let result = LogSearch.filter(Self.log, search: "Ready")
        #expect(result.matchCount == 1)
        #expect(result.text == "2026-10-16 09:00:03,000 [1] INFO  - [Startup] Ready\n")
    }

    @Test func textBeforeTheFirstEntryIsAnEntry() {
        let result = LogSearch.filter("leftover of a rolled file\n" + Self.log, search: "leftover")
        #expect(result.matchCount == 1)
        #expect(result.entryCount == 5)
        #expect(result.text == "leftover of a rolled file\n")
    }

    @Test func withoutSearchReturnsTheLog() {
        #expect(LogSearch.filter(Self.log, search: "").text == Self.log)
        #expect(LogSearch.filter(Self.log, search: nil).text == Self.log)
    }

    @Test func noMatchIsEmpty() {
        let result = LogSearch.filter(Self.log, search: "nothing like this")
        #expect(result.text.isEmpty)
        #expect(result.matchCount == 0)
    }

    @Test func linkSearchTextIsLimitedTrimmedAndEscaped() {
        #expect(LogSearch.linkSearchText(nil) == "")
        #expect(LogSearch.linkSearchText("  upload failed \n") == "upload failed")
        #expect(LogSearch.linkSearchText("a\u{202E}b") == "a\\u202Eb")
        let long = String(repeating: "x", count: 500)
        #expect(LogSearch.linkSearchText(long).count == LogSearch.maxLinkSearchLength)
    }

    @Test func matchesTextCountsEntries() {
        let result = LogSearch.Result(text: "", matchCount: 2, entryCount: 1_204)
        #expect(LogSearch.matchesText(result, search: "hdr") == "2 of 1,204 log entries contain \u{201C}hdr\u{201D}")
    }
}
