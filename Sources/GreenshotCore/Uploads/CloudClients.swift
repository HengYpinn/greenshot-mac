// Greenshot for Mac (Community) - an unofficial macOS port of Greenshot
// Copyright (C) 2026 Greenshot for Mac (Community) contributors
// Based on Greenshot, Copyright (C) 2007-2026 Thomas Braun, Jens Klingen, Robin Krom
// SPDX-License-Identifier: GPL-3.0-or-later

import Foundation

// Box and Dropbox uploads: the logic of upstream `Greenshot.Plugin.Box/Api/BoxUtils.cs` and
// `Greenshot.Plugin.Dropbox/Api/DropboxUtils.cs`. The access token comes from an `OAuthClient`.

/// What an upload to Box or Dropbox ends with: where the file is, and a link to it (shared when asked for).
public struct CloudUpload: Equatable, Sendable {
    public var fileID: String
    public var path: String
    /// A page or shared link for the file.
    public var link: URL
    public var isSharedLink: Bool

    public init(fileID: String, path: String, link: URL, isSharedLink: Bool) {
        self.fileID = fileID
        self.path = path
        self.link = link
        self.isSharedLink = isSharedLink
    }
}

/// Box (`api.box.com/2.0`).
public struct BoxClient: Sendable {
    public static let uploadURL = URL(string: "https://upload.box.com/api/2.0/files/content")!
    public static let filesURL = URL(string: "https://api.box.com/2.0/files")!
    public let http: HTTPClient

    public init(http: HTTPClient) {
        self.http = http
    }

    /// `POST /files/content`: the `attributes` part (name, parent folder, "0" is the root) has to come before the file.
    public static func uploadRequest(file: UploadFile, folderID: String, accessToken: String,
                                     boundary: String = "greenshot-" + UUID().uuidString) -> URLRequest {
        var form = MultipartForm(boundary: boundary)
        let folder = folderID.trimmingCharacters(in: .whitespaces)
        let attributes: [String: Any] = ["name": file.name, "parent": ["id": folder.isEmpty ? "0" : folder]]
        form.addField("attributes", value: HTTPSupport.asciiJSON(attributes))
        form.addFile("file", file: file)
        var request = URLRequest(url: uploadURL, timeoutInterval: 120)
        request.httpMethod = "POST"
        request.setValue("Bearer \(accessToken)", forHTTPHeaderField: "Authorization")
        request.setValue(form.contentType, forHTTPHeaderField: "Content-Type")
        request.httpBody = form.finished()
        return request
    }

    /// The id of the uploaded file (`entries[0].id`).
    public static func uploadedFileID(fromJSON data: Data) throws -> String {
        let object = try HTTPSupport.json(data)
        guard let entry = (object["entries"] as? [[String: Any]])?.first, let id = entry["id"].map({ "\($0)" }) else {
            throw UploadError.unexpectedResponse("no file in Box's answer")
        }
        return id
    }

    /// `PUT /files/{id}?fields=shared_link` turning on an open shared link.
    public static func sharedLinkRequest(fileID: String, accessToken: String) -> URLRequest {
        var request = URLRequest(url: filesURL.appendingPathComponent(fileID).appending(queryItem: "fields", value: "shared_link"), timeoutInterval: 60)
        request.httpMethod = "PUT"
        request.setValue("Bearer \(accessToken)", forHTTPHeaderField: "Authorization")
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.httpBody = Data(#"{"shared_link":{"access":"open"}}"#.utf8)
        return request
    }

    public static func sharedLink(fromJSON data: Data) throws -> URL {
        let object = try HTTPSupport.json(data)
        guard let link = (object["shared_link"] as? [String: Any])?["url"] as? String, let url = URL(string: link) else {
            throw UploadError.unexpectedResponse("no shared link in Box's answer")
        }
        return url
    }

    /// The file in the Box web app.
    public static func fileURL(id: String) -> URL {
        URL(string: "https://app.box.com/file/\(id)")!
    }

    public func upload(_ file: UploadFile, folderID: String, sharedLink: Bool, accessToken: String) async throws -> CloudUpload {
        let data = try await HTTPSupport.send(Self.uploadRequest(file: file, folderID: folderID, accessToken: accessToken), with: http)
        let id = try Self.uploadedFileID(fromJSON: data)
        var result = CloudUpload(fileID: id, path: file.name, link: Self.fileURL(id: id), isSharedLink: false)
        if sharedLink {
            let answer = try await HTTPSupport.send(Self.sharedLinkRequest(fileID: id, accessToken: accessToken), with: http)
            result.link = try Self.sharedLink(fromJSON: answer)
            result.isSharedLink = true
        }
        return result
    }
}

/// Dropbox (`api.dropboxapi.com/2`).
public struct DropboxClient: Sendable {
    public static let uploadURL = URL(string: "https://content.dropboxapi.com/2/files/upload")!
    public static let createSharedLinkURL = URL(string: "https://api.dropboxapi.com/2/sharing/create_shared_link_with_settings")!
    public static let listSharedLinksURL = URL(string: "https://api.dropboxapi.com/2/sharing/list_shared_links")!
    public let http: HTTPClient

