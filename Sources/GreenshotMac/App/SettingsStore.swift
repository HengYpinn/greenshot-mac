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
    /// The settings in effect: the user's with the locked values.
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
    /// The user's own settings, the ones saved.
    private var stored: AppSettings
    private var observers: [(_ old: AppSettings, _ new: AppSettings) -> Void] = []
    private let log = Log("Managed")

    /// `managed` defaults to `defaults` itself: the app's user defaults, or for the snapshots an empty suite.
    init(defaults: UserDefaults = .standard, fileURL: URL? = nil, managed: ManagedValueSource? = nil) {
        self.defaults = defaults
        self.fileURL = fileURL
        let source = managed ?? UserDefaultsManagedSource(defaults)
        self.managed = source
        let policy = ManagedPolicy(source: source)
        let loaded = fileURL.map { url in
            SettingsStorage.load(fromFile: url) { aside in
                DispatchQueue.main.async {
                    ErrorPresenter.show(message: String(localized: "The settings file could not be read"),
                                        detail: String(localized: "It was renamed to \(aside.lastPathComponent) and Greenshot started with the default settings."))
                }
            }
        } ?? SettingsStorage.load(from: defaults)
        let stored = policy.loaded(loaded, storedJSON: Self.storedJSON(defaults: defaults, fileURL: fileURL))
        self.policy = policy
        self.stored = stored
        value = policy.effective(stored)
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
        commit(stored: policy.loaded(reloaded.settings, storedJSON: reloaded.json), save: false)
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
        commit(stored: policy.stored(afterEditing: changed, effective: value, stored: stored), save: true)
    }

    /// Takes `newStored` as the user's settings, saves them when asked and they changed, and tells the observers what
    /// changed in effect.
    private func commit(stored newStored: AppSettings, save shouldSave: Bool) {
        if shouldSave && newStored != stored { save(newStored) }
        stored = newStored
        let old = value
        let new = policy.effective(newStored)
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

    /// Increments and returns the counter behind `${NUM}`.
    func nextIncrementingNumber() -> UInt {
        var number: UInt = 0
        update {
            $0.incrementingNumber += 1
            number = $0.incrementingNumber
        }
        return number
    }

    /// The values a filename pattern can use. `consumeNumber: false` previews `${NUM}` without counting up.
    func patternContext(title: String?, date: Date, consumeNumber: Bool = true) -> FilenamePattern.Context {
        let current = value.incrementingNumber
        return FilenamePattern.Context(
            captureTime: date, title: title, environment: ProcessInfo.processInfo.environment,
            nextNumber: consumeNumber ? { [weak self] in self?.nextIncrementingNumber() ?? current + 1 } : { current + 1 },
            // `${url}`, `${browser}`, `${Browser.*}` of a capture from the browser extension (BROWSER).
            metadata: CaptureMetadataStore.shared.patternMetadata(forCaptureAt: date))
    }
}
