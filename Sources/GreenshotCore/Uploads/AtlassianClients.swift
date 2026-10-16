// Greenshot for Mac (Community) - an unofficial macOS port of Greenshot
// Copyright (C) 2026 Greenshot for Mac (Community) contributors
// Based on Greenshot, Copyright (C) 2007-2026 Thomas Braun, Jens Klingen, Robin Krom
// SPDX-License-Identifier: GPL-3.0-or-later

import Foundation

// Jira and Confluence over their REST APIs with an Atlassian API token: the logic of upstream
// `Greenshot.Plugin.Jira/Api/JiraConnector.cs` and `Greenshot.Plugin.Confluence/Api/Confluence.cs` (which use the
// Dapplo clients and a login dialog). Requests and answers are plain functions, so tests can check them without a
// server.

/// An Atlassian Cloud site with the credentials of its API token (email + token as basic authentication).
public struct AtlassianSite: Equatable, Sendable {
    public var baseURL: URL
    public var email: String
    public var apiToken: String

    /// `url` is trimmed, gets `https://` when it has no scheme and loses a trailing slash. Nil when it is empty
    /// or not a URL.
    public init?(url: String, email: String, apiToken: String) {
        var text = url.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !text.isEmpty else { return nil }
        if !text.contains("://") { text = "https://" + text }
        while text.hasSuffix("/") { text.removeLast() }
        guard let parsed = URL(string: text), parsed.host != nil else { return nil }
        baseURL = parsed
        self.email = email.trimmingCharacters(in: .whitespaces)
        self.apiToken = apiToken
    }

    public var authorizationHeader: String { HTTPSupport.basicAuthorization(user: email, password: apiToken) }

