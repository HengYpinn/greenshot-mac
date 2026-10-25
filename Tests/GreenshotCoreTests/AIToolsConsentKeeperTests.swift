// Greenshot for Mac (Community) - an unofficial macOS port of Greenshot
// Copyright (C) 2026 Greenshot for Mac (Community) contributors
// SPDX-License-Identifier: GPL-3.0-or-later

import Foundation
import Testing
@testable import GreenshotCore

/// A secret store like the login keychain whose reads and writes can be locked apart (the read prompt cancelled, the
/// password typed at the write prompt): a locked call throws `SecretStoreUnavailableError` and changes nothing. Counts
/// the reads, writes and deletes it was asked for.
final class SplitLockSecretStore: SecretStore, @unchecked Sendable {
    private let base = InMemorySecretStore()
    private let lock = NSLock()
    private var readsAreLocked = false
    private var writesAreLocked = false
    private var deletesAreLocked = false
    private var readCount = 0
    private var writeCount = 0
    private var deleteCount = 0

    var readsLocked: Bool {
        get { lock.withLock { readsAreLocked } }
        set { lock.withLock { readsAreLocked = newValue } }
    }

    var writesLocked: Bool {
        get { lock.withLock { writesAreLocked } }
        set { lock.withLock { writesAreLocked = newValue } }
    }

    /// Removing an item. By Apple's sources a locked login keychain deletes without the password; not observed here.
    var deletesLocked: Bool {
        get { lock.withLock { deletesAreLocked } }
        set { lock.withLock { deletesAreLocked = newValue } }
    }

    /// Reads, writes and deletes at once.
    var isLocked: Bool {
        get { readsLocked && writesLocked && deletesLocked }
        set {
            readsLocked = newValue
            writesLocked = newValue
            deletesLocked = newValue
        }
    }

    var reads: Int { lock.withLock { readCount } }
    var writes: Int { lock.withLock { writeCount } }
    var deletes: Int { lock.withLock { deleteCount } }
    /// Every call: reads, writes and deletes.
    var calls: Int { lock.withLock { readCount + writeCount + deleteCount } }

    /// What is stored, without counting a read.
    func value(_ key: String) -> String? {
        (try? base.secret(for: key)) ?? nil
    }

    func secret(for key: String) throws -> String? {
        let isLocked = lock.withLock {
            readCount += 1
            return readsAreLocked
        }
        if isLocked { throw SecretStoreUnavailableError("The Keychain is locked.") }
        return try base.secret(for: key)
    }

    func setSecret(_ value: String?, for key: String) throws {
        let isLocked = lock.withLock {
            if value == nil {
                deleteCount += 1
                return deletesAreLocked
            }
            writeCount += 1
            return writesAreLocked
        }
        if isLocked { throw SecretStoreUnavailableError("The Keychain is locked.") }
        try base.setSecret(value, for: key)
    }
}

/// A settings file of its own (`--settings-dir`) in a new temporary folder; the test removes the folder in a `defer`.
/// Not a user defaults suite: removing one leaves an empty file in ~/Library/Preferences.
func consentSettingsFile() -> URL {
    FileManager.default.temporaryDirectory.appendingPathComponent("consent-keeper-\(UUID().uuidString)", isDirectory: true)
        .appendingPathComponent("settings.json")
}

/// The seal stored next to `file`, read without the key.
func storedSealText(_ file: URL) -> String? {
    AIToolsConsentSeal(secrets: InMemorySecretStore(), location: .file(file)).storedSeal
}

/// The file of the seal next to `file`.
func sealFile(_ file: URL) -> URL {
    file.appendingPathExtension("aitools-seal")
}

/// Programs allowed, the notification off: what a user who uses AI tools has.
func consentAllowing(_ paths: String...) -> AIToolsSettings {
    var settings = AIToolsSettings()
    settings.allowedClients = paths
    settings.notifyOnCapture = false
    return settings
}


/// One run of the app driving the keeper as `SettingsStore` does: the settings' sealed values in the file are always
/// the keeper's `stored`, written after it sealed. A new run on the same file and store is a restart.
struct ConsentRun {
    let file: URL
    let secrets: SplitLockSecretStore
    var keeper: AIToolsConsentKeeper
    /// What the user was told.
    var notices: [AIToolsConsentKeeper.Notice] = []

