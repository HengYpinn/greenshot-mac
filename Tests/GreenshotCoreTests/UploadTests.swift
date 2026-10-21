// SPDX-License-Identifier: GPL-3.0-or-later

import CryptoKit
import Foundation
import os
import Testing
@testable import GreenshotCore

/// Answers queued responses and records every request.
final class StubHTTPClient: HTTPClient, @unchecked Sendable {
    struct Response {
        var status: Int
        var body: String
    }

    private let lock = NSLock()
    private var queue: [Response]
    private(set) var requests: [URLRequest] = []

    init(_ responses: [Response]) {
        queue = responses
    }

    convenience init(status: Int = 200, body: String) {
        self.init([Response(status: status, body: body)])
    }

    func data(for request: URLRequest) async throws -> (Data, URLResponse) {
        let next: Response = try lock.withLock {
            requests.append(request)
            guard !queue.isEmpty else { throw UploadError.unexpectedResponse("no stubbed answer for \(request.url!)") }
            return queue.removeFirst()
        }
        let response = HTTPURLResponse(url: request.url!, statusCode: next.status, httpVersion: nil, headerFields: nil)!
        return (Data(next.body.utf8), response)
    }

    var last: URLRequest { requests.last! }
}

private extension URLRequest {
    var bodyText: String { String(decoding: httpBody ?? Data(), as: UTF8.self) }
    func query(_ name: String) -> String? {
        URLComponents(url: url!, resolvingAgainstBaseURL: false)?.queryItems?.first { $0.name == name }?.value
    }
}

/// A Jira or Confluence search that takes only the text (or title) search: any other query is "not JQL" (HTTP 400).
struct TextOnlySearchServer: HTTPClient {
    let answer: String
    let isText: @Sendable (String) -> Bool
    private let sent = OSAllocatedUnfairLock<[String]>(initialState: [])

    init(answer: String, isText: @escaping @Sendable (String) -> Bool) {
        self.answer = answer
        self.isText = isText
    }

    /// The `jql` or `cql` of every request, in order.
    var queries: [String] { sent.withLock { $0 } }

    func data(for request: URLRequest) async throws -> (Data, URLResponse) {
        let items = URLComponents(url: request.url!, resolvingAgainstBaseURL: false)?.queryItems ?? []
        let query = items.first { $0.name == "jql" || $0.name == "cql" }?.value ?? ""
        sent.withLock { $0.append(query) }
        let accepted = isText(query)
        let body = accepted ? answer : #"{"errorMessages":["Error in the JQL Query"]}"#
        let response = HTTPURLResponse(url: request.url!, statusCode: accepted ? 200 : 400, httpVersion: nil, headerFields: nil)!
        return (Data(body.utf8), response)
    }
}

// ASCII bytes, so the multipart bodies can be compared as text.
private let png = UploadFile(name: "shot.png", data: Data("PNGDATA".utf8), mimeType: "image/png")

struct UploadSupportTests {
    @Test func fileNamesGetTheFormatsExtension() {
        #expect(UploadFile.fileName("shot", format: .png) == "shot.png")
        #expect(UploadFile.fileName("shot.png", format: .jpg) == "shot.jpg")
        #expect(UploadFile.fileName("shot.jpeg", format: .jpg) == "shot.jpeg")
        #expect(UploadFile.fileName("v1.2 notes", format: .png) == "v1.2 notes.png")
        #expect(UploadFile.fileName("  ", format: .png) == "Screenshot.png")
    }

    @Test func multipartBodyHasFieldsAndFile() {
        var form = MultipartForm(boundary: "B")
        form.addField("minorEdit", value: "true")
        form.addFile("file", file: png)
        let body = String(decoding: form.finished(), as: UTF8.self)
        #expect(form.contentType == "multipart/form-data; boundary=B")
        #expect(body.hasPrefix("--B\r\nContent-Disposition: form-data; name=\"minorEdit\"\r\n\r\ntrue\r\n--B\r\n"))
        #expect(body.contains("Content-Disposition: form-data; name=\"file\"; filename=\"shot.png\"\r\nContent-Type: image/png\r\n\r\nPNGDATA\r\n"))
        #expect(body.hasSuffix("--B--\r\n"))
    }

    @Test func serverErrorsAreReadable() async {
        let http = StubHTTPClient(status: 404, body: #"{"errorMessages":["Issue does not exist or you do not have permission to see it."],"errors":{}}"#)
        await #expect(throws: UploadError.http(status: 404, message: "Issue does not exist or you do not have permission to see it.")) {
            _ = try await HTTPSupport.send(URLRequest(url: URL(string: "https://x.test/")!), with: http)
        }
        #expect(HTTPSupport.errorMessage(in: Data(#"{"error":"invalid_grant","error_description":"Refresh token has expired"}"#.utf8), status: 400) == "Refresh token has expired")
        #expect(HTTPSupport.errorMessage(in: Data("<html>gateway</html>".utf8), status: 502) == HTTPURLResponse.localizedString(forStatusCode: 502))
        #expect(UploadError.http(status: 401, message: "Unauthorized").errorDescription == "HTTP 401: Unauthorized")
    }

    @Test func asciiJSONEscapesNonASCII() {
        let text = HTTPSupport.asciiJSON(["path": "/Ärger \"q\" ✓.png", "mute": true, "n": 2, "parent": ["id": "0"]])
        #expect(text == #"{"mute":true,"n":2,"parent":{"id":"0"},"path":"/\u00c4rger \"q\" \u2713.png"}"#)
    }

    @Test func formBodyPercentEncodes() {
        let body = String(decoding: HTTPSupport.formBody([("grant_type", "authorization_code"), ("redirect_uri", "http://127.0.0.1:1/x y")]), as: UTF8.self)
        #expect(body == "grant_type=authorization_code&redirect_uri=http%3A%2F%2F127.0.0.1%3A1%2Fx%20y")
    }