    /// A request for `path` (relative to the base URL) with the credentials and JSON accepted.
    public func request(_ method: String, path: String, query: [URLQueryItem] = []) -> URLRequest {
        var components = URLComponents(url: baseURL, resolvingAgainstBaseURL: false)!
        let base = components.path.hasSuffix("/") ? String(components.path.dropLast()) : components.path
        components.path = base + "/" + path
        components.queryItems = query.isEmpty ? nil : query
        var request = URLRequest(url: components.url!, timeoutInterval: 60)
        request.httpMethod = method
        request.setValue(authorizationHeader, forHTTPHeaderField: "Authorization")
        request.setValue("application/json", forHTTPHeaderField: "Accept")
        return request
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

    public init(key: String, summary: String) {
        self.key = key
        self.summary = summary
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

/// Jira Cloud (`/rest/api/3`): attach a file to an issue, look issues up and add a comment.
public struct JiraClient: Sendable {
    public let site: AtlassianSite
    public let http: HTTPClient

    public init(site: AtlassianSite, http: HTTPClient) {
        self.site = site
        self.http = http
    }

    /// "PROJ-123" (upper case is applied first).
    public static func isIssueKey(_ text: String) -> Bool {
        let key = text.trimmingCharacters(in: .whitespaces).uppercased()
        return key.range(of: #"^[A-Z][A-Z0-9_]*-[0-9]+$"#, options: .regularExpression) != nil
    }

    public static func normalizedKey(_ text: String) -> String {
        text.trimmingCharacters(in: .whitespaces).uppercased()
    }

    /// What to search for: an issue key finds that issue, text that looks like JQL (`=`, `~`, `ORDER BY`) is used
    /// as it is, anything else is a text search, newest first.
    public static func jql(forSearch text: String) -> String {
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        if isIssueKey(trimmed) { return "key = \(normalizedKey(trimmed))" }
        let lower = trimmed.lowercased()
        if trimmed.contains("=") || trimmed.contains("~") || lower.contains(" order by ") || lower.hasPrefix("project ") {
            return trimmed
        }
        return "text ~ \"\(escaped(trimmed))\" ORDER BY updated DESC"
    }

    /// Quotes and backslashes inside a JQL/CQL string.
    public static func escaped(_ text: String) -> String {
        text.replacingOccurrences(of: "\\", with: "\\\\").replacingOccurrences(of: "\"", with: "\\\"")
    }

    public func browseURL(for issueKey: String) -> URL {
        site.baseURL.appendingPathComponent("browse").appendingPathComponent(issueKey)
    }

    // Requests

    /// `POST /rest/api/3/issue/{key}/attachments` with the file as `multipart/form-data` (the `X-Atlassian-Token`
    /// header turns off the XSRF check, as the API requires).
    public func attachRequest(issueKey: String, file: UploadFile, boundary: String = "greenshot-" + UUID().uuidString) -> URLRequest {
        var form = MultipartForm(boundary: boundary)
        form.addFile("file", file: file)
        var request = site.request("POST", path: "rest/api/3/issue/\(issueKey)/attachments")
        request.setValue("no-check", forHTTPHeaderField: "X-Atlassian-Token")
        request.setValue(form.contentType, forHTTPHeaderField: "Content-Type")
        request.httpBody = form.finished()
        return request
    }

    /// `GET /rest/api/3/search/jql` (the endpoint that replaced `/search` in 2025; `fields` is needed, the default
    /// is the id alone).
    public func searchRequest(jql: String, maxResults: Int = 20) -> URLRequest {
        site.request("GET", path: "rest/api/3/search/jql", query: [
            URLQueryItem(name: "jql", value: jql),
            URLQueryItem(name: "maxResults", value: String(maxResults)),
            URLQueryItem(name: "fields", value: "summary"),
        ])
    }

    public func issueRequest(key: String) -> URLRequest {
        site.request("GET", path: "rest/api/3/issue/\(key)", query: [URLQueryItem(name: "fields", value: "summary")])
    }

    /// `POST /rest/api/3/issue/{key}/comment` with the text as one paragraph of Atlassian Document Format.
    public func commentRequest(issueKey: String, text: String) -> URLRequest {
        var request = site.request("POST", path: "rest/api/3/issue/\(issueKey)/comment")
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        let body: [String: Any] = ["body": [
            "type": "doc", "version": 1,
            "content": [["type": "paragraph", "content": [["type": "text", "text": text]]]],
        ]]
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
        return JiraIssue(key: key, summary: fields?["summary"] as? String ?? "")
    }

    // Calls

    public func attach(_ file: UploadFile, to issueKey: String) async throws -> [JiraAttachment] {
        try Self.attachments(fromJSON: try await HTTPSupport.send(attachRequest(issueKey: issueKey, file: file), with: http))
    }

    public func search(_ text: String, maxResults: Int = 20) async throws -> [JiraIssue] {
        let request = searchRequest(jql: Self.jql(forSearch: text), maxResults: maxResults)
        return try Self.issues(fromJSON: try await HTTPSupport.send(request, with: http))
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

/// Confluence (`/rest/api`, Cloud sites end in `/wiki`): find pages by title with CQL, attach a file to a page.
public struct ConfluenceClient: Sendable {
    public let site: AtlassianSite
    public let http: HTTPClient

    public init(site: AtlassianSite, http: HTTPClient) {
        self.site = site
        self.http = http
    }

    /// Pages whose title contains the words, last changed first. Text that already is CQL (`=`, `~`) is used as it is.
    public static func cql(forTitleSearch text: String) -> String {
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        if trimmed.contains("=") || trimmed.contains("~") { return trimmed }
        return "type = page AND title ~ \"\(JiraClient.escaped(trimmed))\" ORDER BY lastmodified DESC"
    }

    /// Upstream puts `!name!` on the clipboard after the upload: the wiki markup that shows the attachment.
    public static func wikiMarkup(for filename: String) -> String { "!\(filename)!" }

    // Requests

    /// `GET /rest/api/search?cql=…` (the CQL search stays while the v1 content endpoints go).
    public func searchRequest(cql: String, limit: Int = 20) -> URLRequest {
        site.request("GET", path: "rest/api/search", query: [
            URLQueryItem(name: "cql", value: cql),
            URLQueryItem(name: "limit", value: String(limit)),
        ])
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
    /// search); their links are made absolute with the answer's `_links.base` or the site.
    public func pages(fromJSON data: Data) throws -> [ConfluencePage] {
        let object = try HTTPSupport.json(data)
        guard let results = object["results"] as? [[String: Any]] else {
            throw UploadError.unexpectedResponse("no results in the answer")
        }
        let base = (object["_links"] as? [String: Any])?["base"] as? String
        return results.compactMap { result in
            let content = result["content"] as? [String: Any] ?? result
            guard let id = content["id"].map({ "\($0)" }), let title = content["title"] as? String else { return nil }
            if let type = content["type"] as? String, type != "page" { return nil }
            let space = (content["space"] as? [String: Any])?["name"] as? String
                ?? (result["resultGlobalContainer"] as? [String: Any])?["title"] as? String ?? ""
            let links = content["_links"] as? [String: Any]
            let url = site.url(forLink: links?["webui"] as? String, base: base)
                ?? site.url(forLink: result["url"] as? String, base: base)
                ?? site.baseURL.appendingPathComponent("pages/viewpage.action").appending(queryItem: "pageId", value: id)
            return ConfluencePage(id: id, title: title, spaceName: space, url: url)
        }
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

    public func searchPages(title: String, limit: Int = 20) async throws -> [ConfluencePage] {
        try pages(fromJSON: try await HTTPSupport.send(searchRequest(cql: Self.cql(forTitleSearch: title), limit: limit), with: http))
    }

    public func attach(_ file: UploadFile, toPage pageID: String, comment: String? = nil) async throws -> [ConfluenceAttachment] {
        try attachments(fromJSON: try await HTTPSupport.send(attachRequest(pageID: pageID, file: file, comment: comment), with: http))
    }
}

extension URL {
    func appending(queryItem name: String, value: String) -> URL {
        var components = URLComponents(url: self, resolvingAgainstBaseURL: false)!
        components.queryItems = (components.queryItems ?? []) + [URLQueryItem(name: name, value: value)]
        return components.url ?? self
    }
}
