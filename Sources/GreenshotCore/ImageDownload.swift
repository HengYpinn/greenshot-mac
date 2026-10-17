// Greenshot for Mac (Community) - an unofficial macOS port of Greenshot
// Copyright (C) 2026 Greenshot for Mac (Community) contributors
// Based on Greenshot, Copyright (C) 2007-2026 Thomas Braun, Jens Klingen, Robin Krom
// SPDX-License-Identifier: GPL-3.0-or-later

import Foundation

/// Downloads of pictures named in pasted HTML or dropped links (upstream `NetworkHelper.DownloadImageAsync`). The page
/// that put the link on the clipboard decides what is fetched, so the download is limited: http and https only, at
/// most `maxBytes` (counted while it arrives, not after), at most `resourceTimeout` seconds in all, a session without
/// cookies or cache (the Jira and Confluence sign-ins are never sent along), and only the first `maxURLs` links tried.
public enum ImageDownload {
    public static let maxBytes = 50 * 1024 * 1024
    public static let maxURLs = 5
    static let requestTimeout: TimeInterval = 15
    static let resourceTimeout: TimeInterval = 45

    static let session: URLSession = {
        let configuration = URLSessionConfiguration.ephemeral
        configuration.timeoutIntervalForRequest = requestTimeout
        configuration.timeoutIntervalForResource = resourceTimeout
        configuration.httpShouldSetCookies = false
        configuration.httpCookieAcceptPolicy = .never
        configuration.urlCache = nil
        return URLSession(configuration: configuration)
    }()

    /// The body at `url`; nil for another scheme, an error status, a body over `maxBytes` or a timeout.
    public static func data(from url: URL, session: URLSession? = nil, maxBytes: Int = maxBytes) async -> Data? {
        guard let scheme = url.scheme?.lowercased(), scheme == "http" || scheme == "https" else { return nil }
        var request = URLRequest(url: url, timeoutInterval: requestTimeout)
        request.setValue("image/*", forHTTPHeaderField: "Accept")
        guard let (bytes, response) = try? await (session ?? Self.session).bytes(for: request) else { return nil }
        if let http = response as? HTTPURLResponse, !(200..<300).contains(http.statusCode) { return nil }
        if response.expectedContentLength > Int64(maxBytes) { return nil }
        var data = Data()
        if response.expectedContentLength > 0 { data.reserveCapacity(Int(response.expectedContentLength)) }
        do {
            for try await byte in bytes {
                data.append(byte)
                if data.count > maxBytes { return nil }
            }
        } catch {
            return nil
        }
        return data
    }
}