    public init(http: HTTPClient) {
        self.http = http
    }

    /// `/folder/name.png` from a folder setting ("", "/", "Screenshots", "/a/b/") and the file name.
    public static func path(folder: String, filename: String) -> String {
        let parts = folder.split(separator: "/").map { $0.trimmingCharacters(in: .whitespaces) }.filter { !$0.isEmpty }
        return "/" + (parts + [filename.replacingOccurrences(of: "/", with: "-")]).joined(separator: "/")
    }

    /// `POST /files/upload` with the arguments in the `Dropbox-API-Arg` header (ASCII only) and the bytes as the body.
    public static func uploadRequest(file: UploadFile, folder: String, accessToken: String) -> URLRequest {
        var request = URLRequest(url: uploadURL, timeoutInterval: 120)
        request.httpMethod = "POST"
        request.setValue("Bearer \(accessToken)", forHTTPHeaderField: "Authorization")
        request.setValue("application/octet-stream", forHTTPHeaderField: "Content-Type")
        let arguments: [String: Any] = ["path": path(folder: folder, filename: file.name), "mode": "add", "autorename": true, "mute": true]
        request.setValue(HTTPSupport.asciiJSON(arguments), forHTTPHeaderField: "Dropbox-API-Arg")
        request.httpBody = file.data
        return request
    }

    /// The id and path of the uploaded file.
    public static func uploaded(fromJSON data: Data) throws -> (id: String, path: String) {
        let object = try HTTPSupport.json(data)
        guard let id = object["id"] as? String, let path = object["path_display"] as? String ?? object["path_lower"] as? String else {
            throw UploadError.unexpectedResponse("no file in Dropbox's answer")
        }
        return (id, path)
    }

    public static func createSharedLinkRequest(path: String, accessToken: String) -> URLRequest {
        jsonRequest(createSharedLinkURL, body: ["path": path], accessToken: accessToken)
    }

    public static func listSharedLinksRequest(path: String, accessToken: String) -> URLRequest {
        jsonRequest(listSharedLinksURL, body: ["path": path, "direct_only": true], accessToken: accessToken)
    }

    private static func jsonRequest(_ url: URL, body: [String: Any], accessToken: String) -> URLRequest {
        var request = URLRequest(url: url, timeoutInterval: 60)
        request.httpMethod = "POST"
        request.setValue("Bearer \(accessToken)", forHTTPHeaderField: "Authorization")
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.httpBody = Data(HTTPSupport.asciiJSON(body).utf8)
        return request
    }

    /// The `url` of a created link, or the first of a list of links.
    public static func sharedLink(fromJSON data: Data) throws -> URL {
        let object = try HTTPSupport.json(data)
        let text = object["url"] as? String ?? ((object["links"] as? [[String: Any]])?.first?["url"] as? String)
        guard let text, let url = URL(string: text) else { throw UploadError.unexpectedResponse("no shared link in Dropbox's answer") }
        return url
    }

    /// Dropbox answers 409 `shared_link_already_exists` when the file has a link already.
    public static func isLinkExistsError(_ error: Error) -> Bool {
        if case UploadError.http(let status, let message) = error { return status == 409 && message.contains("shared_link_already_exists") }
        return false
    }

    /// The file in the Dropbox web app.
    public static func homeURL(path: String) -> URL {
        let folder = (path as NSString).deletingLastPathComponent
        var components = URLComponents(string: "https://www.dropbox.com/home" + folder)!
        components.queryItems = [URLQueryItem(name: "preview", value: (path as NSString).lastPathComponent)]
        return components.url!
    }

    public func upload(_ file: UploadFile, folder: String, sharedLink: Bool, accessToken: String) async throws -> CloudUpload {
        let data = try await HTTPSupport.send(Self.uploadRequest(file: file, folder: folder, accessToken: accessToken), with: http)
        let uploaded = try Self.uploaded(fromJSON: data)
        var result = CloudUpload(fileID: uploaded.id, path: uploaded.path, link: Self.homeURL(path: uploaded.path), isSharedLink: false)
        if sharedLink {
            do {
                let answer = try await HTTPSupport.send(Self.createSharedLinkRequest(path: uploaded.path, accessToken: accessToken), with: http)
                result.link = try Self.sharedLink(fromJSON: answer)
            } catch where Self.isLinkExistsError(error) {
                let answer = try await HTTPSupport.send(Self.listSharedLinksRequest(path: uploaded.path, accessToken: accessToken), with: http)
                result.link = try Self.sharedLink(fromJSON: answer)
            }
            result.isSharedLink = true
        }
        return result
    }
}
