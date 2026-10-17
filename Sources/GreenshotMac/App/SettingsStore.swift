// Greenshot for Mac (Community) - an unofficial macOS port of Greenshot
// Copyright (C) 2026 Greenshot for Mac (Community) contributors
// SPDX-License-Identifier: GPL-3.0-or-later

import Foundation
import GreenshotCore
import SwiftUI

/// The live settings: every change is saved right away.
@MainActor
final class SettingsStore: ObservableObject {
    @Published private(set) var value: AppSettings
    /// Called after the hotkeys changed, to register them again.
    var onHotkeysChange: (() -> Void)?
    /// Called after "Show in Dock while a window is open" changed.
    var onDockChange: (() -> Void)?
    private let defaults: UserDefaults
    /// The settings file of `--settings-dir` (upstream `--ini-directory`); nil keeps them in the user defaults.
    private let fileURL: URL?
    private var observers: [(_ old: AppSettings, _ new: AppSettings) -> Void] = []

    init(defaults: UserDefaults = .standard, fileURL: URL? = nil) {
        self.defaults = defaults
        self.fileURL = fileURL
        value = fileURL.map { url in
            SettingsStorage.load(fromFile: url) { aside in
                DispatchQueue.main.async {
                    ErrorPresenter.show(message: "The settings file could not be read",
                                        detail: "It was renamed to \(aside.lastPathComponent) and Greenshot started with the default settings.")
                }
            }
        } ?? SettingsStorage.load(from: defaults)
    }

    /// Reads the settings again from where they are stored (`greenshot-cli --reload`, upstream's RELOAD command) and
    /// applies them like any change.
    func reloadFromDisk() {
        let loaded = fileURL.map { SettingsStorage.load(fromFile: $0) } ?? SettingsStorage.load(from: defaults)
        update { $0 = loaded }
    }

    func update(_ body: (inout AppSettings) -> Void) {
        var changed = value
        body(&changed)
        guard changed != value else { return }
        let old = value
        let hotkeysChanged = changed.hotkeys != value.hotkeys
        let dockChanged = changed.dockIconWhileWindowOpen != value.dockIconWhileWindowOpen
        value = changed
        save(changed)
        if hotkeysChanged { onHotkeysChange?() }
        if dockChanged { onDockChange?() }
        observers.forEach { $0(old, changed) }
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
            nextNumber: consumeNumber ? { [weak self] in self?.nextIncrementingNumber() ?? current + 1 } : { current + 1 })
    }
}
