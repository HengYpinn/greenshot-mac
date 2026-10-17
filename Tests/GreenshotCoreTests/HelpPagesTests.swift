// SPDX-License-Identifier: GPL-3.0-or-later

import Foundation
import Testing
@testable import GreenshotCore

/// Which help page Help opens (`HelpPages`, upstream `HelpFileLoader`). The website and the bundle are stand-ins.
struct HelpPagesTests {
    private let german = LanguagePacks.resolve("de-DE")!
    private let japanese = LanguagePacks.resolve("ja-JP")!
    private let localized = URL(string: "https://getgreenshot.org/help/de-de/")!

    private func bundled(_ name: String) -> URL? {
        URL(fileURLWithPath: "/Help/\(name)")
    }

    @Test func onlineURLs() {
        #expect(HelpPages.onlineURL(for: german) == localized)
        #expect(HelpPages.onlineURL(for: LanguagePacks.english) == HelpPages.website)
    }

    @Test func bundledPagesInOrder() {
        #expect(HelpPages.localFiles(for: german) == ["help-de-DE.html", "help-en-US.html"])
        #expect(HelpPages.localFiles(for: japanese) == ["help-en-US.html"])
        #expect(HelpPages.localFiles(for: LanguagePacks.english) == ["help-en-US.html"])
    }

    @Test func theLocalizedOnlinePageFirst() async {
        let page = await HelpPages.page(for: german, status: { _ in 200 }, bundled: bundled)
        #expect(page == localized)
    }

    @Test func theEnglishOnlinePageWhenTheLanguageHasNone() async {
        let website = HelpPages.website
        let page = await HelpPages.page(for: german, status: { $0 == website ? 200 : 404 }, bundled: bundled)
        #expect(page == website)
    }

    @Test func theBundledPageWhenTheWebsiteFailsOrIsOffline() async {
        let broken = await HelpPages.page(for: german, status: { _ in 500 }, bundled: bundled)
        #expect(broken.lastPathComponent == "help-de-DE.html")
        let offline = await HelpPages.page(for: japanese, status: { _ in nil }, bundled: bundled)
        #expect(offline.lastPathComponent == "help-en-US.html")
        let nothing = await HelpPages.page(for: german, status: { _ in nil }, bundled: { _ in nil })
        #expect(nothing == HelpPages.website)
    }
}
