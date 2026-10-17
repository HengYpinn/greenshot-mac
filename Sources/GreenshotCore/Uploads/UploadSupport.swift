// Greenshot for Mac (Community) - an unofficial macOS port of Greenshot
// Copyright (C) 2026 Greenshot for Mac (Community) contributors
// Based on Greenshot, Copyright (C) 2007-2026 Thomas Braun, Jens Klingen, Robin Krom
// SPDX-License-Identifier: GPL-3.0-or-later

import Foundation

// What the upload destinations (Jira, Confluence, Box, Dropbox) share: the network and secret storage seams the
// tests replace, the encoded file, multipart bodies and the errors.

/// The network: `URLSession` in the app, a stub in the tests.
public protocol HTTPClient: Sendable {
    func data(for request: URLRequest) async throws -> (Data, URLResponse)
}

extension URLSession: HTTPClient {}

/// Where API tokens, client secrets and OAuth tokens live: the Keychain in the app, memory in the tests. Never
/// the settings (UserDefaults).
public protocol SecretStore: Sendable {
    func secret(for key: String) throws -> String?
    /// nil removes the secret.
    func setSecret(_ value: String?, for key: String) throws
}

/// The test double of the secret store, also usable as a cache.
public final class InMemorySecretStore: SecretStore, @unchecked Sendable {
    private let lock = NSLock()
    private var values: [String: String]

    public init(_ values: [String: String] = [:]) {
        self.values = values
    }

    public func secret(for key: String) throws -> String? {
        lock.lock()
        defer { lock.unlock() }
        return values[key]
    }

    public func setSecret(_ value: String?, for key: String) throws {
        lock.lock()
        defer { lock.unlock() }
        values[key] = value
    }

    public var keys: [String] {
        lock.lock()
        defer { lock.unlock() }
        return values.keys.sorted()
    }
}

/// The formats an upload can use (upstream `UploadFormat`: png or jpg).
public enum UploadFormat: String, Codable, CaseIterable, Sendable {
    case png, jpg

    public var imageFormat: ImageFormat {
        switch self {
        case .png: return .png
        case .jpg: return .jpg
        }
    }

    public var mimeType: String {
        switch self {
        case .png: return "image/png"
        case .jpg: return "image/jpeg"
        }
    }

    public var fileExtension: String { rawValue }
    public var displayName: String { imageFormat.displayName }
}

/// An encoded screenshot on its way to a server.
public struct UploadFile: Equatable, Sendable {
    public var name: String
    public var data: Data
    public var mimeType: String

    public init(name: String, data: Data, mimeType: String) {
        self.name = name
        self.data = data
        self.mimeType = mimeType
    }

    /// `name` with the format's extension when it has none (or another one).
    public static func fileName(_ base: String, format: UploadFormat) -> String {
        var name = base.trimmingCharacters(in: .whitespacesAndNewlines)
        if name.isEmpty { name = "Screenshot" }
        let ext = (name as NSString).pathExtension.lowercased()
        if ext == format.fileExtension || (format == .jpg && ext == "jpeg") { return name }
        if ImageFormat(fileExtension: ext) != nil { name = (name as NSString).deletingPathExtension }
        return name + "." + format.fileExtension
    }
}

public enum UploadError: Error, LocalizedError, Equatable {
    /// A setting is missing (its name).
    case notConfigured(String)
    case invalidURL(String)
    /// The server answered with an error status; `message` is what it said, when it said something readable.
    case http(status: Int, message: String)
    case unexpectedResponse(String)
    /// Box or Dropbox without a stored token and no way to ask.
    case notSignedIn(String)
    case cancelled
    case oauth(String)

    public var errorDescription: String? {
        switch self {
        case .notConfigured(let what):
            return String(localized: "\(what) is not set up. Add it in Settings › Destinations.", comment: "%@ names a setting, e.g. \"The Dropbox app key\"")
        case .invalidURL(let url): return String(localized: "“\(url)” is not a valid URL.")
        case .http(let status, let message):
            return message.isEmpty ? String(localized: "The server answered with HTTP \(status).") : "HTTP \(status): \(message)"
        case .unexpectedResponse(let detail):
            return String(localized: "Unexpected answer from the server: \(detail)", comment: "%@ is a technical detail in English")
        case .notSignedIn(let service):
            return String(localized: "Not signed in to \(service). Sign in under Settings › Destinations.", comment: "%@ is a service: Box or Dropbox")
        case .cancelled: return String(localized: "Cancelled.")
        case .oauth(let detail): return detail
        }
    }
}

/// A `multipart/form-data` body (upstream `NetworkHelper.CreateMultipartContent`). The boundary can be fixed for tests.
public struct MultipartForm: Sendable {
    public let boundary: String
    private var body = Data()

    public init(boundary: String = "greenshot-" + UUID().uuidString) {
        self.boundary = boundary
    }

    public var contentType: String { "multipart/form-data; boundary=\(boundary)" }

