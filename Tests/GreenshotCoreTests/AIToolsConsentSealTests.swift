// Greenshot for Mac (Community) - an unofficial macOS port of Greenshot
// Copyright (C) 2026 Greenshot for Mac (Community) contributors
// SPDX-License-Identifier: GPL-3.0-or-later

import Foundation
import Testing
@testable import GreenshotCore

/// A user defaults suite of its own and its name; the test removes it in a `defer` (`removePersistentDomain`).
private func consentSuite() -> (UserDefaults, String) {
    let name = "seal-test-\(UUID().uuidString)"
    return (UserDefaults(suiteName: name)!, name)
}

/// Whether loading `settings` with `seal` resets them (their seal is missing or wrong), like the start does.
func consentIsReset(_ settings: AIToolsSettings, seal: AIToolsConsentSeal) -> Bool {
    let keeper = AIToolsConsentKeeper(seal: seal, loaded: settings)
    return !AIToolsConsentSeal.sealedValuesEqual(keeper.stored, settings)
}

/// The AI tools consent is sealed: an edit of the settings outside Greenshot is reset at load.
@Suite struct AIToolsConsentSealTests {
    private func attackerBlob(into defaults: UserDefaults) {
        let json = """
        {"aiTools":{"enabled":true,"allowedClients":["/tmp/x"],"notifyOnCapture":false,"excludedApplications":[]}}
        """
        defaults.set(Data(json.utf8), forKey: SettingsStorage.key)
    }

    /// The consent as the start loads it: what is in effect, and whether it was reset.
    private func load(_ defaults: UserDefaults, _ secrets: InMemorySecretStore) -> (AIToolsSettings, Bool) {
        let loaded = SettingsStorage.load(from: defaults).aiTools
        let keeper = AIToolsConsentKeeper(seal: AIToolsConsentSeal(secrets: secrets, location: .defaults(defaults)), loaded: loaded)
        return (keeper.inEffect, !AIToolsConsentSeal.sealedValuesEqual(keeper.stored, loaded))
    }

    @Test func unsealedEditIsReset() {
        let (defaults, suiteName) = consentSuite()
        defer { defaults.removePersistentDomain(forName: suiteName) }
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
        let (defaults, suiteName) = consentSuite()
        defer { defaults.removePersistentDomain(forName: suiteName) }
        var settings = AppSettings()
        settings.aiTools.excludedApplications = ["1password", "MyVault"]
        SettingsStorage.save(settings, to: defaults)
        let (loaded, wasReset) = load(defaults, InMemorySecretStore())
        #expect(wasReset)
        #expect(loaded.excludedApplications.count == AIToolsSettings.defaultExcludedApplications.count + 1)
        #expect(loaded.excludedApplications.last == "MyVault")
    }

    @Test func savedValuesSurviveLoad() throws {
        let (defaults, suiteName) = consentSuite()
        defer { defaults.removePersistentDomain(forName: suiteName) }
        let secrets = InMemorySecretStore()
        var settings = AppSettings()
        settings.aiTools.allowedClients = ["/usr/local/bin/node"]
        settings.aiTools.notifyOnCapture = false
        settings.aiTools.excludedApplications.removeAll { $0 == "Passwords" }
        SettingsStorage.save(settings, to: defaults)
        try AIToolsConsentSeal(secrets: secrets, location: .defaults(defaults)).save(settings.aiTools)
        let (loaded, wasReset) = load(defaults, secrets)
        #expect(!wasReset)
        #expect(loaded == settings.aiTools)
        #expect(!loaded.excludedApplications.contains("Passwords"))
    }

    @Test func editAfterSealingIsReset() throws {
        let (defaults, suiteName) = consentSuite()
        defer { defaults.removePersistentDomain(forName: suiteName) }
        let secrets = InMemorySecretStore()
        var settings = AppSettings()
        settings.aiTools.allowedClients = ["/usr/local/bin/node"]
        SettingsStorage.save(settings, to: defaults)
        try AIToolsConsentSeal(secrets: secrets, location: .defaults(defaults)).save(settings.aiTools)
        settings.aiTools.allowedClients.append("/tmp/x")
        SettingsStorage.save(settings, to: defaults)
        let (loaded, wasReset) = load(defaults, secrets)
        #expect(wasReset)
        #expect(loaded.allowedClients.isEmpty)
    }

