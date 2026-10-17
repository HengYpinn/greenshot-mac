// Greenshot for Mac (Community) - an unofficial macOS port of Greenshot
// Copyright (C) 2026 Greenshot for Mac (Community) contributors
// Based on Greenshot, Copyright (C) 2007-2026 Thomas Braun, Jens Klingen, Robin Krom
// SPDX-License-Identifier: GPL-3.0-or-later

import GreenshotCore
import SwiftUI

/// The Hotkeys section of Settings › General (upstream's hotkey fields on the General tab, `SettingsWindow.xaml`, and
/// "Capture text" for the built-in recipe "OCR text to clipboard"). Under a row: why the keys just typed can't be used,
/// or a clash with another hotkey.
struct HotkeysSection: View {
    @ObservedObject var store: SettingsStore
    /// For the snapshots: a message under the row with this title, as if the keys just typed couldn't be used.
    var initialProblems: [String: String] = [:]
    /// Whether hotkeys can tell the left modifier keys from the right ones.
    @StateObject private var access: AccessibilityStatus

    /// `access` is given by the snapshots, to show the rows without the permission.
    @MainActor
    init(store: SettingsStore, initialProblems: [String: String] = [:], access: AccessibilityStatus? = nil) {
        self.store = store
        self.initialProblems = initialProblems
        _access = StateObject(wrappedValue: access ?? AccessibilityStatus())
    }

    private static var rows: [(title: String, keyPath: WritableKeyPath<HotkeySettings, KeyCombo?>)] {
        [("Capture region", \.region), ("Capture window", \.window), ("Capture full screen", \.fullScreen),
         ("Capture last region", \.lastRegion), ("Capture text", \.text), ("Start or stop recording", \.recordVideo), ("Open image from clipboard", \.clipboard)]
    }

    var body: some View {
        Section {
            ForEach(Self.rows, id: \.title) { row in
                let keyPath = (\AppSettings.hotkeys).appending(path: row.keyPath)
                HotkeyRow(title: row.title, combo: store.binding(keyPath),
                          conflict: conflict(for: row.title), initialProblem: initialProblems[row.title], access: access)
                    .managed(keyPath)
            }
        } header: {
            Text("Hotkeys")
        } footer: {
            Text("""
                Click a shortcut, then type the new one. ⌫ clears it, ⎋ cancels. + adds a step, for hotkeys like ⌃⌥⌘K then C \
                (within 2.5 seconds). The keyboard menu makes a modifier count only on its left or right key. Keyboards \
                with an F13 key can use it like Print Screen.
                """)
                .font(.caption).foregroundStyle(.secondary)
        }
    }

    /// The clash of a row's hotkey with the others.
    private func conflict(for title: String) -> String? {
        let hotkeys = store.value.hotkeys
        let all = Self.rows.compactMap { row in hotkeys[keyPath: row.keyPath].map { (name: row.title, combo: $0) } }
        guard let mine = all.first(where: { $0.name == title }) else { return nil }
        return KeyCombo.conflict(of: mine.combo, with: all.filter { $0.name != title })
    }
}

private struct HotkeyRow: View {
    let title: String
    @Binding var combo: KeyCombo?
    let conflict: String?
    @ObservedObject var access: AccessibilityStatus
    @State private var problem: String?

    init(title: String, combo: Binding<KeyCombo?>, conflict: String?, initialProblem: String?, access: AccessibilityStatus) {
        self.title = title
        _combo = combo
        self.conflict = conflict
        self.access = access
        _problem = State(initialValue: initialProblem)
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            LabeledContent(title) {
                HStack(spacing: 4) {
                    ShortcutRecorder(combo: $combo, problem: $problem).fixedSize()
                    ModifierSidesMenu(combo: $combo)
                }
            }
            if let message = problem ?? conflict {
                Text(message)
                    .font(.caption)
                    .foregroundStyle(problem != nil ? Color.red : Color.orange)
                    .frame(maxWidth: .infinity, alignment: .trailing)
            }
            if combo?.usesSides == true && !access.canTellSides {
                HStack(alignment: .firstTextBaseline) {
                    Text("Left and right keys need the Accessibility permission. Until then this hotkey works with either key.")
                        .font(.caption)
                        .foregroundStyle(.orange)
                    Spacer()
                    Button("Allow…") {
                        Permissions.requestAccessibility()
                        access.refresh()
                    }
                    .controlSize(.small)
                }
            }
        }
    }
}

/// Which key of each modifier a hotkey needs: either, the left or the right one (upstream's location boxes in
/// "Configure Hotkey", `HotkeyEditorView.xaml`). A side chosen here also takes the key pressed when the hotkey is typed
/// again. Hotkeys with a side go through the keyboard event tap (`HotkeyManager`).
private struct ModifierSidesMenu: View {
    @Binding var combo: KeyCombo?

    private static let names: [UInt32: String] = [KeyCombo.control: "⌃ Control", KeyCombo.option: "⌥ Option",
                                                  KeyCombo.shift: "⇧ Shift", KeyCombo.command: "⌘ Command"]

    var body: some View {
        Menu {
            if let combo {
                ForEach(Array(combo.chords.enumerated()), id: \.offset) { index, step in
                    if step.modifiers != 0 {
                        Section(combo.isSequence ? "Step \(index + 1)" : "Left or right key") {
                            ForEach(ModifierSides.modifiers.filter { step.modifiers & $0 != 0 }, id: \.self) { modifier in
                                Picker(Self.names[modifier] ?? "", selection: side(step: index, modifier: modifier)) {
                                    Text("Either key").tag(ModifierSide.any)
                                    Text("Left key").tag(ModifierSide.left)
                                    Text("Right key").tag(ModifierSide.right)
                                }
                            }
                        }
                    }
                }
            }
        } label: {
            Image(systemName: "keyboard")
        }
        .menuStyle(.borderlessButton)
        .menuIndicator(.hidden)
        .fixedSize()
        .disabled(combo?.chords.contains { $0.modifiers != 0 } != true)
        .help("Left or right modifier keys: e.g. only the right ⌘")
        .accessibilityLabel("Left or right modifier keys")
    }

    private func side(step index: Int, modifier: UInt32) -> Binding<ModifierSide> {
        Binding(get: { combo?.chords[safe: index]?.sides[modifier] ?? .any },
                set: { side in
                    guard let current = combo, var step = current.chords[safe: index] else { return }
                    step.sides[modifier] = side
                    combo = current.replacing(step: index, with: step)
                })
    }
}

private extension Array {
    subscript(safe index: Int) -> Element? { indices.contains(index) ? self[index] : nil }
}
