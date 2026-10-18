// Greenshot for Mac (Community) - an unofficial macOS port of Greenshot
// Copyright (C) 2026 Greenshot for Mac (Community) contributors
// Based on Greenshot, Copyright (C) 2007-2026 Thomas Braun, Jens Klingen, Robin Krom
// SPDX-License-Identifier: GPL-3.0-or-later

import Foundation

/// The Jira issues the user looked at recently, from the titles of their windows: the logic of upstream
/// `Greenshot.Plugin.Jira/Monitoring/JiraMonitor.cs` without its event source. Upstream gets an event whenever a window
/// title changes (`WinEventHook.WindowTitleChangeObservable`); the Mac reads the titles every few seconds, and a title
/// that is new or changed since the last reading counts as that event. A key in such a title is seen now: a new key goes
/// to the front of the list, a known one moves there (upstream `SeenAt`). At most `maxEntries` keys, the oldest go.
///
/// Only keys stay, never the titles of windows that are gone; nothing is saved. Like upstream, only keys of projects the
/// configured Jira has count (`projects`, upstream `_projectJiraClientMap`), so no fragment of another title ("UTF-8",
/// "CVE-2026-1234", another company's Jira) is ever looked up on it. Upstream reads the projects when it signs in; the
/// Mac when the picker or the upload window first needs them (no Keychain or network in the background): keys seen
/// before stay in memory unchecked and go once the projects are known. A key the server doesn't know is `forget`-ten.
public struct JiraRecentIssues: Equatable, Sendable {
    /// Upstream `JiraMonitor(int maxEntries = 40)`.
    public static let maxEntries = 40

    /// When each key was last seen in a changed title.
    public private(set) var seenAt: [String: Date] = [:]
    /// The title each window had at the last reading, to tell which ones changed.
    private var titles: [UInt32: String] = [:]
    /// Keys the server doesn't know: never offered again.
    private var rejected: Set<String> = []
    /// The project keys of the configured Jira, upper case; nil until they are known.
    public private(set) var projects: Set<String>?

    public init() {}

    /// One reading of the windows' titles at `now`. Windows whose title is new or changed since the last reading give
    /// their keys (`JiraClient.issueKeys(inTitles:)`); windows that are gone are forgotten. Returns the keys that were
    /// not in the list before.
    @discardableResult
    public mutating func observe(_ windows: [(id: UInt32, title: String)], at now: Date) -> [String] {
        var current: [UInt32: String] = [:]
        var changed: [String] = []
        for window in windows {
            current[window.id] = window.title
            if titles[window.id] != window.title, !window.title.isEmpty { changed.append(window.title) }
        }
        titles = current
        guard !changed.isEmpty else { return [] }
        var added: [String] = []
        for key in JiraClient.issueKeys(inTitles: changed, limit: Self.maxEntries) where isAllowed(key) {
            if seenAt[key] == nil { added.append(key) }
            seenAt[key] = now
        }
        trim()
        return added.filter { seenAt[$0] != nil }
    }

    /// A key the server doesn't know (it answered 404): out of the list, and not taken again.
    public mutating func forget(_ key: String) {
        seenAt[key] = nil
        rejected.insert(key)
    }

    /// The project keys of the configured Jira (nil: not known, e.g. another Jira was set up): keys of other projects
    /// go now and aren't taken any more.
    public mutating func setProjects(_ keys: Set<String>?) {
        projects = keys.map { Set($0.map { $0.uppercased() }) }
        for key in Array(seenAt.keys) where !isAllowed(key) { seenAt[key] = nil }
    }

    /// Whether `key` may be offered and looked up: not rejected, and of one of the `projects` once they are known.
    public func isAllowed(_ key: String) -> Bool {
        guard !rejected.contains(key) else { return false }
        guard let projects else { return true }
        return Self.belongs(key, to: projects)
    }

