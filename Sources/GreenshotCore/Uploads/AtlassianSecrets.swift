// Greenshot for Mac (Community) - an unofficial macOS port of Greenshot
// Copyright (C) 2026 Greenshot for Mac (Community) contributors
// Based on Greenshot, Copyright (C) 2007-2026 Thomas Braun, Jens Klingen, Robin Krom
// SPDX-License-Identifier: GPL-3.0-or-later

import CryptoKit
import Foundation

/// The server a Jira or Confluence token or password belongs to: the origin of the site's URL, i.e. its scheme, host and
/// port (the scheme's default when the URL has none), lower case. A token saved for https://jira.example.com goes neither
/// to http://jira.example.com nor to another port of that host; another path or the case of the host don't matter.
public struct AtlassianServer: Hashable, Sendable {
    /// `https://jira.example.com:443`: kept with the secret, and shown in the question before a secret kept without
    /// its server goes there.
    public let origin: String
    /// The host alone, lower case: for the host entry of older versions.
    let host: String

    /// The server of a site's URL; nil without a scheme or a plain host (`AtlassianSite.isPlainHost`).
    public init?(_ url: URL) {
        guard let host = url.host, AtlassianSite.isPlainHost(host), let origin = AtlassianSite.origin(of: url) else { return nil }
        self.origin = origin
        self.host = host.lowercased()
    }

    /// The server of a Jira or Confluence URL as the settings hold it (see `AtlassianSite.init(url:login:user:secret:)`);
    /// nil when it isn't one.
    public init?(url: String) {
        guard let site = AtlassianSite(url: url, login: .serverToken, user: "", secret: "") else { return nil }
        self.init(site.baseURL)
    }
}

extension AtlassianSite {
    /// The server the site's token or password belongs to.
    public var server: AtlassianServer? { AtlassianServer(baseURL) }
}

/// The token or password of Jira or Confluence in the secret store, kept in one entry with the server it was saved for
/// (`entryMarker`, the server's origin, the secret): a token is only given to that server (address and port), so
/// changing the URL in the settings (or someone else changing it) doesn't send it to another one. The server is read
/// and written with the secret, never on its own. Older versions kept the host in a second entry, `<key>.host`: their
/// token counts as saved without a server (`Lookup.unbound`: asked about at each use until the user allows it), and
/// that entry can only refuse another host, never grant one. Upstream keeps the password in its ini file next to the URL.
public struct AtlassianSecrets: Sendable {
    public let store: SecretStore

    /// The stored secret, seen from a site's server.
    public enum Lookup: Equatable, Sendable {
        /// Saved for this server: it may go there.
        case bound(String)
        /// Saved without a server (by an older version, or before the URL was entered): Settings show it, but it goes
        /// to a server only after the user allowed it for that server (`confirmUnbound`).
        case unbound(String)
        /// None, or saved for another server.
        case nothing
    }

    /// The user's answer about a secret saved without a server (`confirmUnbound`).
    public enum Confirmation: Equatable, Sendable {
        /// It isn't one: bound, for another server, or none.
        case nothingToAsk
        /// Allowed, and saved for the server from now on.
        case allowed(String)
        /// Not allowed (or the secret changed while the user was asked): it stays as it was.
        case declined
    }

    /// A site with the secret that may go to its server (`site(_:key:)`).
    public struct SiteSecret: Equatable, Sendable {
        /// The site with the secret saved for its server; none (empty) when there isn't one.
        public var site: AtlassianSite
        /// A secret kept without a server: it goes to the site's server only after the user allowed it there
        /// (`confirmUnbound`).
        public var unbound: String?

        public init(site: AtlassianSite, unbound: String? = nil) {
            self.site = site
            self.unbound = unbound
        }
    }

    /// The URL the secret can't be kept for: its server has a line break or another control character.
    struct UnusableServerError: LocalizedError {
        let origin: String

        var errorDescription: String? { String(localized: "“\(origin)” is not a valid URL.") }
    }

    /// The first line of an entry; the server's origin (empty for none) and the secret follow on lines of their own. An
    /// older version's token or password, which is the whole entry, doesn't start with it.
    static let entryMarker = "greenshot-mac.atlassian-secret.v1"

    public init(store: SecretStore) {
        self.store = store
    }

    static func hostKey(_ key: String) -> String {
        key + ".host"
    }

    /// The entry of `secret` for the server `origin` (nil: none); nil when the origin has a line break or another
    /// control character, which would move the secret's line.
    static func entry(_ secret: String, origin: String?) -> String? {
        if let origin, origin.unicodeScalars.contains(where: CharacterSet.controlCharacters.contains) { return nil }
        return [entryMarker, origin ?? "", secret].joined(separator: "\n")
    }

    /// The server's origin (nil for none) and the secret of an entry; nil for an older version's token or password.
    static func parse(_ entry: String) -> (origin: String?, secret: String)? {
        let lines = entry.split(separator: "\n", maxSplits: 2, omittingEmptySubsequences: false)
        guard lines.count == 3, lines[0] == entryMarker else { return nil }
        return (lines[1].isEmpty ? nil : String(lines[1]), String(lines[2]))
    }

