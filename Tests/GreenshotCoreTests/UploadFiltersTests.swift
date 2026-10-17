// SPDX-License-Identifier: GPL-3.0-or-later

import Foundation
import Testing
@testable import GreenshotCore

struct UploadFiltersTests {
    private let jira = JiraClient(site: AtlassianSite(url: "yourco.atlassian.net", email: "me@example.com", apiToken: "t")!,
                                  http: StubHTTPClient(body: "[]"))

    @Test func favouriteFilters() async throws {
        let http = StubHTTPClient(body: #"[{"id":"10001","name":"My open issues","jql":"assignee = currentUser() AND resolution = Unresolved"},{"id":"2","name":"Broken"}]"#)
        let client = JiraClient(site: jira.site, http: http)
        let filters = try await client.favouriteFilters()
        #expect(filters == [JiraFilter(id: "10001", name: "My open issues", jql: "assignee = currentUser() AND resolution = Unresolved")])
        #expect(http.last.url?.absoluteString == "https://yourco.atlassian.net/rest/api/3/filter/favourite")
        #expect(throws: UploadError.self) { try JiraClient.filters(fromJSON: Data(#"{"no":"list"}"#.utf8)) }
    }

    @Test func filterSearchUsesItsJQL() async throws {
        let http = StubHTTPClient(body: #"{"issues":[]}"#)
        _ = try await JiraClient(site: jira.site, http: http).search(jql: "project = SHOT")
        let query = URLComponents(url: http.last.url!, resolvingAgainstBaseURL: false)?.queryItems ?? []
        #expect(query.first { $0.name == "jql" }?.value == "project = SHOT")
        #expect(query.first { $0.name == "maxResults" }?.value == "50")
    }

    @Test func issueColumns() throws {
        let json = #"{"issues":[{"key":"SHOT-1","fields":{"summary":"Cut off","issuetype":{"name":"Bug","iconUrl":"https://yourco.atlassian.net/rest/api/2/universal_avatar/view/type/issuetype/avatar/10303?size=medium"},"created":"2026-10-01T12:34:56.789+0200","assignee":{"displayName":"Alex"},"reporter":{"displayName":"Sam"}}}]}"#
        let issue = try #require(try JiraClient.issues(fromJSON: Data(json.utf8)).first)
        #expect(issue.type == "Bug" && issue.assignee == "Alex" && issue.reporter == "Sam")
        #expect(abs((issue.created?.timeIntervalSince1970 ?? 0) - 1_790_850_896.789) < 0.001)
        let icon = JiraClient.pngIconURL(try #require(issue.typeIconURL))
        #expect(icon.absoluteString.hasSuffix("avatar/10303?size=medium&format=png"))
        let other = URL(string: "https://example.org/icon.svg")!
        #expect(JiraClient.pngIconURL(other) == other)
    }

    @Test func issueKeysInWindowTitles() {
        let titles = ["[SHOT-12] Torn edge – Jira", "SHOT-9 and SHOT-12 again", "Unicode UTF-8 notes", "no key here", "abcSHOT-3"]
        #expect(JiraClient.issueKeys(inTitles: titles) == ["SHOT-12", "SHOT-9", "UTF-8"])
        #expect(JiraClient.issueKeys(inTitles: titles, limit: 1) == ["SHOT-12"])
    }

    @Test func pageSearchInOneSpace() {
        #expect(ConfluenceClient.cql(forTitleSearch: "release notes", spaceKey: "ENG")
                == #"type = page AND space = "ENG" AND title ~ "release notes" ORDER BY lastmodified DESC"#)
        #expect(ConfluenceClient.cql(forTitleSearch: "notes", spaceKey: "")
                == #"type = page AND title ~ "notes" ORDER BY lastmodified DESC"#)
        #expect(ConfluenceClient.cql(forTitleSearch: "space = X", spaceKey: "ENG") == "space = X")
    }

    @Test func spacesFromV2AndV1() async throws {
        let site = AtlassianSite(url: "yourco.atlassian.net/wiki", email: "me@example.com", apiToken: "t")!
        let v2 = StubHTTPClient(body: #"{"results":[{"id":"1","key":"HR","name":"People"},{"id":"2","key":"ENG","name":"Engineering"},{"name":"no key"}]}"#)
        #expect(try await ConfluenceClient(site: site, http: v2).spaces()
                == [ConfluenceSpace(key: "ENG", name: "Engineering"), ConfluenceSpace(key: "HR", name: "People")])
        #expect(v2.last.url?.absoluteString == "https://yourco.atlassian.net/wiki/api/v2/spaces?limit=250")
        let v1 = StubHTTPClient([.init(status: 404, body: "{}"), .init(status: 200, body: #"{"results":[{"key":"OPS","name":"Operations"}]}"#)])
        #expect(try await ConfluenceClient(site: site, http: v1).spaces() == [ConfluenceSpace(key: "OPS", name: "Operations")])
        #expect(v1.last.url?.absoluteString == "https://yourco.atlassian.net/wiki/rest/api/space?limit=250")
    }

    @Test func confluenceSettingsBeforeTheSpaceStillLoad() throws {
        let json = #"{"url":"https://yourco.atlassian.net/wiki","email":"me@example.com","uploadFormat":"jpg","jpegQuality":70,"openPageAfterUpload":false,"clipboardContent":"imageLink","recentPages":[]}"#
        let settings = try JSONDecoder().decode(ConfluenceSettings.self, from: Data(json.utf8))
        #expect(settings.url == "https://yourco.atlassian.net/wiki" && settings.uploadFormat == .jpg && settings.jpegQuality == 70)
        #expect(!settings.openPageAfterUpload && settings.clipboardContent == .imageLink)
        #expect(settings.searchSpaceKey == "" && !settings.reduceColors)
    }
}