    @Test func settingsWithoutUploadKeysGetDefaults() throws {
        let decoded = try JSONDecoder().decode(AppSettings.self, from: Data(#"{"outputFolder": "~/Desktop"}"#.utf8))
        #expect(decoded.jira == JiraSettings() && decoded.confluence == ConfluenceSettings())
        #expect(decoded.box.folderID == "0" && decoded.dropbox.copyLinkToClipboard)
        var s = AppSettings()
        s.destinations = [.jira, .dropbox]
        s.jira.url = "https://a.atlassian.net"
        s.jira.remember(issueKey: "A-1")
        s.jira.remember(issueKey: "A-2")
        s.jira.remember(issueKey: "A-1")
        let round = try JSONDecoder().decode(AppSettings.self, from: JSONEncoder().encode(s))
        #expect(round.destinations == [.jira, .dropbox] && round.jira.recentIssueKeys == ["A-1", "A-2"])
        for i in 0..<15 { s.jira.remember(issueKey: "B-\(i)") }
        #expect(s.jira.recentIssueKeys.count == JiraSettings.maxRecentIssueKeys)
    }

    @Test func inMemorySecretStore() throws {
        let store = InMemorySecretStore()
        try store.setSecret("t", for: "jira.apiToken")
        #expect(try store.secret(for: "jira.apiToken") == "t")
        try store.setSecret(nil, for: "jira.apiToken")
        #expect(try store.secret(for: "jira.apiToken") == nil)
    }
}

struct JiraClientTests {
    let site = AtlassianSite(url: " yourco.atlassian.net/ ", email: "me@x.test", apiToken: "tok")!

    @Test func siteNormalizesTheURL() {
        #expect(site.baseURL.absoluteString == "https://yourco.atlassian.net")
        #expect(AtlassianSite(url: "", email: "", apiToken: "") == nil)
        #expect(AtlassianSite(url: "https://x.test/wiki/", email: "", apiToken: "")?.baseURL.absoluteString == "https://x.test/wiki")
        #expect(site.authorizationHeader == "Basic " + Data("me@x.test:tok".utf8).base64EncodedString())
    }

    @Test func issueKeysAndSearchText() {
        #expect(JiraClient.isIssueKey("proj-12") && JiraClient.isIssueKey("AB_C1-7") && !JiraClient.isIssueKey("12") && !JiraClient.isIssueKey("login bug"))
        #expect(JiraClient.jql(forSearch: "proj-12") == "key = PROJ-12")
        #expect(JiraClient.jql(forSearch: "login \"bug\"") == "text ~ \"login \\\"bug\\\"\" ORDER BY updated DESC")
        #expect(JiraClient.jql(forSearch: "assignee = currentUser()") == "assignee = currentUser()")
        #expect(JiraClient.jql(forSearch: "project = X order by created") == "project = X order by created")
    }

    /// Words without an operator after the first word are a text search right away.
    @Test func plainWordsAreATextSearch() {
        func text(_ words: String) -> String { "text ~ \"\(words)\" ORDER BY updated DESC" }
        for words in ["project kickoff", "Project plan", "project in progress", "Status: in progress", "login (beta)",
                      "Berlin (office)", "Domain (DNS) setup", "plugin(v2)", "admin (panel) notes", "Thesis null",
                      "notin (a)", "C++ tips"] {
            #expect(JiraClient.jql(forSearch: words) == text(words), "\(words)")
        }
    }

    /// JQL is used as it is: "=" or "~" anywhere, ORDER BY, or a field (any word, a quoted name, cf[123]) followed by
    /// an operator, a list or a function, also of custom fields and with WAS and CHANGED.
    @Test func jqlIsUsedAsItIs() {
        let queries = [
            "project in (A, B)", "summary ~ login", "status != Done", "assignee is EMPTY", "\"Epic Link\" = PROJ-1",
            "cf[10010]=3", "cf[10010] > 3", "(priority = High OR priority = Highest)", "order by created DESC",
            "ORDER BY rank", "Order By created DESC", "status not in (Done, Closed)", "created > -1w", "duedate<=now()",
            "\"Story Points\" > 3", "Team IS EMPTY", "Team IN (Blue)", "a=b", "status IN (Done)", "NOT status in (Done)",
            "not project = X", "NOT (project = X)",
            // Functions, history and custom fields (the review's list).
            "sprint in openSprints() AND assignee = currentUser()", "fixVersion in unreleasedVersions() and project = ABC",
            "assignee in membersOf(\"jira-devs\") AND status = Open", "issue in watchedIssues() and resolution = Unresolved",
            "status was Open and project = X", "status changed to Done after -1w and project = X",
            "issueFunction in linkedIssuesOf(\"project = X\")", "votes > 5 AND project = X", "workratio > 100 and project = X",
            "timespent > 4h AND assignee = bob", "originalEstimate > 2d and project = X",
            "worklogDate >= startOfWeek() and worklogAuthor = bob", "team in (Blue) AND status = Done",
            "statusCategoryChangedDate > -2d and project = X", "issueLinkType in (blocks) and project = X",
            "sprint in openSprints()", "votes > 5", "team in (Blue)", "status was Open", "status changed",
            "assignee was not in (bob, alex)", "order by updated",
        ]
        for jql in queries {
            #expect(JiraClient.jql(forSearch: jql) == jql, "\(jql)")
        }
    }

    /// Words that look like JQL are searched as words when Jira refuses the query (HTTP 400): one more request, never a
    /// failed search.
    @Test func wordsThatLookLikeJQLFallBackToATextSearch() async throws {
        let words = [
            "This is empty", "a<b", "x > y", "Meeting in (Berlin)", "Tuesday was in (x)", "order by phone",
            "reports sorted order by date", "error: x=1 failed", "how to use ~ in a path", "Comment <br> tag",
            "Description > 255 characters", "Summary <b> missing", "Parent > Child", "Sprint > 2 weeks", "Due < Friday",
            "Level > 9000", "Issue <-> link", "Title in (draft)", "Space in (office)", "Status is empty", "Text in (quotes)",
            "Type is null", "MEETING IN (BERLIN)", "THIS IS EMPTY", "ORDER BY PHONE", "Key = value pairs", "E=mc2", "x = y",
            "a~b", "url=https://x", "Labels is empty", "Epic > story", "Login fails with status = 500", "status = 500 error",
            "project kickoff", "login (beta)", "Thesis null",
        ]
        for text in words {
            let server = TextOnlySearchServer(answer: #"{"issues":[{"key":"PROJ-7","fields":{"summary":"Found"}}]}"#) {
                $0.hasPrefix("text ~ ")
            }
            let issues = try await JiraClient(site: site, http: server).search(text)
            #expect(issues.map(\.key) == ["PROJ-7"], "\(text)")
            let sent = server.queries
            #expect(sent.last == "text ~ \"\(JiraClient.escaped(text))\" ORDER BY updated DESC", "\(text)")
            #expect(sent.count <= 2, "\(text)")
        }
    }

    /// A query with a mistake ("project = ABCD") whose words find nothing either keeps Jira's message, which says what
    /// is wrong; words that find something give those issues.
    @Test func aRefusedQueryWhoseWordsFindNothingKeepsJirasMessage() async throws {
        let refused = #"{"errorMessages":["The value 'ABCD' does not exist for the field 'project'."]}"#
        let nothing = StubHTTPClient([.init(status: 400, body: refused), .init(status: 200, body: #"{"issues":[]}"#)])
        await #expect(throws: UploadError.http(status: 400, message: "The value 'ABCD' does not exist for the field 'project'.")) {
            _ = try await JiraClient(site: site, http: nothing).search("project = ABCD")
        }
        #expect(nothing.requests.count == 2)
        let found = StubHTTPClient([.init(status: 400, body: refused),
                                    .init(status: 200, body: #"{"issues":[{"key":"PROJ-7","fields":{"summary":"Found"}}]}"#)])
        let issues = try await JiraClient(site: site, http: found).search("project = ABCD")
        #expect(issues.map(\.key) == ["PROJ-7"])
    }

    /// Only a refused query (HTTP 400) is tried again as words: not a login problem, a server or network error, a query
    /// that works, or a text search.
    @Test func otherAnswersAreNotRetriedAsWords() async throws {
        for status in [401, 403, 500, 503] {
            let http = StubHTTPClient(status: status, body: "{}")
            await #expect(throws: UploadError.self) { _ = try await JiraClient(site: site, http: http).search("votes > 5") }
            #expect(http.requests.count == 1, "HTTP \(status)")
        }
        let offline = StubHTTPClient([])
        await #expect(throws: UploadError.self) { _ = try await JiraClient(site: site, http: offline).search("votes > 5") }
        #expect(offline.requests.count == 1)
        let works = StubHTTPClient(status: 200, body: #"{"issues":[]}"#)
        _ = try await JiraClient(site: site, http: works).search("votes > 5")
        #expect(works.requests.count == 1)
        #expect(works.last.query("jql") == "votes > 5")
        let refusedText = StubHTTPClient([.init(status: 400, body: "{}"), .init(status: 200, body: #"{"issues":[]}"#)])
        await #expect(throws: UploadError.self) { _ = try await JiraClient(site: site, http: refusedText).search("project kickoff") }
        #expect(refusedText.requests.count == 1)
        // A key that doesn't exist: Jira's answer says so, a text search would hide it.
        let missingKey = StubHTTPClient([.init(status: 400, body: #"{"errorMessages":["An issue with key 'PROJ-99' does not exist"]}"#),
                                         .init(status: 200, body: #"{"issues":[]}"#)])
        await #expect(throws: UploadError.self) { _ = try await JiraClient(site: site, http: missingKey).search("proj-99") }
        #expect(missingKey.requests.count == 1)
    }

    /// The check reads the text once: a long run of "not" (which took seconds with a pattern before) is instant.
    @Test func longTextIsCheckedQuickly() {
        let elapsed = ContinuousClock().measure {
            #expect(!JiraClient.isQuery(String(repeating: "not   ", count: 16) + "!"))
            #expect(!JiraClient.isQuery(String(repeating: "(", count: 10_000) + "x"))
            #expect(!JiraClient.isQuery(String(repeating: "word ", count: 10_000)))
        }
        #expect(elapsed < .milliseconds(500))
    }

    /// A "+" goes as "%2B": servers read a plain "+" in a query as a space, so "C++" would be searched as "C  ".
    @Test func aPlusInTheSearchStaysAPlus() throws {
        let request = JiraClient(site: site, http: StubHTTPClient([])).searchRequest(jql: JiraClient.jql(forSearch: "C++ a+b"))
        let query = try #require(request.url?.query)
        #expect(query.contains("C%2B%2B%20a%2Bb"))
        #expect(!query.contains("+"))
        #expect(request.query("jql") == "text ~ \"C++ a+b\" ORDER BY updated DESC")
        let confluence = ConfluenceClient(site: site, http: StubHTTPClient([])).searchRequest(cql: "title ~ \"Q3+Q4\"")
        let cql = try #require(confluence.url?.query)
        #expect(cql.contains("Q3%2BQ4") && !cql.contains("+"))
        let link = URL(string: "https://x.test/wiki/pages/viewpage.action")!.appending(queryItem: "title", value: "a+b c")
        #expect(link.absoluteString == "https://x.test/wiki/pages/viewpage.action?title=a%2Bb%20c")
    }

    @Test func attachesThroughTheRestAPI() async throws {
        let http = StubHTTPClient(status: 200, body: #"[{"id": 10001, "filename": "shot.png", "content": "https://yourco.atlassian.net/rest/api/3/attachment/content/10001"}]"#)
        let client = JiraClient(site: site, http: http)
        let attachments = try await client.attach(png, to: "PROJ-7")
        #expect(attachments == [JiraAttachment(id: "10001", filename: "shot.png", contentURL: URL(string: "https://yourco.atlassian.net/rest/api/3/attachment/content/10001"))])
        let request = http.last
        #expect(request.url?.absoluteString == "https://yourco.atlassian.net/rest/api/3/issue/PROJ-7/attachments")
        #expect(request.httpMethod == "POST")
        #expect(request.value(forHTTPHeaderField: "X-Atlassian-Token") == "no-check")
        #expect(request.value(forHTTPHeaderField: "Authorization") == site.authorizationHeader)
        #expect(request.value(forHTTPHeaderField: "Content-Type")?.hasPrefix("multipart/form-data; boundary=") == true)
        #expect(request.bodyText.contains("name=\"file\"; filename=\"shot.png\"\r\nContent-Type: image/png\r\n\r\nPNGDATA\r\n"))
        #expect(client.browseURL(for: "PROJ-7").absoluteString == "https://yourco.atlassian.net/browse/PROJ-7")
    }

    @Test func fixedBoundaryGivesAnExactBody() {
        let request = JiraClient(site: site, http: StubHTTPClient([])).attachRequest(issueKey: "A-1", file: png, boundary: "B")
        #expect(request.bodyText == "--B\r\nContent-Disposition: form-data; name=\"file\"; filename=\"shot.png\"\r\nContent-Type: image/png\r\n\r\nPNGDATA\r\n--B--\r\n")
    }

    @Test func searchesWithJQL() async throws {
        let http = StubHTTPClient(status: 200, body: #"{"issues":[{"id":"1","key":"PROJ-7","fields":{"summary":"Login fails"}},{"key":"PROJ-8","fields":{}}],"isLast":true}"#)
        let issues = try await JiraClient(site: site, http: http).search("login")
        #expect(issues == [JiraIssue(key: "PROJ-7", summary: "Login fails"), JiraIssue(key: "PROJ-8", summary: "")])
        let request = http.last
        #expect(request.url?.path == "/rest/api/3/search/jql")
        #expect(request.query("jql") == "text ~ \"login\" ORDER BY updated DESC")
        #expect(request.query("maxResults") == "20" && request.query("fields") == "summary,issuetype,created,assignee,reporter")
        #expect(request.value(forHTTPHeaderField: "Accept") == "application/json")
    }

    @Test func issueLookupAndComment() async throws {
        let http = StubHTTPClient([.init(status: 200, body: #"{"key":"PROJ-7","fields":{"summary":"Login fails"}}"#), .init(status: 201, body: "{}")])
        let client = JiraClient(site: site, http: http)
        #expect(try await client.issue("PROJ-7") == JiraIssue(key: "PROJ-7", summary: "Login fails"))
        #expect(http.last.url?.absoluteString == "https://yourco.atlassian.net/rest/api/3/issue/PROJ-7?fields=summary")
        try await client.addComment("See the screenshot", to: "PROJ-7")
        #expect(http.last.url?.path == "/rest/api/3/issue/PROJ-7/comment")
        #expect(http.last.bodyText == #"{"body":{"content":[{"content":[{"text":"See the screenshot","type":"text"}],"type":"paragraph"}],"type":"doc","version":1}}"#)
    }

    /// The file is on the issue when only the comment fails (no permission to comment): the comment's error comes
    /// back instead of failing the upload, so trying again doesn't attach the file twice.
    @Test func aFailedCommentKeepsTheAttachment() async throws {
        let http = StubHTTPClient([.init(status: 200, body: #"[{"id": "10001", "filename": "shot.png"}]"#),
                                   .init(status: 403, body: #"{"errorMessages":["No permission to comment."]}"#)])
        let result = try await JiraClient(site: site, http: http).attach(png, to: "PROJ-7", comment: "See the screenshot")
        #expect(result.attachments.map(\.id) == ["10001"])
        let error = try #require(result.commentError as? UploadError)
        #expect(error == .http(status: 403, message: "No permission to comment."))
        #expect(http.requests.count == 2)
    }

    @Test func noCommentNoCommentRequest() async throws {
        let http = StubHTTPClient(status: 200, body: #"[{"id": "10001", "filename": "shot.png"}]"#)
        let result = try await JiraClient(site: site, http: http).attach(png, to: "PROJ-7", comment: "")
        #expect(result.attachments.count == 1 && result.commentError == nil)
        #expect(http.requests.count == 1)
    }

    /// A failed attachment fails the upload, and no comment is sent.
    @Test func aFailedAttachmentSendsNoComment() async {
        let http = StubHTTPClient([.init(status: 401, body: "{}"), .init(status: 201, body: "{}")])
        await #expect(throws: UploadError.self) {
            _ = try await JiraClient(site: site, http: http).attach(png, to: "PROJ-7", comment: "See the screenshot")
        }
        #expect(http.requests.count == 1)
    }

    @Test func serverErrorsSurface() async {
        let http = StubHTTPClient(status: 401, body: #"{"errorMessages":[],"errors":{}}"#)
        await #expect(throws: UploadError.http(status: 401, message: HTTPURLResponse.localizedString(forStatusCode: 401))) {
            _ = try await JiraClient(site: site, http: http).attach(png, to: "PROJ-7")
        }
        #expect(throws: UploadError.self) { try JiraClient.attachments(fromJSON: Data("{}".utf8)) }
    }
}

/// The password logins checked once per session.
struct VerifiedLoginsTests {
    let site = AtlassianSite(url: "https://jira.example.test", login: .serverPassword, user: "alex", secret: "old")!

    /// A password changed in Settings is checked again before the next upload.
    @Test func anotherPasswordIsCheckedAgain() {
        var verified = VerifiedLogins()
        verified.insert(site, service: "Jira")
        #expect(verified.contains(site, service: "Jira"))
        #expect(!verified.contains(site.with(user: "alex", secret: "new"), service: "Jira"))
        #expect(!verified.contains(site.with(user: "sam", secret: "old"), service: "Jira"))
        #expect(!verified.contains(site, service: "Confluence"))
    }

    /// An upload the server refuses (the password changed on the server) brings the login dialog back next time.
    @Test func aRefusedUploadForgetsTheLogin() {
        var verified = VerifiedLogins()
        verified.insert(site, service: "Jira")
        verified.uploadFailed(UploadError.http(status: 404, message: "No issue"), site: site, service: "Jira")
        #expect(verified.contains(site, service: "Jira"))
        verified.uploadFailed(UploadError.http(status: 401, message: ""), site: site, service: "Jira")
        #expect(!verified.contains(site, service: "Jira"))
        verified.insert(site, service: "Jira")
        verified.uploadFailed(UploadError.http(status: 403, message: ""), site: site, service: "Jira")
        #expect(!verified.contains(site, service: "Jira"))
    }
}

struct ConfluenceClientTests {
    let site = AtlassianSite(url: "https://yourco.atlassian.net/wiki", email: "me@x.test", apiToken: "tok")!

    @Test func titleSearchCQL() {
        #expect(ConfluenceClient.cql(forTitleSearch: "Release \"notes\"") == "type = page AND title ~ \"Release \\\"notes\\\"\" ORDER BY lastmodified DESC")
        #expect(ConfluenceClient.cql(forTitleSearch: "space = DEV and type = page") == "space = DEV and type = page")
        #expect(ConfluenceClient.cql(forTitleSearch: "Berlin (office)") == "type = page AND title ~ \"Berlin (office)\" ORDER BY lastmodified DESC")
        #expect(ConfluenceClient.cql(forTitleSearch: "label in (howto, faq)") == "label in (howto, faq)")
        #expect(ConfluenceClient.cql(forTitleSearch: "id in recentlyViewedContent(10) and type = page")
                == "id in recentlyViewedContent(10) and type = page")
    }

    /// A query with a mistake whose title search finds nothing either keeps Confluence's message; a title search that
    /// finds pages gives those.
    @Test func aRefusedQueryWhoseTitleFindsNothingKeepsConfluencesMessage() async throws {
        let refused = #"{"message":"Could not parse cql"}"#
        let nothing = StubHTTPClient([.init(status: 400, body: refused), .init(status: 200, body: #"{"results":[]}"#)])
        await #expect(throws: UploadError.http(status: 400, message: "Could not parse cql")) {
            _ = try await ConfluenceClient(site: site, http: nothing).searchPages(title: "space = NOPE")
        }
        #expect(nothing.requests.count == 2)
        let found = StubHTTPClient([.init(status: 400, body: refused),
                                    .init(status: 200, body: #"{"results":[{"content":{"id":"1","type":"page","title":"Found"}}]}"#)])
        let pages = try await ConfluenceClient(site: site, http: found).searchPages(title: "space = NOPE")
        #expect(pages.map(\.title) == ["Found"])
    }

    /// Only a refused query (HTTP 400) is tried again as a title search.
    @Test func otherAnswersAreNotRetriedAsATitleSearch() async {
        for status in [401, 403, 500] {
            let http = StubHTTPClient(status: status, body: "{}")
            await #expect(throws: UploadError.self) { _ = try await ConfluenceClient(site: site, http: http).searchPages(title: "Space > Page") }
            #expect(http.requests.count == 1, "HTTP \(status)")
        }
        let refusedTitle = StubHTTPClient([.init(status: 400, body: "{}"), .init(status: 200, body: #"{"results":[]}"#)])
        await #expect(throws: UploadError.self) { _ = try await ConfluenceClient(site: site, http: refusedTitle).searchPages(title: "Berlin (office)") }
        #expect(refusedTitle.requests.count == 1)
    }

    /// A title that looks like CQL is searched as a title when Confluence refuses the query (HTTP 400).
    @Test func titlesThatLookLikeCQLFallBackToATitleSearch() async throws {
        for title in ["Space > Page", "Content > Guidelines", "Plan: cost = time", "Title in (draft)", "Status is empty", "Berlin (office)"] {
            let server = TextOnlySearchServer(answer: #"{"results":[{"content":{"id":"1","type":"page","title":"Found"}}]}"#) {
                $0.hasPrefix("type = page AND ")
            }
            let pages = try await ConfluenceClient(site: site, http: server).searchPages(title: title, spaceKey: "ENG")
            #expect(pages.map(\.title) == ["Found"], "\(title)")
            let sent = server.queries
            #expect(sent.last == "type = page AND space = \"ENG\" AND title ~ \"\(title)\" ORDER BY lastmodified DESC", "\(title)")
            #expect(sent.count <= 2, "\(title)")
        }
    }

    @Test func findsPagesByTitle() async throws {
        let json = """
        {"results":[
          {"content":{"id":"123","type":"page","title":"Release notes","_links":{"webui":"/spaces/DEV/pages/123/Release+notes"}},
           "resultGlobalContainer":{"title":"Development"}},
          {"content":{"id":"9","type":"attachment","title":"x.png"}},
          {"content":{"id":"124","type":"page","title":"Plan","_links":{"webui":"https://other.test/p/124"}}}
        ],"_links":{"base":"https://yourco.atlassian.net/wiki"}}
        """
        let http = StubHTTPClient(status: 200, body: json)
        let pages = try await ConfluenceClient(site: site, http: http).searchPages(title: "Release")
        #expect(pages == [
            ConfluencePage(id: "123", title: "Release notes", spaceName: "Development", url: URL(string: "https://yourco.atlassian.net/wiki/spaces/DEV/pages/123/Release+notes")!),
            ConfluencePage(id: "124", title: "Plan", spaceName: "", url: URL(string: "https://other.test/p/124")!),
        ])
        #expect(http.last.url?.path == "/wiki/rest/api/search")
        #expect(http.last.query("cql") == "type = page AND title ~ \"Release\" ORDER BY lastmodified DESC")
        #expect(http.last.query("limit") == "20")
    }

    @Test func attachesToAPage() async throws {
        let json = #"{"results":[{"id":"att55","type":"attachment","title":"shot.png","_links":{"download":"/download/attachments/123/shot.png?version=1","webui":"/pages/viewpageattachments.action?pageId=123"}}],"_links":{"base":"https://yourco.atlassian.net/wiki"}}"#
        let http = StubHTTPClient(status: 200, body: json)
        let client = ConfluenceClient(site: site, http: http)
        let attachments = try await client.attach(png, toPage: "123", comment: "from Greenshot")
        #expect(attachments == [ConfluenceAttachment(id: "att55", title: "shot.png", downloadURL: URL(string: "https://yourco.atlassian.net/wiki/download/attachments/123/shot.png?version=1"))])
        let request = http.last
        #expect(request.url?.absoluteString == "https://yourco.atlassian.net/wiki/rest/api/content/123/child/attachment")
        #expect(request.httpMethod == "POST" && request.value(forHTTPHeaderField: "X-Atlassian-Token") == "nocheck")
        #expect(request.value(forHTTPHeaderField: "Authorization") == site.authorizationHeader)
        let body = request.bodyText
        #expect(body.contains("name=\"file\"; filename=\"shot.png\"") && body.contains("name=\"minorEdit\"\r\n\r\ntrue"))
        #expect(body.contains("name=\"comment\"\r\nContent-Type: text/plain; charset=utf-8\r\n\r\nfrom Greenshot"))
        #expect(ConfluenceClient.wikiMarkup(for: "shot.png") == "!shot.png!")
    }
}

/// Answers the sign-in page with a callback carrying the code and the state the URL asked for.
struct StubAuthorizer: OAuthAuthorizer {
    var code = "the-code"
    var port: UInt16? = nil
    var deny = false
    let seen = Seen()

    final class Seen: @unchecked Sendable {
        var url: URL?
    }

    func authorize(url: URL, redirect: OAuthRedirect) async throws -> URL {
        seen.url = url
        let state = URLComponents(url: url, resolvingAgainstBaseURL: false)!.queryItems!.first { $0.name == "state" }!.value!
        var callback = URLComponents(url: port.map(redirect.onPort)?.url ?? redirect.url, resolvingAgainstBaseURL: false)!
        // A provider returns the state with an error too (RFC 6749 4.1.2.1)
        callback.queryItems = deny ? [URLQueryItem(name: "error", value: "access_denied"), URLQueryItem(name: "state", value: state)]
            : [URLQueryItem(name: "code", value: code), URLQueryItem(name: "state", value: state)]
        return callback.url!
    }
}

struct OAuthTests {
    let now = Date(timeIntervalSince1970: 1_800_000_000)

    @Test func pkceMatchesTheRFCVector() {
        #expect(PKCE.challenge(for: "dBjftJeZ4CVP-mB92K27uhbUJU1p1r_wW1gFWFOEjXk") == "E9Melhoa2OwvFrEMTJguCHaoeK1t8URWbuGJSstw-cM")
        let verifier = PKCE.verifier()
        #expect(verifier.count == 64 && verifier.allSatisfy { "ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz0123456789-._~".contains($0) })
        #expect(PKCE.verifier() != verifier)
    }

    @Test func authorizationURLAndCallback() throws {
        let url = OAuthFlow.authorizationURL(provider: .dropbox, clientID: "key", redirect: OAuthProvider.dropbox.redirect, state: "s1", codeChallenge: "c")
        let items = URLComponents(url: url, resolvingAgainstBaseURL: false)!.queryItems!
        func value(_ n: String) -> String? { items.first { $0.name == n }?.value }
        #expect(url.absoluteString.hasPrefix("https://www.dropbox.com/oauth2/authorize?"))
        #expect(value("client_id") == "key" && value("response_type") == "code" && value("state") == "s1")
        #expect(value("redirect_uri") == "greenshotmac://oauth/dropbox" && value("code_challenge") == "c" && value("code_challenge_method") == "S256")
        #expect(value("token_access_type") == "offline")
        #expect(OAuthProvider.box.redirect.url.absoluteString == "http://127.0.0.1:52398/box")

        #expect(try OAuthFlow.authorizationCode(fromCallback: URL(string: "greenshotmac://oauth/dropbox?code=abc&state=s1")!, expectedState: "s1") == "abc")
        #expect(throws: UploadError.self) { try OAuthFlow.authorizationCode(fromCallback: URL(string: "greenshotmac://oauth/dropbox?code=abc&state=other")!, expectedState: "s1") }
        #expect(throws: UploadError.cancelled) { try OAuthFlow.authorizationCode(fromCallback: URL(string: "http://127.0.0.1:1/box?error=access_denied&state=s1")!, expectedState: "s1") }
    }

    /// Another loopback port changes only `redirect_uri`; a "+" elsewhere stays "%2B".
    @Test func anotherLoopbackPortKeepsTheRest() throws {
        let url = OAuthFlow.authorizationURL(provider: .box, clientID: "a+b", redirect: OAuthProvider.box.redirect,
                                             state: "s1", codeChallenge: "c")
        let moved = OAuthFlow.replacingRedirect(in: url, with: URL(string: "http://127.0.0.1:52400/box")!)
        let query = try #require(moved.query)
        #expect(query.contains("client_id=a%2Bb"))
        let items = try #require(URLComponents(url: moved, resolvingAgainstBaseURL: false)?.queryItems)
        #expect(items.first { $0.name == "redirect_uri" }?.value == "http://127.0.0.1:52400/box")
        #expect(items.first { $0.name == "state" }?.value == "s1")
    }

    @Test func tokensParseWithExpiryAndKeepTheRefreshToken() throws {
        let first = try OAuthTokens.parse(json: Data(#"{"access_token":"a1","expires_in":14400,"refresh_token":"r1","token_type":"bearer"}"#.utf8), now: now)
        #expect(first == OAuthTokens(accessToken: "a1", refreshToken: "r1", expiresAt: now.addingTimeInterval(14400)))
        let refreshed = try OAuthTokens.parse(json: Data(#"{"access_token":"a2","expires_in":3600}"#.utf8), now: now, previous: first)
        #expect(refreshed.refreshToken == "r1" && refreshed.accessToken == "a2")
        #expect(first.isUsable(at: now) && !first.isUsable(at: now.addingTimeInterval(14400 - 30)))
        #expect(throws: UploadError.self) { try OAuthTokens.parse(json: Data(#"{"error":"x"}"#.utf8), now: now) }
    }

    private func client(_ http: HTTPClient, store: SecretStore, provider: OAuthProvider = .dropbox, secret: String? = nil) -> OAuthClient {
        OAuthClient(provider: provider, clientID: "key", clientSecret: secret, store: store, storeKey: "tokens", http: http, now: { now })
    }

    @Test func signInExchangesTheCodeWithTheVerifier() async throws {
        let http = StubHTTPClient(status: 200, body: #"{"access_token":"a1","expires_in":14400,"refresh_token":"r1"}"#)
        let store = InMemorySecretStore()
        let authorizer = StubAuthorizer()
        let client = client(http, store: store)
        #expect(!client.isSignedIn)
        let token = try await client.accessToken(authorizer: authorizer)
        #expect(token == "a1" && client.isSignedIn && client.tokens?.refreshToken == "r1")
        let request = http.last
        #expect(request.url == OAuthProvider.dropbox.tokenURL && request.httpMethod == "POST")
        let fields = Dictionary(uniqueKeysWithValues: request.bodyText.split(separator: "&").map { pair -> (String, String) in
            let parts = pair.split(separator: "=", maxSplits: 1).map { String($0).removingPercentEncoding! }
            return (parts[0], parts[1])
        })
        #expect(fields["grant_type"] == "authorization_code" && fields["code"] == "the-code" && fields["client_id"] == "key")
        #expect(fields["redirect_uri"] == "greenshotmac://oauth/dropbox" && fields["client_secret"] == nil)
        let challenge = URLComponents(url: authorizer.seen.url!, resolvingAgainstBaseURL: false)!.queryItems!.first { $0.name == "code_challenge" }!.value!
        #expect(PKCE.challenge(for: fields["code_verifier"]!) == challenge)
        // The next call uses the stored token without the network.
        #expect(try await client.accessToken(authorizer: nil) == "a1")
        #expect(http.requests.count == 1)
    }

    @Test func expiredTokenIsRefreshedAndBoxRotatesTheRefreshToken() async throws {
        let store = InMemorySecretStore()
        let old = OAuthTokens(accessToken: "old", refreshToken: "r1", expiresAt: now.addingTimeInterval(-1))
        try store.setSecret(String(decoding: try JSONEncoder().encode(old), as: UTF8.self), for: "tokens")
        let http = StubHTTPClient(status: 200, body: #"{"access_token":"a2","expires_in":3600,"refresh_token":"r2"}"#)
        let client = client(http, store: store, provider: .box, secret: "sec")
        #expect(try await client.accessToken(authorizer: nil) == "a2")
        #expect(client.tokens == OAuthTokens(accessToken: "a2", refreshToken: "r2", expiresAt: now.addingTimeInterval(3600)))
        #expect(http.last.url == OAuthProvider.box.tokenURL)
        #expect(http.last.bodyText == "grant_type=refresh_token&refresh_token=r1&client_id=key&client_secret=sec")
    }

    @Test func rejectedRefreshSignsInAgainOrFails() async throws {
        let store = InMemorySecretStore()
        try store.setSecret(String(decoding: try JSONEncoder().encode(OAuthTokens(accessToken: "old", refreshToken: "r1", expiresAt: .distantPast)), as: UTF8.self), for: "tokens")
        let http = StubHTTPClient([.init(status: 400, body: #"{"error":"invalid_grant"}"#)])
        await #expect(throws: UploadError.notSignedIn("Dropbox")) { _ = try await client(http, store: store).accessToken(authorizer: nil) }
        #expect(!client(http, store: store).isSignedIn)
        await #expect(throws: UploadError.cancelled) { _ = try await client(http, store: store).accessToken(authorizer: StubAuthorizer(deny: true)) }
        await #expect(throws: UploadError.notConfigured("The Dropbox app key")) {
            _ = try await OAuthClient(provider: .dropbox, clientID: " ", store: store, storeKey: "t", http: http).accessToken(authorizer: nil)
        }
    }

    @Test func loopbackOnAnotherPortIsNamedInTheTokenRequest() async throws {
        let http = StubHTTPClient(status: 200, body: #"{"access_token":"a1","expires_in":3600,"refresh_token":"r1"}"#)
        try await client(http, store: InMemorySecretStore(), provider: .box, secret: "sec").signIn(with: StubAuthorizer(port: 50000))
        #expect(http.last.bodyText.contains("redirect_uri=http%3A%2F%2F127.0.0.1%3A50000%2Fbox"))
        #expect(http.last.bodyText.contains("&client_secret=sec"))
    }
}

struct CloudClientTests {
    @Test func boxUploadsThenSharesALink() async throws {
        let http = StubHTTPClient([
            .init(status: 201, body: #"{"total_count":1,"entries":[{"type":"file","id":"12345","name":"shot.png"}]}"#),
            .init(status: 200, body: #"{"id":"12345","shared_link":{"url":"https://app.box.com/s/abc","access":"open"}}"#),
        ])
        let result = try await BoxClient(http: http).upload(png, folderID: "77", sharedLink: true, accessToken: "T")
        #expect(result == CloudUpload(fileID: "12345", path: "shot.png", link: URL(string: "https://app.box.com/s/abc")!, isSharedLink: true))
        let upload = http.requests[0]
        #expect(upload.url == BoxClient.uploadURL && upload.value(forHTTPHeaderField: "Authorization") == "Bearer T")
        let body = upload.bodyText
        let attributes = body.range(of: "name=\"attributes\"")!, file = body.range(of: "name=\"file\"")!
        #expect(attributes.lowerBound < file.lowerBound)
        #expect(body.contains("\r\n\r\n{\"name\":\"shot.png\",\"parent\":{\"id\":\"77\"}}\r\n"))
        let share = http.requests[1]
        #expect(share.httpMethod == "PUT" && share.url?.absoluteString == "https://api.box.com/2.0/files/12345?fields=shared_link")
        #expect(share.bodyText == #"{"shared_link":{"access":"open"}}"#)
    }

    @Test func boxPrivateLinkWithoutSharing() async throws {
        let http = StubHTTPClient(status: 201, body: #"{"entries":[{"id":"9"}]}"#)
        let result = try await BoxClient(http: http).upload(png, folderID: "", sharedLink: false, accessToken: "T")
        #expect(result.link.absoluteString == "https://app.box.com/file/9" && !result.isSharedLink)
        #expect(http.last.bodyText.contains(#"{"name":"shot.png","parent":{"id":"0"}}"#))
        #expect(throws: UploadError.self) { try BoxClient.uploadedFileID(fromJSON: Data(#"{"entries":[]}"#.utf8)) }
    }

    /// The file name of the Dropbox web app's link keeps its "+" (servers read a plain "+" in a query as a space).
    @Test func dropboxLinkKeepsAPlusInTheName() throws {
        let url = DropboxClient.homeURL(path: "/Screenshots/Q3+Q4 plan.png")
        #expect(url.absoluteString == "https://www.dropbox.com/home/Screenshots?preview=Q3%2BQ4%20plan.png")
        let oauth = OAuthFlow.authorizationURL(provider: .dropbox, clientID: "a+b", redirect: OAuthProvider.dropbox.redirect,
                                               state: "s1", codeChallenge: "c")
        let query = try #require(oauth.query)
        #expect(query.contains("client_id=a%2Bb"))
    }

    @Test func dropboxPathsAndUpload() async throws {
        #expect(DropboxClient.path(folder: "", filename: "a.png") == "/a.png")
        #expect(DropboxClient.path(folder: "/Screenshots/ work /", filename: "a/b.png") == "/Screenshots/work/a-b.png")
        let http = StubHTTPClient([
            .init(status: 200, body: #"{"id":"id:AAA","name":"Ärger.png","path_lower":"/screenshots/ärger.png","path_display":"/Screenshots/Ärger.png"}"#),
            .init(status: 200, body: #"{"url":"https://www.dropbox.com/scl/fi/x/%C3%84rger.png?dl=0"}"#),
        ])
        let file = UploadFile(name: "Ärger.png", data: png.data, mimeType: "image/png")
        let result = try await DropboxClient(http: http).upload(file, folder: "Screenshots", sharedLink: true, accessToken: "T")
        #expect(result.link.absoluteString == "https://www.dropbox.com/scl/fi/x/%C3%84rger.png?dl=0" && result.isSharedLink)
        #expect(result.fileID == "id:AAA" && result.path == "/Screenshots/Ärger.png")
        let upload = http.requests[0]
        #expect(upload.url == DropboxClient.uploadURL && upload.httpBody == png.data)
        #expect(upload.value(forHTTPHeaderField: "Content-Type") == "application/octet-stream")
        #expect(upload.value(forHTTPHeaderField: "Dropbox-API-Arg") == #"{"autorename":true,"mode":"add","mute":true,"path":"/Screenshots/\u00c4rger.png"}"#)
        #expect(upload.value(forHTTPHeaderField: "Authorization") == "Bearer T")
        #expect(http.requests[1].url == DropboxClient.createSharedLinkURL && http.requests[1].bodyText == #"{"path":"/Screenshots/\u00c4rger.png"}"#)
    }

    @Test func dropboxReusesAnExistingSharedLink() async throws {
        let http = StubHTTPClient([
            .init(status: 200, body: #"{"id":"id:B","path_display":"/shot.png"}"#),
            .init(status: 409, body: #"{"error_summary":"shared_link_already_exists/metadata/..","error":{".tag":"shared_link_already_exists"}}"#),
            .init(status: 200, body: #"{"links":[{"url":"https://www.dropbox.com/s/old?dl=0"}],"has_more":false}"#),
        ])
        let result = try await DropboxClient(http: http).upload(png, folder: "", sharedLink: true, accessToken: "T")
        #expect(result.link.absoluteString == "https://www.dropbox.com/s/old?dl=0")
        #expect(http.requests[2].url == DropboxClient.listSharedLinksURL && http.requests[2].bodyText == #"{"direct_only":true,"path":"/shot.png"}"#)
    }

    @Test func dropboxHomeLinkWithoutSharing() async throws {
        let http = StubHTTPClient(status: 200, body: #"{"id":"id:B","path_display":"/Screenshots/shot.png"}"#)
        let result = try await DropboxClient(http: http).upload(png, folder: "Screenshots", sharedLink: false, accessToken: "T")
        #expect(result.link.absoluteString == "https://www.dropbox.com/home/Screenshots?preview=shot.png" && !result.isSharedLink)
    }
}
