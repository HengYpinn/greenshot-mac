// SPDX-License-Identifier: GPL-3.0-or-later

import Foundation
import Testing
@testable import GreenshotCore

/// DST-088: the issues seen in window titles (upstream `JiraMonitor`), read every few seconds on the Mac.
struct JiraRecentIssuesTests {
    private let start = Date(timeIntervalSince1970: 1_800_000_000)

    private func at(_ seconds: Double) -> Date {
        start.addingTimeInterval(seconds)
    }

    @Test func keysOfNewTitlesAreSeen() {
        var recent = JiraRecentIssues()
        let added = recent.observe([(id: 1, title: "[SHOT-12] Torn edge - Jira"), (id: 2, title: "Inbox")], at: at(0))
        #expect(added == ["SHOT-12"])
        #expect(recent.keys == ["SHOT-12"])
    }

    @Test func anUnchangedTitleDoesNotCountAgain() {
        var recent = JiraRecentIssues()
        recent.observe([(id: 1, title: "SHOT-1 first")], at: at(0))
        recent.observe([(id: 1, title: "SHOT-1 first"), (id: 2, title: "SHOT-2 second")], at: at(2))
        // Window 1 didn't change: SHOT-1 keeps its time, SHOT-2 is newer.
        #expect(recent.keys == ["SHOT-2", "SHOT-1"])
        let again = recent.observe([(id: 1, title: "SHOT-1 first"), (id: 2, title: "SHOT-2 second")], at: at(4))
        #expect(again.isEmpty)
        #expect(recent.seenAt["SHOT-1"] == at(0))
    }

    @Test func aChangedTitleMovesItsKeyToTheFront() {
        var recent = JiraRecentIssues()
        recent.observe([(id: 1, title: "SHOT-1 first")], at: at(0))
        recent.observe([(id: 1, title: "SHOT-1 first"), (id: 2, title: "SHOT-2 second")], at: at(2))
        // The browser tab of window 1 switches to another page and back: its title changes.
        recent.observe([(id: 1, title: "Search"), (id: 2, title: "SHOT-2 second")], at: at(4))
        let added = recent.observe([(id: 1, title: "SHOT-1 first"), (id: 2, title: "SHOT-2 second")], at: at(6))
        #expect(added.isEmpty, "SHOT-1 was in the list already")
        #expect(recent.keys == ["SHOT-1", "SHOT-2"])
    }

    @Test func aClosedWindowIsForgottenButItsKeyStays() {
        var recent = JiraRecentIssues()
        recent.observe([(id: 1, title: "SHOT-1 first")], at: at(0))
        recent.observe([], at: at(2))
        #expect(recent.keys == ["SHOT-1"])
        // The same title in a new window (or the window back) counts as seen again.
        recent.observe([(id: 1, title: "SHOT-1 first")], at: at(4))
        #expect(recent.seenAt["SHOT-1"] == at(4))
    }

    @Test func atMostFortyKeysTheOldestGo() {
        var recent = JiraRecentIssues()
        for index in 0..<45 {
            recent.observe([(id: UInt32(index + 1), title: "KEY-\(index) page")], at: at(Double(index)))
        }
        #expect(recent.keys.count == JiraRecentIssues.maxEntries)
        #expect(recent.keys.first == "KEY-44")
        #expect(recent.keys.last == "KEY-5")
        #expect(recent.seenAt["KEY-4"] == nil)
    }

    @Test func forgottenKeysAreNotTakenAgain() {
        var recent = JiraRecentIssues()
        recent.observe([(id: 1, title: "UTF-8 encoding")], at: at(0))
        #expect(recent.keys == ["UTF-8"])
        recent.forget("UTF-8")
        #expect(recent.keys.isEmpty)
        let added = recent.observe([(id: 1, title: "Encoding: UTF-8")], at: at(2))
        #expect(added.isEmpty)
        #expect(recent.keys.isEmpty)
        let merged = recent.merged(onScreen: ["UTF-8"], uploadedTo: ["UTF-8", "SHOT-3"])
        #expect(merged == ["SHOT-3"])
    }

    @Test func mergedPutsTheSeenIssuesFirst() {
        var recent = JiraRecentIssues()
        recent.observe([(id: 1, title: "SHOT-7 page")], at: at(0))
        recent.observe([(id: 1, title: "SHOT-7 page"), (id: 2, title: "SHOT-8 page")], at: at(2))
        let keys = recent.merged(onScreen: ["SHOT-9", "SHOT-8"], uploadedTo: ["SHOT-1", "SHOT-7"])
        #expect(keys == ["SHOT-8", "SHOT-7", "SHOT-9", "SHOT-1"])
        let two = recent.merged(onScreen: ["SHOT-9"], uploadedTo: ["SHOT-1"], limit: 2)
        #expect(two == ["SHOT-8", "SHOT-7"])
    }

    @Test func watchedOnlyWhileJiraIsSetUp() {
        var jira = JiraSettings()
        #expect(!JiraRecentIssues.watches(jira))
        jira.url = "https://example.atlassian.net"
        #expect(!JiraRecentIssues.watches(jira), "a Cloud site needs its user")
        jira.email = "me@example.com"
        #expect(JiraRecentIssues.watches(jira))
        var server = JiraSettings()
        server.url = "https://jira.example.com"
        server.login = .serverToken
        #expect(JiraRecentIssues.watches(server), "a personal access token needs no user")
    }
}
