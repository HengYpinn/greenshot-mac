// Greenshot for Mac (Community) - an unofficial macOS port of Greenshot
// Copyright (C) 2026 Greenshot for Mac (Community) contributors
// Based on Greenshot, Copyright (C) 2007-2026 Thomas Braun, Jens Klingen, Robin Krom
// SPDX-License-Identifier: GPL-3.0-or-later

import AppKit
import GreenshotCore

private let log = Log("Confluence")

/// The Confluence pages open in the browsers: port of upstream `ConfluenceUtils.GetCurrentPagesAsync`, with the tab
/// addresses of Safari and the Chromium browsers read by AppleScript. macOS asks once per browser whether Greenshot may
/// read them, so that only happens when the user asks for it.
@MainActor
enum BrowserPages {
    static func runningBrowsers() -> [ScriptableBrowser] {
        ScriptableBrowser.all.filter { AppleScriptRunner.isRunning($0.bundleID) }
    }

    /// The pages of this Confluence open in a running browser. Without `ask`, only browsers Greenshot may already
    /// control are read, and nil means a running browser would have to ask first (and none could be read).
    static func openPages(client: ConfluenceClient, ask: Bool) async throws -> [ConfluencePage]? {
        let browsers = runningBrowsers()
        guard !browsers.isEmpty else { return [] }
        var readable: [ScriptableBrowser] = []
        var waiting = false
        for browser in browsers {
            switch await AppleScriptRunner.permission(for: browser.bundleID, ask: ask) {
            case .allowed: readable.append(browser)
            case .notAsked, .unknown: waiting = true
            case .denied, .notRunning: break
            }
        }
        if readable.isEmpty && waiting && !ask { return nil }
        var urls: [String] = []
        for browser in readable {
            do {
                urls += AppleScriptOutput.lines(try await AppleScriptRunner.run(browser.tabURLsScript, timeout: 10))
            } catch {
                log.warn("Could not read the tabs of \(browser.name)", error: error)
            }
        }
        return await pages(for: ConfluencePageReference.references(in: urls, site: client.site), client: client)
    }

    /// The pages behind the references; one that can't be looked up is left out (upstream logs it and goes on).
    static func pages(for references: [ConfluencePageReference], client: ConfluenceClient) async -> [ConfluencePage] {
        var pages: [ConfluencePage] = []
        for reference in references.prefix(20) {
            do {
                let page: ConfluencePage?
                switch reference {
                case .id(let id): page = try await client.page(id: id)
                case .title(let space, let title): page = try await client.page(space: space, title: title)
                }
                if let page, !pages.contains(where: { $0.id == page.id }) { pages.append(page) }
            } catch {
                log.warn("Could not look up the open page \(reference)", error: error)
            }
        }
        return pages
    }
}
