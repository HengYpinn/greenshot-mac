// Greenshot for Mac (Community) - an unofficial macOS port of Greenshot
// Copyright (C) 2026 Greenshot for Mac (Community) contributors
// SPDX-License-Identifier: GPL-3.0-or-later

import Foundation
import GreenshotCore
import Security

private let log = Log("Keychain")

/// The secrets of the upload destinations (API tokens, a client secret, OAuth tokens) as generic passwords in the
/// user's login keychain, one item per key. Upstream encrypts them into its ini file; the settings here never see them.
/// A locked Keychain, or its prompt cancelled or denied, throws `SecretStoreUnavailableError` (never "not found",
/// `KeychainStatus`), so a caller keeps what is stored instead of making a new key or asking to sign in again.
final class KeychainSecretStore: SecretStore {
    static let shared = KeychainSecretStore(service: "io.github.greenshot-mac")

    struct KeychainError: LocalizedError {
        enum Operation { case read, remove, update, add }

        let status: OSStatus
        let operation: Operation

        var errorDescription: String? {
            // The system's message (in the user's language), else the status code.
            let text = SecCopyErrorMessageString(status, nil) as String? ?? "error \(status)"
            switch operation {
            case .read: return String(localized: "The Keychain could not read the item: \(text)")
            case .remove: return String(localized: "The Keychain could not remove the item: \(text)")
            case .update: return String(localized: "The Keychain could not update the item: \(text)")
            case .add: return String(localized: "The Keychain could not add the item: \(text)")
            }
        }
    }

    let service: String

    init(service: String) {
        self.service = service
    }

    private func query(_ key: String) -> [CFString: Any] {
        [kSecClass: kSecClassGenericPassword, kSecAttrService: service, kSecAttrAccount: key]
    }

    /// The error of a failed `operation` on `key`: `SecretStoreUnavailableError` when the Keychain can't be used right
    /// now (`KeychainStatus.unavailable`: what is stored is still there, try again later), else a `KeychainError`. The
    /// unavailable status and the system's text go to the log only: macOS may not ask again (refused without a prompt,
    /// no window server), and after a "Deny" or such a refusal its text ("The user name or passphrase you entered is
    /// not correct.") would mislead.
    private static func error(_ status: OSStatus, _ operation: KeychainError.Operation, _ key: String) -> Error {
        guard KeychainStatus(status) == .unavailable else { return KeychainError(status: status, operation: operation) }
        let text = SecCopyErrorMessageString(status, nil) as String? ?? "-"
        log.warn("The Keychain can't be used right now (\(operation) of '\(key)'): OSStatus \(status), \(text)")
        return SecretStoreUnavailableError(String(localized: "The Keychain is locked, or Greenshot isn't allowed to use it. Try again, and unlock it or allow Greenshot when macOS asks. If macOS doesn't ask, lock and unlock the login keychain in Keychain Access (find it with Spotlight), or restart Greenshot."))
    }

    func secret(for key: String) throws -> String? {
        var query = query(key)
        query[kSecReturnData] = true
        query[kSecMatchLimit] = kSecMatchLimitOne
        var item: CFTypeRef?
        let status = SecItemCopyMatching(query as CFDictionary, &item)
        switch KeychainStatus(status) {
        case .success:
            guard let data = item as? Data else { return nil }
            return String(data: data, encoding: .utf8)
        case .notFound:
            return nil
        case .unavailable, .failed:
            throw Self.error(status, .read, key)
        }
    }

    func setSecret(_ value: String?, for key: String) throws {
        guard let value, !value.isEmpty else {
            let status = SecItemDelete(query(key) as CFDictionary)
            switch KeychainStatus(status) {
            case .success, .notFound: return
            case .unavailable, .failed: throw Self.error(status, .remove, key)
            }
        }
        let data = Data(value.utf8)
        var item = query(key)
        item[kSecValueData] = data
        item[kSecAttrLabel] = "Greenshot for Mac – \(key)"
        let attributes = item
        let written = KeychainStatus.write(update: { SecItemUpdate(query(key) as CFDictionary, [kSecValueData: data] as CFDictionary) },
                                           add: { SecItemAdd(attributes as CFDictionary, nil) })
        guard written.status != errSecSuccess else { return }
        throw Self.error(written.status, written.call == .add ? .add : .update, key)
    }
}

/// The keys of the secrets in the store.
enum SecretKey {
    static let jiraToken = "jira.apiToken"
    static let confluenceToken = "confluence.apiToken"
    static let boxClientSecret = "box.clientSecret"
    static let boxTokens = "box.oauth"
    static let dropboxTokens = "dropbox.oauth"
    /// The key that seals the AI tools consent in the settings (`AIToolsConsentSeal`).
    static let aiToolsConsentKey = AIToolsConsentSeal.keyName
}
