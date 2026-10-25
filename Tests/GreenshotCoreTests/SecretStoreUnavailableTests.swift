// Greenshot for Mac (Community) - an unofficial macOS port of Greenshot
// Copyright (C) 2026 Greenshot for Mac (Community) contributors
// SPDX-License-Identifier: GPL-3.0-or-later

import Foundation
import Security
import Testing
@testable import GreenshotCore

/// A secret store that can be locked like the login keychain: while `isLocked` every read and write throws
/// `SecretStoreUnavailableError` and changes nothing. Counts the reads and writes it was asked for.
final class LockableSecretStore: SecretStore, @unchecked Sendable {
    private let base: InMemorySecretStore
    private let lock = NSLock()
    private var locked = false
    private var readCount = 0
    private var writeCount = 0

    init(_ values: [String: String] = [:]) {
        base = InMemorySecretStore(values)
    }

    var isLocked: Bool {
        get { lock.withLock { locked } }
        set { lock.withLock { locked = newValue } }
    }

    var reads: Int { lock.withLock { readCount } }
    var writes: Int { lock.withLock { writeCount } }

    /// What is stored, without counting a read.
    func value(_ key: String) -> String? {
        (try? base.secret(for: key)) ?? nil
    }

    func secret(for key: String) throws -> String? {
        let isLocked = lock.withLock {
            readCount += 1
            return locked
        }
        if isLocked { throw SecretStoreUnavailableError("The Keychain is locked.") }
        return try base.secret(for: key)
    }

    func setSecret(_ value: String?, for key: String) throws {
        let isLocked = lock.withLock {
            writeCount += 1
            return locked
        }
        if isLocked { throw SecretStoreUnavailableError("The Keychain is locked.") }
        try base.setSecret(value, for: key)
    }
}

/// A locked Keychain, or its password prompt cancelled or denied, is not a missing secret: nothing that is stored is
/// replaced, nobody is asked to sign in again, and the approvals and the AI tools consent come back once it can be read.
@Suite struct SecretStoreUnavailableTests {
    private let now = Date(timeIntervalSince1970: 1_800_000_000)

    // MARK: The Keychain's statuses

    @Test func aLockedCancelledOrDeniedKeychainItemIsUnavailableNotMissing() {
        let unavailable = SecretStoreUnavailableError.keychainStatuses
        #expect(unavailable.contains(errSecInteractionNotAllowed))
        #expect(unavailable.contains(errSecUserCanceled))
        #expect(unavailable.contains(errSecAuthFailed))
        #expect(!unavailable.contains(errSecItemNotFound))
        #expect(!unavailable.contains(errSecSuccess))
    }

    // MARK: Recipe approvals

    private func approve(_ id: String, _ path: String, _ hash: String, in store: RecipeTrustStore) throws {
        try store.recordApproval(RecipeApproval(recipeId: id), forFile: path, sha256: hash, content: nil, origin: nil,
                                 recipeName: nil, recipeVersion: nil)
    }

    @Test func aLockedKeychainNeverReplacesTheKeyOfTheApprovals() throws {
        let folder = recipeTemporaryFolder()
        defer { try? FileManager.default.removeItem(at: folder) }
        let file = folder.appendingPathComponent("trust.json")
        let secrets = LockableSecretStore()
        let first = "/tmp/recipes/first.gsrecipe.json"
        let second = "/tmp/recipes/second.gsrecipe.json"
        try approve("one", first, "11", in: RecipeTrustStore(fileURL: file, secrets: secrets))
        let key = secrets.value(RecipeTrustStore.keyName)
        let saved = try Data(contentsOf: file)

        // Greenshot starts with the Keychain locked: nothing is approved meanwhile (default-deny), nothing is tampered.
        secrets.isLocked = true
        let store = RecipeTrustStore(fileURL: file, secrets: secrets)
        #expect(store.approval(forFile: first, sha256: "11", recipeId: "one") == nil)
        #expect(!store.wasTampered)
        // An approval or a revocation says it failed and changes nothing: no new key, the file as it was.
        #expect(throws: SecretStoreUnavailableError.self) { try approve("two", second, "22", in: store) }
        #expect(throws: SecretStoreUnavailableError.self) { try store.revokeApproval(recipeId: "one", forFile: first) }
        #expect(secrets.value(RecipeTrustStore.keyName) == key)
        #expect(try Data(contentsOf: file) == saved)

        // Unlocked (the user typed the password at the next prompt): the approval is saved next to the earlier one.
        secrets.isLocked = false
        try approve("two", second, "22", in: store)
        #expect(secrets.value(RecipeTrustStore.keyName) == key)
        let reopened = RecipeTrustStore(fileURL: file, secrets: secrets)
        #expect(reopened.allRecords.map(\.filePath) == [first, second].map(RecipeTrustStore.standardized))
        #expect(reopened.approval(forFile: first, sha256: "11", recipeId: "one") != nil)
        #expect(!reopened.wasTampered)
    }

