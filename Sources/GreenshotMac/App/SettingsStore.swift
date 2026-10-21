// Greenshot for Mac (Community) - an unofficial macOS port of Greenshot
// Copyright (C) 2026 Greenshot for Mac (Community) contributors
// SPDX-License-Identifier: GPL-3.0-or-later

import Foundation
import GreenshotCore
import SwiftUI

/// The live settings: every change is saved right away.
///
/// An administrator's configuration profile can lock settings and set defaults (`ManagedPolicy`, the Mac's
/// greenshot-fixed.ini and greenshot-defaults.ini). `value` is what is in effect; the store saves only the user's own
/// values, so a locked value never overwrites them and they come back when the profile is removed.
@MainActor
final class SettingsStore: ObservableObject {
    /// The settings in effect: the user's with the locked values (and the AI tools consent reset while its seal can't
    /// be checked, `unverifiedConsent`).
    @Published private(set) var value: AppSettings
    /// What the administrator locked or preset; Settings disables the locked controls (`.managed(\.keyPath)`).
    @Published private(set) var policy: ManagedPolicy
    /// Called after the hotkeys changed, to register them again.
    var onHotkeysChange: (() -> Void)?
    /// Called after "Show in Dock while a window is open" changed.
    var onDockChange: (() -> Void)?
    private let defaults: UserDefaults
    /// The settings file of `--settings-dir` (upstream `--ini-directory`); nil keeps them in the user defaults.
    private let fileURL: URL?
    /// The managed values: the app's user defaults (a profile forces them per bundle id, also with `--settings-dir`,
    /// like upstream reads greenshot-fixed.ini from the installation and never from `--ini-directory`).
    private let managed: ManagedValueSource
    /// Seals the AI tools consent: a change made outside Greenshot is reset when the settings are loaded.
    private let seal: AIToolsConsentSeal
    /// The user's own settings, the ones saved.
    private var stored: AppSettings
    /// The AI tools consent in effect while the stored one can't be checked (its key can't be read: the Keychain is
    /// locked, or its prompt was cancelled): the reset values (nobody allowed, the notification on). The stored values
    /// and their seal stay as they are, so they count again once the key can be read: at the next start, a reload, or a
    /// change of the consent (`update`).
    private var unverifiedConsent: AIToolsSettings?
    private var observers: [(_ old: AppSettings, _ new: AppSettings) -> Void] = []
    private let log = Log("Managed")

    /// `secrets` defaults to the Keychain for the app's own user defaults and to an in-memory store for any other suite
    /// (the `--snapshot` renderer, tests), so those never create a Keychain item.
    /// `managed` defaults to `defaults` itself: the app's user defaults, or for the snapshots an empty suite.
    init(defaults: UserDefaults = .standard, fileURL: URL? = nil, managed: ManagedValueSource? = nil,
         secrets: (any SecretStore)? = nil) {
        self.defaults = defaults
        self.fileURL = fileURL
        let source = managed ?? UserDefaultsManagedSource(defaults)
        self.managed = source
        let policy = ManagedPolicy(source: source)
        let sealSecrets: any SecretStore = secrets ?? (defaults === UserDefaults.standard ? KeychainSecretStore.shared : InMemorySecretStore())
        let sealLocation: AIToolsConsentSeal.Location = fileURL.map { .file($0) } ?? .defaults(defaults)
        let seal = AIToolsConsentSeal(secrets: sealSecrets, location: sealLocation)
        self.seal = seal
        let loaded = fileURL.map { url in
            SettingsStorage.load(fromFile: url) { aside in
                DispatchQueue.main.async {
                    ErrorPresenter.show(message: String(localized: "The settings file could not be read"),
                                        detail: String(localized: "It was renamed to \(aside.lastPathComponent) and Greenshot started with the default settings."))
                }
            }
        } ?? SettingsStorage.load(from: defaults)
        let checked = Self.sealChecked(policy.loaded(loaded, storedJSON: Self.storedJSON(defaults: defaults, fileURL: fileURL)),
                                       seal: seal, defaults: defaults, fileURL: fileURL)
        self.policy = policy
        stored = checked.stored
        unverifiedConsent = checked.unverifiedConsent
        value = Self.inEffect(checked.stored, unverifiedConsent: checked.unverifiedConsent, policy: policy)
    }

