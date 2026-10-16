// SPDX-License-Identifier: GPL-3.0-or-later

import Foundation
import Testing
@testable import GreenshotCore

struct FilenamePatternTests {
    static let utc = TimeZone(identifier: "UTC")!
    /// Friday 16 October 2026, 14:05:09 UTC
    static let date: Date = {
        var components = DateComponents()
        components.year = 2026
        components.month = 10
        components.day = 16
        components.hour = 14
        components.minute = 5
        components.second = 9
        components.timeZone = utc
        return Calendar(identifier: .gregorian).date(from: components)!
    }()

    func context(title: String? = "Safari", counter: UInt = 41, locale: String = "en_US_POSIX") -> FilenamePattern.Context {
        var number = counter
        return FilenamePattern.Context(
            captureTime: Self.date, title: title, environment: ["HOME": "/Users/test"], userName: "tester", hostName: "mac",
            homeDirectory: URL(fileURLWithPath: "/Users/test"), locale: Locale(identifier: locale), timeZone: Self.utc,
            nextNumber: { number += 1; return number }, randomIndex: { _ in 0 })
    }

    func fill(_ pattern: String, title: String? = "Safari") -> String {
        FilenamePattern.fill(pattern, context: context(title: title))
    }

    @Test func defaultPatternMatchesUpstream() {
        #expect(fill(FilenamePattern.defaultPattern, title: "Safari: Start/Page") == "2026-10-16 14_05_09-Safari_ Start_Page")
    }

    @Test func emptyPatternFallsBackLikeUpstream() {
        #expect(fill("  ") == "greenshot 2026-10-16 14-05-09")
    }

    @Test func dateParts() {
        #expect(fill("${YYYY}${MM}${DD}-${hh}${mm}${ss}") == "20261016-140509")
    }

    @Test func numberIsIncrementedThenPadded() {
        #expect(fill("${NUM}") == "000042")
        #expect(fill("${NUM:p-3,0}") == "042")
    }

    @Test func padding() {
        #expect(fill("${title:p8,*}", title: "Saf") == "Saf*****")
        #expect(fill("${title:p-6,0}", title: "Saf") == "000Saf")
    }

    @Test func substring() {
        #expect(fill("${title:s0,3}") == "Saf")
        #expect(fill("${title:s2}") == "fari")
        #expect(fill("${title:s-3}") == "ari")
        // Out of range: upstream catches the exception and keeps the value.
        #expect(fill("${title:s2,99}") == "Safari")
    }

    @Test func replace() {
        #expect(fill("${title:rSafari,Web}") == "Web")
    }

    @Test func severalParameters() {
        #expect(fill("${capturetime:d\"yyyy\";p6,_}") == "2026__")
    }

    @Test func userHostAndEnvironment() {
        #expect(fill("${user}@${hostname} ${HOME}") == "tester@mac /Users/test")
    }

    @Test func specialFolders() {
        #expect(fill("${MyPictures}") == "/Users/test/Pictures")
        #expect(fill("${Desktop}") == "/Users/test/Desktop")
    }

    @Test func unknownVariableIsEmpty() {
        #expect(fill("a${nope}b") == "ab")
    }

    @Test func randomCharacters() {
        #expect(fill("${RRRR}") == "0000")
    }

    @Test func titleDefaultsAndIsCut() {
        #expect(fill("${title}", title: nil) == "Greenshot")
        #expect(fill("${title}", title: String(repeating: "x", count: 100)).count == 80)
    }

    @Test func literalSubfolderIsKeptButTitleSlashIsReplaced() {
        #expect(fill("${YYYY}/${title}", title: "a/b") == "2026/a_b")
    }

    @Test func notFilenameSafeKeepsCharacters() {
        #expect(FilenamePattern.fill("${title}", context: context(title: "a:b"), filenameSafe: false) == "a:b")
    }

    @Test func dotNetStandardLongDate() {
        let value = FilenamePattern.fill("${capturetime:d\"D\"}", context: context(locale: "en_US"))
        #expect(value == "Friday, October 16, 2026")
    }

    @Test func dotNetCustomFormats() {
        func format(_ f: String) -> String {
            DotNetDateFormat.string(from: Self.date, format: f, locale: Locale(identifier: "en_US_POSIX"), timeZone: Self.utc)
        }
        #expect(format("dddd, d MMM yy 'at' h tt") == "Friday, 16 Oct 26 at 2 PM")
        #expect(format("yyyyTHH") == "2026T14")
        #expect(format("yyyy\\yMM") == "2026y10")
        #expect(format("HH:mm:ss.fff") == "14:05:09.000")
    }

    @Test func fileNameNeverEndsUpWithoutAName() {
        #expect(FilenamePattern.fileName("${nope}", context: context()) == "greenshot 2026-10-16 14-05-09")
        #expect(FilenamePattern.fileName("${title}", context: context(title: "")) == "greenshot 2026-10-16 14-05-09")
        #expect(FilenamePattern.fileName("${YYYY}/", context: context()) == "2026/greenshot 2026-10-16 14-05-09")
        #expect(FilenamePattern.fileName("${YYYY}/${title}", context: context()) == "2026/Safari")
    }

    @Test func parameterSplittingRespectsQuotes() {
        #expect(FilenamePattern.splitParameters("d\"a;b\";p3") == ["d\"a;b\"", "p3"])
    }
}
