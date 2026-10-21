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
        // Cleaned like ${title}: a page can't add folders
        #expect(variables["Browser.Url"] == "https___jira.example.org_browse_QA-9")
        #expect(context.currentURL == "https://jira.example.org/browse/QA-9")
        #expect(variables["Browser.Domain"] == "jira.example.org")
        #expect(variables["Browser.Title"] == "Login")
        #expect(variables["Browser.Ticket"] == "QA-9")
        context.clear()
        #expect(context.patternVariables.isEmpty)
    }

    /// Mac: a stale page must not keep naming captures. The connection that ends forgets only the tab it reported
    /// (another browser's stays); switching the extension off in Settings forgets any.
    @Test func aConnectionForgetsOnlyItsOwnTab() {
        let context = BrowserContext()
        context.update(url: "https://jira.example.org/browse/QA-9", title: "Login", reporter: 101)
        context.clear(reporter: 202)
        #expect(context.currentURL == "https://jira.example.org/browse/QA-9")
        context.clear(reporter: 101)
        #expect(context.patternVariables.isEmpty)
        #expect(context.safeSubfolder.isEmpty)

        // The browser reporting last owns the tab
        context.update(url: "https://a.example/", title: "A", reporter: 101)
        context.update(url: "https://b.example/", title: "B", reporter: 202)
        context.clear(reporter: 101)
        #expect(context.currentDomain == "b.example")
        context.clear()
        #expect(context.currentURL.isEmpty)
        #expect(context.currentTitle.isEmpty)
    }

    /// Mac: the extension sends `"tracking": false` when the user turns its tab tracking off.
    @Test func turningTabTrackingOffForgetsTheTab() throws {
        let context = BrowserContext()
        let tab = try #require(IPCJSON.parseObject(Data(#"{"command":"TAB_CHANGED","url":"https://example.org/QA-1","title":"QA-1"}"#.utf8)))
        context.apply(BrowserTabChange(envelope: IPCEnvelope(json: tab)), reporter: 101)
        #expect(context.currentTicket == "QA-1")
        let off = try #require(IPCJSON.parseObject(Data(#"{"command":"TAB_CHANGED","url":"","title":"","tracking":false}"#.utf8)))
        context.apply(BrowserTabChange(envelope: IPCEnvelope(json: off)), reporter: 101)
        #expect(context.patternVariables.isEmpty)
    }

    /// Mac: a capture from the extension's button makes its page the tab (upstream), unless the extension's tab
    /// tracking is off: then later captures must not be named after it. The capture keeps its own `${url}`.
    @Test func anExtensionCaptureIsTheTabOnlyWithTrackingOn() throws {
        let context = BrowserContext()
        func request(_ json: String) throws -> BrowserImportRequest {
            BrowserImportRequest(envelope: IPCEnvelope(json: try #require(IPCJSON.parseObject(Data(json.utf8)))))
        }
        let untracked = try request(#"{"command":"IMPORT_CAPTURE","tracking":false,"metadata":{"title":"QA-2","url":"https://example.org/QA-2"}}"#)
        context.remember(untracked, reporter: 101)
        #expect(context.patternVariables.isEmpty)
        #expect(untracked.metadata["url"] == "https://example.org/QA-2")
        let tracked = try request(#"{"command":"IMPORT_CAPTURE","metadata":{"title":"QA-3","url":"https://example.org/QA-3"}}"#)
        context.remember(tracked, reporter: 101)
        #expect(context.currentTicket == "QA-3")
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
        #expect(variables["url"] == "https___page.example_")
        #expect(variables["Browser.Title"] == "Own")
        #expect(variables["Browser.Url"] == "https___tab.example_")
        // What was recorded stays as it was
        #expect(store.metadata(forCaptureAt: date)["url"] == "https://page.example/")
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
        // Cleaned like ${title} (upstream's MakePathSafe kept "/", so a URL made sub folders)
        #expect(FilenamePattern.fill("${browser} ${url}", context: pattern) == "firefox https___example.org_page")
    }
}