    /// The start.
    init(_ file: URL, _ secrets: SplitLockSecretStore) {
        self.file = file
        self.secrets = secrets
        keeper = AIToolsConsentKeeper(seal: AIToolsConsentSeal(secrets: secrets, location: .file(file)),
                                      loaded: Self.onDisk(file))
        write()
    }

    static func onDisk(_ file: URL) -> AIToolsSettings {
        SettingsStorage.load(fromFile: file).aiTools
    }

    var inEffect: AIToolsSettings { keeper.inEffect }
    var status: AIToolsConsentKeeper.Status { keeper.status }

    /// The settings saved with the sealed values to store, when they changed.
    private func write() {
        var settings = SettingsStorage.load(fromFile: file)
        let sealed = AIToolsConsentSeal.withSealedValues(of: keeper.stored, in: settings.aiTools)
        guard sealed != settings.aiTools else { return }
        settings.aiTools = sealed
        do {
            try SettingsStorage.save(settings, toFile: file)
        } catch {
            Issue.record(error)
        }
    }

    /// The user changes the consent in effect (the question's Allow, Settings › AI Tools).
    mutating func edit(_ body: (inout AIToolsSettings) -> Void) {
        let before = keeper.inEffect
        var after = before
        body(&after)
        if let notice = keeper.change(from: before, to: after) { notices.append(notice) }
        save()
    }

    /// A save of the settings, e.g. at every capture (`${NUM}`, the last region).
    mutating func save() {
        write()
        keeper.settingsSaved()
    }

    /// Retry in Settings › AI Tools.
    mutating func retry() {
        keeper.check()
        write()
    }

    /// `greenshot-cli --reload`.
    mutating func reload() {
        keeper.reload(Self.onDisk(file))
        write()
    }
}

/// The programs allowed after a restart on the same suite and store.
func allowedAfterRestart(_ file: URL, _ secrets: SplitLockSecretStore) -> [String] {
    ConsentRun(file, secrets).inEffect.allowedClients
}

/// The seal is written before the settings, and a seal that can't be written leaves the stored one alone.
@Suite struct AIToolsConsentSealSavingTests {
    @Test func aKeyThatCantBeWrittenKeepsTheStoredSeal() throws {
        let file = consentSettingsFile()
        defer { try? FileManager.default.removeItem(at: file.deletingLastPathComponent()) }
        let secrets = SplitLockSecretStore()
        let seal = AIToolsConsentSeal(secrets: secrets, location: .file(file))
        let allowed = consentAllowing("/A")
        try seal.save(allowed)
        let storedSeal = storedSealText(file)
        let key = secrets.value(AIToolsConsentSeal.keyName)

        secrets.writesLocked = true
        #expect(throws: SecretStoreUnavailableError.self) { try seal.save(consentAllowing("/A", "/X")) }
        #expect(storedSealText(file) == storedSeal)
        #expect(secrets.value(AIToolsConsentSeal.keyName) == key)
        secrets.writesLocked = false
        #expect(seal.verification(of: allowed) == .valid)
    }

    /// The defaults need no seal, but the key goes first: while it can't, the stored seal stays too.
    @Test func theDefaultsKeepTheSealWhileTheKeyCantBeRemoved() throws {
        let file = consentSettingsFile()
        defer { try? FileManager.default.removeItem(at: file.deletingLastPathComponent()) }
        let secrets = SplitLockSecretStore()
        let seal = AIToolsConsentSeal(secrets: secrets, location: .file(file))
        try seal.save(consentAllowing("/A"))
        let storedSeal = seal.storedSeal
        secrets.isLocked = true
        #expect(throws: SecretStoreUnavailableError.self) { try seal.save(AIToolsSettings()) }
        #expect(seal.storedSeal == storedSeal)
        secrets.isLocked = false
        try seal.save(AIToolsSettings())
        #expect(seal.storedSeal == nil)
        #expect(secrets.value(AIToolsConsentSeal.keyName) == nil)
    }

