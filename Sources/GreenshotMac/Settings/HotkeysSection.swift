// Greenshot for Mac (Community) - an unofficial macOS port of Greenshot
// Copyright (C) 2026 Greenshot for Mac (Community) contributors
// Based on Greenshot, Copyright (C) 2007-2026 Thomas Braun, Jens Klingen, Robin Krom
// SPDX-License-Identifier: GPL-3.0-or-later

import GreenshotCore
import SwiftUI

/// The Hotkeys section of Settings › General (upstream's hotkey fields on the General tab).
struct HotkeysSection: View {
    @ObservedObject var store: SettingsStore

    var body: some View {
        Section {
            LabeledContent("Capture region") { ShortcutRecorder(combo: store.binding(\.hotkeys.region)) }
            LabeledContent("Capture window") { ShortcutRecorder(combo: store.binding(\.hotkeys.window)) }
            LabeledContent("Capture full screen") { ShortcutRecorder(combo: store.binding(\.hotkeys.fullScreen)) }
            LabeledContent("Capture last region") { ShortcutRecorder(combo: store.binding(\.hotkeys.lastRegion)) }
            LabeledContent("Open image from clipboard") { ShortcutRecorder(combo: store.binding(\.hotkeys.clipboard)) }
        } header: {
            Text("Hotkeys")
        } footer: {
            Text("Click a shortcut, then type the new one. ⌫ clears it, ⎋ cancels. Keyboards with an F13 key can use it like Print Screen.")
                .font(.caption).foregroundStyle(.secondary)
        }
    }
}