    /// The settings that are about to be the user's, with the AI tools consent checked last: whatever filled values in
    /// (the stored ones, a managed default), the sealed ones must carry a valid seal or are reset, and the reset is saved.
    /// A seal that can't be checked keeps the stored values and gives the reset ones to use meanwhile.
    private static func sealChecked(_ settings: AppSettings, seal: AIToolsConsentSeal, defaults: UserDefaults,
                                    fileURL: URL?) -> (stored: AppSettings, unverifiedConsent: AIToolsSettings?) {
        let sealed = seal.verifiedOrReset(settings.aiTools)
        if sealed.isUnverifiable { return (settings, sealed.settings) }
        guard sealed.wasReset else { return (settings, nil) }
        var result = settings
        result.aiTools = sealed.settings
        write(result, defaults: defaults, fileURL: fileURL)
        return (result, nil)
    }

    /// The settings in effect for `stored`: the consent that can't be checked replaced by the reset values, then the
    /// managed values.
    private static func inEffect(_ stored: AppSettings, unverifiedConsent: AIToolsSettings?, policy: ManagedPolicy) -> AppSettings {
        guard let unverifiedConsent else { return policy.effective(stored) }
        var replaced = stored
        replaced.aiTools = AIToolsConsentSeal.withSealedValues(of: unverifiedConsent, in: stored.aiTools)
        return policy.effective(replaced)
    }

    private func inEffect(_ stored: AppSettings) -> AppSettings {
        Self.inEffect(stored, unverifiedConsent: unverifiedConsent, policy: policy)
    }

    /// Checks the AI tools consent that couldn't be checked once more (the Keychain may be unlocked now).
    private func recheckConsent() {
        guard unverifiedConsent != nil else { return }
        let checked = Self.sealChecked(stored, seal: seal, defaults: defaults, fileURL: fileURL)
        unverifiedConsent = checked.unverifiedConsent
        commit(stored: checked.stored, save: false)
    }

    /// The saved settings as they are, to see which values they have (defaults fill in the others).
    private static func storedJSON(defaults: UserDefaults, fileURL: URL?) -> Data? {
        guard let fileURL else { return defaults.data(forKey: SettingsStorage.key) }
        return try? Data(contentsOf: fileURL)
    }

    /// Reads the settings again from where they are stored (`greenshot-cli --reload`, upstream's RELOAD command) and
    /// applies them like any change, with the managed values read again too. Settings that can't be read (a hand-edited
    /// settings.json with a mistake) throw a `SettingsReloadError` and change nothing: the settings in use stay, and the
    /// file stays where it is for the user to fix.
    func reloadFromDisk() throws {
        refreshManaged()
        let reloaded: (settings: AppSettings, json: Data?)
        do {
            if let fileURL {
                reloaded = try SettingsStorage.reload(fromFile: fileURL)
            } else {
                reloaded = try SettingsStorage.reload(from: defaults)
            }
        } catch {
            Log("Settings").error("The settings were not reloaded, the ones in use stay: \(error)")
            throw error
        }
        let checked = Self.sealChecked(policy.loaded(reloaded.settings, storedJSON: reloaded.json),
                                       seal: seal, defaults: defaults, fileURL: fileURL)
        unverifiedConsent = checked.unverifiedConsent
        commit(stored: checked.stored, save: false)
    }

    /// Reads the managed values again (a profile installed or removed while the app runs): when Settings or the menu
    /// bar menu opens.
    func refreshManaged() {
        let newPolicy = ManagedPolicy(source: managed)
        guard newPolicy != policy else { return }
        policy = newPolicy
        logManagedPolicy()
        commit(stored: stored, save: false)
    }

    /// Logs what the administrator set, by name (never the values); nothing without a profile.
    func logManagedPolicy() {
        guard !policy.isEmpty else { return }
        log.info("Managed settings: \(policy.summary)")
        for problem in policy.problems {
            log.warn("Managed setting ignored: \(problem)")
        }
    }

    /// Whether an administrator locked the setting at `keyPath`.
    func isLocked(_ keyPath: PartialKeyPath<AppSettings>) -> Bool {
        policy.isLocked(keyPath)
    }

