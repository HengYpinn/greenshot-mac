// Greenshot for Mac (Community) - an unofficial macOS port of Greenshot
// Copyright (C) 2026 Greenshot for Mac (Community) contributors
// Based on Greenshot, Copyright (C) 2007-2026 Thomas Braun, Jens Klingen, Robin Krom
// SPDX-License-Identifier: GPL-3.0-or-later

import Foundation

// Jira and Confluence over their REST APIs, on Atlassian Cloud (email + API token) and on Server / Data Center
// (personal access token, or user name + password): the logic of upstream `Greenshot.Plugin.Jira/Api/JiraConnector.cs`
// and `Greenshot.Plugin.Confluence/Api/Confluence.cs` (which use the Dapplo clients and a login dialog). Requests and
// answers are plain functions, so tests can check them without a server.

/// A Jira or Confluence site with the credentials of its login.
public struct AtlassianSite: Equatable, Sendable {
    public var baseURL: URL
    public var login: AtlassianLogin
    /// The account's email (Cloud) or the user name (Server/Data Center password); not used with a personal access token.
    public var user: String
    /// The API token, the personal access token or the password.
    public var secret: String

    /// `url` is trimmed, gets `https://` when it has no scheme and loses a trailing slash. Nil when it is empty
    /// or not a URL.
    public init?(url: String, login: AtlassianLogin, user: String, secret: String) {
        var text = url.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !text.isEmpty else { return nil }
        if !text.contains("://") { text = "https://" + text }
        while text.hasSuffix("/") { text.removeLast() }
        guard let parsed = URL(string: text), parsed.host != nil else { return nil }
        baseURL = parsed
        self.login = login
        self.user = user.trimmingCharacters(in: .whitespaces)
        self.secret = secret
    }

    /// An Atlassian Cloud site with an API token.
    public init?(url: String, email: String, apiToken: String) {
        self.init(url: url, login: .cloudAPIToken, user: email, secret: apiToken)
    }

    public var email: String { user }
    public var apiToken: String { secret }

    /// Whether the login has what it needs: the secret, and the user unless it is a personal access token.
    public var hasCredentials: Bool {
        !secret.isEmpty && (login == .serverToken || !user.isEmpty)
    }

    /// Basic authentication with the email and API token or the user name and password; a personal access token is a
    /// bearer token (Data Center).
    public var authorizationHeader: String {
        switch login {
        case .serverToken: return "Bearer " + secret
        case .cloudAPIToken, .serverPassword: return HTTPSupport.basicAuthorization(user: user, password: secret)
        }
    }

    /// The same site with another secret (a password typed in the login dialog).
    public func with(user: String, secret: String) -> AtlassianSite {
        var site = self
        site.user = user.trimmingCharacters(in: .whitespaces)
        site.secret = secret
        return site
    }

    /// A request for `path` (relative to the base URL) with the credentials and JSON accepted.
    public func request(_ method: String, path: String, query: [URLQueryItem] = []) -> URLRequest {
        var components = URLComponents(url: baseURL, resolvingAgainstBaseURL: false)!
        let base = components.path.hasSuffix("/") ? String(components.path.dropLast()) : components.path
        components.path = base + "/" + path
        components.setQueryItemsEncodingPlus(query.isEmpty ? nil : query)
        var request = URLRequest(url: components.url!, timeoutInterval: 60)
        request.httpMethod = method
        request.setValue(authorizationHeader, forHTTPHeaderField: "Authorization")
        request.setValue("application/json", forHTTPHeaderField: "Accept")
        return request
    }

    /// Whether `url` is on the site itself, so the credentials may go with a request for it: the same scheme, host
    /// (case doesn't matter) and port (none is the scheme's default). An `http://` link on the site's host would send
    /// them unencrypted, a link to another port to another server.
    public func isSameOrigin(_ url: URL) -> Bool {
        Self.origin(of: url).map { $0 == Self.origin(of: baseURL) } ?? false
    }

    /// Scheme, host and port of `url`, lower case, with the default port of http and https; nil without a host.
    static func origin(of url: URL) -> String? {
        guard let scheme = url.scheme?.lowercased(), let host = url.host?.lowercased(), !host.isEmpty else { return nil }
        let port = url.port ?? (scheme == "https" ? 443 : scheme == "http" ? 80 : -1)
        return "\(scheme)://\(host):\(port)"
    }

    /// Whether `url` is a web page on the site's host (http or https, case doesn't matter), so it may be opened in
    /// the browser: the links of pages and attachments come from the server, and a `file://` link or another app's
    /// URL must not be opened.
    public func isOnSite(_ url: URL) -> Bool {
        guard let scheme = url.scheme?.lowercased(), scheme == "https" || scheme == "http",
              let host = url.host, let own = baseURL.host else { return false }
        return host.caseInsensitiveCompare(own) == .orderedSame
    }

