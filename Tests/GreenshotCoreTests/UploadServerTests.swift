// SPDX-License-Identifier: GPL-3.0-or-later

import Foundation
import Testing
@testable import GreenshotCore

private extension URLRequest {
    var bodyText: String { String(decoding: httpBody ?? Data(), as: UTF8.self) }
    func query(_ name: String) -> String? {
        URLComponents(url: url!, resolvingAgainstBaseURL: false)?.queryItems?.first { $0.name == name }?.value
    }
}

/// Jira and Confluence on Server / Data Center: logins, REST v2 and the v1 content calls (upstream's Dapplo clients).
struct UploadServerTests {
    private let jiraPAT = AtlassianSite(url: "jira.example.test", login: .serverToken, user: "", secret: "pat-123")!
    private let jiraPassword = AtlassianSite(url: "https://jira.example.test/", login: .serverPassword, user: " alex ", secret: "pw")!
    private let confluenceServer = AtlassianSite(url: "https://wiki.example.test", login: .serverToken, user: "", secret: "pat")!
    private let png = UploadFile(name: "shot.png", data: Data("PNGDATA".utf8), mimeType: "image/png")

    @Test func authorizationPerLogin() {
        let cloud = AtlassianSite(url: "x.atlassian.net", email: "me@x.test", apiToken: "tok")!
        #expect(cloud.login == .cloudAPIToken)
        #expect(cloud.authorizationHeader == "Basic " + Data("me@x.test:tok".utf8).base64EncodedString())
        #expect(jiraPAT.authorizationHeader == "Bearer pat-123")
        #expect(jiraPassword.user == "alex")
        #expect(jiraPassword.authorizationHeader == "Basic " + Data("alex:pw".utf8).base64EncodedString())
        #expect(jiraPassword.baseURL.absoluteString == "https://jira.example.test")
    }

    @Test func credentialsNeedTheUserExceptForATokenOfItsOwn() {
        #expect(jiraPAT.hasCredentials)
        #expect(jiraPassword.hasCredentials)
        #expect(!jiraPassword.with(user: "alex", secret: "").hasCredentials)
        #expect(!jiraPassword.with(user: "", secret: "pw").hasCredentials)
        let cloud = AtlassianSite(url: "x.atlassian.net", email: "", apiToken: "tok")!
        #expect(!cloud.hasCredentials)
    }

