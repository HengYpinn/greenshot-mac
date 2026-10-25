// Greenshot for Mac (Community) - an unofficial macOS port of Greenshot
// Copyright (C) 2026 Greenshot for Mac (Community) contributors
// SPDX-License-Identifier: GPL-3.0-or-later

import Foundation
import Testing
@testable import GreenshotCore

/// A secret store that refuses some items like a locked or denied Keychain (macOS asks per item, so "Deny" is per item):
/// reading a key in `denied` throws `SecretStoreUnavailableError`. Counts the reads.
private final class DenyingSecretStore: SecretStore, @unchecked Sendable {
    private let lock = NSLock()
    private var values: [String: String]
    private var deniedKeys: Set<String> = []
    private var readCount = 0

    init(_ values: [String: String]) {
        self.values = values
    }

    var denied: Set<String> {
        get { lock.withLock { deniedKeys } }
        set { lock.withLock { deniedKeys = newValue } }
    }

    var reads: Int { lock.withLock { readCount } }

    func secret(for key: String) throws -> String? {
        try lock.withLock {
            readCount += 1
            if deniedKeys.contains(key) { throw SecretStoreUnavailableError("The Keychain is locked.") }
            return values[key]
        }
    }

    func setSecret(_ value: String?, for key: String) throws {
        try lock.withLock {
            if deniedKeys.contains(key) { throw SecretStoreUnavailableError("The Keychain is locked.") }
            values[key] = value
        }
    }
}

/// A token field of Settings › Destinations as the app has it: reads its secret when it is shown, unless the list says
/// the Keychain can't be read; Retry reads it again.
@MainActor
private final class TokenField: RetryableSecret {
    let key: String
    let store: SecretStore
    private(set) var text = ""
    private(set) var secretState = SecretState.usable

    init(_ key: String, store: SecretStore, list: SecretRetryList) {
        self.key = key
        self.store = store
        secretState = list.readUnlessUnavailable { read() }
        list.add(self)
    }

    func readAgain() {
        secretState = read()
    }

    private func read() -> SecretState {
        do {
            text = try store.secret(for: key) ?? ""
            return .usable
        } catch {
            text = ""
            return SecretState(error: error)
        }
    }
}

/// Any other error of the store, e.g. a damaged item.
private struct DamagedItemError: LocalizedError {
    var errorDescription: String? { "The item is damaged." }
}

/// What Settings › Destinations shows for a secret: only a store that can't be used right now disables it (with Retry);
/// one Retry reads every such secret again, and while the Keychain is locked a press asks once.
@MainActor
@Suite struct SecretStateTests {
    @Test func onlyAStoreThatCantBeUsedDisablesTheSecret() {
        #expect(SecretState(error: nil) == .usable)
        #expect(SecretState.usable.message == nil)
        let locked = SecretState(error: SecretStoreUnavailableError("The Keychain is locked."))
        #expect(locked == .unavailable("The Keychain is locked."))
        #expect(locked.isUnavailable)
        #expect(locked.message == "The Keychain is locked.")
        // Reading again would give the same: shown, but the field stays editable, so a new secret replaces the item.
        let damaged = SecretState(error: DamagedItemError())
        #expect(damaged == .failed("The item is damaged."))
        #expect(!damaged.isUnavailable)
        #expect(damaged.message == "The item is damaged.")
    }

    @Test func theAccountOffersOnlyRetryWhileTheStoreCantBeUsed() {
        #expect(CloudAccountAction(signedIn: true, state: .usable) == .signOut)
        #expect(CloudAccountAction(signedIn: false, state: .usable) == .signIn)
        #expect(CloudAccountAction(signedIn: false, state: .unavailable("locked")) == .retry)
        #expect(CloudAccountAction(signedIn: true, state: .unavailable("locked")) == .retry)
        // A damaged item: signing in again replaces it.
        #expect(CloudAccountAction(signedIn: false, state: .failed("damaged")) == .signIn)
    }

    @Test func whileTheKeychainIsLockedTheTabAsksOnceAndOneRetryReadsEverySecretAgain() {
        let store = DenyingSecretStore(["a": "1", "b": "2", "c": "3"])
        store.denied = ["a", "b", "c"]
        let list = SecretRetryList()
        let a = TokenField("a", store: store, list: list)
        // Shown after the first couldn't be read: they don't ask again (one password prompt, not one per field).
        let b = TokenField("b", store: store, list: list)
        let c = TokenField("c", store: store, list: list)
        #expect(store.reads == 1)
        #expect(b.secretState == .unavailable("The Keychain is locked."))
        #expect(c.secretState.isUnavailable)

        // Retry while it is still locked: one prompt.
        list.retry(from: b)
        #expect(store.reads == 2)
        #expect(a.secretState.isUnavailable)
        #expect(c.secretState.isUnavailable)

        // Unlocked: one Retry reads them all.
        store.denied = []
        list.retry(from: c)
        #expect(store.reads == 5)
        #expect(list.unavailable == nil)
        #expect([a.text, b.text, c.text] == ["1", "2", "3"])
    }

    /// "Deny" is per item: a Retry stops at the first secret that still can't be read, so a press shows one prompt the
    /// user refuses, not one per secret.
    @Test func aRetryStopsAtTheFirstSecretThatStillCantBeRead() {
        let store = DenyingSecretStore(["a": "1", "b": "2", "c": "3"])
        store.denied = ["a", "b", "c"]
        let list = SecretRetryList()
        let a = TokenField("a", store: store, list: list)
        let b = TokenField("b", store: store, list: list)
        let c = TokenField("c", store: store, list: list)

        store.denied = ["b"]
        list.retry(from: a)
        #expect(a.secretState == .usable)
        #expect(b.secretState.isUnavailable)
        #expect(c.secretState.isUnavailable)
        #expect(store.reads == 3)

        store.denied = []
        list.retry(from: c)
        #expect(list.unavailable == nil)
        #expect([a.text, b.text, c.text] == ["1", "2", "3"])
    }

    /// A field that is gone (another URL makes a new one) doesn't keep the others from reading; another error doesn't
    /// either: the Keychain could be used.
    @Test func onlySecretsShownThatCantBeReadKeepTheOthersFromReading() {
        let store = DenyingSecretStore(["a": "1", "b": "2"])
        let list = SecretRetryList()
        store.denied = ["a"]
        withExtendedLifetime(TokenField("a", store: store, list: list)) { field in
            #expect(field.secretState.isUnavailable)
            #expect(list.unavailable != nil)
        }
        #expect(list.unavailable == nil)
        let b = TokenField("b", store: store, list: list)
        #expect(b.text == "2")

        let damaged = TokenField("x", store: ThrowingSecretStore(), list: list)
        #expect(damaged.secretState == .failed("The item is damaged."))
        #expect(list.unavailable == nil)
    }
}

/// Every read fails with an error that isn't a locked Keychain.
private struct ThrowingSecretStore: SecretStore {
    func secret(for key: String) throws -> String? { throw DamagedItemError() }
    func setSecret(_ value: String?, for key: String) throws { throw DamagedItemError() }
}