    public mutating func addField(_ name: String, value: String, contentType: String? = nil) {
        append("--\(boundary)\r\nContent-Disposition: form-data; name=\"\(name)\"\r\n")
        if let contentType { append("Content-Type: \(contentType)\r\n") }
        append("\r\n\(value)\r\n")
    }

    public mutating func addFile(_ name: String, file: UploadFile) {
        append("--\(boundary)\r\nContent-Disposition: form-data; name=\"\(name)\"; filename=\"\(file.name.replacingOccurrences(of: "\"", with: "'"))\"\r\n")
        append("Content-Type: \(file.mimeType)\r\n\r\n")
        body.append(file.data)
        append("\r\n")
    }

    /// The body with the closing boundary.
    public func finished() -> Data {
        var data = body
        data.append(Data("--\(boundary)--\r\n".utf8))
        return data
    }

    private mutating func append(_ text: String) {
        body.append(Data(text.utf8))
    }
}

/// Helpers the clients share.
public enum HTTPSupport {
    /// `user:password` as a Basic Authorization header value.
    public static func basicAuthorization(user: String, password: String) -> String {
        "Basic " + Data("\(user):\(password)".utf8).base64EncodedString()
    }

    /// Sends the request and returns the body of a 2xx answer; anything else is an `UploadError.http` with the
    /// server's message.
    public static func send(_ request: URLRequest, with http: HTTPClient) async throws -> Data {
        let (data, response) = try await http.data(for: request)
        let status = (response as? HTTPURLResponse)?.statusCode ?? 0
        guard (200..<300).contains(status) else {
            throw UploadError.http(status: status, message: errorMessage(in: data, status: status))
        }
        return data
    }

    /// The readable part of an error answer: Jira's `errorMessages`/`errors`, Confluence's `message`, Box's
    /// `message`, OAuth's `error_description`, Dropbox's `error_summary`, else the start of the text.
    public static func errorMessage(in data: Data, status: Int) -> String {
        if let object = try? JSONSerialization.jsonObject(with: data) as? [String: Any] {
            var parts: [String] = []
            if let messages = object["errorMessages"] as? [String] { parts += messages }
            if let errors = object["errors"] as? [String: Any] {
                parts += errors.keys.sorted().compactMap { key in (errors[key] as? String).map { "\(key): \($0)" } }
            }
            for key in ["message", "error_description", "error_summary"] {
                if let text = object[key] as? String, !text.isEmpty { parts.append(text) }
            }
            if parts.isEmpty, let error = object["error"] as? String { parts.append(error) }
            return parts.isEmpty ? HTTPURLResponse.localizedString(forStatusCode: status) : parts.joined(separator: " ")
        }
        let text = String(decoding: data.prefix(300), as: UTF8.self).trimmingCharacters(in: .whitespacesAndNewlines)
        if text.isEmpty || text.hasPrefix("<") {
            return HTTPURLResponse.localizedString(forStatusCode: status)
        }
        return text
    }

    public static func json(_ data: Data) throws -> [String: Any] {
        guard let object = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else {
            throw UploadError.unexpectedResponse("not a JSON object")
        }
        return object
    }

    /// `application/x-www-form-urlencoded` (RFC 3986 unreserved characters are left as they are).
    public static func formBody(_ fields: [(String, String)]) -> Data {
        var allowed = CharacterSet.alphanumerics
        allowed.insert(charactersIn: "-._~")
        let text = fields.map { key, value in
            let k = key.addingPercentEncoding(withAllowedCharacters: allowed) ?? key
            let v = value.addingPercentEncoding(withAllowedCharacters: allowed) ?? value
            return "\(k)=\(v)"
        }.joined(separator: "&")
        return Data(text.utf8)
    }

    /// A JSON object text for simple values (strings, numbers, booleans, nested objects), keys sorted, every
    /// non-ASCII character escaped: the form the `Dropbox-API-Arg` header needs.
    public static func asciiJSON(_ object: [String: Any]) -> String {
        func encode(_ value: Any) -> String {
            switch value {
            case let text as String: return "\"" + escape(text) + "\""
            case let flag as Bool: return flag ? "true" : "false"
            case let number as Int: return String(number)
            case let number as Double: return String(number)
            case let nested as [String: Any]: return asciiJSON(nested)
            case let list as [Any]: return "[" + list.map(encode).joined(separator: ",") + "]"
            default: return "null"
            }
        }
        func escape(_ text: String) -> String {
            var out = ""
            for unit in text.utf16 {
                switch unit {
                case 0x22: out += "\\\""
                case 0x5C: out += "\\\\"
                case 0x0A: out += "\\n"
                case 0x0D: out += "\\r"
                case 0x09: out += "\\t"
                case 0x20...0x7E: out.append(Character(UnicodeScalar(unit)!))
                default: out += String(format: "\\u%04x", unit)
                }
            }
            return out
        }
        let members = object.keys.sorted().map { "\"\(escape($0))\":\(encode(object[$0]!))" }
        return "{" + members.joined(separator: ",") + "}"
    }
}