    @Test func jiraServerUsesRestV2() async throws {
        let http = StubHTTPClient([
            .init(status: 200, body: #"[{"id":"1","filename":"shot.png"}]"#),
            .init(status: 200, body: #"{"issues":[{"key":"OPS-1","fields":{"summary":"Down"}}]}"#),
            .init(status: 200, body: "[]"),
            .init(status: 200, body: #"{"key":"OPS-1","fields":{"summary":"Down"}}"#),
            .init(status: 201, body: "{}"),
        ])
        let client = JiraClient(site: jiraPAT, http: http)
        _ = try await client.attach(png, to: "OPS-1")
        #expect(http.last.url?.absoluteString == "https://jira.example.test/rest/api/2/issue/OPS-1/attachments")
        #expect(http.last.value(forHTTPHeaderField: "Authorization") == "Bearer pat-123")
        #expect(http.last.value(forHTTPHeaderField: "X-Atlassian-Token") == "no-check")
        let issues = try await client.search("down")
        #expect(issues == [JiraIssue(key: "OPS-1", summary: "Down")])
        #expect(http.last.url?.path == "/rest/api/2/search")
        #expect(http.last.query("jql") == "text ~ \"down\" ORDER BY updated DESC")
        #expect(http.last.query("fields") == JiraClient.listFields)
        _ = try await client.favouriteFilters()
        #expect(http.last.url?.absoluteString == "https://jira.example.test/rest/api/2/filter/favourite")
        _ = try await client.issue("OPS-1")
        #expect(http.last.url?.absoluteString == "https://jira.example.test/rest/api/2/issue/OPS-1?fields=summary")
        try await client.addComment("See \"the\" screenshot", to: "OPS-1")
        #expect(http.last.url?.path == "/rest/api/2/issue/OPS-1/comment")
        #expect(http.last.bodyText == #"{"body":"See \"the\" screenshot"}"#)
    }

    @Test func myselfFollowsTheAPIVersion() {
        let cloud = AtlassianSite(url: "x.atlassian.net", email: "me@x.test", apiToken: "tok")!
        #expect(JiraClient(site: cloud, http: StubHTTPClient([])).myselfRequest().url?.path == "/rest/api/3/myself")
        #expect(JiraClient(site: jiraPassword, http: StubHTTPClient([])).myselfRequest().url?.path == "/rest/api/2/myself")
    }

    @Test func confluenceServerSearchesContentWithTheSpace() async throws {
        let json = #"{"results":[{"id":"42","type":"page","title":"Runbook","space":{"key":"OPS","name":"Operations"},"_links":{"webui":"/display/OPS/Runbook"}}],"_links":{"base":"https://wiki.example.test"}}"#
        let http = StubHTTPClient(body: json)
        let pages = try await ConfluenceClient(site: confluenceServer, http: http).searchPages(title: "Runbook", includePersonalSpaces: false)
        #expect(pages == [ConfluencePage(id: "42", title: "Runbook", spaceName: "Operations", url: URL(string: "https://wiki.example.test/display/OPS/Runbook")!)])
        #expect(http.last.url?.path == "/rest/api/content/search")
        #expect(http.last.query("expand") == "space")
        #expect(http.last.query("cql") == #"type = page AND space.type = global AND title ~ "Runbook" ORDER BY lastmodified DESC"#)
    }

    @Test func personalSpacesStayOutUnlessWanted() {
        #expect(ConfluenceClient.cql(forTitleSearch: "notes", includePersonalSpaces: false)
                == #"type = page AND space.type = global AND title ~ "notes" ORDER BY lastmodified DESC"#)
        // A chosen space wins over the filter.
        #expect(ConfluenceClient.cql(forTitleSearch: "notes", spaceKey: "~alex", includePersonalSpaces: false)
                == #"type = page AND space = "~alex" AND title ~ "notes" ORDER BY lastmodified DESC"#)
        let spaces = [ConfluenceSpace(key: "ENG", name: "Engineering"), ConfluenceSpace(key: "~alex", name: "Alex", isPersonal: true)]
        #expect(ConfluenceClient.filtered(spaces, includePersonal: false).map(\.key) == ["ENG"])
        #expect(ConfluenceClient.filtered(spaces, includePersonal: true).count == 2)
    }

    @Test func spacesKnowTheirHomePageAndKind() throws {
        let v2 = #"{"results":[{"id":"9","key":"ENG","name":"Engineering","type":"global","homepageId":"1001"},{"id":"10","key":"~557058","name":"Alex","type":"personal","homepageId":2002}]}"#
        let fromV2 = try ConfluenceClient.spaces(fromJSON: Data(v2.utf8))
        #expect(fromV2 == [ConfluenceSpace(key: "~557058", name: "Alex", homepageID: "2002", isPersonal: true),
                           ConfluenceSpace(key: "ENG", name: "Engineering", homepageID: "1001")])
        let v1 = #"{"results":[{"key":"OPS","name":"Operations","type":"global","homepage":{"id":"77","title":"Operations Home"}},{"key":"~sam","name":"Sam"}]}"#
        let fromV1 = try ConfluenceClient.spaces(fromJSON: Data(v1.utf8))
        #expect(fromV1 == [ConfluenceSpace(key: "OPS", name: "Operations", homepageID: "77"),
                           ConfluenceSpace(key: "~sam", name: "Sam", isPersonal: true)])
    }

    @Test func serverSpacesComeFromV1WithTheHomePage() async throws {
        let http = StubHTTPClient(body: #"{"results":[]}"#)
        _ = try await ConfluenceClient(site: confluenceServer, http: http).spaces()
        #expect(http.requests.count == 1)
        #expect(http.last.url?.absoluteString == "https://wiki.example.test/rest/api/space?limit=250&expand=homepage")
    }

    @Test func childPagesFromV2OrV1() async throws {
        let cloud = AtlassianSite(url: "yourco.atlassian.net/wiki", email: "me@x.test", apiToken: "t")!
        let v2 = StubHTTPClient(body: #"{"results":[{"id":"5","title":"Zebra","status":"current"},{"id":"4","title":"alpha","status":"current"}],"_links":{}}"#)
        let children = try await ConfluenceClient(site: cloud, http: v2).childPages(of: "1001", spaceName: "Engineering")
        #expect(children.map(\.title) == ["alpha", "Zebra"])
        #expect(children.first?.spaceName == "Engineering")
        #expect(children.first?.url.absoluteString == "https://yourco.atlassian.net/wiki/pages/viewpage.action?pageId=4")
        #expect(v2.last.url?.absoluteString == "https://yourco.atlassian.net/wiki/api/v2/pages/1001/children?limit=250")

        let v1 = StubHTTPClient(body: #"{"results":[{"id":"8","type":"page","title":"Child","_links":{"webui":"/display/OPS/Child"}}],"_links":{"base":"https://wiki.example.test"}}"#)
        let serverChildren = try await ConfluenceClient(site: confluenceServer, http: v1).childPages(of: "77", spaceName: "Operations")
        #expect(serverChildren == [ConfluencePage(id: "8", title: "Child", spaceName: "Operations", url: URL(string: "https://wiki.example.test/display/OPS/Child")!)])
        #expect(v1.last.url?.absoluteString == "https://wiki.example.test/rest/api/content/77/child/page?limit=250")
    }

    @Test func pageByIDFallsBackToV1OnCloud() async throws {
        let cloud = AtlassianSite(url: "yourco.atlassian.net/wiki", email: "me@x.test", apiToken: "t")!
        let http = StubHTTPClient([
            .init(status: 404, body: "{}"),
            .init(status: 200, body: #"{"id":"123","type":"page","title":"Release notes","space":{"key":"DEV","name":"Development"},"_links":{"base":"https://yourco.atlassian.net/wiki","webui":"/spaces/DEV/pages/123"}}"#),
        ])
        let page = try await ConfluenceClient(site: cloud, http: http).page(id: "123")
        #expect(page == ConfluencePage(id: "123", title: "Release notes", spaceName: "Development",
                                       url: URL(string: "https://yourco.atlassian.net/wiki/spaces/DEV/pages/123")!))
        #expect(http.requests.first?.url?.path == "/wiki/api/v2/pages/123")
        #expect(http.last.url?.absoluteString == "https://yourco.atlassian.net/wiki/rest/api/content/123?expand=space")
    }

    @Test func pageBySpaceAndTitle() async throws {
        let http = StubHTTPClient(body: #"{"results":[]}"#)
        let page = try await ConfluenceClient(site: confluenceServer, http: http).page(space: "OPS", title: "Run \"book\"")
        #expect(page == nil)
        #expect(http.last.query("cql") == #"type = page AND space = "OPS" AND title = "Run \"book\"""#)
        #expect(http.last.query("limit") == "1")
    }

    @Test func loginsDecodeToleratingUnknownValues() throws {
        let json = #"{"url":"https://jira.example.test","email":"alex","login":"kerberos"}"#
        let jira = try JSONDecoder().decode(JiraSettings.self, from: Data(json.utf8))
        #expect(jira.login == .cloudAPIToken)
        #expect(jira.url == "https://jira.example.test")
        var settings = AppSettings()
        settings.jira.login = .serverPassword
        settings.confluence.login = .serverToken
        settings.confluence.includePersonalSpaces = true
        let round = try JSONDecoder().decode(AppSettings.self, from: JSONEncoder().encode(settings))
        #expect(round.jira.login == .serverPassword)
        #expect(round.confluence.login == .serverToken)
        #expect(round.confluence.includePersonalSpaces)
    }
}
