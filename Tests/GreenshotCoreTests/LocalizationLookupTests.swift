// SPDX-License-Identifier: GPL-3.0-or-later

import Foundation
import Testing
@testable import GreenshotCore

/// Lookups in tables like the generated ones (Fixtures/l10n), and that tests themselves stay English.
struct LocalizationLookupTests {
    private static let german = Bundle(url: Bundle.module.url(forResource: "Fixtures", withExtension: nil)!
        .appendingPathComponent("l10n/de.lproj", isDirectory: true))!

    @Test func generatedEntriesTranslate() {
        #expect(Self.german.localizedString(forKey: "Cancel", value: nil, table: nil) == "Abbrechen")
        #expect(Self.german.localizedString(forKey: "Not in the table", value: nil, table: nil) == "Not in the table")
        #expect(Self.german.localizedString(forKey: "Quality 100%", value: nil, table: nil) == "Qualität 100 %")
    }

    @Test func positionalPlaceholdersReorder() {
        let format = Self.german.localizedString(forKey: "Saved %lld files to %@", value: nil, table: nil)
        let count = 3
        let text = String(format: format, count, "Desktop")
        #expect(text == "Nach Desktop wurden 3 Dateien gespeichert")
    }

    @Test func textsThatAreAlsoData() {
        #expect(L10nText.display("Capture region", bundle: Self.german) == "Bereich abfotografieren")
        #expect(L10nText.display("A recipe of the user", bundle: Self.german) == "A recipe of the user")
        #expect(L10nText.translationCredit(bundle: Self.german) == "Deutsche Übersetzung: Test")
    }

    /// The test runner has no tables: every text is the English, which is why no test of an English text changes.
    @Test func testsAndHelpersStayEnglish() {
        #expect(L10nText.display("Capture region") == "Capture region")
        #expect(L10nText.translationCredit() == nil)
        #expect(String(localized: "Cancel") == "Cancel")
    }

    @Test func bidiIsolation() {
        let isolated = BidiText.isolatedLTR("⌃⌥⌘4")
        #expect(isolated.unicodeScalars.first == BidiText.leftToRightIsolate)
        #expect(isolated.unicodeScalars.last == BidiText.popDirectionalIsolate)
        #expect(isolated.unicodeScalars.count == "⌃⌥⌘4".unicodeScalars.count + 2)
        #expect(BidiText.isolatedLTR("") == "")
    }
}