    /// The secret of `key` for a site on `server` (nil while the URL has none). Reading never changes the store.
    public func lookup(_ key: String, server: AtlassianServer?) throws -> Lookup {
        guard let stored = try store.secret(for: key), !stored.isEmpty else { return .nothing }
        if let entry = Self.parse(stored) {
            guard !entry.secret.isEmpty else { return .nothing }
            guard let saved = entry.origin else { return .unbound(entry.secret) }
            // The whole origin: http:// or another port of the same host is another server.
            guard let server, saved == server.origin else { return .nothing }
            return .bound(entry.secret)
        }
        // An older version's: its separate host entry may only refuse another host, never grant one (`confirmUnbound`).
        if let saved = try store.secret(for: Self.hostKey(key)), !saved.isEmpty,
           saved.caseInsensitiveCompare(server?.host ?? "") != .orderedSame {
            return .nothing
        }
        return .unbound(stored)
    }

    /// What Settings show for a site on `server`: the secret saved for it or without a server; nil when there is none
    /// or it was saved for another server.
    public func secret(for key: String, server: AtlassianServer?) throws -> String? {
        switch try lookup(key, server: server) {
        case .bound(let secret), .unbound(let secret): return secret
        case .nothing: return nil
        }
    }

    /// The secret that may go to a site on `server`: only one saved for that server.
    public func boundSecret(for key: String, server: AtlassianServer?) throws -> String? {
        guard case .bound(let secret) = try lookup(key, server: server) else { return nil }
        return secret
    }

    /// `site` with the secret that may go to its server: only one saved for that server (`.bound`), none otherwise; a
    /// secret kept without a server comes in `unbound`, for the question (`confirmUnbound`). Uploads, recipe steps, the
    /// connection test and the destination menu take their site from here.
    public func site(_ site: AtlassianSite, key: String) throws -> SiteSecret {
        switch try lookup(key, server: site.server) {
        case .bound(let secret): return SiteSecret(site: site.with(user: site.user, secret: secret))
        case .unbound(let secret): return SiteSecret(site: site.with(user: site.user, secret: ""), unbound: secret)
        case .nothing: return SiteSecret(site: site.with(user: site.user, secret: ""))
        }
    }

    /// Before a secret saved without a server goes to `server`: `ask` asks the user (only then), and an allowed secret
    /// is saved for `server` from now on. `known` is a lookup made just before (`site(_:key:)`), so the store isn't read
    /// twice before the question; it is read again after the answer, which is about the secret that was there when the
    /// question came up.
    public func confirmUnbound(_ key: String, server: AtlassianServer, known: Lookup? = nil,
                               ask: () throws -> Bool) throws -> Confirmation {
        let current = try known ?? lookup(key, server: server)
        guard case .unbound(let secret) = current else { return .nothingToAsk }
        guard try ask() else { return .declined }
        switch try lookup(key, server: server) {
        case .unbound(secret):
            try setSecret(secret, for: key, server: server)
            return .allowed(secret)
        case .bound(secret):
            // Allowed for this server meanwhile (another question, or typed in Settings): the same secret.
            return .allowed(secret)
        default:
            return .declined
        }
    }

    /// Keeps `secret` for a site on `server` (nil while the URL has none: it is then asked about at its uses); nil or
    /// empty removes it.
    public func setSecret(_ secret: String?, for key: String, server: AtlassianServer?) throws {
        if let kept = secret.flatMap({ $0.isEmpty ? nil : $0 }) {
            guard let entry = Self.entry(kept, origin: server?.origin) else {
                throw UnusableServerError(origin: server?.origin ?? "")
            }
            try store.setSecret(entry, for: key)
        } else {
            try store.setSecret(nil, for: key)
        }
        // The host entry of older versions.
        try store.setSecret(nil, for: Self.hostKey(key))
    }
}

/// The Server / Data Center password logins checked in this session (upstream logs in once per session). A login is
/// kept with a hash of its password, so another password (changed in Settings) is checked again; an upload the server
/// refuses forgets it (the password changed on the server), so the next upload checks it and asks for a new one.
public struct VerifiedLogins: Sendable {
    private var keys: Set<String> = []

    public init() {}

    private static func key(_ service: String, _ site: AtlassianSite) -> String {
        let password = Data(SHA256.hash(data: Data(site.secret.utf8))).base64EncodedString()
        return "\(service)|\(site.baseURL.absoluteString)|\(site.user)|\(password)"
    }

    public func contains(_ site: AtlassianSite, service: String) -> Bool {
        keys.contains(Self.key(service, site))
    }

    public mutating func insert(_ site: AtlassianSite, service: String) {
        keys.insert(Self.key(service, site))
    }

    /// After an upload to `site` failed with `error`: a refused login (401, 403) is forgotten.
    public mutating func uploadFailed(_ error: Error, site: AtlassianSite, service: String) {
        guard Self.isLoginError(error) else { return }
        keys.remove(Self.key(service, site))
    }

    /// 401 and 403 are a wrong user name or password (or a CAPTCHA the server wants solved in the browser first).
    public static func isLoginError(_ error: Error) -> Bool {
        if case UploadError.http(let status, _) = error { return status == 401 || status == 403 }
        return false
    }
}
