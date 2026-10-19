// Greenshot for Mac (Community) - an unofficial macOS port of Greenshot
// Copyright (C) 2026 Greenshot for Mac (Community) contributors
// SPDX-License-Identifier: GPL-3.0-or-later

import Foundation
import Testing
@testable import GreenshotCore

/// The AI tools consent is sealed: an edit of the settings outside Greenshot is reset at load.
@Suite struct AIToolsConsentSealTests {
    private func suite() -> UserDefaults {
        let name = "seal-test-\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: name)!
        defaults.removePersistentDomain(forName: name)
        return defaults
    }

    private func attackerBlob(into defaults: UserDefaults) {
        let json = """
        {"aiTools":{"enabled":true,"allowedClients":["/tmp/x"],"notifyOnCapture":false,"excludedApplications":[]}}
        """
        defaults.set(Data(json.utf8), forKey: SettingsStorage.key)
    }

    private func load(_ defaults: UserDefaults, _ secrets: InMemorySecretStore) -> (AIToolsSettings, Bool) {
        let seal = AIToolsConsentSeal(secrets: secrets, location: .defaults(defaults))
        let outcome = seal.verifiedOrReset(SettingsStorage.load(from: defaults).aiTools)
        return (outcome.settings, outcome.wasReset)
    }

    @Test func unsealedEditIsReset() {
        let defaults = suite()
        let secrets = InMemorySecretStore()
        attackerBlob(into: defaults)
        let (loaded, wasReset) = load(defaults, secrets)
        #expect(wasReset)
        #expect(loaded.enabled)
        #expect(loaded.allowedClients.isEmpty)
        #expect(loaded.notifyOnCapture)
        #expect(loaded.excludedApplications == AIToolsSettings.defaultExcludedApplications)
        let client = AIToolClient(path: "/tmp/x", displayName: "x")
        #expect(!AIToolAccess.isAllowed(client, settings: loaded))
    }

    @Test func resetKeepsStoredExtraExclusions() {
        let defaults = suite()
        var settings = AppSettings()
        settings.aiTools.excludedApplications = ["1password", "MyVault"]
        SettingsStorage.save(settings, to: defaults)
        let (loaded, wasReset) = load(defaults, InMemorySecretStore())
        #expect(wasReset)
        #expect(loaded.excludedApplications.count == AIToolsSettings.defaultExcludedApplications.count + 1)
        #expect(loaded.excludedApplications.last == "MyVault")
    }

    @Test func savedValuesSurviveLoad() {
        let defaults = suite()
        let secrets = InMemorySecretStore()
        var settings = AppSettings()
        settings.aiTools.allowedClients = ["/usr/local/bin/node"]
        settings.aiTools.notifyOnCapture = false
        settings.aiTools.excludedApplications.removeAll { $0 == "Passwords" }
        SettingsStorage.save(settings, to: defaults)
        AIToolsConsentSeal(secrets: secrets, location: .defaults(defaults)).save(settings.aiTools)
        let (loaded, wasReset) = load(defaults, secrets)
        #expect(!wasReset)
        #expect(loaded == settings.aiTools)
        #expect(!loaded.excludedApplications.contains("Passwords"))
    }

    @Test func editAfterSealingIsReset() {
        let defaults = suite()
        let secrets = InMemorySecretStore()
        var settings = AppSettings()
        settings.aiTools.allowedClients = ["/usr/local/bin/node"]
        SettingsStorage.save(settings, to: defaults)
        AIToolsConsentSeal(secrets: secrets, location: .defaults(defaults)).save(settings.aiTools)
        settings.aiTools.allowedClients.append("/tmp/x")
        SettingsStorage.save(settings, to: defaults)
        let (loaded, wasReset) = load(defaults, secrets)
        #expect(wasReset)
        #expect(loaded.allowedClients.isEmpty)
    }

    @Test func sealFromAnotherKeyIsReset() {
        let defaults = suite()
        var settings = AppSettings()
        settings.aiTools.allowedClients = ["/usr/local/bin/node"]
        SettingsStorage.save(settings, to: defaults)
        AIToolsConsentSeal(secrets: InMemorySecretStore(), location: .defaults(defaults)).save(settings.aiTools)
        let (loaded, wasReset) = load(defaults, InMemorySecretStore())
        #expect(wasReset)
        #expect(loaded.allowedClients.isEmpty)
    }

    @Test func defaultsWithoutSealAreLeftAlone() {
        let defaults = suite()
        let secrets = InMemorySecretStore()
        var settings = AppSettings()
        settings.aiTools.enabled = true
        SettingsStorage.save(settings, to: defaults)
        let (loaded, wasReset) = load(defaults, secrets)
        #expect(!wasReset)
        #expect(loaded == settings.aiTools)
        #expect((try? secrets.secret(for: AIToolsConsentSeal.keyName)) == nil)
    }

    @Test func resetWritesAFreshSealSoNextLoadIsQuiet() {
        let defaults = suite()
        let secrets = InMemorySecretStore()
        var settings = AppSettings()
        settings.aiTools.allowedClients = ["/tmp/x"]
        SettingsStorage.save(settings, to: defaults)
        let (first, firstReset) = load(defaults, secrets)
        #expect(firstReset)
        var fixed = settings
        fixed.aiTools = first
        SettingsStorage.save(fixed, to: defaults)
        let (_, secondReset) = load(defaults, secrets)
        #expect(!secondReset)
    }

    @Test func fileLocationWorks() throws {
        let folder = FileManager.default.temporaryDirectory.appendingPathComponent("seal-\(UUID().uuidString)")
        defer { try? FileManager.default.removeItem(at: folder) }
        let file = folder.appendingPathComponent("settings.json")
        let secrets = InMemorySecretStore()
        let seal = AIToolsConsentSeal(secrets: secrets, location: .file(file))
        var settings = AppSettings()
        settings.aiTools.allowedClients = ["/usr/local/bin/node"]
        try SettingsStorage.save(settings, toFile: file)
        seal.save(settings.aiTools)
        #expect(!seal.verifiedOrReset(settings.aiTools).wasReset)
        settings.aiTools.allowedClients = ["/tmp/x"]
        #expect(seal.verifiedOrReset(settings.aiTools).wasReset)
    }
}
