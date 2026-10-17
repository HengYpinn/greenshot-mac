// Greenshot for Mac (Community) - an unofficial macOS port of Greenshot
// Copyright (C) 2026 Greenshot for Mac (Community) contributors
// Based on Greenshot, Copyright (C) 2007-2026 Thomas Braun, Jens Klingen, Robin Krom
// SPDX-License-Identifier: GPL-3.0-or-later

import AppKit
import GreenshotCore
import SwiftUI

/// Settings › Expert: port of the Expert tab of upstream `Greenshot/Settings/Views/SettingsWindow.xaml`
/// (window thumbnails, unstable updates, the `${NUM}` counter, clipboard formats) and the ini-only `MaxMenuItemLength`.
struct ExpertSettings: View {
    @ObservedObject var store: SettingsStore

    var body: some View {
        Form {
            menusSection
            Section("Updates") {
                Toggle("Check for unstable updates (pre-releases)", isOn: store.binding(\.checkForUnstable))
                    .help("Also offer beta versions of \(AppInfo.name) when it looks for updates.")
                    .managed(\.checkForUnstable)
            }
            clipboardSection
            counterSection
            AutomationSettingsSection(store: store)
            BrowserExtensionSettingsSection(store: store)
            troubleshootingSection
        }
        .formStyle(.grouped)
    }

    /// Self-Service and the log viewer (upstream opens them from the About window and `greenshot://` links).
    private var troubleshootingSection: some View {
        Section {
            HStack {
                Button("Open Self-Service…") { (NSApp.delegate as? AppDelegate)?.showSelfService(section: nil) }
                Button("Open Log Viewer…") { (NSApp.delegate as? AppDelegate)?.showLogViewer(search: nil) }
                Spacer()
                Button("Show Welcome…") { (NSApp.delegate as? AppDelegate)?.showWelcome() }
            }
        } header: {
            Text("Troubleshooting")
        } footer: {
            Text("Checks of the setup, the system, the hotkeys and the clipboard, and the log of \(AppInfo.name).")
                .font(.caption).foregroundStyle(.secondary)
        }
    }

    private var clipboardSection: some View {
        Section {
            ForEach(ClipboardFormat.allCases, id: \.self) { format in
                Toggle(format.displayName, isOn: clipboardFormat(format))
                    .managed(\.clipboardFormats)
            }
        } header: {
            Text("Clipboard formats")
        } footer: {
            Text("What “Copy to clipboard” puts there. Apps take the first format they understand; HTML embeds the image as PNG for mail and web editors.")
                .font(.caption).foregroundStyle(.secondary)
        }
    }

    private var menusSection: some View {
        Section("Menus") {
            Toggle("Show window thumbnails in the window list", isOn: store.binding(\.thumbnailPreview))
                .help("Pointing at a window in Capture Window from List shows a picture of it. Needs the screen recording permission.")
                .managed(\.thumbnailPreview)
            Stepper(value: store.binding(\.maxMenuItemLength), in: 5...200, step: 5) {
                Text("Window titles in menus: up to \(store.value.maxMenuItemLength) characters")
            }
            .managed(\.maxMenuItemLength)
        }
    }

    private var counterSection: some View {
        Section {
            LabeledContent("Next number") {
                HStack {
                    TextField("Next number", value: nextNumber, format: .number.grouping(.never))
                        .labelsHidden()
                        .textFieldStyle(.roundedBorder)
                        .multilineTextAlignment(.trailing)
                        .monospacedDigit()
                        .frame(width: 90)
                    Button("Reset") { store.update { $0.incrementingNumber = 0 } }
                        .disabled(store.value.incrementingNumber == 0)
                }
            }
            .managed(\.incrementingNumber)
        } header: {
            Text("File name counter")
        } footer: {
            Text("${NUM} in the file name pattern counts up with every file, six digits with leading zeros.")
                .font(.caption).foregroundStyle(.secondary)
        }
    }

    /// The number the next ${NUM} gets. Upstream's field edits the stored last-used number
    /// (`OutputFileIncrementingNumber`, counted up before use); this one shows and edits the next.
    private var nextNumber: Binding<Int> {
        Binding(get: { Int(clamping: store.value.incrementingNumber) + 1 },
                set: { next in store.update { $0.incrementingNumber = UInt(max(next, 1) - 1) } })
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