    /// Without a stored seal there is nothing to check: invalid, whatever the Keychain says, and the key isn't read.
    @Test func noSealIsInvalidEvenWhileLocked() {
        let file = consentSettingsFile()
        defer { try? FileManager.default.removeItem(at: file.deletingLastPathComponent()) }
        let secrets = SplitLockSecretStore()
        secrets.isLocked = true
        let seal = AIToolsConsentSeal(secrets: secrets, location: .file(file))
        #expect(seal.verification(of: consentAllowing("/tmp/x")) == .invalid)
        #expect(secrets.reads == 0)
    }

    @Test func onlyTheSealedValuesCount() {
        let allowed = consentAllowing("/usr/local/bin/node")
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
}

/// The AI tools consent while the Keychain is locked: nothing is allowed that the user didn't allow, nothing stored is
/// lost, a restriction holds, and a locked Keychain isn't asked at every save (security review F1, F3-F5).
@Suite struct AIToolsConsentKeeperTests {
    /// A first run that allowed `paths` (and switched the notification off), sealed.
    private func allowedBefore(_ file: URL, _ secrets: SplitLockSecretStore, _ paths: String...) {
        var run = ConsentRun(file, secrets)
        run.edit { settings in
            settings.allowedClients = paths
            settings.notifyOnCapture = false
        }
        #expect(!run.status.needsAttention)
    }

    // MARK: Locked at the start

    @Test func aLockedStartKeepsTheConsentStoredButNotInEffect() {
        let file = consentSettingsFile()
        defer { try? FileManager.default.removeItem(at: file.deletingLastPathComponent()) }
        let secrets = SplitLockSecretStore()
        allowedBefore(file, secrets, "/A")
        let storedSeal = storedSealText(file)
        let key = secrets.value(AIToolsConsentSeal.keyName)
        let writes = secrets.writes

        secrets.isLocked = true
        let run = ConsentRun(file, secrets)
        // In effect: nobody allowed, the notification on, like a seal that doesn't match.
        #expect(run.inEffect.allowedClients.isEmpty)
        #expect(run.inEffect.notifyOnCapture)
        #expect(run.status.isUnverifiable)
        #expect(run.status.problem != nil)
        // Not saved: the stored values, their seal and key stay for when the Keychain can be read.
        #expect(ConsentRun.onDisk(file) == consentAllowing("/A"))
        #expect(storedSealText(file) == storedSeal)
        #expect(secrets.writes == writes)

        secrets.isLocked = false
        #expect(secrets.value(AIToolsConsentSeal.keyName) == key)
        let unlocked = ConsentRun(file, secrets)
        #expect(unlocked.inEffect == consentAllowing("/A"))
        #expect(!unlocked.status.needsAttention)
    }

    /// The negative control: a seal that doesn't match is still reset, and the reset sealed and saved.
    @Test func aWrongSealIsStillResetAndSaved() throws {
        let file = consentSettingsFile()
        defer { try? FileManager.default.removeItem(at: file.deletingLastPathComponent()) }
        let secrets = SplitLockSecretStore()
        allowedBefore(file, secrets, "/A")
        // An extra exclusion survives the reset, so the reset isn't the defaults (which need no seal) and is sealed.
        var edited = SettingsStorage.load(fromFile: file)
        edited.aiTools.allowedClients = ["/tmp/attacker"]
        edited.aiTools.excludedApplications.append("MyVault")
        try SettingsStorage.save(edited, toFile: file)
        let run = ConsentRun(file, secrets)
        #expect(run.inEffect.allowedClients.isEmpty)
        #expect(run.inEffect.excludedApplications.contains("MyVault"))
        #expect(!run.status.needsAttention)
        let onDisk = ConsentRun.onDisk(file)
        #expect(onDisk == run.inEffect)
        let seal = AIToolsConsentSeal(secrets: secrets, location: .file(file))
        #expect(seal.verification(of: onDisk) == .valid)
    }

