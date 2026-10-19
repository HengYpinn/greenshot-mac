// Greenshot for Mac (Community) - an unofficial macOS port of Greenshot
// Copyright (C) 2026 Greenshot for Mac (Community) contributors
// SPDX-License-Identifier: GPL-3.0-or-later

import Foundation
import GreenshotCore
import Security

/// The secrets of the upload destinations (API tokens, a client secret, OAuth tokens) as generic passwords in the
/// user's login keychain, one item per key. Upstream encrypts them into its ini file; the settings here never see them.
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

    func secret(for key: String) throws -> String? {
        var query = query(key)
        query[kSecReturnData] = true
        query[kSecMatchLimit] = kSecMatchLimitOne
        var item: CFTypeRef?
        let status = SecItemCopyMatching(query as CFDictionary, &item)
        switch status {
        case errSecSuccess:
            guard let data = item as? Data else { return nil }
            return String(data: data, encoding: .utf8)
        case errSecItemNotFound, errSecUserCanceled, errSecAuthFailed, errSecInteractionNotAllowed:
            // Not there, or not for this build of the app: the same as not set up.
            return nil
        default:
            throw KeychainError(status: status, operation: .read)
        }
    }

    func setSecret(_ value: String?, for key: String) throws {
        guard let value, !value.isEmpty else {
            let status = SecItemDelete(query(key) as CFDictionary)
            guard status == errSecSuccess || status == errSecItemNotFound else { throw KeychainError(status: status, operation: .remove) }
            return
        }
        let data = Data(value.utf8)
        let update = SecItemUpdate(query(key) as CFDictionary, [kSecValueData: data] as CFDictionary)
        if update == errSecSuccess { return }
        guard update == errSecItemNotFound else { throw KeychainError(status: update, operation: .update) }
        var item = query(key)
        item[kSecValueData] = data
        item[kSecAttrLabel] = "Greenshot for Mac – \(key)"
        let add = SecItemAdd(item as CFDictionary, nil)
        guard add == errSecSuccess else { throw KeychainError(status: add, operation: .add) }
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
