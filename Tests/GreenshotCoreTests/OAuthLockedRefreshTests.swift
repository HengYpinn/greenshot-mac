// Greenshot for Mac (Community) - an unofficial macOS port of Greenshot
// Copyright (C) 2026 Greenshot for Mac (Community) contributors
// SPDX-License-Identifier: GPL-3.0-or-later

import Foundation
import Testing
@testable import GreenshotCore

/// The Keychain locks while a refresh token is refused: the old tokens can't be removed, and a browser sign-in would
/// only make tokens that can't be saved, so the failure comes first.
@Suite struct OAuthLockedRefreshTests {
    private let now = Date(timeIntervalSince1970: 1_800_000_000)

    /// Locks the store, then refuses the refresh token (400).
    private final class LockingTokenServer: HTTPClient, @unchecked Sendable {
        let store: LockableSecretStore
        private let lock = NSLock()
        private var count = 0

        init(store: LockableSecretStore) {
            self.store = store
        }

        var requests: Int { lock.withLock { count } }

        func data(for request: URLRequest) async throws -> (Data, URLResponse) {
            lock.withLock { count += 1 }
            store.isLocked = true
            let response = HTTPURLResponse(url: request.url!, statusCode: 400, httpVersion: nil, headerFields: nil)!
            return (Data(#"{"error":"invalid_grant"}"#.utf8), response)
        }
    }

    @Test func aRefusedRefreshDoesntSignInWhenTheOldTokensCantBeRemoved() async throws {
        let expired = OAuthTokens(accessToken: "old", refreshToken: "r1", expiresAt: now.addingTimeInterval(-1))
        let stored = String(decoding: try JSONEncoder().encode(expired), as: UTF8.self)
        let secrets = LockableSecretStore(["tokens": stored])
        let server = LockingTokenServer(store: secrets)
        let authorizer = StubAuthorizer()
        let now = now
        let client = OAuthClient(provider: .box, clientID: "key", clientSecret: "sec", store: secrets, storeKey: "tokens",
                                 http: server, now: { now })
        await #expect(throws: SecretStoreUnavailableError.self) { _ = try await client.accessToken(authorizer: authorizer) }
        // No sign-in page whose tokens couldn't be kept: only the refresh went out, the stored tokens are as they were.
        #expect(authorizer.seen.url == nil)
        #expect(server.requests == 1)
        #expect(secrets.value("tokens") == stored)
    }
}