    /// Q2a: locked at the start, "Allow" X, every prompt cancelled: X until Greenshot quits, A kept.
    @Test func allowingWhileTheConsentCantBeCheckedKeepsTheStoredOne() {
        let file = consentSettingsFile()
        defer { try? FileManager.default.removeItem(at: file.deletingLastPathComponent()) }
        let secrets = SplitLockSecretStore()
        allowedBefore(file, secrets, "/A")
        let storedSeal = storedSealText(file)
        let key = secrets.value(AIToolsConsentSeal.keyName)

        secrets.isLocked = true
        var run = ConsentRun(file, secrets)
        run.edit { $0.allowedClients.append("/X") }
        #expect(run.inEffect.allowedClients == ["/X"])
        #expect(run.notices == [.untilQuit])
        #expect(run.status.isUnverifiable)
        #expect(run.status.hasChangesUntilQuit)
        #expect(!run.status.isStoredUnsealed)
        // Nothing stored changed: the values, the seal and the key.
        #expect(ConsentRun.onDisk(file) == consentAllowing("/A"))
        #expect(storedSealText(file) == storedSeal)
        #expect(secrets.value(AIToolsConsentSeal.keyName) == key)

        secrets.isLocked = false
        let restarted = ConsentRun(file, secrets)
        #expect(restarted.inEffect == consentAllowing("/A"))
    }

    /// Q2a with Retry: unlocked later in the same run, the earlier programs come back with the new one, sealed.
    @Test func retryAfterUnlockingKeepsTheEarlierAndTheNewProgram() {
        let file = consentSettingsFile()
        defer { try? FileManager.default.removeItem(at: file.deletingLastPathComponent()) }
        let secrets = SplitLockSecretStore()
        allowedBefore(file, secrets, "/A")
        secrets.isLocked = true
        var run = ConsentRun(file, secrets)
        run.edit { $0.allowedClients.append("/X") }
        run.retry()
        #expect(run.status.isUnverifiable)

        secrets.isLocked = false
        run.retry()
        #expect(run.inEffect.allowedClients == ["/A", "/X"])
        #expect(!run.inEffect.notifyOnCapture)
        #expect(!run.status.needsAttention)
        #expect(run.status.problem == nil)
        let restarted = ConsentRun(file, secrets)
        #expect(restarted.inEffect.allowedClients == ["/A", "/X"])
    }

    /// Q2b: the read prompt cancelled, the password typed at the write prompt. The key isn't written over values that
    /// weren't checked: A stays.
    @Test func aKeyThatCantBeReadIsNeverWrittenOverUncheckedValues() {
        let file = consentSettingsFile()
        defer { try? FileManager.default.removeItem(at: file.deletingLastPathComponent()) }
        let secrets = SplitLockSecretStore()
        allowedBefore(file, secrets, "/A")
        let key = secrets.value(AIToolsConsentSeal.keyName)
        secrets.isLocked = true
        var run = ConsentRun(file, secrets)
        secrets.writesLocked = false
        secrets.deletesLocked = false
        let writes = secrets.writes
        run.edit { $0.allowedClients.append("/X") }
        #expect(secrets.writes == writes)
        #expect(secrets.value(AIToolsConsentSeal.keyName) == key)

        secrets.isLocked = false
        let restarted = ConsentRun(file, secrets)
        #expect(restarted.inEffect.allowedClients == ["/A"])
    }

    /// Q2c: the password typed at the check of the change: A and X, sealed.
    @Test func unlockingAtTheChangeKeepsBoth() {
        let file = consentSettingsFile()
        defer { try? FileManager.default.removeItem(at: file.deletingLastPathComponent()) }
        let secrets = SplitLockSecretStore()
        allowedBefore(file, secrets, "/A")
        secrets.isLocked = true
        var run = ConsentRun(file, secrets)
        secrets.isLocked = false
        run.edit { $0.allowedClients.append("/X") }
        #expect(run.inEffect.allowedClients == ["/A", "/X"])
        #expect(run.notices.isEmpty)
        let restarted = ConsentRun(file, secrets)
        #expect(restarted.inEffect.allowedClients == ["/A", "/X"])
        #expect(!restarted.inEffect.notifyOnCapture)
    }

