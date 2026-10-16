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
    private let defaults: UserDefaults

    init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
        value = SettingsStorage.load(from: defaults)
    }

    func update(_ body: (inout AppSettings) -> Void) {
        var changed = value
        body(&changed)
        guard changed != value else { return }
        let hotkeysChanged = changed.hotkeys != value.hotkeys
        value = changed
        SettingsStorage.save(changed, to: defaults)
        if hotkeysChanged { onHotkeysChange?() }
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
