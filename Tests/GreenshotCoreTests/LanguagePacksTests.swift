// SPDX-License-Identifier: GPL-3.0-or-later

import Foundation
import Testing
@testable import GreenshotCore

/// The language packs (`LanguagePacks`, generated from scripts/l10n/languages.tsv and upstream's packs).
struct LanguagePacksTests {
    @Test func everyUpstreamPackIsThereOnce() {
        #expect(LanguagePacks.all.count == 40)
        #expect(Set(LanguagePacks.all.map(\.ietf)).count == 40)
        #expect(Set(LanguagePacks.all.map(\.lproj)).count == 40)
        #expect(LanguagePacks.all.allSatisfy { !$0.description.isEmpty })
        #expect(LanguagePacks.byName.count == 40)
    }

    @Test func appleLocalizations() {
        let expected = ["ar-SY": "ar", "de-DE": "de", "de-x-franconia": "vmf", "en-US": "en", "fr-QC": "fr-CA",
                        "nn-NO": "nn", "pt-BR": "pt-BR", "pt-PT": "pt-PT", "sr-RS": "sr", "va-VA": "ca-ES-valencia",
                        "zh-CN": "zh-Hans", "zh-TW": "zh-Hant", "kab-DZ": "kab"]
        for (ietf, lproj) in expected {
            let pack = LanguagePacks.all.first { $0.ietf == ietf }
            #expect(pack?.lproj == lproj, "\(ietf)")
        }
        let german = LanguagePacks.pack(lproj: "de")
        #expect(german?.description == "Deutsch")
        #expect(LanguagePacks.english.ietf == "en-US")
    }

    @Test func rightToLeftAreArabicPersianHebrew() {
        let rightToLeft = LanguagePacks.all.filter(\.rightToLeft).map(\.ietf).sorted()
        #expect(rightToLeft == ["ar-SY", "fa-IR", "he-IL"])
    }

    @Test func helpPages() {
        let withHelp = LanguagePacks.all.compactMap(\.helpFile).sorted()
        #expect(withHelp.count == 17)
        #expect(withHelp.contains("help-de-DE.html"))
        #expect(withHelp.contains("help-en-US.html"))
        let japanese = LanguagePacks.resolve("ja-JP")
        #expect(japanese?.helpFile == nil)
    }

    @Test func theLanguageInUse() {
        #expect(LanguagePacks.inUse(preferredLocalizations: ["de"]).ietf == "de-DE")
        #expect(LanguagePacks.inUse(preferredLocalizations: ["zh-Hans", "en"]).ietf == "zh-CN")
        #expect(LanguagePacks.inUse(preferredLocalizations: []).ietf == "en-US")
        #expect(LanguagePacks.inUse(preferredLocalizations: ["Base"]).ietf == "en-US")
    }

    /// Recipes read `config.language` like upstream's `ICoreConfiguration.Language`: a pack's code, not a locale.
    @Test func recipesSeeTheLanguageCode() {
        let value = SystemRecipeEnvironment(settings: AppSettings()).configValue("language")
        let code = value?.asString ?? ""
        #expect(LanguagePacks.resolve(code)?.ietf == code)
        #expect(!code.contains("@"))
    }

    @Test func resolveAcceptsUpstreamAndAppleCodes() {
        let cases: [(String, String?)] = [
            ("de-DE", "de-DE"), ("de_de", "de-DE"), ("DE", "de-DE"), ("de-AT", "de-DE"), ("zh-Hans", "zh-CN"),
            ("zh-CN", "zh-CN"), ("zh-Hant-TW", "zh-TW"), ("zh", "zh-CN"), ("va-VA", "va-VA"),
            ("ca-ES-valencia", "va-VA"), ("ca", "ca-CA"), ("vmf", "de-x-franconia"), ("de-x-franconia", "de-x-franconia"),
            ("fr-CA", "fr-QC"), ("fr", "fr-FR"), ("pt", "pt-BR"), ("en", "en-US"), (" ja-JP ", "ja-JP"),
            ("xx", nil), ("", nil), ("system", nil), ("System", nil),
        ]
        for (code, ietf) in cases {
            let resolved = LanguagePacks.resolve(code)?.ietf
            #expect(resolved == ietf, "\(code)")
        }
    }
}
