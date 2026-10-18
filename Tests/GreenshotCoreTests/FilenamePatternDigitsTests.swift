// SPDX-License-Identifier: GPL-3.0-or-later

import Foundation
import Testing
@testable import GreenshotCore

/// File name dates have Latin digits in every language and region (upstream: .NET `DateTime.ToString`), the calendar
/// stays the region's.
struct FilenamePatternDigitsTests {
    private let date = Date(timeIntervalSince1970: 1_792_329_005) // 2026-10-18 13:10:05 UTC
    private let utc = TimeZone(identifier: "UTC")!

    private static func isLatin(_ text: String) -> Bool {
        text.unicodeScalars.allSatisfy { $0.isASCII }
    }

    @Test(arguments: ["ar_EG", "ar_SA", "ar_SY", "ar_US@rg=egzzzz", "fa_IR", "en_US"])
    func customPatternsUseLatinDigits(_ identifier: String) {
        let text = DotNetDateFormat.string(from: date, format: "yyyyMMdd_HHmmss", locale: Locale(identifier: identifier),
                                           timeZone: utc)
        #expect(Self.isLatin(text), "\(identifier): \(text)")
        #expect(text.count == 15)
    }

    @Test func theCalendarStaysTheRegions() {
        let gregorian = DotNetDateFormat.string(from: date, format: "yyyy", locale: Locale(identifier: "ar_EG"), timeZone: utc)
        #expect(gregorian == "2026")
        let hijri = DotNetDateFormat.string(from: date, format: "yyyy", locale: Locale(identifier: "en_SA"), timeZone: utc)
        #expect(hijri.hasPrefix("14"))
        #expect(Self.isLatin(hijri))
    }

    @Test func standardFormatsToo() {
        let text = DotNetDateFormat.string(from: date, format: "d", locale: Locale(identifier: "ar_EG"), timeZone: utc)
        #expect(!text.unicodeScalars.contains { (0x0660...0x0669).contains($0.value) || (0x06F0...0x06F9).contains($0.value) })
    }

    @Test func theDefaultFileNameInArabic() {
        let context = FilenamePattern.Context(captureTime: date, title: "Safari", locale: Locale(identifier: "ar_EG"),
                                              timeZone: utc)
        let name = FilenamePattern.fill(FilenamePattern.defaultPattern, context: context)
        #expect(name == "2026-10-18 13_10_05-Safari")
    }
}
