// Greenshot for Mac (Community) - an unofficial macOS port of Greenshot
// Copyright (C) 2026 Greenshot for Mac (Community) contributors
// Based on Greenshot, Copyright (C) 2007-2026 Thomas Braun, Jens Klingen, Robin Krom
// SPDX-License-Identifier: GPL-3.0-or-later

import Foundation

/// The token or password of Jira or Confluence in the secret store, with the host it was saved for (a second entry,
/// `<key>.host`): a token is only given to that host, so changing the URL in the settings (or someone else changing
/// it) doesn't send it to another server. Upstream keeps the password in its ini file next to the URL.
public struct AtlassianSecrets: Sendable {
    public let store: SecretStore

    public init(store: SecretStore) {
        self.store = store
    }

    static func hostKey(_ key: String) -> String {
        key + ".host"
    }

    /// The secret of `key` for a site on `host`; nil when there is none or it was saved for another host. A secret
    /// saved without a host (by an older version, or before the URL was entered) goes with any host, and with `claim`
    /// (an upload, a connection test) it is bound to `host` from then on.
    public func secret(for key: String, host: String?, claim: Bool = false) throws -> String? {
        guard let secret = try store.secret(for: key), !secret.isEmpty else { return nil }
        guard let saved = try store.secret(for: Self.hostKey(key)), !saved.isEmpty else {
            if claim, let host, !host.isEmpty { try store.setSecret(host.lowercased(), for: Self.hostKey(key)) }
            return secret
        }
        guard let host, saved.caseInsensitiveCompare(host) == .orderedSame else { return nil }
        return secret
    }

    /// Keeps `secret` for a site on `host` (nil while the URL has none); nil or empty removes it.
    public func setSecret(_ secret: String?, for key: String, host: String?) throws {
        let kept = secret.flatMap { $0.isEmpty ? nil : $0 }
        try store.setSecret(kept, for: key)
        let bound = kept == nil ? nil : host.flatMap { $0.isEmpty ? nil : $0.lowercased() }
        try store.setSecret(bound, for: Self.hostKey(key))
    }
}
