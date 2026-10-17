// Greenshot for Mac (Community) - an unofficial macOS port of Greenshot
// Copyright (C) 2026 Greenshot for Mac (Community) contributors
// Based on Greenshot, Copyright (C) 2007-2026 Thomas Braun, Jens Klingen, Robin Krom
// SPDX-License-Identifier: GPL-3.0-or-later

import GreenshotCore
import SwiftUI

extension View {
    /// Marks a settings control whose value an administrator can force with a configuration profile: then it is
    /// disabled and shows a lock, "Set by your organisation" (upstream `FixedToEnabledConverter` on the controls of
    /// `SettingsWindow.xaml`). Pass every setting the control writes, e.g. `.managed(\.outputFormat)`,
    /// `.managed(\.printing.grayscale, \.printing.monochrome)`. The key paths must be in `ManagedSettingKeys`.
    func managed(_ keyPaths: PartialKeyPath<AppSettings>...) -> some View {
        modifier(ManagedControl(keyPaths: keyPaths))
    }
}

extension EnvironmentValues {
    /// The administrator's policy for the settings controls; `SettingsView` sets it from the store. Nothing is locked
    /// without it.
    var managedPolicy: ManagedPolicy {
        get { self[ManagedPolicyKey.self] }
        set { self[ManagedPolicyKey.self] = newValue }
    }
}

private struct ManagedPolicyKey: EnvironmentKey {
    static let defaultValue = ManagedPolicy()
}

/// Disables a locked control and puts a lock after it, in room kept free at the trailing edge of its row.
private struct ManagedControl: ViewModifier {
    @Environment(\.managedPolicy) private var policy
    let keyPaths: [PartialKeyPath<AppSettings>]

    func body(content: Content) -> some View {
        let locked = isLocked
        return content
            .disabled(locked)
            .padding(.trailing, locked ? 22 : 0)
            .overlay(alignment: .trailing) {
                if locked { ManagedLock() }
            }
    }

    private var isLocked: Bool {
        ManagedControlCheck.warnAboutUnknown(keyPaths)
        return keyPaths.contains { policy.isLocked($0) }
    }
}

/// The lock of a setting an administrator set.
struct ManagedLock: View {
    var body: some View {
        Image(systemName: "lock.fill")
            .font(.caption)
            .foregroundStyle(.secondary)
            .help(ManagedPolicy.lockedHelp)
            .accessibilityLabel(ManagedPolicy.lockedHelp)
    }
}

/// A key path without a name in `ManagedSettingKeys` can never be locked: said once in the log, so a new setting's
/// missing table line is found (an assertion would stop other work in progress).
@MainActor
private enum ManagedControlCheck {
    private static var reported: Set<AnyKeyPath> = []
    private static let log = Log("Managed")

    static func warnAboutUnknown(_ keyPaths: [PartialKeyPath<AppSettings>]) {
        for keyPath in keyPaths where ManagedSettingKeys.name(for: keyPath) == nil && !reported.contains(keyPath) {
            reported.insert(keyPath)
            log.warn("A settings control uses a setting without a name in ManagedSettingKeys: \(keyPath)")
        }
    }
}