    /// Q2d: an exclusion added while the consent can't be checked takes effect and is stored at once (unsealed: the
    /// next start resets, the exclusion holds). The key stays, so Retry can still keep A.
    @Test func anExclusionAddedWhileLockedIsStoredAndHolds() {
        let file = consentSettingsFile()
        defer { try? FileManager.default.removeItem(at: file.deletingLastPathComponent()) }
        let secrets = SplitLockSecretStore()
        allowedBefore(file, secrets, "/A")
        let key = secrets.value(AIToolsConsentSeal.keyName)
        secrets.isLocked = true
        var run = ConsentRun(file, secrets)
        run.edit { $0.excludedApplications.append("Vault") }
        #expect(run.inEffect.excludedApplications.contains("Vault"))
        #expect(run.inEffect.allowedClients.isEmpty)
        #expect(run.notices == [.storedUnsealed])
        #expect(run.status.isStoredUnsealed)
        #expect(ConsentRun.onDisk(file).excludedApplications.contains("Vault"))
        #expect(ConsentRun.onDisk(file).allowedClients == ["/A"])
        #expect(secrets.value(AIToolsConsentSeal.keyName) == key)

        secrets.isLocked = false
        let restarted = ConsentRun(file, secrets)
        #expect(restarted.inEffect.allowedClients.isEmpty)
        #expect(restarted.inEffect.notifyOnCapture)
        #expect(restarted.inEffect.excludedApplications.contains("Vault"))
    }

    /// Q2d with Retry: unlocked in the same run, A and the exclusion are sealed together.
    @Test func retryKeepsTheProgramsAndTheExclusion() {
        let file = consentSettingsFile()
        defer { try? FileManager.default.removeItem(at: file.deletingLastPathComponent()) }
        let secrets = SplitLockSecretStore()
        allowedBefore(file, secrets, "/A")
        secrets.isLocked = true
        var run = ConsentRun(file, secrets)
        run.edit { $0.excludedApplications.append("Vault") }
        secrets.isLocked = false
        run.retry()
        #expect(!run.status.needsAttention)
        let restarted = ConsentRun(file, secrets)
        #expect(restarted.inEffect.allowedClients == ["/A"])
        #expect(restarted.inEffect.excludedApplications.contains("Vault"))
    }

    /// A program allowed for this run, then removed again: nothing stored changed, so nothing is unsealed.
    @Test func removingAProgramAllowedForThisRunStoresNothing() {
        let file = consentSettingsFile()
        defer { try? FileManager.default.removeItem(at: file.deletingLastPathComponent()) }
        let secrets = SplitLockSecretStore()
        allowedBefore(file, secrets, "/A")
        secrets.isLocked = true
        var run = ConsentRun(file, secrets)
        run.edit { $0.allowedClients.append("/X") }
        run.edit { $0.allowedClients.removeAll { $0 == "/X" } }
        #expect(run.inEffect.allowedClients.isEmpty)
        #expect(run.notices == [.untilQuit])
        #expect(!run.status.isStoredUnsealed)
        #expect(!run.status.hasChangesUntilQuit)
        #expect(ConsentRun.onDisk(file) == consentAllowing("/A"))
    }

    // MARK: Locked during a run

    /// Q3a: checked at the start, then the Keychain locks: saves don't use it, nothing changes.
    @Test func savesDontAskALockedKeychain() {
        let file = consentSettingsFile()
        defer { try? FileManager.default.removeItem(at: file.deletingLastPathComponent()) }
        let secrets = SplitLockSecretStore()
        allowedBefore(file, secrets, "/A")
        var run = ConsentRun(file, secrets)
        secrets.isLocked = true
        let calls = secrets.calls
        for _ in 0..<5 { run.save() }
        #expect(secrets.calls == calls)
        #expect(run.inEffect.allowedClients == ["/A"])
        #expect(!run.status.needsAttention)
    }

    /// Q3c / F4: the default consent (most users): no Keychain call at the start or at any save.
    @Test func theDefaultConsentNeverUsesTheKeychain() {
        let file = consentSettingsFile()
        defer { try? FileManager.default.removeItem(at: file.deletingLastPathComponent()) }
        let secrets = SplitLockSecretStore()
        var run = ConsentRun(file, secrets)
        for _ in 0..<5 { run.save() }
        #expect(secrets.calls == 0)
        #expect(!run.status.needsAttention)
    }

