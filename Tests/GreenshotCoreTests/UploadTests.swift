// SPDX-License-Identifier: GPL-3.0-or-later

import CryptoKit
import Foundation
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
        lock.lock()
        defer { lock.unlock() }
        requests.append(request)
        guard !queue.isEmpty else { throw UploadError.unexpectedResponse("no stubbed answer for \(request.url!)") }
        let next = queue.removeFirst()
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

    /// Words that only start like JQL, or have "=" or "~" somewhere, are a text search; JQL is a field and an operator.
    @Test func plainWordsAreATextSearch() {
        func text(_ words: String) -> String { "text ~ \"\(words)\" ORDER BY updated DESC" }
        #expect(JiraClient.jql(forSearch: "project kickoff") == text("project kickoff"))
        #expect(JiraClient.jql(forSearch: "Project plan") == text("Project plan"))
        #expect(JiraClient.jql(forSearch: "error: x=1 failed") == text("error: x=1 failed"))
        #expect(JiraClient.jql(forSearch: "how to use ~ in a path") == text("how to use ~ in a path"))
        #expect(JiraClient.jql(forSearch: "project in progress") == text("project in progress"))
        #expect(JiraClient.jql(forSearch: "reports sorted order by date") == text("reports sorted order by date"))
        // JQL stays JQL.
        #expect(JiraClient.jql(forSearch: "project in (A, B)") == "project in (A, B)")
        #expect(JiraClient.jql(forSearch: "summary ~ login") == "summary ~ login")
        #expect(JiraClient.jql(forSearch: "status != Done") == "status != Done")
        #expect(JiraClient.jql(forSearch: "assignee is EMPTY") == "assignee is EMPTY")
        #expect(JiraClient.jql(forSearch: "\"Epic Link\" = PROJ-1") == "\"Epic Link\" = PROJ-1")
        #expect(JiraClient.jql(forSearch: "cf[10010]=3") == "cf[10010]=3")
        #expect(JiraClient.jql(forSearch: "(priority = High OR priority = Highest)") == "(priority = High OR priority = Highest)")
        #expect(JiraClient.jql(forSearch: "order by created DESC") == "order by created DESC")
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

    @Test func serverErrorsSurface() async {
        let http = StubHTTPClient(status: 401, body: #"{"errorMessages":[],"errors":{}}"#)
        await #expect(throws: UploadError.http(status: 401, message: HTTPURLResponse.localizedString(forStatusCode: 401))) {
            _ = try await JiraClient(site: site, http: http).attach(png, to: "PROJ-7")
        }
        #expect(throws: UploadError.self) { try JiraClient.attachments(fromJSON: Data("{}".utf8)) }
    }
}

struct ConfluenceClientTests {
    let site = AtlassianSite(url: "https://yourco.atlassian.net/wiki", email: "me@x.test", apiToken: "tok")!

    @Test func titleSearchCQL() {
        #expect(ConfluenceClient.cql(forTitleSearch: "Release \"notes\"") == "type = page AND title ~ \"Release \\\"notes\\\"\" ORDER BY lastmodified DESC")
        #expect(ConfluenceClient.cql(forTitleSearch: "space = DEV and type = page") == "space = DEV and type = page")
        // "=" in a title doesn't make it CQL.
        #expect(ConfluenceClient.cql(forTitleSearch: "Plan: cost = time") == "type = page AND title ~ \"Plan: cost = time\" ORDER BY lastmodified DESC")
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
