// Greenshot for Mac (Community) - an unofficial macOS port of Greenshot
// Copyright (C) 2026 Greenshot for Mac (Community) contributors
// Based on Greenshot, Copyright (C) 2007-2026 Thomas Braun, Jens Klingen, Robin Krom
// SPDX-License-Identifier: GPL-3.0-or-later

import AppKit
import GreenshotCore
import SwiftUI

/// Settings › Editor: port of the Editor tab of upstream `Greenshot/Settings/Views/SettingsWindow.xaml`
/// (`IEditorConfiguration.MatchSizeToCapture`, `ReuseEditor`, `SuppressSaveDialogAtClose`).
struct EditorSettings: View {
    @ObservedObject var store: SettingsStore

    var body: some View {
        Form {
            Section {
                Toggle("Match the editor window size to the capture", isOn: store.binding(\.matchSizeToCapture))
                Toggle("Reuse the editor if possible", isOn: store.binding(\.reuseEditor))
                    .help("A new capture replaces the screenshot of an editor that has no unsaved changes, instead of opening another window.")
                Toggle("Don't ask to save when closing an editor", isOn: store.binding(\.suppressSaveDialogAtClose))
                    .help("Closing an editor with changes discards them without a question.")
            } header: {
                Text("Editor windows")
            }
        }
        .formStyle(.grouped)
    }
}