    /// Whether the site is reached over `http://`: the token or password travels unencrypted.
    public var isUnencrypted: Bool { baseURL.scheme?.lowercased() == "http" }

    /// The host (lower case) of a Jira or Confluence URL as the settings hold it (see `init(url:login:user:secret:)`),
    /// nil when it isn't one.
    public static func host(ofURL url: String) -> String? {
        AtlassianSite(url: url, login: .serverToken, user: "", secret: "")?.baseURL.host?.lowercased()
    }

    /// Whether a Jira or Confluence URL of the settings starts with `http://`.
    public static func isUnencrypted(url: String) -> Bool {
        AtlassianSite(url: url, login: .serverToken, user: "", secret: "")?.isUnencrypted ?? false
    }

    /// A URL under the site for a link the server gave (absolute, or relative to the site).
    public func url(forLink link: String?, base: String? = nil) -> URL? {
        guard let link, !link.isEmpty else { return nil }
        if link.contains("://") { return URL(string: link) }
        let root = base.flatMap(URL.init(string:)) ?? baseURL
        return URL(string: root.absoluteString + (link.hasPrefix("/") ? link : "/" + link))
    }
}

// MARK: Jira

public struct JiraIssue: Equatable, Sendable, Codable {
    public var key: String
    public var summary: String
    /// The issue type's name and icon (upstream's type column, `IssueTypeBitmapCache`).
    public var type: String?
    public var typeIconURL: URL?
    public var created: Date?
    public var assignee: String?
    public var reporter: String?

    public init(key: String, summary: String, type: String? = nil, typeIconURL: URL? = nil, created: Date? = nil,
                assignee: String? = nil, reporter: String? = nil) {
        self.key = key
        self.summary = summary
        self.type = type
        self.typeIconURL = typeIconURL
        self.created = created
        self.assignee = assignee
        self.reporter = reporter
    }
}

/// A favourite filter of the Jira user (upstream `JiraConnector.GetFavoriteFiltersAsync`).
public struct JiraFilter: Equatable, Sendable {
    public var id: String
    public var name: String
    public var jql: String

    public init(id: String, name: String, jql: String) {
        self.id = id
        self.name = name
        self.jql = jql
    }
}

public struct JiraAttachment: Equatable, Sendable {
    public var id: String
    public var filename: String
    public var contentURL: URL?

    public init(id: String, filename: String, contentURL: URL?) {
        self.id = id
        self.filename = filename
        self.contentURL = contentURL
    }
}

/// Jira: attach a file to an issue, look issues up and add a comment. Cloud uses `/rest/api/3`, Server and Data Center
/// `/rest/api/2` (upstream's Dapplo.Jira client).
public struct JiraClient: Sendable {
    public let site: AtlassianSite
    public let http: HTTPClient

    public init(site: AtlassianSite, http: HTTPClient) {
        self.site = site
        self.http = http
    }

    /// The REST API of the site: version 3 on Cloud, 2 on Server and Data Center.
    public var api: String { site.login.isCloud ? "rest/api/3" : "rest/api/2" }