    @Test func sealFromAnotherKeyIsReset() throws {
        let (defaults, suiteName) = consentSuite()
        defer { defaults.removePersistentDomain(forName: suiteName) }
        var settings = AppSettings()
        settings.aiTools.allowedClients = ["/usr/local/bin/node"]
        SettingsStorage.save(settings, to: defaults)
        try AIToolsConsentSeal(secrets: InMemorySecretStore(), location: .defaults(defaults)).save(settings.aiTools)
        let (loaded, wasReset) = load(defaults, InMemorySecretStore())
        #expect(wasReset)
        #expect(loaded.allowedClients.isEmpty)
    }

    @Test func defaultsWithoutSealAreLeftAlone() {
        let (defaults, suiteName) = consentSuite()
        defer { defaults.removePersistentDomain(forName: suiteName) }
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
        let (defaults, suiteName) = consentSuite()
        defer { defaults.removePersistentDomain(forName: suiteName) }
        let secrets = InMemorySecretStore()
        var settings = AppSettings()
        settings.aiTools.allowedClients = ["/tmp/x"]
        settings.aiTools.excludedApplications.append("MyVault")
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
        try seal.save(settings.aiTools)
        #expect(!consentIsReset(settings.aiTools, seal: seal))
        settings.aiTools.allowedClients = ["/tmp/x"]
        #expect(consentIsReset(settings.aiTools, seal: seal))
    }
}

@Suite struct AIToolsConsentSealRollbackTests {
    @Test func oldSettingsWithOldSealAreReset() throws {
        let (defaults, suiteName) = consentSuite()
        defer { defaults.removePersistentDomain(forName: suiteName) }
        let secrets = InMemorySecretStore()
        let seal = AIToolsConsentSeal(secrets: secrets, location: .defaults(defaults))
        var a = AIToolsSettings()
        a.allowedClients = ["/usr/local/bin/node", "/tmp/old"]
        try seal.save(a)
        let sealA = defaults.string(forKey: AIToolsConsentSeal.defaultsKey)
        var b = a
        b.allowedClients = ["/usr/local/bin/node"]
        try seal.save(b)
        #expect(!consentIsReset(b, seal: seal))
        defaults.set(sealA, forKey: AIToolsConsentSeal.defaultsKey)
        #expect(consentIsReset(a, seal: seal))
    }

    @Test func anOldSealDoesNotVerifyAfterTheDefaultsWereSaved() throws {
        // Allow X, then remove it (back to the defaults): putting X and its old seal back must reset (second review, 1).
        let (defaults, suiteName) = consentSuite()
        defer { defaults.removePersistentDomain(forName: suiteName) }
        let seal = AIToolsConsentSeal(secrets: InMemorySecretStore(), location: .defaults(defaults))
        var allowed = AIToolsSettings()
        allowed.allowedClients = ["/tmp/x"]
        try seal.save(allowed)
        let oldSeal = defaults.string(forKey: AIToolsConsentSeal.defaultsKey)
        #expect(oldSeal != nil)
        try seal.save(AIToolsSettings())
        defaults.set(oldSeal, forKey: AIToolsConsentSeal.defaultsKey)
        let keeper = AIToolsConsentKeeper(seal: seal, loaded: allowed)
        #expect(keeper.inEffect.allowedClients.isEmpty)
        #expect(keeper.stored.allowedClients.isEmpty)
    }

    @Test func sealOfAnotherLocationDoesNotVerify() throws {
        let secrets = InMemorySecretStore()
        let folder = FileManager.default.temporaryDirectory.appendingPathComponent("seal-\(UUID().uuidString)")
        defer { try? FileManager.default.removeItem(at: folder) }
        let one = folder.appendingPathComponent("one.json")
        let two = folder.appendingPathComponent("two.json")
        var a = AIToolsSettings()
        a.allowedClients = ["/usr/local/bin/node"]
        try AIToolsConsentSeal(secrets: secrets, location: .file(one)).save(a)
        try FileManager.default.copyItem(at: URL(fileURLWithPath: one.path + ".aitools-seal"), to: URL(fileURLWithPath: two.path + ".aitools-seal"))
        #expect(consentIsReset(a, seal: AIToolsConsentSeal(secrets: secrets, location: .file(two))))
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