    /// Whether the project of `key` ("ABC" of "ABC-123") is one of `projects` (upper case).
    public static func belongs(_ key: String, to projects: Set<String>) -> Bool {
        guard let dash = key.lastIndex(of: "-") else { return false }
        return projects.contains(String(key[..<dash]).uppercased())
    }

    /// The keys, the one seen last first.
    public var keys: [String] {
        seenAt.sorted { $0.value != $1.value ? $0.value > $1.value : $0.key < $1.key }.map(\.key)
    }

    /// The keys for the destination picker and the upload window: these first, then `onScreen` (the titles on screen
    /// right now), then `uploadedTo` (the issues uploaded to last), each once, at most `limit`, only allowed ones
    /// (`isAllowed`).
    public func merged(onScreen: [String], uploadedTo: [String], limit: Int = maxEntries) -> [String] {
        var result: [String] = []
        for key in keys + onScreen + uploadedTo where isAllowed(key) && !result.contains(key) {
            result.append(key)
            if result.count == limit { break }
        }
        return result
    }

    /// Whether the titles are watched for these settings: Jira set up with its address and its user (a personal access
    /// token needs none), like upstream, whose monitor starts when it signs in. Reads no Keychain.
    public static func watches(_ jira: JiraSettings) -> Bool {
        guard !jira.url.trimmingCharacters(in: .whitespaces).isEmpty else { return false }
        return jira.login == .serverToken || !jira.email.trimmingCharacters(in: .whitespaces).isEmpty
    }

    /// Only the newest `maxEntries` keys stay (upstream orders by `SeenAt` and takes `_maxEntries`).
    private mutating func trim() {
        guard seenAt.count > Self.maxEntries else { return }
        for key in keys.dropFirst(Self.maxEntries) { seenAt[key] = nil }
    }
}

// MARK: The projects of a Jira

extension JiraClient {
    /// The projects the user can see (upstream `JiraMonitor.AddJiraInstanceAsync`, `Project.GetAllAsync`). Cloud:
    /// `GET /rest/api/3/project/search`, pages of 100 (the list without pages is deprecated there); Server and Data
    /// Center: `GET /rest/api/2/project`.
    public func projectsRequest(startAt: Int = 0) -> URLRequest {
        guard site.login.isCloud else { return site.request("GET", path: "rest/api/2/project") }
        return site.request("GET", path: "rest/api/3/project/search",
                            query: [URLQueryItem(name: "startAt", value: String(startAt)), URLQueryItem(name: "maxResults", value: "100")])
    }

    /// The project keys of a `projectsRequest` answer: a list (Server, Data Center) or a page (`values`, `isLast`,
    /// `total`); `isLast` is true when there is no further page.
    public static func projectKeys(fromJSON data: Data) throws -> (keys: Set<String>, isLast: Bool, count: Int) {
        let object = try JSONSerialization.jsonObject(with: data)
        func keys(_ list: [[String: Any]]) -> Set<String> {
            Set(list.compactMap { ($0["key"] as? String)?.uppercased() })
        }
        if let list = object as? [[String: Any]] { return (keys(list), true, list.count) }
        guard let page = object as? [String: Any], let values = page["values"] as? [[String: Any]] else {
            throw UploadError.unexpectedResponse("no projects in Jira's answer")
        }
        let start = page["startAt"] as? Int ?? 0
        let total = page["total"] as? Int
        let isLast = page["isLast"] as? Bool ?? (values.isEmpty || total.map { start + values.count >= $0 } ?? true)
        return (keys(values), isLast, values.count)
    }

    /// All project keys, at most `maxPages` pages.
    public func projectKeys(maxPages: Int = 20) async throws -> Set<String> {
        var result: Set<String> = []
        var startAt = 0
        for _ in 0..<maxPages {
            let page = try Self.projectKeys(fromJSON: try await HTTPSupport.send(projectsRequest(startAt: startAt), with: http))
            result.formUnion(page.keys)
            guard !page.isLast, page.count > 0 else { break }
            startAt += page.count
        }
        return result
    }
}