    /// "PROJ-123" (upper case is applied first).
    public static func isIssueKey(_ text: String) -> Bool {
        let key = text.trimmingCharacters(in: .whitespaces).uppercased()
        return key.range(of: #"^[A-Z][A-Z0-9_]*-[0-9]+$"#, options: .regularExpression) != nil
    }

    public static func normalizedKey(_ text: String) -> String {
        text.trimmingCharacters(in: .whitespaces).uppercased()
    }

    /// What to search for: an issue key finds that issue, text that is JQL (see `isQuery`) is used as it is,
    /// anything else is a text search, newest first.
    public static func jql(forSearch text: String) -> String {
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        if isIssueKey(trimmed) { return "key = \(normalizedKey(trimmed))" }
        if isQuery(trimmed) { return trimmed }
        return "text ~ \"\(escaped(trimmed))\" ORDER BY updated DESC"
    }

    /// A JQL or CQL clause at the start: a field (a whole word, `cf[123]` or a quoted name), maybe after `(` or `NOT`,
    /// then a symbol operator (group 2: `=`, `!=`, `~`, `!~`, `<`, `>`, `<=`, `>=`) or, after a space, a word operator
    /// (group 3: `IN (`, `NOT IN (`, `WAS [NOT] IN (`, `IS [NOT] EMPTY|NULL`). Group 1 is the field.
    private static let clauseRegex = try! NSRegularExpression(
        pattern: #"^(?:[(\s]|not\s+)*("[^"]+"|cf\[\d+\]|[\p{L}_][\p{L}\p{N}_.]*+)"#
            + #"(?:\s*(!=|!~|<=|>=|[=~<>])|\s+((?:was\s+)?(?:not\s+)?in\s*\(|is\s+(?:not\s+)?(?:empty|null)\b))"#,
        options: [.caseInsensitive])

    /// `ORDER BY` (group 1) and the field after it (group 2) at the start.
    private static let orderByRegex = try! NSRegularExpression(
        pattern: #"^\s*(order\s+by)\s+("[^"]+"|cf\[\d+\]|[\p{L}_][\p{L}\p{N}_.]*+)"#, options: [.caseInsensitive])

    /// Fields of Jira (JQL) and Confluence (CQL) that a search names, in lower case.
    private static let knownFields: Set<String> = [
        "project", "status", "statuscategory", "assignee", "reporter", "creator", "priority", "resolution", "issuetype",
        "type", "labels", "component", "fixversion", "affectedversion", "sprint", "parent", "key", "issuekey", "issue",
        "epic", "watcher", "voter", "text", "summary", "description", "comment", "environment", "created",
        "createddate", "updated", "updateddate", "resolved", "resolutiondate", "due", "duedate", "lastviewed", "filter",
        "level", "category", "attachments", "rank",
        "space", "title", "label", "ancestor", "contributor", "mention", "favourite", "favorite", "lastmodified", "id",
        "content", "container", "macro",
    ]

    /// A field that is clearly one: a quoted name, `cf[123]`, or a field Jira or Confluence has (`space.type` counts
    /// as `space`).
    private static func isKnownField(_ field: String) -> Bool {
        let name = field.lowercased()
        if name.hasPrefix("\"") || name.hasPrefix("cf[") { return true }
        return knownFields.contains(String(name.prefix { $0 != "." }))
    }

    /// Whether search text is a query (JQL, or CQL, which has the same clauses) rather than words: a field followed by
    /// an operator. With `=` or `~` (`!=`, `<=`, …) any word counts as the field, as before. `<`, `>` and the word
    /// operators (`in (`, `is empty`) also turn up in plain words ("Meeting in (Berlin)", "This is empty", "a<b"), so
    /// they need a known field, or a word operator in capitals ("Team IS EMPTY"); likewise `ORDER BY`. When in doubt it
    /// is words: a text search never fails, a query that isn't one does (HTTP 400).
    static func isQuery(_ text: String) -> Bool {
        let range = NSRange(text.startIndex..., in: text)
        func group(_ match: NSTextCheckingResult, _ index: Int) -> String? {
            Range(match.range(at: index), in: text).map { String(text[$0]) }
        }
        if let match = orderByRegex.firstMatch(in: text, range: range), let keyword = group(match, 1),
           let field = group(match, 2) {
            return isKnownField(field) || keyword == keyword.uppercased()
        }
        guard let match = clauseRegex.firstMatch(in: text, range: range), let field = group(match, 1) else { return false }
        if let symbol = group(match, 2) {
            return symbol.contains("=") || symbol.contains("~") || isKnownField(field)
        }
        guard let word = group(match, 3) else { return false }
        return isKnownField(field) || word == word.uppercased()
    }

    /// Quotes and backslashes inside a JQL/CQL string.
    public static func escaped(_ text: String) -> String {
        text.replacingOccurrences(of: "\\", with: "\\\\").replacingOccurrences(of: "\"", with: "\\\"")
    }

    public func browseURL(for issueKey: String) -> URL {
        site.baseURL.appendingPathComponent("browse").appendingPathComponent(issueKey)
    }

    private static let issueKeyRegex = try! NSRegularExpression(pattern: #"\b[A-Z][A-Z0-9]+-[0-9]+\b"#)

    /// The issue keys in window titles, first seen first, each once, at most `limit` (upstream `JiraMonitor` watches
    /// the titles for `[A-Z][A-Z0-9]+-[0-9]+`). Text like "UTF-8" matches too; the API check drops those.
    public static func issueKeys(inTitles titles: [String], limit: Int = 10) -> [String] {
        var keys: [String] = []
        for title in titles {
            let ns = title as NSString
            for match in issueKeyRegex.matches(in: title, range: NSRange(location: 0, length: ns.length)) {
                let key = ns.substring(with: match.range)
                if !keys.contains(key) { keys.append(key) }
                if keys.count == limit { return keys }
            }
        }
        return keys
    }

    /// An issue type icon as PNG: Jira Cloud's avatar URLs answer SVG unless asked for `format=png`, which `NSImage`
    /// reads everywhere.
    public static func pngIconURL(_ url: URL) -> URL {
        guard url.path.contains("/universal_avatar/"),
              var components = URLComponents(url: url, resolvingAgainstBaseURL: false) else { return url }
        var items = (components.queryItems ?? []).filter { $0.name != "format" }
        items.append(URLQueryItem(name: "format", value: "png"))
        components.queryItems = items
        return components.url ?? url
    }

    /// The fields the issue list shows (upstream's columns: type, key, created, assignee, reporter, summary).
    public static let listFields = "summary,issuetype,created,assignee,reporter"

    // Requests

    /// `POST /rest/api/{3|2}/issue/{key}/attachments` with the file as `multipart/form-data` (the `X-Atlassian-Token`
    /// header turns off the XSRF check, as the API requires).
    public func attachRequest(issueKey: String, file: UploadFile, boundary: String = "greenshot-" + UUID().uuidString) -> URLRequest {
        var form = MultipartForm(boundary: boundary)
        form.addFile("file", file: file)
        var request = site.request("POST", path: "\(api)/issue/\(issueKey)/attachments")
        request.setValue("no-check", forHTTPHeaderField: "X-Atlassian-Token")
        request.setValue(form.contentType, forHTTPHeaderField: "Content-Type")
        request.httpBody = form.finished()
        return request
    }

    /// Cloud: `GET /rest/api/3/search/jql` (the endpoint that replaced `/search` in 2025; `fields` is needed, the
    /// default is the id alone). Server and Data Center: `GET /rest/api/2/search`.
    public func searchRequest(jql: String, maxResults: Int = 20) -> URLRequest {
        site.request("GET", path: site.login.isCloud ? "rest/api/3/search/jql" : "rest/api/2/search", query: [
            URLQueryItem(name: "jql", value: jql),
            URLQueryItem(name: "maxResults", value: String(maxResults)),
            URLQueryItem(name: "fields", value: Self.listFields),
        ])
    }

    /// `GET /rest/api/{3|2}/filter/favourite`: the filters the user starred.
    public func favouriteFiltersRequest() -> URLRequest {
        site.request("GET", path: "\(api)/filter/favourite")
    }

    public func issueRequest(key: String) -> URLRequest {
        site.request("GET", path: "\(api)/issue/\(key)", query: [URLQueryItem(name: "fields", value: "summary")])
    }

    /// `GET /rest/api/{3|2}/myself`: who the credentials belong to (the connection test, upstream's login check).
    public func myselfRequest() -> URLRequest {
        site.request("GET", path: "\(api)/myself")
    }

    /// `POST /rest/api/{3|2}/issue/{key}/comment`: on Cloud the text as one paragraph of Atlassian Document Format, on
    /// Server and Data Center as the plain body (wiki markup) of REST v2.
    public func commentRequest(issueKey: String, text: String) -> URLRequest {
        var request = site.request("POST", path: "\(api)/issue/\(issueKey)/comment")
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        let body: [String: Any]
        if site.login.isCloud {
            body = ["body": [
                "type": "doc", "version": 1,
                "content": [["type": "paragraph", "content": [["type": "text", "text": text]]]],
            ]]
        } else {
            body = ["body": text]
        }
        request.httpBody = try? JSONSerialization.data(withJSONObject: body, options: [.sortedKeys])
        return request
    }

    // Answers

    /// The attachments the attach call answers with (a JSON array).
    public static func attachments(fromJSON data: Data) throws -> [JiraAttachment] {
        guard let list = try? JSONSerialization.jsonObject(with: data) as? [[String: Any]] else {
            throw UploadError.unexpectedResponse("expected a list of attachments")
        }
        return list.compactMap { item in
            guard let id = item["id"].map({ "\($0)" }) else { return nil }
            return JiraAttachment(id: id, filename: item["filename"] as? String ?? "",
                                  contentURL: (item["content"] as? String).flatMap(URL.init(string:)))
        }
    }

    /// The favourite filters answer (a JSON array), in the server's order; filters without JQL are left out.
    public static func filters(fromJSON data: Data) throws -> [JiraFilter] {
        guard let list = try? JSONSerialization.jsonObject(with: data) as? [[String: Any]] else {
            throw UploadError.unexpectedResponse("expected a list of filters")
        }
        return list.compactMap { item in
            guard let id = item["id"].map({ "\($0)" }), let name = item["name"] as? String,
                  let jql = item["jql"] as? String, !jql.isEmpty else { return nil }
            return JiraFilter(id: id, name: name, jql: jql)
        }
    }

    public static func issues(fromJSON data: Data) throws -> [JiraIssue] {
        let object = try HTTPSupport.json(data)
        guard let issues = object["issues"] as? [[String: Any]] else {
            throw UploadError.unexpectedResponse("no issues in the answer")
        }
        return issues.compactMap(issue(from:))
    }

    public static func issue(fromJSON data: Data) throws -> JiraIssue {
        guard let issue = issue(from: try HTTPSupport.json(data)) else {
            throw UploadError.unexpectedResponse("no issue in the answer")
        }
        return issue
    }

    private static func issue(from object: [String: Any]) -> JiraIssue? {
        guard let key = object["key"] as? String else { return nil }
        let fields = object["fields"] as? [String: Any]
        let type = fields?["issuetype"] as? [String: Any]
        func person(_ name: String) -> String? { (fields?[name] as? [String: Any])?["displayName"] as? String }
        return JiraIssue(key: key, summary: fields?["summary"] as? String ?? "", type: type?["name"] as? String,
                         typeIconURL: (type?["iconUrl"] as? String).flatMap(URL.init(string:)),
                         created: (fields?["created"] as? String).flatMap(date(fromJira:)),
                         assignee: person("assignee"), reporter: person("reporter"))
    }

    /// Jira's timestamps, e.g. "2026-10-01T12:34:56.789+0200".
    static func date(fromJira text: String) -> Date? {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX")
        for format in ["yyyy-MM-dd'T'HH:mm:ss.SSSZ", "yyyy-MM-dd'T'HH:mm:ssZ"] {
            formatter.dateFormat = format
            if let date = formatter.date(from: text) { return date }
        }
        return nil
    }

    // Calls

    public func attach(_ file: UploadFile, to issueKey: String) async throws -> [JiraAttachment] {
        try Self.attachments(fromJSON: try await HTTPSupport.send(attachRequest(issueKey: issueKey, file: file), with: http))
    }

    /// Attaches the file, then adds the comment when there is one (upstream `JiraDestination`). A comment that fails
    /// (no permission to comment, a rejected text, Cancel) doesn't fail the upload, the file is on the issue: its error
    /// comes back instead, so trying again doesn't attach the file twice (upstream fails the whole upload).
    public func attach(_ file: UploadFile, to issueKey: String, comment: String) async throws
        -> (attachments: [JiraAttachment], commentError: Error?) {
        let attachments = try await attach(file, to: issueKey)
        guard !comment.isEmpty else { return (attachments, nil) }
        do {
            try await addComment(comment, to: issueKey)
            return (attachments, nil)
        } catch {
            return (attachments, error)
        }
    }

    public func search(_ text: String, maxResults: Int = 20) async throws -> [JiraIssue] {
        try await search(jql: Self.jql(forSearch: text), maxResults: maxResults)
    }

    /// The issues of a JQL query as it is, e.g. a favourite filter's.
    public func search(jql: String, maxResults: Int = 50) async throws -> [JiraIssue] {
        let request = searchRequest(jql: jql, maxResults: maxResults)
        return try Self.issues(fromJSON: try await HTTPSupport.send(request, with: http))
    }

    public func favouriteFilters() async throws -> [JiraFilter] {
        try Self.filters(fromJSON: try await HTTPSupport.send(favouriteFiltersRequest(), with: http))
    }

    /// An image of the site with the credentials (issue type icons need them); an image anywhere else without them.
    public func imageData(at url: URL) async throws -> Data {
        var request = URLRequest(url: url, timeoutInterval: 30)
        if site.isSameOrigin(url) { request.setValue(site.authorizationHeader, forHTTPHeaderField: "Authorization") }
        return try await HTTPSupport.send(request, with: http)
    }

    public func issue(_ key: String) async throws -> JiraIssue {
        try Self.issue(fromJSON: try await HTTPSupport.send(issueRequest(key: key), with: http))
    }

    public func addComment(_ text: String, to issueKey: String) async throws {
        _ = try await HTTPSupport.send(commentRequest(issueKey: issueKey, text: text), with: http)
    }
}

// MARK: Confluence

public struct ConfluencePage: Equatable, Sendable, Codable, Identifiable {
    public var id: String
    public var title: String
    public var spaceName: String
    public var url: URL

    public init(id: String, title: String, spaceName: String, url: URL) {
        self.id = id
        self.title = title
        self.spaceName = spaceName
        self.url = url
    }
}

/// A Confluence space for the search and the page tree (upstream `Entities.Space`).
public struct ConfluenceSpace: Equatable, Sendable {
    public var key: String
    public var name: String
    /// The id of the space's home page, the root of its page tree (upstream `GetSpaceHomepageAsync`).
    public var homepageID: String?
    /// A personal space (`type` "personal", keys start with `~`), left out unless `IncludePersonSpaces` is on.
    public var isPersonal: Bool

    public init(key: String, name: String, homepageID: String? = nil, isPersonal: Bool = false) {
        self.key = key
        self.name = name
        self.homepageID = homepageID
        self.isPersonal = isPersonal
    }
}

public struct ConfluenceAttachment: Equatable, Sendable {
    public var id: String
    public var title: String
    public var downloadURL: URL?

    public init(id: String, title: String, downloadURL: URL?) {
        self.id = id
        self.title = title
        self.downloadURL = downloadURL
    }
}

/// Confluence (`/rest/api`, Cloud sites end in `/wiki`): find pages by title with CQL, browse the spaces' page trees,
/// attach a file to a page. Cloud uses the v2 API where the v1 one is going; Server and Data Center use v1 only.
public struct ConfluenceClient: Sendable {
    public let site: AtlassianSite
    public let http: HTTPClient

    public init(site: AtlassianSite, http: HTTPClient) {
        self.site = site
        self.http = http
    }

    /// Pages whose title contains the words, last changed first, in one space when `spaceKey` isn't empty (upstream
    /// `SearchPagesAsync(query, space)`). Without `includePersonalSpaces` a search of all spaces leaves the personal
    /// ones out (upstream `IncludePersonSpaces`). Text that already is CQL (a field and an operator) is used as it is.
    public static func cql(forTitleSearch text: String, spaceKey: String = "", includePersonalSpaces: Bool = true) -> String {
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        if JiraClient.isQuery(trimmed) { return trimmed }
        let space = spaceKey.trimmingCharacters(in: .whitespaces)
        var scope = ""
        if !space.isEmpty {
            scope = "space = \"\(JiraClient.escaped(space))\" AND "
        } else if !includePersonalSpaces {
            scope = "space.type = global AND "
        }
        return "type = page AND \(scope)title ~ \"\(JiraClient.escaped(trimmed))\" ORDER BY lastmodified DESC"
    }

    /// The page with this exact title in the space (a `/display/SPACE/Title` link, upstream `GetPageAsync(space, title)`).
    public static func cql(space: String, title: String) -> String {
        "type = page AND space = \"\(JiraClient.escaped(space))\" AND title = \"\(JiraClient.escaped(title))\""
    }

    /// Upstream puts `!name!` on the clipboard after the upload: the wiki markup that shows the attachment.
    public static func wikiMarkup(for filename: String) -> String { "!\(filename)!" }

    /// The spaces without the personal ones, unless they are wanted.
    public static func filtered(_ spaces: [ConfluenceSpace], includePersonal: Bool) -> [ConfluenceSpace] {
        includePersonal ? spaces : spaces.filter { !$0.isPersonal }
    }

    // Requests

    /// Cloud: `GET /rest/api/search?cql=…` (the CQL search stays while the v1 content endpoints go). Server and Data
    /// Center: `GET /rest/api/content/search?cql=…&expand=space`, which older servers have too.
    public func searchRequest(cql: String, limit: Int = 20) -> URLRequest {
        var query = [URLQueryItem(name: "cql", value: cql), URLQueryItem(name: "limit", value: String(limit))]
        if !site.login.isCloud { query.append(URLQueryItem(name: "expand", value: "space")) }
        return site.request("GET", path: site.login.isCloud ? "rest/api/search" : "rest/api/content/search", query: query)
    }

    /// The spaces: `GET /api/v2/spaces` on Cloud (the v1 space endpoints are going), `GET /rest/api/space?expand=homepage`
    /// on Server and Data Center and older sites. Both answer `results[]` with `key`, `name` and `type`; v2 has the
    /// home page's id in `homepageId`, v1 the home page in `homepage`.
    public func spacesRequest(v2: Bool = true, limit: Int = 250) -> URLRequest {
        var query = [URLQueryItem(name: "limit", value: String(limit))]
        if !v2 { query.append(URLQueryItem(name: "expand", value: "homepage")) }
        return site.request("GET", path: v2 ? "api/v2/spaces" : "rest/api/space", query: query)
    }

    /// The child pages of a page: `GET /api/v2/pages/{id}/children` on Cloud, `GET /rest/api/content/{id}/child/page`
    /// on Server and Data Center (upstream `GetPageChildrenAsync`).
    public func childPagesRequest(pageID: String, v2: Bool = true, limit: Int = 250) -> URLRequest {
        site.request("GET", path: v2 ? "api/v2/pages/\(pageID)/children" : "rest/api/content/\(pageID)/child/page",
                     query: [URLQueryItem(name: "limit", value: String(limit))])
    }

    /// One page: `GET /api/v2/pages/{id}` on Cloud, `GET /rest/api/content/{id}?expand=space` on Server and Data Center
    /// (upstream `GetPageAsync(pageId)`).
    public func pageRequest(id: String, v2: Bool = true) -> URLRequest {
        site.request("GET", path: v2 ? "api/v2/pages/\(id)" : "rest/api/content/\(id)",
                     query: v2 ? [] : [URLQueryItem(name: "expand", value: "space")])
    }

    /// `POST /rest/api/content/{id}/child/attachment` as `multipart/form-data`, a minor edit (no notification).
    public func attachRequest(pageID: String, file: UploadFile, comment: String? = nil,
                              boundary: String = "greenshot-" + UUID().uuidString) -> URLRequest {
        var form = MultipartForm(boundary: boundary)
        form.addFile("file", file: file)
        form.addField("minorEdit", value: "true")
        if let comment, !comment.isEmpty { form.addField("comment", value: comment, contentType: "text/plain; charset=utf-8") }
        var request = site.request("POST", path: "rest/api/content/\(pageID)/child/attachment")
        request.setValue("nocheck", forHTTPHeaderField: "X-Atlassian-Token")
        request.setValue(form.contentType, forHTTPHeaderField: "Content-Type")
        request.httpBody = form.finished()
        return request
    }

    // Answers

    /// The pages of a search answer (`results[].content` from `/rest/api/search`, or `results[]` from the content
    /// search, the child pages and v2), their links made absolute with the answer's `_links.base` or the site; a page
    /// without a link gets the site's `viewpage.action?pageId=` link. `spaceName` is for answers that don't name it.
    public func pages(fromJSON data: Data, spaceName fallbackSpace: String = "") throws -> [ConfluencePage] {
        let object = try HTTPSupport.json(data)
        guard let results = object["results"] as? [[String: Any]] else {
            throw UploadError.unexpectedResponse("no results in the answer")
        }
        let base = (object["_links"] as? [String: Any])?["base"] as? String
        return results.compactMap { page(from: $0, base: base, spaceName: fallbackSpace) }
    }

    /// One page (a v2 page, or v1 content with its space expanded).
    public func page(fromJSON data: Data, spaceName fallbackSpace: String = "") throws -> ConfluencePage {
        let object = try HTTPSupport.json(data)
        let base = (object["_links"] as? [String: Any])?["base"] as? String
        guard let page = page(from: object, base: base, spaceName: fallbackSpace) else {
            throw UploadError.unexpectedResponse("no page in the answer")
        }
        return page
    }

    private func page(from result: [String: Any], base: String?, spaceName fallbackSpace: String) -> ConfluencePage? {
        let content = result["content"] as? [String: Any] ?? result
        guard let id = content["id"].map({ "\($0)" }), let title = content["title"] as? String else { return nil }
        if let type = content["type"] as? String, type != "page" { return nil }
        let space = (content["space"] as? [String: Any])?["name"] as? String
            ?? (result["resultGlobalContainer"] as? [String: Any])?["title"] as? String ?? fallbackSpace
        let links = content["_links"] as? [String: Any]
        let pageBase = links?["base"] as? String ?? base
        let url = site.url(forLink: links?["webui"] as? String, base: pageBase)
            ?? site.url(forLink: result["url"] as? String, base: pageBase)
            ?? site.baseURL.appendingPathComponent("pages/viewpage.action").appending(queryItem: "pageId", value: id)
        return ConfluencePage(id: id, title: title, spaceName: space, url: url)
    }

    /// The spaces of a v2 or v1 answer, sorted by name (upstream `GetSpaceSummariesAsync`).
    public static func spaces(fromJSON data: Data) throws -> [ConfluenceSpace] {
        let object = try HTTPSupport.json(data)
        guard let results = object["results"] as? [[String: Any]] else {
            throw UploadError.unexpectedResponse("no results in the answer")
        }
        return results.compactMap { item -> ConfluenceSpace? in
            guard let key = item["key"] as? String, !key.isEmpty else { return nil }
            let homepage = item["homepageId"].map { "\($0)" } ?? (item["homepage"] as? [String: Any])?["id"].map { "\($0)" }
            let personal = (item["type"] as? String)?.lowercased() == "personal" || key.hasPrefix("~")
            return ConfluenceSpace(key: key, name: item["name"] as? String ?? key, homepageID: homepage, isPersonal: personal)
        }.sorted { $0.name.localizedStandardCompare($1.name) == .orderedAscending }
    }

    public func attachments(fromJSON data: Data) throws -> [ConfluenceAttachment] {
        let object = try HTTPSupport.json(data)
        guard let results = object["results"] as? [[String: Any]] else {
            throw UploadError.unexpectedResponse("no results in the answer")
        }
        let base = (object["_links"] as? [String: Any])?["base"] as? String
        return results.compactMap { item in
            guard let id = item["id"].map({ "\($0)" }) else { return nil }
            let links = item["_links"] as? [String: Any]
            return ConfluenceAttachment(id: id, title: item["title"] as? String ?? "",
                                        downloadURL: site.url(forLink: links?["download"] as? String, base: base))
        }
    }

    // Calls

    public func searchPages(title: String, spaceKey: String = "", includePersonalSpaces: Bool = true,
                            limit: Int = 20) async throws -> [ConfluencePage] {
        let cql = Self.cql(forTitleSearch: title, spaceKey: spaceKey, includePersonalSpaces: includePersonalSpaces)
        return try pages(fromJSON: try await HTTPSupport.send(searchRequest(cql: cql, limit: limit), with: http))
    }

    /// The spaces, from the v2 API on Cloud and from v1 on Server and Data Center or when v2 is missing (404).
    public func spaces() async throws -> [ConfluenceSpace] {
        guard site.login.isCloud else {
            return try Self.spaces(fromJSON: try await HTTPSupport.send(spacesRequest(v2: false), with: http))
        }
        return try await withV1Fallback { v2 in try Self.spaces(fromJSON: try await HTTPSupport.send(spacesRequest(v2: v2), with: http)) }
    }

    /// The child pages of a page, by title (upstream sorts them by title).
    public func childPages(of pageID: String, spaceName: String) async throws -> [ConfluencePage] {
        let found = try await withV1Fallback { v2 in
            try pages(fromJSON: try await HTTPSupport.send(childPagesRequest(pageID: pageID, v2: v2), with: http), spaceName: spaceName)
        }
        return found.sorted { $0.title.localizedStandardCompare($1.title) == .orderedAscending }
    }

    /// One page by its id (for a home page or a page open in the browser).
    public func page(id: String, spaceName: String = "") async throws -> ConfluencePage {
        try await withV1Fallback { v2 in
            try page(fromJSON: try await HTTPSupport.send(pageRequest(id: id, v2: v2), with: http), spaceName: spaceName)
        }
    }

    /// The page with this title in the space, nil when there is none.
    public func page(space: String, title: String) async throws -> ConfluencePage? {
        try pages(fromJSON: try await HTTPSupport.send(searchRequest(cql: Self.cql(space: space, title: title), limit: 1), with: http)).first
    }

    public func attach(_ file: UploadFile, toPage pageID: String, comment: String? = nil) async throws -> [ConfluenceAttachment] {
        try attachments(fromJSON: try await HTTPSupport.send(attachRequest(pageID: pageID, file: file, comment: comment), with: http))
    }

    /// Cloud tries the v2 API first and v1 when the site doesn't have it (404); Server and Data Center use v1.
    private func withV1Fallback<T>(_ call: (Bool) async throws -> T) async throws -> T {
        guard site.login.isCloud else { return try await call(false) }
        do {
            return try await call(true)
        } catch UploadError.http(let status, _) where status == 404 {
            return try await call(false)
        }
    }
}

/// A Confluence page found by its address in a browser (upstream `ConfluenceUtils.GetCurrentPagesAsync`).
public enum ConfluencePageReference: Equatable, Hashable, Sendable {
    /// `…?pageId=123` (Server, Data Center) or `…/spaces/KEY/pages/123/…` (Cloud, Data Center 7 and later).
    case id(String)
    /// `…/display/KEY/Page+title` (Server, Data Center).
    case title(space: String, title: String)

    private static let pageID = try! NSRegularExpression(pattern: #"[?&]pageId=(\d+)"#)
    private static let spacesPage = try! NSRegularExpression(pattern: #"/spaces/[^/]+/pages/(\d+)"#)
    private static let display = try! NSRegularExpression(pattern: #"/display/([^/]+)/([^#?]+)"#)

    /// The pages of this site among the addresses, each once, in order. Addresses of other sites don't count.
    public static func references(in urls: [String], site: AtlassianSite) -> [ConfluencePageReference] {
        let host = site.baseURL.host?.lowercased()
        var found: [ConfluencePageReference] = []
        for text in urls {
            guard let url = URL(string: text.trimmingCharacters(in: .whitespaces)), url.host?.lowercased() == host,
                  let reference = reference(in: text), !found.contains(reference) else { continue }
            found.append(reference)
        }
        return found
    }

    /// The page an address points at, nil when it isn't a page.
    public static func reference(in url: String) -> ConfluencePageReference? {
        let range = NSRange(url.startIndex..., in: url)
        func group(_ match: NSTextCheckingResult, _ index: Int) -> String? {
            Range(match.range(at: index), in: url).map { String(url[$0]) }
        }
        if let match = pageID.firstMatch(in: url, range: range) ?? spacesPage.firstMatch(in: url, range: range),
           let id = group(match, 1) {
            return .id(id)
        }
        // Upstream unescapes the address and reads "+" as a space.
        if let match = display.firstMatch(in: url, range: range), let space = group(match, 1), let title = group(match, 2) {
            func plain(_ text: String) -> String {
                (text.replacingOccurrences(of: "+", with: " ").removingPercentEncoding ?? text)
                    .trimmingCharacters(in: .whitespaces)
            }
            let name = plain(title)
            guard !name.isEmpty, !space.isEmpty else { return nil }
            return .title(space: plain(space), title: name)
        }
        return nil
    }
}

extension URL {
    func appending(queryItem name: String, value: String) -> URL {
        var components = URLComponents(url: self, resolvingAgainstBaseURL: false)!
        components.setQueryItemsEncodingPlus((components.queryItems ?? []) + [URLQueryItem(name: name, value: value)])
        return components.url ?? self
    }
}
