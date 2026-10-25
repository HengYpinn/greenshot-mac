// Greenshot for Mac (Community) - an unofficial macOS port of Greenshot
// Copyright (C) 2026 Greenshot for Mac (Community) contributors
// Based on Greenshot, Copyright (C) 2007-2026 Thomas Braun, Jens Klingen, Robin Krom
// SPDX-License-Identifier: GPL-3.0-or-later

import CryptoKit
import Foundation

/// The token or password of Jira or Confluence in the secret store, kept in one entry with the host it was saved for
/// (`entryMarker`, the host, the secret): a token is only given to that host, so changing the URL in the settings (or
/// someone else changing it) doesn't send it to another server. The host is read and written with the secret, never on
/// its own. Older versions kept it in a second entry, `<key>.host`: their token counts as saved without a host
/// (`Lookup.unbound`, asked about once), and that entry can only refuse another host, never grant one. Upstream keeps
/// the password in its ini file next to the URL.
public struct AtlassianSecrets: Sendable {
    public let store: SecretStore

    /// The stored secret, seen from a site on a host.
    public enum Lookup: Equatable, Sendable {
        /// Saved for this host: it may go there.
        case bound(String)
        /// Saved without a host (by an older version, or before the URL was entered): Settings show it, but it goes to
        /// a server only after the user allowed it for that host (`confirmUnbound`).
        case unbound(String)
        /// None, or saved for another host.
        case nothing
    }

    /// The user's answer about a secret saved without a host (`confirmUnbound`).
    public enum Confirmation: Equatable, Sendable {
        /// It isn't one: bound, for another host, or none.
        case nothingToAsk
        /// Allowed, and saved for the host from now on.
        case allowed(String)
        /// Not allowed (or the secret changed while the user was asked): it stays as it was.
        case declined
    }

    /// The first line of an entry; the host (empty for none) and the secret follow on lines of their own. An older
    /// version's token or password, which is the whole entry, doesn't start with it.
    static let entryMarker = "greenshot-mac.atlassian-secret.v1"

    public init(store: SecretStore) {
        self.store = store
    }

    static func hostKey(_ key: String) -> String {
        key + ".host"
    }

    static func entry(_ secret: String, host: String?) -> String {
        [entryMarker, host ?? "", secret].joined(separator: "\n")
    }

    /// The host (nil for none) and the secret of an entry; nil for an older version's token or password.
    static func parse(_ entry: String) -> (host: String?, secret: String)? {
        let lines = entry.split(separator: "\n", maxSplits: 2, omittingEmptySubsequences: false)
        guard lines.count == 3, lines[0] == entryMarker else { return nil }
        return (lines[1].isEmpty ? nil : String(lines[1]), String(lines[2]))
    }

    /// The secret of `key` for a site on `host`. Reading never changes the store.
    public func lookup(_ key: String, host: String?) throws -> Lookup {
        guard let stored = try store.secret(for: key), !stored.isEmpty else { return .nothing }
        if let entry = Self.parse(stored) {
            guard !entry.secret.isEmpty else { return .nothing }
            guard let saved = entry.host else { return .unbound(entry.secret) }
            guard let host, saved.caseInsensitiveCompare(host) == .orderedSame else { return .nothing }
            return .bound(entry.secret)
        }
        // An older version's: its separate host entry may only refuse another host, never grant one (`confirmUnbound`).
        if let saved = try store.secret(for: Self.hostKey(key)), !saved.isEmpty,
           saved.caseInsensitiveCompare(host ?? "") != .orderedSame {
            return .nothing
        }
        return .unbound(stored)
    }

    /// What Settings show for a site on `host`: the secret saved for it or without a host; nil when there is none or it
    /// was saved for another host.
    public func secret(for key: String, host: String?) throws -> String? {
        switch try lookup(key, host: host) {
        case .bound(let secret), .unbound(let secret): return secret
        case .nothing: return nil
        }
    }

    /// The secret that may go to a site on `host`: only one saved for that host.
    public func boundSecret(for key: String, host: String?) throws -> String? {
        guard case .bound(let secret) = try lookup(key, host: host) else { return nil }
        return secret
    }

    /// Before a secret saved without a host goes to `host`: `ask` asks the user (only then), and an allowed secret is
    /// saved for `host` from now on.
    public func confirmUnbound(_ key: String, host: String, ask: () throws -> Bool) throws -> Confirmation {
        guard case .unbound(let secret) = try lookup(key, host: host) else { return .nothingToAsk }
        guard try ask() else { return .declined }
        // The answer is about the secret that was there when the question came up.
        guard case .unbound(secret) = try lookup(key, host: host) else { return .declined }
        try setSecret(secret, for: key, host: host)
        return .allowed(secret)
    }

    /// Keeps `secret` for a site on `host` (nil while the URL has none: it is then asked about at its first use); nil
    /// or empty removes it.
    public func setSecret(_ secret: String?, for key: String, host: String?) throws {
        let kept = secret.flatMap { $0.isEmpty ? nil : $0 }
        let bound = host.flatMap { $0.isEmpty ? nil : $0.lowercased() }
        try store.setSecret(kept.map { Self.entry($0, host: bound) }, for: key)
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