    /// Q3d: "Allow" X while the Keychain is locked during the run: X until Greenshot quits, A sealed as it was; saves
    /// don't retry, Retry after unlocking keeps both.
    @Test func allowingDuringALockKeepsTheSealAndRetryKeepsIt() {
        let file = consentSettingsFile()
        defer { try? FileManager.default.removeItem(at: file.deletingLastPathComponent()) }
        let secrets = SplitLockSecretStore()
        allowedBefore(file, secrets, "/A")
        var run = ConsentRun(file, secrets)
        let storedSeal = storedSealText(file)
        secrets.isLocked = true
        run.edit { $0.allowedClients.append("/X") }
        #expect(run.inEffect.allowedClients == ["/A", "/X"])
        #expect(run.notices == [.untilQuit])
        #expect(run.status.hasChangesUntilQuit)
        #expect(!run.status.isStoredUnsealed)
        #expect(storedSealText(file) == storedSeal)
        #expect(ConsentRun.onDisk(file).allowedClients == ["/A"])
        let calls = secrets.calls
        for _ in 0..<5 { run.save() }
        #expect(secrets.calls == calls)

        // Quit now: A stays, X was for this run.
        secrets.isLocked = false
        #expect(allowedAfterRestart(file, secrets) == ["/A"])
        run.retry()
        #expect(!run.status.needsAttention)
        #expect(allowedAfterRestart(file, secrets) == ["/A", "/X"])
    }

    /// The next change after unlocking seals the earlier one of this run too.
    @Test func theNextChangeSealsTheEarlierOnes() {
        let file = consentSettingsFile()
        defer { try? FileManager.default.removeItem(at: file.deletingLastPathComponent()) }
        let secrets = SplitLockSecretStore()
        allowedBefore(file, secrets, "/A")
        var run = ConsentRun(file, secrets)
        secrets.isLocked = true
        run.edit { $0.allowedClients.append("/X") }
        secrets.isLocked = false
        run.edit { $0.allowedClients.append("/Y") }
        #expect(!run.status.needsAttention)
        #expect(allowedAfterRestart(file, secrets) == ["/A", "/X", "/Y"])
    }

    /// Q3b: a program removed while the Keychain is locked during the run: removed at once and stored (unsealed, so the
    /// next start resets and it stays removed); one write attempt, no Keychain call at the saves after it.
    @Test func removingDuringALockIsStoredAndSavesDontRetry() {
        let file = consentSettingsFile()
        defer { try? FileManager.default.removeItem(at: file.deletingLastPathComponent()) }
        let secrets = SplitLockSecretStore()
        allowedBefore(file, secrets, "/A", "/B")
        var run = ConsentRun(file, secrets)
        secrets.isLocked = true
        let writes = secrets.writes
        run.edit { $0.allowedClients.removeAll { $0 == "/A" } }
        #expect(secrets.writes == writes + 1)
        #expect(run.inEffect.allowedClients == ["/B"])
        #expect(run.notices == [.storedUnsealed])
        #expect(run.status.isStoredUnsealed)
        #expect(ConsentRun.onDisk(file).allowedClients == ["/B"])
        let calls = secrets.calls
        for _ in 0..<5 { run.save() }
        #expect(secrets.calls == calls)

        secrets.isLocked = false
        let restarted = ConsentRun(file, secrets)
        #expect(restarted.inEffect.allowedClients.isEmpty)
    }

    /// Q3b with Retry: unlocked in the same run, B stays allowed and A removed, sealed with a new key.
    @Test func retryAfterARemovalKeepsTheOthers() {
        let file = consentSettingsFile()
        defer { try? FileManager.default.removeItem(at: file.deletingLastPathComponent()) }
        let secrets = SplitLockSecretStore()
        allowedBefore(file, secrets, "/A", "/B")
        var run = ConsentRun(file, secrets)
        secrets.isLocked = true
        run.edit { $0.allowedClients.removeAll { $0 == "/A" } }
        secrets.isLocked = false
        run.retry()
        #expect(!run.status.needsAttention)
        #expect(allowedAfterRestart(file, secrets) == ["/B"])
    }

