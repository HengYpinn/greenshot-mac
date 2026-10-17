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

    private static var rows: [(title: String, keyPath: WritableKeyPath<HotkeySettings, KeyCombo?>)] {
        [("Capture region", \.region), ("Capture window", \.window), ("Capture full screen", \.fullScreen),
         ("Capture last region", \.lastRegion), ("Capture text", \.text), ("Open image from clipboard", \.clipboard)]
    }

    var body: some View {
        Section {
            ForEach(Self.rows, id: \.title) { row in
                HotkeyRow(title: row.title, combo: store.binding((\AppSettings.hotkeys).appending(path: row.keyPath)),
                          conflict: conflict(for: row.title), initialProblem: initialProblems[row.title])
            }
        } header: {
            Text("Hotkeys")
        } footer: {
            Text("""
                Click a shortcut, then type the new one. ⌫ clears it, ⎋ cancels. + adds a step, for hotkeys like ⌃⌥⌘K then C \
                (within 2.5 seconds). Keyboards with an F13 key can use it like Print Screen.
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
    @State private var problem: String?

    init(title: String, combo: Binding<KeyCombo?>, conflict: String?, initialProblem: String?) {
        self.title = title
        _combo = combo
        self.conflict = conflict
        _problem = State(initialValue: initialProblem)
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            LabeledContent(title) { ShortcutRecorder(combo: $combo, problem: $problem) }
            if let message = problem ?? conflict {
                Text(message)
                    .font(.caption)
                    .foregroundStyle(problem != nil ? Color.red : Color.orange)
                    .frame(maxWidth: .infinity, alignment: .trailing)
            }
        }
    }
}
