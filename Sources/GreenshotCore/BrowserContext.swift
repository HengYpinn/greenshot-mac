// Greenshot for Mac (Community) - an unofficial macOS port of Greenshot
// Copyright (C) 2026 Greenshot for Mac (Community) contributors
// Based on Greenshot, Copyright (C) 2007-2026 Thomas Braun, Jens Klingen, Robin Krom
// SPDX-License-Identifier: GPL-3.0-or-later

import Foundation

/// The browser's active tab as the extension reports it ("QA Tab URL Tracking"), for file names that sort captures by
/// ticket or site (upstream `Ipc/BrowserExtension/BrowserContextTracker.cs`). Upstream documents `${Browser.Url}`,
/// `${Browser.Domain}`, `${Browser.Title}` and `${Browser.Ticket}` (docs/greenshot-proxy-and-integration.md §4.2) but
/// never reads the tracker; the Mac gives them to file name patterns. Kept in memory only, never logged.
public final class BrowserContext: @unchecked Sendable {
    public static let shared = BrowserContext()

    /// Upstream's ticket key: two to ten capitals, a dash, one to six digits ("PROJ-1234").
    private static let ticketPattern = try! NSRegularExpression(pattern: #"\b([A-Z]{2,10}-[0-9]{1,6})\b"#)

    private let lock = NSLock()
    private var url = ""
    private var title = ""
    private var domain = ""
    private var ticket = ""
    /// Who reported the tab last: the process of the native messaging host behind that browser's connection.
    private var reporter: pid_t?

    public init() {}

    public var currentURL: String { locked { url } }
    public var currentTitle: String { locked { title } }
    public var currentDomain: String { locked { domain } }
    public var currentTicket: String { locked { ticket } }

    /// A tab change (upstream `UpdateContext`): a new URL without a title clears the old page's title (the extension
    /// sends the URL first while the page loads), a title alone updates the title. `reporter`: the connection's
    /// program, so that its end forgets only the tab it reported.
    public func update(url newURL: String, title newTitle: String, reporter newReporter: pid_t? = nil) {
        lock.lock()
        defer { lock.unlock() }
        if !newURL.allSatisfy(\.isWhitespace) || !newTitle.allSatisfy(\.isWhitespace) { reporter = newReporter }
        if !newURL.allSatisfy(\.isWhitespace) {
            let cleaned = BrowserText.clean(newURL, limit: BrowserText.urlLimit)
            if url.caseInsensitiveCompare(cleaned) != .orderedSame {
                url = cleaned
                domain = Self.domain(of: cleaned)
                if newTitle.allSatisfy(\.isWhitespace) { title = "" }
            }
        }
        if !newTitle.allSatisfy(\.isWhitespace) {
            title = BrowserText.clean(newTitle, limit: BrowserText.titleLimit)
        }
        ticket = Self.ticket(url: url, title: title)
    }

    /// A capture from the extension's button: its page becomes the tab (upstream `HandleImportCaptureAsync`). Mac: not
    /// with the extension's tab tracking off, or later captures would be named after a page the user doesn't share.
    public func remember(_ request: BrowserImportRequest, reporter: pid_t? = nil) {
        guard request.tracking, !request.url.isEmpty else { return }
        update(url: request.url, title: request.title, reporter: reporter)
    }

    /// A TAB_CHANGED message: the tab, or with the extension's tab tracking turned off, forgetting it (Mac).
    public func apply(_ change: BrowserTabChange, reporter: pid_t? = nil) {
        if change.tracking {
            update(url: change.url, title: change.title, reporter: reporter)
        } else {
            clear(reporter: reporter)
        }
    }

    /// Forgets the tab (Mac: upstream keeps it until the app ends, but the Mac puts it into file names): when the
    /// extension is switched off, or with `reporter` when that browser's connection ended or it stopped tracking, then
    /// only if it reported the tab last (another browser's tab stays).
    public func clear(reporter ending: pid_t? = nil) {
        lock.lock()
        defer { lock.unlock() }
        if let ending, reporter != ending { return }
        url = ""
        title = ""
        domain = ""
        ticket = ""
        reporter = nil
    }

    /// The ticket, else the domain, safe as a folder name (upstream `GetSafeDestinationSubfolder`).
    public var safeSubfolder: String {
        let candidate = locked { ticket.isEmpty ? domain : ticket }
        return candidate.isEmpty ? "" : FilenamePattern.makeFilenameSafe(candidate)
    }

    /// `Browser.Url`, `Browser.Domain`, `Browser.Title`, `Browser.Ticket` for a file name pattern; nothing before the
    /// extension reported a tab. Cleaned like `${title}`: any web page sets them, and a "/" or ".." in them must not
    /// choose where a file goes.
    public var patternVariables: [String: String] {
        locked {
            guard !url.isEmpty || !title.isEmpty else { return [:] }
            return ["Browser.Url": url, "Browser.Domain": domain, "Browser.Title": title, "Browser.Ticket": ticket]
                .mapValues(FilenamePattern.makeFilenameSafe)
        }
    }

    private func locked<T>(_ body: () -> T) -> T {
        lock.lock()
        defer { lock.unlock() }
        return body()
    }

    /// The host of an absolute URL (upstream `Uri.Host`), "" otherwise.
    static func domain(of url: String) -> String {
        guard let components = URLComponents(string: url), components.scheme != nil, let host = components.host else { return "" }
        return host.lowercased()
    }

    /// The first ticket key in the title, else in the URL (e.g. "/browse/PROJ-1234").
    static func ticket(url: String, title: String) -> String {
        for text in [title, url] where !text.isEmpty {
            let range = NSRange(text.startIndex..., in: text)
            if let match = ticketPattern.firstMatch(in: text, range: range), let found = Range(match.range(at: 1), in: text) {
                return String(text[found])
            }
        }
        return ""
    }
}

/// The browser extensions whose HANDSHAKE Greenshot accepted, while their connection lasts (Mac). Switching the
/// extension off in Settings forgets the tab (`BrowserContext.clear`) while the browser stays connected, and the
/// extension only reports a tab when it changes; switching it on asks each one for its active tab again, as a
/// handshake does (`{"event": "report_tab"}`).
public final class BrowserConnections: @unchecked Sendable {
    public static let shared = BrowserConnections()

    private let lock = NSLock()
    private var connections: [pid_t: IPCReplyContext] = [:]

    public init() {}

    /// The HANDSHAKE on the connection of `context` was accepted.
    public func accepted(_ context: IPCReplyContext) {
        guard let peer = context.peer else { return }
        lock.lock()
        connections[peer.pid] = context
        lock.unlock()
    }

    /// The connection of `peer` ended (`IPCServer.Configuration.connectionEnded`).
    public func ended(_ peer: IPCPeer) {
        lock.lock()
        if connections[peer.pid]?.peer == peer { connections.removeValue(forKey: peer.pid) }
        lock.unlock()
    }

    /// Asks every accepted extension to report its active tab.
    public func askForActiveTab() {
        lock.lock()
        let contexts = Array(connections.values)
        lock.unlock()
        for context in contexts { context.send(BrowserReplies.reportTabEvent) }
    }
}
