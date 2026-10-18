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

    // SL1: only keys of the Jira's projects (upstream `JiraMonitor._projectJiraClientMap`).

    @Test func onlyKeysOfTheJirasProjects() {
        var recent = JiraRecentIssues()
        recent.observe([(id: 1, title: "SHOT-1 page"), (id: 2, title: "CVE-2026-1234 advisory"), (id: 3, title: "UTF-8")], at: at(0))
        #expect(recent.keys.count == 3, "unchecked until the projects are known")
        recent.setProjects(["shot", "DOC"])
        #expect(recent.keys == ["SHOT-1"])
        recent.observe([(id: 4, title: "OTHER-9 and DOC-2")], at: at(2))
        #expect(recent.keys == ["DOC-2", "SHOT-1"])
        #expect(recent.merged(onScreen: ["CVE-2026-1", "SHOT-5"], uploadedTo: ["OLD-3", "DOC-1"]) == ["DOC-2", "SHOT-1", "SHOT-5", "DOC-1"])
        #expect(recent.isAllowed("SHOT-77"))
        #expect(!recent.isAllowed("CVE-2026-1234"))
        recent.setProjects(nil)
        #expect(recent.isAllowed("CVE-2026-1234"), "another account: unchecked again until read")
    }

    @Test func projectOfAKey() {
        #expect(JiraRecentIssues.belongs("ABC-12", to: ["ABC"]))
        #expect(JiraRecentIssues.belongs("abc-12", to: ["ABC"]))
        #expect(!JiraRecentIssues.belongs("ABCD-12", to: ["ABC"]))
        #expect(!JiraRecentIssues.belongs("ABC", to: ["ABC"]))
    }

    @Test func projectsRequestPerKindOfSite() throws {
        let cloud = JiraClient(site: AtlassianSite(url: "https://x.atlassian.net", email: "me@x.test", apiToken: "t")!,
                               http: StubHTTPClient(body: "[]"))
        let page = try #require(cloud.projectsRequest(startAt: 100).url?.absoluteString)
        #expect(page.hasPrefix("https://x.atlassian.net/rest/api/3/project/search?"))
        #expect(page.contains("startAt=100"))
        #expect(page.contains("maxResults=100"))
        let server = JiraClient(site: AtlassianSite(url: "https://jira.x.test", login: .serverToken, user: "", secret: "t")!,
                                http: StubHTTPClient(body: "[]"))
        let list = try #require(server.projectsRequest().url?.absoluteString)
        #expect(list == "https://jira.x.test/rest/api/2/project")
    }

    @Test func projectAnswersParse() throws {
        let list = try JiraClient.projectKeys(fromJSON: Data(#"[{"key":"ABC","name":"A"},{"key":"doc"}]"#.utf8))
        #expect(list.keys == ["ABC", "DOC"])
        #expect(list.isLast)
        let first = try JiraClient.projectKeys(fromJSON: Data(#"{"startAt":0,"total":3,"isLast":false,"values":[{"key":"A"},{"key":"B"}]}"#.utf8))
        #expect(first.keys == ["A", "B"])
        #expect(!first.isLast)
        let noFlag = try JiraClient.projectKeys(fromJSON: Data(#"{"startAt":2,"total":3,"values":[{"key":"C"}]}"#.utf8))
        #expect(noFlag.isLast)
        #expect(throws: (any Error).self) { try JiraClient.projectKeys(fromJSON: Data(#"{"errorMessages":["no"]}"#.utf8)) }
    }

    @Test func allProjectPagesAreRead() async throws {
        let http = StubHTTPClient([
            .init(status: 200, body: #"{"startAt":0,"total":3,"isLast":false,"values":[{"key":"A"},{"key":"B"}]}"#),
            .init(status: 200, body: #"{"startAt":2,"total":3,"isLast":true,"values":[{"key":"C"}]}"#),
        ])
        let client = JiraClient(site: AtlassianSite(url: "https://x.atlassian.net", email: "me@x.test", apiToken: "t")!, http: http)
        let keys = try await client.projectKeys()
        #expect(keys == ["A", "B", "C"])
        #expect(http.requests.count == 2)
        let second = try #require(http.requests.last?.url?.absoluteString)
        #expect(second.contains("startAt=2"))
    }
}