    /// F5: a program removed while the Keychain is locked, then someone puts back the old settings with their old seal.
    /// The key of that seal was removed (Apple's sources: deleting needs no unlock), so the old values don't count.
    @Test func anOldSealCantBringBackARemovedProgram() throws {
        let file = consentSettingsFile()
        defer { try? FileManager.default.removeItem(at: file.deletingLastPathComponent()) }
        let secrets = SplitLockSecretStore()
        allowedBefore(file, secrets, "/A")
        var run = ConsentRun(file, secrets)
        let oldBlob = try Data(contentsOf: file)
        let oldSeal = try Data(contentsOf: sealFile(file))
        secrets.readsLocked = true
        secrets.writesLocked = true
        run.edit { $0.allowedClients.removeAll() }
        #expect(secrets.value(AIToolsConsentSeal.keyName) == nil)

        try oldBlob.write(to: file)
        try oldSeal.write(to: sealFile(file))
        secrets.isLocked = false
        let restarted = ConsentRun(file, secrets)
        #expect(restarted.inEffect.allowedClients.isEmpty)
    }

    /// A program allowed again with another Team ID (`AIToolAccess.allowing` replaces its entry) allows more: for this
    /// run only, the stored entry and its key stay.
    @Test func aReplacedEntryIsAGrant() {
        let file = consentSettingsFile()
        defer { try? FileManager.default.removeItem(at: file.deletingLastPathComponent()) }
        let secrets = SplitLockSecretStore()
        let old = AIToolAllowedEntry(key: "/A", teamID: "OLDTEAM").line
        allowedBefore(file, secrets, old)
        var run = ConsentRun(file, secrets)
        secrets.isLocked = true
        let client = AIToolClient(path: "/A", displayName: "A", teamID: "NEWTEAM")
        run.edit { $0.allowedClients = AIToolAccess.allowing(client, in: $0.allowedClients) }
        #expect(run.inEffect.allowedClients == [client.allowedEntry.line])
        #expect(run.notices == [.untilQuit])
        #expect(secrets.deletes == 0)
        secrets.isLocked = false
        #expect(allowedAfterRestart(file, secrets) == [old])
        run.retry()
        #expect(allowedAfterRestart(file, secrets) == [client.allowedEntry.line])
    }

    /// The notification off allows more (this run only); on again allows less (stored at once).
    @Test func theNotificationOffIsAGrantAndOnARestriction() {
        let file = consentSettingsFile()
        defer { try? FileManager.default.removeItem(at: file.deletingLastPathComponent()) }
        let secrets = SplitLockSecretStore()
        var first = ConsentRun(file, secrets)
        first.edit { $0.allowedClients = ["/A"] }
        var run = ConsentRun(file, secrets)
        secrets.isLocked = true
        run.edit { $0.notifyOnCapture = false }
        #expect(!run.inEffect.notifyOnCapture)
        #expect(ConsentRun.onDisk(file).notifyOnCapture)
        #expect(run.notices == [.untilQuit])
        run.edit { $0.notifyOnCapture = true }
        #expect(run.inEffect.notifyOnCapture)
        #expect(!run.status.needsAttention)
    }

    /// The user is told once until a check succeeds, not at every change.
    @Test func theUserIsToldOnceUntilItWorksAgain() {
        let file = consentSettingsFile()
        defer { try? FileManager.default.removeItem(at: file.deletingLastPathComponent()) }
        let secrets = SplitLockSecretStore()
        allowedBefore(file, secrets, "/A")
        var run = ConsentRun(file, secrets)
        secrets.isLocked = true
        run.edit { $0.allowedClients.append("/X") }
        run.edit { $0.allowedClients.append("/Y") }
        #expect(run.notices == [.untilQuit])
        secrets.isLocked = false
        run.retry()
        secrets.isLocked = true
        run.edit { $0.allowedClients.append("/Z") }
        #expect(run.notices == [.untilQuit, .untilQuit])
    }

