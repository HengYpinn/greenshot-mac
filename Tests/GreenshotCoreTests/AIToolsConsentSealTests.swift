// Greenshot for Mac (Community) - an unofficial macOS port of Greenshot
// Copyright (C) 2026 Greenshot for Mac (Community) contributors
// SPDX-License-Identifier: GPL-3.0-or-later

import Foundation
import Testing
@testable import GreenshotCore

/// A user defaults suite of its own whose name is a path in a new temporary folder, so its file is kept there and not
/// in ~/Library/Preferences (where `removePersistentDomain` can leave it): the test removes the domain and the folder in
/// a `defer`. For every test that checks the user defaults themselves.
func temporarySuite() -> (defaults: UserDefaults, name: String, folder: URL) {
    let folder = FileManager.default.temporaryDirectory.appendingPathComponent("defaults-test-\(UUID().uuidString)", isDirectory: true)
    try? FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
    let name = folder.appendingPathComponent("settings").path
    return (UserDefaults(suiteName: name)!, name, folder)
}

/// Whether loading `settings` with `seal` resets them (their seal is missing or wrong), like the start does.
func consentIsReset(_ settings: AIToolsSettings, seal: AIToolsConsentSeal) -> Bool {
    let keeper = AIToolsConsentKeeper(seal: seal, loaded: settings)
    return !AIToolsConsentSeal.sealedValuesEqual(keeper.stored, settings)
}

/// The AI tools consent is sealed: an edit of the settings outside Greenshot is reset at load.
@Suite struct AIToolsConsentSealTests {
    private static let attackerJSON = """
    {"aiTools":{"enabled":true,"allowedClients":["/tmp/x"],"notifyOnCapture":false,"excludedApplications":[]}}
    """

    /// The consent as the start loads it from `file`: what is in effect, and whether it was reset.
    private func load(_ file: URL, _ secrets: InMemorySecretStore) -> (AIToolsSettings, Bool) {
        let loaded = SettingsStorage.load(fromFile: file).aiTools
        let keeper = AIToolsConsentKeeper(seal: AIToolsConsentSeal(secrets: secrets, location: .file(file)), loaded: loaded)
        return (keeper.inEffect, !AIToolsConsentSeal.sealedValuesEqual(keeper.stored, loaded))
    }

    @Test func unsealedEditIsReset() throws {
        let file = consentSettingsFile()
        defer { try? FileManager.default.removeItem(at: file.deletingLastPathComponent()) }
        let secrets = InMemorySecretStore()
        try FileManager.default.createDirectory(at: file.deletingLastPathComponent(), withIntermediateDirectories: true)
        try Data(Self.attackerJSON.utf8).write(to: file)
        let (loaded, wasReset) = load(file, secrets)
        #expect(wasReset)
        #expect(loaded.enabled)
        #expect(loaded.allowedClients.isEmpty)
        #expect(loaded.notifyOnCapture)
        #expect(loaded.excludedApplications == AIToolsSettings.defaultExcludedApplications)
        let client = AIToolClient(path: "/tmp/x", displayName: "x")
        #expect(!AIToolAccess.isAllowed(client, settings: loaded))
    }

    @Test func resetKeepsStoredExtraExclusions() throws {
        let file = consentSettingsFile()
        defer { try? FileManager.default.removeItem(at: file.deletingLastPathComponent()) }
        var settings = AppSettings()
        settings.aiTools.excludedApplications = ["1password", "MyVault"]
        try SettingsStorage.save(settings, toFile: file)
        let (loaded, wasReset) = load(file, InMemorySecretStore())
        #expect(wasReset)
        #expect(loaded.excludedApplications.count == AIToolsSettings.defaultExcludedApplications.count + 1)
        #expect(loaded.excludedApplications.last == "MyVault")
    }

    @Test func savedValuesSurviveLoad() throws {
        let file = consentSettingsFile()
        defer { try? FileManager.default.removeItem(at: file.deletingLastPathComponent()) }
        let secrets = InMemorySecretStore()
        var settings = AppSettings()
        settings.aiTools.allowedClients = ["/usr/local/bin/node"]
        settings.aiTools.notifyOnCapture = false
        settings.aiTools.excludedApplications.removeAll { $0 == "Passwords" }
        try SettingsStorage.save(settings, toFile: file)
        try AIToolsConsentSeal(secrets: secrets, location: .file(file)).save(settings.aiTools)
        let (loaded, wasReset) = load(file, secrets)
        #expect(!wasReset)
        #expect(loaded == settings.aiTools)
        #expect(!loaded.excludedApplications.contains("Passwords"))
    }

    @Test func editAfterSealingIsReset() throws {
        let file = consentSettingsFile()
        defer { try? FileManager.default.removeItem(at: file.deletingLastPathComponent()) }
        let secrets = InMemorySecretStore()
        var settings = AppSettings()
        settings.aiTools.allowedClients = ["/usr/local/bin/node"]
        try SettingsStorage.save(settings, toFile: file)
        try AIToolsConsentSeal(secrets: secrets, location: .file(file)).save(settings.aiTools)
        settings.aiTools.allowedClients.append("/tmp/x")
        try SettingsStorage.save(settings, toFile: file)
        let (loaded, wasReset) = load(file, secrets)
        #expect(wasReset)
        #expect(loaded.allowedClients.isEmpty)
    }