    /// Every look-up would show the Keychain's password prompt again: a locked Keychain is asked once, and again only
    /// when an approval is to be changed (the user is there then).
    @Test func aLockedKeychainIsAskedOnceNotAtEveryLookUp() throws {
        let folder = recipeTemporaryFolder()
        defer { try? FileManager.default.removeItem(at: folder) }
        let file = folder.appendingPathComponent("trust.json")
        let secrets = LockableSecretStore()
        try approve("one", "/tmp/recipes/a.gsrecipe.json", "11", in: RecipeTrustStore(fileURL: file, secrets: secrets))

        secrets.isLocked = true
        let store = RecipeTrustStore(fileURL: file, secrets: secrets)
        let reads = secrets.reads
        let writes = secrets.writes
        for _ in 0..<5 {
            #expect(store.approval(forFile: "/tmp/recipes/a.gsrecipe.json", sha256: "11", recipeId: "one") == nil)
            #expect(store.allRecords.isEmpty)
        }
        #expect(secrets.reads == reads + 1)
        #expect(throws: SecretStoreUnavailableError.self) { try approve("two", "/tmp/recipes/b.gsrecipe.json", "22", in: store) }
        #expect(secrets.reads == reads + 2)
        #expect(secrets.writes == writes)
    }

    // MARK: Box and Dropbox

    private func tokens(_ expiresAt: Date) throws -> String {
        String(decoding: try JSONEncoder().encode(OAuthTokens(accessToken: "a1", refreshToken: "r1", expiresAt: expiresAt)), as: UTF8.self)
    }

    @Test func aLockedKeychainIsNotASignedOutAccount() async throws {
        let secrets = LockableSecretStore(["tokens": try tokens(now.addingTimeInterval(3600))])
        secrets.isLocked = true
        let http = StubHTTPClient([])
        let authorizer = StubAuthorizer()
        let client = OAuthClient(provider: .dropbox, clientID: "key", store: secrets, storeKey: "tokens", http: http, now: { now })
        #expect(throws: SecretStoreUnavailableError.self) { _ = try client.storedTokens() }
        // No sign-in page, no network, nothing written over the stored tokens.
        await #expect(throws: SecretStoreUnavailableError.self) { _ = try await client.accessToken(authorizer: authorizer) }
        #expect(throws: SecretStoreUnavailableError.self) { try client.invalidateAccessToken() }
        #expect(authorizer.seen.url == nil)
        #expect(http.requests.isEmpty)
        #expect(secrets.writes == 0)

        secrets.isLocked = false
        #expect(try await client.accessToken(authorizer: nil) == "a1")
    }

    // MARK: Jira and Confluence

    @Test func aLockedKeychainNeitherBindsNorHidesAToken() throws {
        let secrets = LockableSecretStore(["jira.apiToken": "tok"])
        secrets.isLocked = true
        let atlassian = AtlassianSecrets(store: secrets)
        #expect(throws: SecretStoreUnavailableError.self) {
            _ = try atlassian.secret(for: "jira.apiToken", host: "jira.example.test", claim: true)
        }
        #expect(secrets.writes == 0)
        secrets.isLocked = false
        #expect(try atlassian.secret(for: "jira.apiToken", host: "jira.example.test", claim: true) == "tok")
        #expect(secrets.value("jira.apiToken.host") == "jira.example.test")
    }
}