    /// A seal removed outside Greenshot during the run: the next save seals the values in use again (one write), and
    /// while the Keychain is locked it tries once, not at every save.
    @Test func aRemovedSealIsRepairedOnceAtASave() {
        let file = consentSettingsFile()
        defer { try? FileManager.default.removeItem(at: file.deletingLastPathComponent()) }
        let secrets = SplitLockSecretStore()
        allowedBefore(file, secrets, "/A")
        var run = ConsentRun(file, secrets)
        try? FileManager.default.removeItem(at: sealFile(file))
        let writes = secrets.writes
        run.save()
        run.save()
        #expect(secrets.writes == writes + 1)
        #expect(allowedAfterRestart(file, secrets) == ["/A"])

        secrets.isLocked = true
        try? FileManager.default.removeItem(at: sealFile(file))
        let calls = secrets.calls
        for _ in 0..<5 { run.save() }
        #expect(secrets.calls == calls + 1)
        #expect(run.status.isStoredUnsealed)
        secrets.isLocked = false
        run.retry()
        #expect(!run.status.needsAttention)
        #expect(allowedAfterRestart(file, secrets) == ["/A"])
    }

    // MARK: Reload and edits outside Greenshot

    /// A reload of the values this run stored (unsealed) checks them as they are known, not as an edit: after
    /// unlocking, B stays allowed.
    @Test func aReloadOfTheValuesStoredThisRunKeepsThem() {
        let file = consentSettingsFile()
        defer { try? FileManager.default.removeItem(at: file.deletingLastPathComponent()) }
        let secrets = SplitLockSecretStore()
        allowedBefore(file, secrets, "/A", "/B")
        var run = ConsentRun(file, secrets)
        secrets.isLocked = true
        run.edit { $0.allowedClients.removeAll { $0 == "/A" } }
        run.reload()
        #expect(run.inEffect.allowedClients == ["/B"])
        secrets.isLocked = false
        run.reload()
        #expect(!run.status.needsAttention)
        #expect(allowedAfterRestart(file, secrets) == ["/B"])
    }

    /// Q1: values edited outside Greenshot and reloaded while the Keychain is locked never take effect and are never
    /// sealed, also not with a program the user allows meanwhile.
    @Test func valuesEditedOutsideNeverCount() throws {
        let file = consentSettingsFile()
        defer { try? FileManager.default.removeItem(at: file.deletingLastPathComponent()) }
        let secrets = SplitLockSecretStore()
        allowedBefore(file, secrets, "/A")
        var run = ConsentRun(file, secrets)
        var evil = SettingsStorage.load(fromFile: file)
        evil.aiTools.allowedClients = ["/EVIL"]
        try SettingsStorage.save(evil, toFile: file)
        secrets.isLocked = true
        run.reload()
        #expect(run.inEffect.allowedClients.isEmpty)
        run.edit { $0.allowedClients.append("/Y") }
        #expect(run.inEffect.allowedClients == ["/Y"])
        for _ in 0..<3 { run.save() }

        secrets.isLocked = false
        #expect(ConsentRun(file, secrets).inEffect.allowedClients.isEmpty)
        run.retry()
        #expect(run.inEffect.allowedClients == ["/Y"])
        #expect(allowedAfterRestart(file, secrets) == ["/Y"])
    }

    /// An administrator's locked list isn't the user's to change: an edit of it changes nothing stored.
    @Test func aLockedValueIsNoChangeOfTheUser() {
        let policy = ManagedPolicy(source: ManagedValues(forced: ["Greenshot.aiTools.allowedClients": ["/opt/approved"]]))
        var current = AIToolsSettings()
        current.allowedClients = ["/opt/approved"]
        var edited = current
        edited.allowedClients.append("/X")
        edited.excludedApplications.append("Vault")
        let userEdit = AIToolsConsentKeeper.userEdit(edited, of: current, policy: policy)
        #expect(userEdit.allowedClients == ["/opt/approved"])
        #expect(userEdit.excludedApplications.contains("Vault"))
    }
}
