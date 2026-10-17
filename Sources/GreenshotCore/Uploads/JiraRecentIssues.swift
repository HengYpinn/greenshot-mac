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
/// Only keys stay, never the titles of windows that are gone; nothing is saved. Upstream keeps only keys of projects
/// its Jira knows; here the server is asked when the list is shown, and a key it doesn't know (`UTF-8` in a title)
/// is `forget`-ten.
public struct JiraRecentIssues: Equatable, Sendable {
    /// Upstream `JiraMonitor(int maxEntries = 40)`.
    public static let maxEntries = 40

    /// When each key was last seen in a changed title.
    public private(set) var seenAt: [String: Date] = [:]
    /// The title each window had at the last reading, to tell which ones changed.
    private var titles: [UInt32: String] = [:]
    /// Keys the server doesn't know: never offered again.
    private var rejected: Set<String> = []

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
        for key in JiraClient.issueKeys(inTitles: changed, limit: Self.maxEntries) where !rejected.contains(key) {
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

    /// The keys, the one seen last first.
    public var keys: [String] {
        seenAt.sorted { $0.value != $1.value ? $0.value > $1.value : $0.key < $1.key }.map(\.key)
    }

    /// The keys for the destination picker and the upload window: these first, then `onScreen` (the titles on screen
    /// right now), then `uploadedTo` (the issues uploaded to last), each once, at most `limit`, without rejected keys.
    public func merged(onScreen: [String], uploadedTo: [String], limit: Int = maxEntries) -> [String] {
        var result: [String] = []
        for key in keys + onScreen + uploadedTo where !rejected.contains(key) && !result.contains(key) {
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