    /// Changes the settings in effect. Changes of locked values are dropped: the locked value stays.
    func update(_ body: (inout AppSettings) -> Void) {
        var changed = value
        body(&changed)
        guard changed != value else { return }
        if unverifiedConsent != nil, !AIToolsConsentSeal.sealedValuesEqual(changed.aiTools, value.aiTools) {
            // A change of the AI tools consent while the stored one can't be checked (e.g. "Allow" in the question): check
            // it once more, as the user is here to unlock the Keychain, and change what is in effect then.
            recheckConsent()
            if let unverifiedConsent {
                // Still not: the consent in effect (the reset, which allows nobody) becomes the stored one and the change
                // is made to it, so a program removed or an application excluded stays so after a restart.
                stored.aiTools = AIToolsConsentSeal.withSealedValues(of: unverifiedConsent, in: stored.aiTools)
                self.unverifiedConsent = nil
            }
            changed = value
            body(&changed)
            guard changed != value else { return }
        }
        commit(stored: policy.stored(afterEditing: changed, effective: value, stored: stored), save: true)
    }

    /// Takes `newStored` as the user's settings, saves them when asked and they changed, and tells the observers what
    /// changed in effect.
    private func commit(stored newStored: AppSettings, save shouldSave: Bool) {
        if shouldSave && newStored != stored { save(newStored) }
        stored = newStored
        let old = value
        let new = inEffect(newStored)
        guard new != old else { return }
        value = new
        if new.hotkeys != old.hotkeys { onHotkeysChange?() }
        if new.dockIconWhileWindowOpen != old.dockIconWhileWindowOpen { onDockChange?() }
        observers.forEach { $0(old, new) }
    }

    /// Calls `handler` with the new value every time the setting at `keyPath` changed.
    func onChange<T: Equatable>(of keyPath: KeyPath<AppSettings, T>, _ handler: @escaping (T) -> Void) {
        observers.append { old, new in
            let value = new[keyPath: keyPath]
            if old[keyPath: keyPath] != value { handler(value) }
        }
    }

    private func save(_ settings: AppSettings) {
        Self.write(settings, defaults: defaults, fileURL: fileURL)
        // Only Greenshot saving writes the seal: when the sealed values change, or their seal is wrong. Not while it
        // can't be checked (a locked Keychain): a new seal would fail and drop the one the stored values have.
        guard unverifiedConsent == nil else { return }
        if !AIToolsConsentSeal.sealedValuesEqual(settings.aiTools, stored.aiTools)
            || seal.verification(of: settings.aiTools) == .invalid {
            seal.save(settings.aiTools)
        }
    }

    private static func write(_ settings: AppSettings, defaults: UserDefaults, fileURL: URL?) {
        guard let fileURL else {
            SettingsStorage.save(settings, to: defaults)
            return
        }
        do {
            try SettingsStorage.save(settings, toFile: fileURL)
        } catch {
            FileHandle.standardError.write(Data("Settings could not be saved to \(fileURL.path): \(error)\n".utf8))
        }
    }

    func binding<T>(_ keyPath: WritableKeyPath<AppSettings, T>) -> Binding<T> {
        Binding(get: { self.value[keyPath: keyPath] },
                set: { newValue in self.update { $0[keyPath: keyPath] = newValue } })
    }

    /// Increments and returns the counter behind `${NUM}`. After UInt.max (only a hand-edited settings file holds it) it
    /// wraps to 0, like upstream's `OutputFileIncrementingNumber++` in a release build, instead of stopping the app.
    func nextIncrementingNumber() -> UInt {
        var number: UInt = 0
        update {
            $0.incrementingNumber &+= 1
            number = $0.incrementingNumber
        }
        return number
    }

    /// The values a filename pattern can use. `consumeNumber: false` previews `${NUM}` without counting up.
    func patternContext(title: String?, date: Date, consumeNumber: Bool = true) -> FilenamePattern.Context {
        let current = value.incrementingNumber
        return FilenamePattern.Context(
            captureTime: date, title: title, environment: ProcessInfo.processInfo.environment,
            nextNumber: consumeNumber ? { [weak self] in self?.nextIncrementingNumber() ?? current &+ 1 } : { current &+ 1 },
            // `${url}`, `${browser}`, `${Browser.*}` of a capture from the browser extension (BROWSER).
            metadata: CaptureMetadataStore.shared.patternMetadata(forCaptureAt: date))
    }
}
