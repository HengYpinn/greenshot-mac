// Greenshot for Mac (Community) - an unofficial macOS port of Greenshot
// Copyright (C) 2026 Greenshot for Mac (Community) contributors
// SPDX-License-Identifier: GPL-3.0-or-later

import CryptoKit
import Foundation

private let log = Log("AITools")

/// Seals the consent of the AI tools against edits made outside Greenshot.
///
/// The allowed programs, the excluded applications and "notify on capture" decide who may take screenshots through
/// greenshot-mcp and what is hidden from them. They sit in the settings (user defaults or `--settings-dir` file), which
/// any program of the user can edit, then `greenshot-cli --reload`. A setting can't protect a consent, so these three
/// values carry an HMAC-SHA256 (like the recipe approvals of `RecipeTrustStore`) under a 32-byte key in the
/// `SecretStore` (the Keychain in the app) under `keyName`, made on the first save that needs it. Only Greenshot saving
/// writes the seal. When the settings are loaded, values that differ from the defaults and have no valid seal (missing,
/// wrong, or the key can't be read) are reset: nobody is allowed, the notification is on, the excluded list is the
/// defaults plus what was stored (an edit can only have removed entries). `enabled` and `allowRecipeProposals` stay
/// unsealed: turning AI tools on still ends in a question per program.
///
/// Limit: this stops a program that only edits the preferences. It can't stop one that deletes and replaces the
/// login-keychain key, because macOS lets any program of the user delete a login-keychain item without asking (checked
/// 2026-10-19 with `security delete-generic-password` on another program's item: exit 0, no dialog). The recipe trust
/// store has the same limit; full protection needs a Developer ID and the data protection keychain.
public struct AIToolsConsentSeal: @unchecked Sendable {
    public static let keyName = "aiTools.consentKey"
    /// Where the seal sits next to `settings.v1` in the user defaults.
    public static let defaultsKey = "settings.v1.aiToolsSeal"

    /// Where the seal is stored: next to the settings.
    public enum Location {
        case defaults(UserDefaults)
        /// A file next to the settings file of `--settings-dir`.
        case file(URL)
    }

    /// The result of `verifiedOrReset`.
    public struct Outcome: Sendable {
        public var settings: AIToolsSettings
        /// True when the values were reset: the caller saves the settings so the file agrees with the new seal.
        public var wasReset: Bool
    }

    private let secrets: any SecretStore
    private let location: Location

    public init(secrets: any SecretStore, location: Location) {
        self.secrets = secrets
        self.location = location
    }

    /// The sealed values are the defaults: nothing to protect, no seal needed.
    public static func isDefault(_ settings: AIToolsSettings) -> Bool {
        let d = AIToolsSettings()
        return settings.allowedClients == d.allowedClients && settings.excludedApplications == d.excludedApplications
            && settings.notifyOnCapture == d.notifyOnCapture
    }

    /// The text that is signed: exactly the three sealed values, in a fixed order and encoding.
    static func canonicalPayload(_ settings: AIToolsSettings) -> Data {
        struct Payload: Encodable {
            var allowedClients: [String]
            var excludedApplications: [String]
            var notifyOnCapture: Bool
        }
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.sortedKeys, .withoutEscapingSlashes]
        let payload = Payload(allowedClients: settings.allowedClients, excludedApplications: settings.excludedApplications,
                              notifyOnCapture: settings.notifyOnCapture)
        return (try? encoder.encode(payload)) ?? Data()
    }

    /// Writes the seal for `settings` (Greenshot saving them). With the defaults the seal and key aren't needed and a
    /// seal that is there goes. A key that can't be read or made is logged: the next load then resets the values.
    public func save(_ settings: AIToolsSettings) {
        guard !Self.isDefault(settings) else {
            writeStoredSeal(nil)
            return
        }
        do {
            let key = try existingKey() ?? newKey()
            let mac = HMAC<SHA256>.authenticationCode(for: Self.canonicalPayload(settings), using: key)
            writeStoredSeal(Data(mac).base64EncodedString())
        } catch {
            writeStoredSeal(nil)
            log.warn("The AI tools consent could not be sealed (\(error)); AI tools will be asked again.")
        }
    }

    /// True when the stored seal is a valid HMAC of the sealed values of `settings`.
    public func isValid(_ settings: AIToolsSettings) -> Bool {
        guard let text = readStoredSeal(), let signature = Data(base64Encoded: text),
              let key = try? existingKey() else { return false }
        return HMAC<SHA256>.isValidAuthenticationCode(signature, authenticating: Self.canonicalPayload(settings), using: key)
    }

    /// The settings as loaded, checked: values that differ from the defaults and have no valid seal are reset, a fresh
    /// seal is written and a warning logged. Values from a configuration profile are applied after this by the caller.
    public func verifiedOrReset(_ settings: AIToolsSettings) -> Outcome {
        if Self.isDefault(settings) || isValid(settings) { return Outcome(settings: settings, wasReset: false) }
        var reset = settings
        reset.allowedClients = []
        reset.notifyOnCapture = true
        var merged = AIToolsSettings.defaultExcludedApplications
        for entry in settings.excludedApplications
        where !merged.contains(where: { $0.caseInsensitiveCompare(entry) == .orderedSame }) {
            merged.append(entry)
        }
        reset.excludedApplications = merged
        save(reset)
        log.warn("The AI tools settings were changed outside Greenshot and are not trusted. They were reset and AI tools will be asked again.")
        return Outcome(settings: reset, wasReset: true)
    }

    // MARK: Key and seal storage

    private func existingKey() throws -> SymmetricKey? {
        guard let text = try secrets.secret(for: Self.keyName), let data = Data(base64Encoded: text), data.count == 32 else { return nil }
        return SymmetricKey(data: data)
    }

    private func newKey() throws -> SymmetricKey {
        let key = SymmetricKey(size: .bits256)
        let data = key.withUnsafeBytes { Data($0) }
        try secrets.setSecret(data.base64EncodedString(), for: Self.keyName)
        return key
    }

    private func sealFile(for settingsFile: URL) -> URL {
        settingsFile.appendingPathExtension("aitools-seal")
    }

    private func readStoredSeal() -> String? {
        switch location {
        case .defaults(let defaults): return defaults.string(forKey: Self.defaultsKey)
        case .file(let url): return (try? String(contentsOf: sealFile(for: url), encoding: .utf8))?.trimmingCharacters(in: .whitespacesAndNewlines)
        }
    }

    private func writeStoredSeal(_ seal: String?) {
        switch location {
        case .defaults(let defaults):
            if let seal { defaults.set(seal, forKey: Self.defaultsKey) } else { defaults.removeObject(forKey: Self.defaultsKey) }
        case .file(let url):
            let file = sealFile(for: url)
            guard let seal else {
                try? FileManager.default.removeItem(at: file)
                return
            }
            try? FileManager.default.createDirectory(at: file.deletingLastPathComponent(), withIntermediateDirectories: true)
            try? Data(seal.utf8).write(to: file, options: .atomic)
        }
    }
}