    @Test func sealFromAnotherKeyIsReset() throws {
        let file = consentSettingsFile()
        defer { try? FileManager.default.removeItem(at: file.deletingLastPathComponent()) }
        var settings = AppSettings()
        settings.aiTools.allowedClients = ["/usr/local/bin/node"]
        try SettingsStorage.save(settings, toFile: file)
        try AIToolsConsentSeal(secrets: InMemorySecretStore(), location: .file(file)).save(settings.aiTools)
        let (loaded, wasReset) = load(file, InMemorySecretStore())
        #expect(wasReset)
        #expect(loaded.allowedClients.isEmpty)
    }

    @Test func defaultsWithoutSealAreLeftAlone() throws {
        let file = consentSettingsFile()
        defer { try? FileManager.default.removeItem(at: file.deletingLastPathComponent()) }
        let secrets = InMemorySecretStore()
        var settings = AppSettings()
        settings.aiTools.enabled = true
        try SettingsStorage.save(settings, toFile: file)
        let (loaded, wasReset) = load(file, secrets)
        #expect(!wasReset)
        #expect(loaded == settings.aiTools)
        #expect((try? secrets.secret(for: AIToolsConsentSeal.keyName)) == nil)
    }

    @Test func resetWritesAFreshSealSoNextLoadIsQuiet() throws {
        let file = consentSettingsFile()
        defer { try? FileManager.default.removeItem(at: file.deletingLastPathComponent()) }
        let secrets = InMemorySecretStore()
        var settings = AppSettings()
        settings.aiTools.allowedClients = ["/tmp/x"]
        settings.aiTools.excludedApplications.append("MyVault")
        try SettingsStorage.save(settings, toFile: file)
        let (first, firstReset) = load(file, secrets)
        #expect(firstReset)
        var fixed = settings
        fixed.aiTools = first
        try SettingsStorage.save(fixed, toFile: file)
        let (_, secondReset) = load(file, secrets)
        #expect(!secondReset)
    }

    /// The app's own place (the user defaults, `settings.v1` and the seal next to it): the same as a settings file.
    @Test func theUserDefaultsLocationWorks() throws {
        let suite = temporarySuite()
        defer {
            suite.defaults.removePersistentDomain(forName: suite.name)
            try? FileManager.default.removeItem(at: suite.folder)
        }
        let defaults = suite.defaults
        let secrets = InMemorySecretStore()
        let seal = AIToolsConsentSeal(secrets: secrets, location: .defaults(defaults))
        // Edited outside Greenshot: reset
        defaults.set(Data(Self.attackerJSON.utf8), forKey: SettingsStorage.key)
        #expect(consentIsReset(SettingsStorage.load(from: defaults).aiTools, seal: seal))
        // Sealed by Greenshot: kept; the seal sits next to the settings
        var settings = AppSettings()
        settings.aiTools.allowedClients = ["/usr/local/bin/node"]
        SettingsStorage.save(settings, to: defaults)
        try seal.save(settings.aiTools)
        #expect(defaults.string(forKey: AIToolsConsentSeal.defaultsKey) == seal.storedSeal)
        #expect(!consentIsReset(SettingsStorage.load(from: defaults).aiTools, seal: seal))
        // Edited after sealing: reset
        settings.aiTools.allowedClients.append("/tmp/x")
        SettingsStorage.save(settings, to: defaults)
        #expect(consentIsReset(SettingsStorage.load(from: defaults).aiTools, seal: seal))
        // The place is part of the signed text
        #expect(seal.locationName == "defaults")
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
        let file = consentSettingsFile()
        defer { try? FileManager.default.removeItem(at: file.deletingLastPathComponent()) }
        let secrets = InMemorySecretStore()
        let seal = AIToolsConsentSeal(secrets: secrets, location: .file(file))
        var a = AIToolsSettings()
        a.allowedClients = ["/usr/local/bin/node", "/tmp/old"]
        try seal.save(a)
        let sealA = try Data(contentsOf: sealFile(file))
        var b = a
        b.allowedClients = ["/usr/local/bin/node"]
        try seal.save(b)
        #expect(!consentIsReset(b, seal: seal))
        try sealA.write(to: sealFile(file))
        #expect(consentIsReset(a, seal: seal))
    }

    @Test func anOldSealDoesNotVerifyAfterTheDefaultsWereSaved() throws {
        // Allow X, then remove it (back to the defaults): putting X and its old seal back must reset (second review, 1).
        let file = consentSettingsFile()
        defer { try? FileManager.default.removeItem(at: file.deletingLastPathComponent()) }
        let seal = AIToolsConsentSeal(secrets: InMemorySecretStore(), location: .file(file))
        var allowed = AIToolsSettings()
        allowed.allowedClients = ["/tmp/x"]
        try seal.save(allowed)
        let oldSeal = try Data(contentsOf: sealFile(file))
        try seal.save(AIToolsSettings())
        #expect(storedSealText(file) == nil)
        try oldSeal.write(to: sealFile(file))
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
