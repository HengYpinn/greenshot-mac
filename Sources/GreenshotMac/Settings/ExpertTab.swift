// Greenshot for Mac (Community) - an unofficial macOS port of Greenshot
// Copyright (C) 2026 Greenshot for Mac (Community) contributors
// Based on Greenshot, Copyright (C) 2007-2026 Thomas Braun, Jens Klingen, Robin Krom
// SPDX-License-Identifier: GPL-3.0-or-later

import AppKit
import GreenshotCore
import SwiftUI

/// Settings › Expert: port of the Expert tab of upstream `Greenshot/Settings/Views/SettingsWindow.xaml`
/// (clipboard formats, the `${NUM}` counter).
struct ExpertSettings: View {
    @ObservedObject var store: SettingsStore

    var body: some View {
        Form {
            clipboardSection
            counterSection
        }
        .formStyle(.grouped)
    }

    private var clipboardSection: some View {
        Section {
            ForEach(ClipboardFormat.allCases, id: \.self) { format in
                Toggle(format.displayName, isOn: clipboardFormat(format))
            }
        } header: {
            Text("Clipboard formats")
        } footer: {
            Text("What “Copy to clipboard” puts there. Apps take the first format they understand; HTML embeds the image as PNG for mail and web editors.")
                .font(.caption).foregroundStyle(.secondary)
        }
    }

    private var counterSection: some View {
        Section {
            LabeledContent("Next number") {
                HStack {
                    Text(String(format: "%06d", store.value.incrementingNumber + 1)).monospacedDigit()
                    Button("Reset") { store.update { $0.incrementingNumber = 0 } }
                        .disabled(store.value.incrementingNumber == 0)
                }
            }
        } header: {
            Text("File name counter")
        } footer: {
            Text("${NUM} in the file name pattern counts up with every file.").font(.caption).foregroundStyle(.secondary)
        }
    }

    private func clipboardFormat(_ format: ClipboardFormat) -> Binding<Bool> {
        Binding(
            get: { store.value.clipboardFormats.contains(format) },
            set: { on in
                store.update { settings in
                    var formats = settings.clipboardFormats.filter { $0 != format }
                    if on { formats.append(format) }
                    // Keep the order of the list, and never none.
                    settings.clipboardFormats = ClipboardFormat.allCases.filter(formats.contains)
                    if settings.clipboardFormats.isEmpty { settings.clipboardFormats = [.png] }
                }
            })
    }
}
