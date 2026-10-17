// Greenshot for Mac (Community) - an unofficial macOS port of Greenshot
// Copyright (C) 2026 Greenshot for Mac (Community) contributors
// Based on Greenshot, Copyright (C) 2007-2026 Thomas Braun, Jens Klingen, Robin Krom
// SPDX-License-Identifier: GPL-3.0-or-later

import AppKit
import GreenshotCore
import SwiftUI

/// Settings › Output (upstream's Output tab); where captures go is in Settings › Destinations.
struct OutputSettings: View {
    @ObservedObject var store: SettingsStore

    var body: some View {
        Form {
            filesSection
            formatSection
            messagesSection
        }
        .formStyle(.grouped)
    }

    private var filesSection: some View {
        Section("Files") {
            LabeledContent("Folder") {
                HStack {
                    Text((store.value.outputFolderURL.path as NSString).abbreviatingWithTildeInPath)
                        .lineLimit(1).truncationMode(.middle)
                    Button("Choose…", action: chooseFolder)
                }
            }
            TextField("File name pattern", text: store.binding(\.filenamePattern))
            Text("Example: \(example)").font(.caption).foregroundStyle(.secondary).textSelection(.enabled)
            DisclosureGroup("Pattern variables") {
                Text(FilenamePattern.helpText).font(.caption).textSelection(.enabled).frame(maxWidth: .infinity, alignment: .leading)
            }
            Toggle("Overwrite a file with the same name", isOn: store.binding(\.allowOverwrite))
                .help("Off: “Save directly” adds (2), (3), … to the name instead.")
            Toggle("Copy the file path to the clipboard every time an image is saved", isOn: store.binding(\.copyPathToClipboard))
        }
    }

    private var formatSection: some View {
        Section("Image format") {
            Picker("Format", selection: store.binding(\.outputFormat)) {
                ForEach(ImageFormat.allCases, id: \.self) { Text($0.displayName).tag($0) }
            }
            if store.value.outputFormat == .jpg {
                Slider(value: jpegQuality, in: 10...100, step: 5) {
                    Text("JPEG quality: \(store.value.jpegQuality)")
                }
            }
            Toggle("Show the quality dialog every time an image is saved", isOn: store.binding(\.promptJpegQuality))
            Toggle("Reduce the colours of PNG and GIF files", isOn: store.binding(\.reduceColors))
            if store.value.reduceColors {
                Stepper(value: store.binding(\.reduceColorsTo), in: 2...256) {
                    Text("At most \(store.value.reduceColorsTo) colours")
                }
            }
        }
    }

    private var messagesSection: some View {
        Section("Messages") {
            Toggle("Show a message after saving or copying", isOn: store.binding(\.showNotifications))
            Picker("Show", selection: store.binding(\.notificationLevel)) {
                ForEach(NotificationLevel.allCases, id: \.self) { Text($0.displayName).tag($0) }
            }
        }
    }

    private var jpegQuality: Binding<Double> {
        Binding(get: { Double(store.value.jpegQuality) },
                set: { value in store.update { $0.jpegQuality = Int(value.rounded()) } })
    }

    private var example: String {
        let name = FilenamePattern.fill(store.value.filenamePattern,
                                        context: store.patternContext(title: "Safari", date: Date(), consumeNumber: false))
        return "\(name).\(store.value.outputFormat.fileExtension)"
    }

    private func chooseFolder() {
        let panel = NSOpenPanel()
        panel.canChooseDirectories = true
        panel.canChooseFiles = false
        panel.canCreateDirectories = true
        panel.directoryURL = store.value.outputFolderURL
        guard panel.runModal() == .OK, let url = panel.url else { return }
        store.update { $0.outputFolder = (url.path as NSString).abbreviatingWithTildeInPath }
    }
}
