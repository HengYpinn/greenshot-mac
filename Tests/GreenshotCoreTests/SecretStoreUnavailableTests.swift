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

    /// What each status the login keychain can give means (Apple's Security sources): only "not found" is a missing
    /// secret. A locked, cancelled, denied or unattended Keychain can't be used right now; any other error fails.
    @Test func aLockedCancelledOrDeniedKeychainItemIsUnavailableNotMissing() {
        let table: [(status: OSStatus, means: KeychainStatus)] = [
            (errSecSuccess, .success),
            (errSecItemNotFound, .notFound),
            // Its unlock prompt cancelled, or (most likely) "Deny" when macOS asked whether Greenshot may use the item.
            (errSecUserCanceled, .unavailable),
            // Too many wrong passwords, or refused without a prompt (another build's item, a stale login keychain).
            (errSecAuthFailed, .unavailable),
            // Locked while macOS can't ask: no window server (SSH), or Power Nap.
            (errSecInteractionNotAllowed, .unavailable),
            (errSecInDarkWake, .unavailable),
            // No keychain service, no keychain that could hold it, a damaged keychain or item, a read-only keychain.
            (errSecNotAvailable, .failed),
            (errSecNoDefaultKeychain, .failed),
            (errSecNoSuchKeychain, .failed),
            (errSecInvalidKeychain, .failed),
            (errSecReadOnly, .failed),
            (errSecWrPerm, .failed),
            (errSecDuplicateItem, .failed),
            (errSecMissingEntitlement, .failed),
            (errSecInvalidItemRef, .failed),
            // The data protection keychain's and LocalAuthentication's (-25330 errSecAuthNeeded), the agent failing.
            (errSecInteractionRequired, .failed),
            (-25330, .failed),
            (errAuthorizationInternal, .failed),
        ]
        for row in table {
            let means = KeychainStatus(row.status)
            #expect(means == row.means, "OSStatus \(row.status)")
        }
    }

    /// A write updates the item, adds it when it isn't there, and updates it once more when another writer added it in
    /// between (the add finds it there after all); any other status counts as it is.
    @Test func aWriteUpdatesAddsAndUpdatesOnceMoreAfterARace() {
        func write(_ updates: [OSStatus], _ adds: [OSStatus]) -> (calls: [String], call: KeychainStatus.WriteCall, status: OSStatus) {
            var calls: [String] = []
            var updates = updates
            var adds = adds
            let written = KeychainStatus.write(update: { calls.append("update"); return updates.removeFirst() },
                                               add: { calls.append("add"); return adds.removeFirst() })
            return (calls, written.call, written.status)
        }
        let updated = write([errSecSuccess], [])
        #expect(updated.calls == ["update"])
        #expect(updated.call == .update)
        #expect(updated.status == errSecSuccess)
        let added = write([errSecItemNotFound], [errSecSuccess])
        #expect(added.calls == ["update", "add"])
        #expect(added.status == errSecSuccess)
        let raced = write([errSecItemNotFound, errSecSuccess], [errSecDuplicateItem])
        #expect(raced.calls == ["update", "add", "update"])
        #expect(raced.call == .update)
        #expect(raced.status == errSecSuccess)
        // Only once: a second miss counts (fails, nothing replaced).
        let racedTwice = write([errSecItemNotFound, errSecItemNotFound], [errSecDuplicateItem])
        #expect(racedTwice.calls == ["update", "add", "update"])
        #expect(racedTwice.status == errSecItemNotFound)
        let locked = write([errSecUserCanceled], [])
        #expect(locked.calls == ["update"])
        #expect(KeychainStatus(locked.status) == .unavailable)
        let addLocked = write([errSecItemNotFound], [errSecInteractionNotAllowed])
        #expect(addLocked.call == .add)
        #expect(addLocked.status == errSecInteractionNotAllowed)
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

    /// Greenshot started with the Keychain locked: unlocking it (in Keychain Access) and Reload Recipes bring the
    /// approvals back without a restart. A reload reads the Keychain once then, and not at all once it was read.
    @MainActor @Test func reloadRecipesReadsALockedKeychainAgain() async throws {
        let secrets = LockableSecretStore()
        let earlier = LibraryFixture(secrets: secrets)
        defer { earlier.cleanUp() }
        let url = try earlier.write(libraryRecipe())
        _ = await earlier.library.importFile(url)
        #expect(earlier.library.recipe(id: "lib_recipe") != nil)

        // The next start, locked: the prompt cancelled, the approval question answered with "Don't run".
        secrets.isLocked = true
        let approver = StubApprover { _ in nil }
        let box = earlier.box
        let library = RecipeLibrary(loadSettings: { box.settings }, saveSettings: { box.settings = $0 },
                                    trustStore: RecipeTrustStore(fileURL: earlier.folder.appendingPathComponent("trust.json"), secrets: secrets),
                                    approver: approver, watchFiles: false)
        _ = await library.reload()
        #expect(approver.requests.count == 1)
        #expect(library.recipe(id: "lib_recipe") == nil)

        secrets.isLocked = false
        let reads = secrets.reads
        _ = await library.reload()
        #expect(approver.requests.count == 1)
        #expect(library.recipe(id: "lib_recipe") != nil)
        #expect(secrets.reads == reads + 1)
        _ = await library.reload()
        #expect(secrets.reads == reads + 1)
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

    // MARK: AI tools consent

    private func suite() -> UserDefaults {
        let name = "seal-locked-\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: name)!
        defaults.removePersistentDomain(forName: name)
        return defaults
    }

    private func allowing(_ path: String) -> AIToolsSettings {
        var settings = AIToolsSettings()
        settings.allowedClients = [path]
        settings.notifyOnCapture = false
        return settings
    }

    @Test func aLockedKeychainKeepsTheConsentStoredButNotInEffect() {
        let defaults = suite()
        let secrets = LockableSecretStore()
        let seal = AIToolsConsentSeal(secrets: secrets, location: .defaults(defaults))
        let allowed = allowing("/usr/local/bin/node")
        seal.save(allowed)
        let storedSeal = defaults.string(forKey: AIToolsConsentSeal.defaultsKey)
        let key = secrets.value(AIToolsConsentSeal.keyName)
        let writes = secrets.writes

        secrets.isLocked = true
        #expect(seal.verification(of: allowed) == .unverifiable)
        let outcome = seal.verifiedOrReset(allowed)
        // In effect: nobody allowed, the notification on, like a seal that doesn't match.
        #expect(outcome.isUnverifiable)
        #expect(outcome.settings.allowedClients.isEmpty)
        #expect(outcome.settings.notifyOnCapture)
        // Not saved: the caller keeps the stored values, their seal and key stay for when the Keychain can be read.
        #expect(!outcome.wasReset)
        #expect(defaults.string(forKey: AIToolsConsentSeal.defaultsKey) == storedSeal)
        #expect(secrets.writes == writes)

        secrets.isLocked = false
        #expect(secrets.value(AIToolsConsentSeal.keyName) == key)
        #expect(seal.verification(of: allowed) == .valid)
        let unlocked = seal.verifiedOrReset(allowed)
        #expect(!unlocked.wasReset)
        #expect(!unlocked.isUnverifiable)
        #expect(unlocked.settings == allowed)
    }

    /// The negative control: a seal that doesn't match is still reset, and the reset saved, as before.
    @Test func aWrongSealIsStillResetAndSaved() {
        let defaults = suite()
        let secrets = LockableSecretStore()
        let seal = AIToolsConsentSeal(secrets: secrets, location: .defaults(defaults))
        seal.save(allowing("/usr/local/bin/node"))
        // An extra exclusion survives the reset, so the reset isn't the defaults (which need no seal) and is sealed.
        var edited = allowing("/tmp/attacker")
        edited.excludedApplications.append("MyVault")
        #expect(seal.verification(of: edited) == .invalid)
        let outcome = seal.verifiedOrReset(edited)
        #expect(outcome.wasReset)
        #expect(!outcome.isUnverifiable)
        #expect(outcome.settings.allowedClients.isEmpty)
        #expect(seal.verification(of: outcome.settings) == .valid)
    }

    /// Without a stored seal there is nothing to check: invalid, whatever the Keychain says.
    @Test func noSealIsInvalidEvenWhileLocked() {
        let defaults = suite()
        let secrets = LockableSecretStore()
        secrets.isLocked = true
        let seal = AIToolsConsentSeal(secrets: secrets, location: .defaults(defaults))
        #expect(seal.verification(of: allowing("/tmp/x")) == .invalid)
    }

    @Test func onlyTheSealedValuesCount() {
        let allowed = allowing("/usr/local/bin/node")
        var switchedOff = allowed
        switchedOff.enabled.toggle()
        switchedOff.allowRecipeProposals.toggle()
        #expect(AIToolsConsentSeal.sealedValuesEqual(allowed, switchedOff))
        #expect(!AIToolsConsentSeal.sealedValuesEqual(allowed, AIToolsSettings()))
        let merged = AIToolsConsentSeal.withSealedValues(of: AIToolsSettings(), in: switchedOff)
        #expect(merged.enabled == switchedOff.enabled)
        #expect(merged.allowRecipeProposals == switchedOff.allowRecipeProposals)
        #expect(AIToolsConsentSeal.sealedValuesEqual(merged, AIToolsSettings()))
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
