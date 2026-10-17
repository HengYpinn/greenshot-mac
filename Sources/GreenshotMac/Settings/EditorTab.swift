// Greenshot for Mac (Community) - an unofficial macOS port of Greenshot
// Copyright (C) 2026 Greenshot for Mac (Community) contributors
// Based on Greenshot, Copyright (C) 2007-2026 Thomas Braun, Jens Klingen, Robin Krom
// SPDX-License-Identifier: GPL-3.0-or-later

import AppKit
import GreenshotCore
import SwiftUI

/// Settings › Editor: port of the Editor tab of upstream `Greenshot/Settings/Views/SettingsWindow.xaml`
/// (`IEditorConfiguration.MatchSizeToCapture`, `ReuseEditor`, `SuppressSaveDialogAtClose`), and two editor settings
/// upstream keeps in its ini file only (`DefaultEditorSize`, `FreehandSensitivity`): the Mac has no ini file to edit.
struct EditorSettings: View {
    @ObservedObject var store: SettingsStore

    var body: some View {
        Form {
            Section {
                Toggle("Match the editor window size to the capture", isOn: store.binding(\.matchSizeToCapture))
                    .managed(\.matchSizeToCapture)
                Toggle("Reuse the editor if possible", isOn: store.binding(\.reuseEditor))
                    .help("A new capture replaces the screenshot of an editor that has no unsaved changes, instead of opening another window.")
                    .managed(\.reuseEditor)
                Toggle("Don't ask to save when closing an editor", isOn: store.binding(\.suppressSaveDialogAtClose))
                    .help("Closing an editor with changes discards them without a question.")
                    .managed(\.suppressSaveDialogAtClose)
            } header: {
                Text("Editor windows")
            }
            Section {
                LabeledContent("New image size") {
                    HStack(spacing: 4) {
                        TextField("Width", value: sizeBinding(\.width), format: .number)
                            .frame(width: 60)
                        Text("×")
                        TextField("Height", value: sizeBinding(\.height), format: .number)
                            .frame(width: 60)
                        Text("points")
                    }
                    .labelsHidden()
                    .textFieldStyle(.roundedBorder)
                }
                .help("The size of File › New Image, a white image to draw on.")
                .managed(\.defaultEditorSize)
                Stepper(value: store.binding(\.freehandSensitivity), in: 1...100) {
                    LabeledContent("Freehand smoothing", value: "\(store.value.freehandSensitivity)")
                }
                .help("Smaller keeps more detail of a freehand line, larger makes it smoother.")
                .managed(\.freehandSensitivity)
            } header: {
                Text("Drawing")
            }
        }
        .formStyle(.grouped)
    }

    /// A side of the new image size, 1 to 10 000 points.
    private func sizeBinding(_ side: WritableKeyPath<CaptureSize, Int>) -> Binding<Int> {
        Binding(get: { store.value.defaultEditorSize[keyPath: side] },
                set: { value in store.update { $0.defaultEditorSize[keyPath: side] = min(max(value, 1), 10_000) } })
    }
}
