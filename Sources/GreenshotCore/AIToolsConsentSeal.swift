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
/// wrong, or no key) are reset: nobody is allowed, the notification is on, the excluded list is the defaults plus what
/// was stored (an edit can only have removed entries). A key that can't be read (a locked Keychain) resets them only in
/// effect: the stored values and their seal are kept for when it can be read again (`Outcome.isUnverifiable`).
/// `enabled` and `allowRecipeProposals` stay unsealed: turning AI tools on still ends in a question per program.
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
        /// True when the seal couldn't be checked (`Verification.unverifiable`): `settings` are the reset values to use
        /// for now, and nothing was saved. The caller keeps the stored values (not these) so they count again once the
        /// key can be read.
        public var isUnverifiable = false
    }

    /// What `verification(of:)` found.
    public enum Verification: Sendable, Equatable {
        case valid
        /// No seal, a wrong one, or no key: the values were changed outside Greenshot, or the key was deleted.
        case invalid
        /// The key can't be read now (a locked Keychain, its prompt cancelled or denied, or another error of the store).
        case unverifiable
    }

    private let secrets: any SecretStore
    private let location: Location

    public init(secrets: any SecretStore, location: Location) {
        self.secrets = secrets
        self.location = location
    }

    /// The sealed values are the defaults: nothing to protect, no seal needed.
    public static func isDefault(_ settings: AIToolsSettings) -> Bool {
        sealedValuesEqual(settings, AIToolsSettings())
    }

    /// The values the seal covers are the same in both.
    public static func sealedValuesEqual(_ a: AIToolsSettings, _ b: AIToolsSettings) -> Bool {
        a.allowedClients == b.allowedClients && a.excludedApplications == b.excludedApplications
            && a.notifyOnCapture == b.notifyOnCapture
    }

    /// `target` with the values the seal covers taken from `source`.
    public static func withSealedValues(of source: AIToolsSettings, in target: AIToolsSettings) -> AIToolsSettings {
        var result = target
        result.allowedClients = source.allowedClients
        result.excludedApplications = source.excludedApplications
        result.notifyOnCapture = source.notifyOnCapture
        return result
    }

    /// The text that is signed: exactly the three sealed values, in a fixed order and encoding.
    func canonicalPayload(_ settings: AIToolsSettings) -> Data {
        struct Payload: Encodable {
            var location: String
            var allowedClients: [String]
            var excludedApplications: [String]
            var notifyOnCapture: Bool
        }
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.sortedKeys, .withoutEscapingSlashes]
        let payload = Payload(location: locationName, allowedClients: settings.allowedClients, excludedApplications: settings.excludedApplications,
                              notifyOnCapture: settings.notifyOnCapture)
        return (try? encoder.encode(payload)) ?? Data()
    }

    /// Where the seal is for: the settings file's path, or the user defaults. Part of the signed text, so a seal of
    /// one place doesn't verify in another.
    private var locationName: String {
        switch location {
        case .defaults: return "defaults"
        case .file(let url): return "file:" + url.standardizedFileURL.path
        }
    }

    /// Writes the seal for `settings` (Greenshot saving them). Every save makes a new random key first, so every earlier
    /// seal stops verifying: putting back an old settings blob with its old seal (a client the user removed, the
    /// notification off) is reset. A crash between the key and the seal leaves a seal that doesn't verify: the next load
    /// resets (safe: AI tools are asked again). With the defaults the seal and key aren't needed and a
    /// seal that is there goes. A key that can't be read or made is logged: the next load then resets the values.
    public func save(_ settings: AIToolsSettings) {
        guard !Self.isDefault(settings) else {
            writeStoredSeal(nil)
            // The key goes too: it signed the last state that wasn't the defaults, and that state's old seal (a client
            // the user has just removed) must not verify again when it is put back.
            do {
                try secrets.setSecret(nil, for: Self.keyName)
            } catch {
                log.warn("The AI tools consent key could not be removed (\(error)).")
            }
            return
        }
        do {
            let key = try newKey()
            let mac = HMAC<SHA256>.authenticationCode(for: canonicalPayload(settings), using: key)
            writeStoredSeal(Data(mac).base64EncodedString())
        } catch {
            writeStoredSeal(nil)
            log.warn("The AI tools consent could not be sealed (\(error)); AI tools will be asked again.")
        }
    }

    /// Whether the stored seal is a valid HMAC of the sealed values of `settings`. Without a stored seal the key isn't
    /// read: invalid.
    public func verification(of settings: AIToolsSettings) -> Verification {
        guard let text = readStoredSeal(), let signature = Data(base64Encoded: text) else { return .invalid }
        let key: SymmetricKey?
        do {
            key = try existingKey()
        } catch {
            return .unverifiable
        }
        guard let key else { return .invalid }
        let valid = HMAC<SHA256>.isValidAuthenticationCode(signature, authenticating: canonicalPayload(settings), using: key)
        return valid ? .valid : .invalid
    }

    /// The settings as loaded, checked: values that differ from the defaults and have no valid seal are reset, a fresh
    /// seal is written and a warning logged. A seal that can't be checked gives the reset values too, but saves nothing
    /// (`Outcome.isUnverifiable`). Values from a configuration profile are applied after this by the caller.
    public func verifiedOrReset(_ settings: AIToolsSettings) -> Outcome {
        if Self.isDefault(settings) { return Outcome(settings: settings, wasReset: false) }
        let found = verification(of: settings)
        if found == .valid { return Outcome(settings: settings, wasReset: false) }
        let reset = Self.reset(settings)
        if found == .unverifiable {
            log.warn("The AI tools consent can't be checked: its key can't be read from the Keychain (locked, or its prompt was cancelled). AI tools are asked as if none were allowed until it can be read; the stored consent is kept.")
            return Outcome(settings: reset, wasReset: false, isUnverifiable: true)
        }
        save(reset)
        log.warn("The AI tools settings were changed outside Greenshot and are not trusted. They were reset and AI tools will be asked again.")
        return Outcome(settings: reset, wasReset: true)
    }

    /// Nobody allowed, the notification on, the default exclusions plus the stored ones.
    private static func reset(_ settings: AIToolsSettings) -> AIToolsSettings {
        var reset = settings
        reset.allowedClients = []
        reset.notifyOnCapture = true
        var merged = AIToolsSettings.defaultExcludedApplications
        for entry in settings.excludedApplications
        where !merged.contains(where: { $0.caseInsensitiveCompare(entry) == .orderedSame }) {
            merged.append(entry)
        }
        reset.excludedApplications = merged
        return reset
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
