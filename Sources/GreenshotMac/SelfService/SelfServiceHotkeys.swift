// Greenshot for Mac (Community) - an unofficial macOS port of Greenshot
// Copyright (C) 2026 Greenshot for Mac (Community) contributors
// Based on Greenshot, Copyright (C) 2007-2026 Thomas Braun, Jens Klingen, Robin Krom
// SPDX-License-Identifier: GPL-3.0-or-later

import AppKit
import GreenshotCore
import SwiftUI

/// The screenshot shortcuts of macOS as the user has them (`com.apple.symbolichotkeys`).
enum SystemShortcuts {
    static func read() -> [SystemScreenshotShortcut] {
        let dictionary = UserDefaults(suiteName: "com.apple.symbolichotkeys")?.dictionary(forKey: "AppleSymbolicHotKeys")
        return SystemScreenshotShortcut.read(symbolicHotKeys: dictionary)
    }
}

/// Self-Service › Hotkeys: port of upstream `HotkeySectionViewModel.cs` for the Mac. Each hotkey with what registering
/// it did and "Register Again"; instead of OneDrive and the Snipping Tool taking the Print key, the screenshot shortcuts
/// of macOS; other capture apps that are running.
@MainActor
final class HotkeysSectionModel: ObservableObject {
    struct Contender: Identifiable, Equatable {
        var id: String { name }
        var name: String
        var note: String
        var running: Bool
    }

    @Published private(set) var rows: [HotkeyStatusRow] = []
    @Published private(set) var systemShortcuts: [SystemScreenshotShortcut] = []
    @Published private(set) var conflictIDs: Set<Int> = []
    @Published private(set) var contenders: [Contender] = []
    @Published private(set) var updated = ""
    private weak var app: AppDelegate?
    private let live: Bool

    init(app: AppDelegate) {
        self.app = app
        live = true
        refresh()
    }

    /// Fixed values (snapshots).
    init(rows: [HotkeyStatusRow], systemShortcuts: [SystemScreenshotShortcut], conflictIDs: Set<Int>, contenders: [Contender]) {
        live = false
        self.rows = rows
        self.systemShortcuts = systemShortcuts
        self.conflictIDs = conflictIDs
        self.contenders = contenders
        updated = "Updated at 09:30:00"
    }

    /// Hotkeys macOS refused and macOS shortcuts with the same keys (upstream's issue count).
    var issueCount: Int {
        rows.filter { $0.state == .refused }.count + conflictIDs.count
    }

    func refresh() {
        guard live, let app else { return }
        let hotkeys = app.settings.value.hotkeys
        let registration = HotkeyDiagnostics.lastRegistration
        let refused = registration.map { reg in reg.refused.filter(reg.combos.indices.contains).map { reg.combos[$0] } } ?? []
        systemShortcuts = SystemShortcuts.read()
        rows = HotkeyStatus.rows(hotkeys, registered: registration?.combos, refused: refused, systemShortcuts: systemShortcuts)
        let combos = HotkeyStatus.slots(hotkeys).compactMap(\.combo)
        conflictIDs = Set(SystemScreenshotShortcut.conflicts(systemShortcuts, with: combos).map(\.id))
        let running = NSWorkspace.shared.runningApplications.map { ($0.bundleIdentifier, $0.localizedName) }
        contenders = CaptureAppContender.known.map { contender in
            Contender(name: contender.name, note: contender.note,
                      running: running.contains { contender.matches(bundleIdentifier: $0.0, name: $0.1) })
        }
        updated = "Updated at \(LogViewerModel.time(Date()))"
    }

    func registerAgain() -> String {
        app?.reregisterHotkeys()
        refresh()
        return rows.contains { $0.state == .refused }
            ? "Hotkeys registered again (some keys are still taken)."
            : "Hotkeys registered again."
    }
}

struct HotkeysSectionView: View {
    @ObservedObject var model: HotkeysSectionModel
    var status: (String) -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            SectionCard(title: "Your hotkeys") {
                ForEach(model.rows) { row in
                    HStack(spacing: 10) {
                        Text(row.name).frame(width: 190, alignment: .leading)
                        Text(row.keys ?? "–").font(.body.monospaced()).frame(width: 110, alignment: .leading)
                        stateLabel(row)
                        Spacer()
                    }
                }
                HStack {
                    Text(model.updated).font(.caption).foregroundStyle(.secondary)
                    Spacer()
                    Button("Register Again") { status(model.registerAgain()) }
                        .help("Register the hotkeys with macOS again, e.g. after another app gave a key back")
                }
            }
            SectionCard(title: "Screenshot shortcuts of macOS") {
                Text("macOS handles these keys before any app. When one has the keys of a hotkey, turn it off under Keyboard › Keyboard Shortcuts › Screenshots, or choose another hotkey.")
                    .font(.caption).foregroundStyle(.secondary).fixedSize(horizontal: false, vertical: true)
                ForEach(model.systemShortcuts, id: \.id) { shortcut in
                    HStack(spacing: 10) {
                        Text(shortcut.combo.displayString).font(.body.monospaced()).frame(width: 70, alignment: .leading)
                        Text(shortcut.name).frame(maxWidth: .infinity, alignment: .leading)
                        if model.conflictIDs.contains(shortcut.id) {
                            Label("Same keys as your hotkey", systemImage: "exclamationmark.triangle.fill").foregroundStyle(.orange)
                        } else {
                            Text(shortcut.enabled ? "On" : "Off").foregroundStyle(.secondary)
                        }
                    }
                }
                HStack {
                    Spacer()
                    Button("Open Keyboard Shortcuts") {
                        SystemSettings.open("com.apple.Keyboard-Settings.extension")
                        status("Opened the keyboard settings.")
                    }
                }
            }
            SectionCard(title: "Other screen capture apps") {
                ForEach(model.contenders) { contender in
                    HStack(spacing: 10) {
                        Text(contender.name).frame(width: 110, alignment: .leading)
                        Text(contender.note).font(.caption).foregroundStyle(.secondary).frame(maxWidth: .infinity, alignment: .leading)
                        Text(contender.running ? "Running" : "Not running")
                            .foregroundStyle(contender.running ? Color.orange : Color.secondary)
                    }
                }
            }
        }
    }

    @ViewBuilder private func stateLabel(_ row: HotkeyStatusRow) -> some View {
        switch row.state {
        case .registered:
            if let conflict = row.systemConflict {
                Label("Registered, but macOS takes it first (\(conflict))", systemImage: "exclamationmark.triangle.fill")
                    .foregroundStyle(.orange)
            } else {
                Label("Registered", systemImage: "checkmark.circle.fill").foregroundStyle(.green)
            }
        case .refused:
            Label("Not registered: another app has it", systemImage: "xmark.octagon.fill").foregroundStyle(.red)
        case .notSet:
            Text("Not set").foregroundStyle(.secondary)
        case .unknown:
            Text("Not registered yet").foregroundStyle(.secondary)
        }
    }
}
