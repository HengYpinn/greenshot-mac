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

@Suite struct AIToolsConsentSealRollbackTests {
    @Test func oldSettingsWithOldSealAreReset() {
        let name = "seal-test-\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: name)!
        defer { defaults.removePersistentDomain(forName: name) }
        let secrets = InMemorySecretStore()
        let seal = AIToolsConsentSeal(secrets: secrets, location: .defaults(defaults))
        var a = AIToolsSettings()
        a.allowedClients = ["/usr/local/bin/node", "/tmp/old"]
        seal.save(a)
        let sealA = defaults.string(forKey: AIToolsConsentSeal.defaultsKey)
        var b = a
        b.allowedClients = ["/usr/local/bin/node"]
        seal.save(b)
        #expect(!seal.verifiedOrReset(b).wasReset)
        defaults.set(sealA, forKey: AIToolsConsentSeal.defaultsKey)
        #expect(seal.verifiedOrReset(a).wasReset)
    }

    @Test func anOldSealDoesNotVerifyAfterTheDefaultsWereSaved() {
        // Allow X, then remove it (back to the defaults): putting X and its old seal back must reset (second review, 1).
        let name = "seal-test-\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: name)!
        defer { defaults.removePersistentDomain(forName: name) }
        let seal = AIToolsConsentSeal(secrets: InMemorySecretStore(), location: .defaults(defaults))
        var allowed = AIToolsSettings()
        allowed.allowedClients = ["/tmp/x"]
        seal.save(allowed)
        let oldSeal = defaults.string(forKey: AIToolsConsentSeal.defaultsKey)
        #expect(oldSeal != nil)
        seal.save(AIToolsSettings())
        defaults.set(oldSeal, forKey: AIToolsConsentSeal.defaultsKey)
        let outcome = seal.verifiedOrReset(allowed)
        #expect(outcome.wasReset)
        #expect(outcome.settings.allowedClients.isEmpty)
    }

    @Test func sealOfAnotherLocationDoesNotVerify() throws {
        let secrets = InMemorySecretStore()
        let folder = FileManager.default.temporaryDirectory.appendingPathComponent("seal-\(UUID().uuidString)")
        defer { try? FileManager.default.removeItem(at: folder) }
        let one = folder.appendingPathComponent("one.json")
        let two = folder.appendingPathComponent("two.json")
        var a = AIToolsSettings()
        a.allowedClients = ["/usr/local/bin/node"]
        AIToolsConsentSeal(secrets: secrets, location: .file(one)).save(a)
        try FileManager.default.copyItem(at: URL(fileURLWithPath: one.path + ".aitools-seal"), to: URL(fileURLWithPath: two.path + ".aitools-seal"))
        #expect(AIToolsConsentSeal(secrets: secrets, location: .file(two)).verifiedOrReset(a).wasReset)
    }

    @Test func unforcedDefaultsCannotSetSealedValues() {
        let source = ManagedValues(unforced: [
            "Greenshot.aiTools.allowedClients": ["/tmp/attacker"], "Greenshot.aiTools.notifyOnCapture": false,
            "Greenshot.defaults": ["aiTools": ["excludedApplications": []]],
            "Greenshot.aiTools.enabled": true,
        ])
        let policy = ManagedPolicy(source: source)
        let loaded = policy.loaded(AppSettings(), storedJSON: Data("{}".utf8))
        #expect(loaded.aiTools.allowedClients.isEmpty)
        #expect(loaded.aiTools.notifyOnCapture)
        #expect(loaded.aiTools.excludedApplications == AIToolsSettings.defaultExcludedApplications)
        #expect(policy.problems.count == 3)
        #expect(policy.problems.allSatisfy { $0.contains("AI tools consent") })
    }

    @Test func forcedValuesStillApply() {
        let policy = ManagedPolicy(source: ManagedValues(forced: ["Greenshot.aiTools.allowedClients": ["/opt/approved"]]))
        let effective = policy.effective(AppSettings())
        #expect(effective.aiTools.allowedClients == ["/opt/approved"])
        #expect(policy.problems.isEmpty)
    }
}
