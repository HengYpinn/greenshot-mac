// Greenshot for Mac (Community) - an unofficial macOS port of Greenshot
// Copyright (C) 2026 Greenshot for Mac (Community) contributors
// SPDX-License-Identifier: GPL-3.0-or-later

import Foundation
import Testing
@testable import GreenshotCore

/// Upstream `IpcSecurityDispatcherTests.BrowserContextTracker_*` and `SecurityDispatcher_TabChanged_UpdatesBrowserContextTracker`,
/// plus the Mac's pattern variables and the capture metadata store.
struct BrowserContextTests {
    @Test func ticketsComeFromTheTitleThenTheURL() {
        let context = BrowserContext()
        context.update(url: "https://jira.company.org/browse/QA-4567?filter=all", title: "QA-4567: Critical regression in login flow")
        #expect(context.currentDomain == "jira.company.org")
        #expect(context.currentTicket == "QA-4567")
        #expect(context.safeSubfolder == "QA-4567")

        context.update(url: "https://github.com/greenshot/greenshot/issues/42", title: "Issue 42: Bug in Greenshot")
        #expect(context.currentDomain == "github.com")
        #expect(context.currentTicket.isEmpty)
        #expect(context.safeSubfolder == "github.com")

        context.update(url: "https://corp.jira.com/browse/PROJ-123", title: "Fix payment portal")
        #expect(context.currentTicket == "PROJ-123")
    }

    @Test func aNewURLWithoutTitleClearsTheStaleTitle() {
        let context = BrowserContext()
        context.update(url: "https://corp.jira.com/browse/PROJ-123", title: "PROJ-123: Fix payment portal")
        #expect(context.currentTitle == "PROJ-123: Fix payment portal")

        // Navigation started: the URL comes first, with an empty title
        context.update(url: "https://github.com/greenshot/greenshot", title: "")
        #expect(context.currentURL == "https://github.com/greenshot/greenshot")
        #expect(context.currentTitle.isEmpty)
        #expect(context.currentTicket.isEmpty)

        // The title follows
        context.update(url: "https://github.com/greenshot/greenshot", title: "Greenshot GitHub Repository")
        #expect(context.currentTitle == "Greenshot GitHub Repository")
        // The same URL in another case doesn't clear it
        context.update(url: "HTTPS://GITHUB.COM/greenshot/greenshot", title: "")
        #expect(context.currentTitle == "Greenshot GitHub Repository")
    }

    @Test func valuesAreCleanedAndTheDomainIsLowerCase() {
        let context = BrowserContext()
        context.update(url: "https://Example.ORG/a\u{0}b", title: "T\u{1B}itle")
        #expect(context.currentURL == "https://Example.ORG/ab")
        #expect(context.currentDomain == "example.org")
        #expect(context.currentTitle == "Title")
        context.update(url: "not a url", title: "")
        #expect(context.currentDomain.isEmpty)
    }

    @Test func patternVariables() {
        let context = BrowserContext()
        #expect(context.patternVariables.isEmpty)
        context.update(url: "https://jira.example.org/browse/QA-9", title: "Login")
        let variables = context.patternVariables
        #expect(variables["Browser.Url"] == "https://jira.example.org/browse/QA-9")
        #expect(variables["Browser.Domain"] == "jira.example.org")
        #expect(variables["Browser.Title"] == "Login")
        #expect(variables["Browser.Ticket"] == "QA-9")
        context.clear()
        #expect(context.patternVariables.isEmpty)
    }

    @Test func browserVariablesFillAFileName() {
        let context = BrowserContext()
        context.update(url: "https://jira.example.org/browse/QA-9", title: "Login")
        let store = CaptureMetadataStore(browser: context)
        let pattern = FilenamePattern.Context(captureTime: Date(timeIntervalSince1970: 0), title: "x",
                                              metadata: store.patternMetadata(forCaptureAt: Date()))
        #expect(FilenamePattern.fill("${Browser.Ticket}/${Browser.Domain}", context: pattern) == "QA-9/jira.example.org")
    }
}

struct CaptureMetadataStoreTests {
    @Test func recordedValuesAreFoundByTheCaptureDate() {
        let store = CaptureMetadataStore(browser: BrowserContext())
        let date = Date()
        store.record(["url": "https://example.org/", "browser": "chrome", "empty": ""], forCaptureAt: date)
        #expect(store.metadata(forCaptureAt: date) == ["url": "https://example.org/", "browser": "chrome"])
        #expect(store.metadata(forCaptureAt: date.addingTimeInterval(0.001)).isEmpty)
        // A second record for the same capture adds to it
        store.record(["source": "Extension", "browser": "edge"], forCaptureAt: date)
        #expect(store.metadata(forCaptureAt: date) == ["url": "https://example.org/", "browser": "edge", "source": "Extension"])
    }

    @Test func theCapturesOwnValuesWinOverTheBrowserTab() {
        let context = BrowserContext()
        context.update(url: "https://tab.example/", title: "Tab")
        let store = CaptureMetadataStore(browser: context)
        let date = Date()
        store.record(["url": "https://page.example/", "Browser.Title": "Own"], forCaptureAt: date)
        let variables = store.patternMetadata(forCaptureAt: date)
        #expect(variables["url"] == "https://page.example/")
        #expect(variables["Browser.Title"] == "Own")
        #expect(variables["Browser.Url"] == "https://tab.example/")
    }

    @Test func onlyTheLatestCapturesAreKept() {
        let store = CaptureMetadataStore(browser: BrowserContext())
        let start = Date(timeIntervalSince1970: 1_000)
        for index in 0..<(CaptureMetadataStore.capacity + 5) {
            store.record(["n": "\(index)"], forCaptureAt: start.addingTimeInterval(Double(index)))
        }
        #expect(store.metadata(forCaptureAt: start).isEmpty)
        let last = start.addingTimeInterval(Double(CaptureMetadataStore.capacity + 4))
        #expect(store.metadata(forCaptureAt: last)["n"] == "\(CaptureMetadataStore.capacity + 4)")
    }

    @Test func urlAndBrowserFillAFileName() {
        let store = CaptureMetadataStore(browser: BrowserContext())
        let date = Date()
        store.record(["url": "https://example.org/page", "browser": "firefox"], forCaptureAt: date)
        let pattern = FilenamePattern.Context(captureTime: date, title: "x", metadata: store.patternMetadata(forCaptureAt: date))
        // Upstream's MakePathSafe keeps "/" (a URL makes sub folders)
        #expect(FilenamePattern.fill("${browser} ${url}", context: pattern) == "firefox https://example.org/page")
    }
}
