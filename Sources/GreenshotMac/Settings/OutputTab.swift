// Greenshot for Mac (Community) - an unofficial macOS port of Greenshot
// Copyright (C) 2026 Greenshot for Mac (Community) contributors
// Based on Greenshot, Copyright (C) 2007-2026 Thomas Braun, Jens Klingen, Robin Krom
// SPDX-License-Identifier: GPL-3.0-or-later

import AppKit
import GreenshotCore
import SwiftUI

/// Settings › Output (upstream's Output and Destination tabs).
struct OutputSettings: View {
    @ObservedObject var store: SettingsStore
    private static let others: [CaptureDestination] = [.editor, .clipboard, .file, .fileAs, .printer]

    var body: some View {
        Form {
            Section {
                Toggle("Ask every time (destination menu)", isOn: destination(.picker))
                // Never disabled: with the menu on and nothing else chosen, there would be no way to switch.
                ForEach(Self.others, id: \.self) { candidate in
                    Toggle(candidate.displayName, isOn: destination(candidate))
                }
            } header: {
                Text("After a capture")
            } footer: {
                Text("Turning on any of the others turns off the menu. Several can be on, e.g. copy and save.")
                    .font(.caption).foregroundStyle(.secondary)
            }
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
                    Text(Self.patternHelp).font(.caption).textSelection(.enabled).frame(maxWidth: .infinity, alignment: .leading)
                }
                Picker("Format", selection: store.binding(\.outputFormat)) {
                    ForEach(ImageFormat.allCases, id: \.self) { Text($0.displayName).tag($0) }
                }
                if store.value.outputFormat == .jpg {
                    Slider(value: Binding(get: { Double(store.value.jpegQuality) },
                                          set: { value in store.update { $0.jpegQuality = Int(value.rounded()) } }),
                           in: 10...100, step: 5) {
                        Text("JPEG quality: \(store.value.jpegQuality)")
                    }
                }
                Toggle("Copy the file path to the clipboard after “Save directly”", isOn: store.binding(\.copyPathToClipboard))
                Toggle("Show a message after saving or copying", isOn: store.binding(\.showNotifications))
            }
        }
        .formStyle(.grouped)
    }

    private var example: String {
        let name = FilenamePattern.fill(store.value.filenamePattern,
                                        context: store.patternContext(title: "Safari", date: Date(), consumeNumber: false))
        return "\(name).\(store.value.outputFormat.fileExtension)"
    }

    /// "Ask every time" excludes the others, like upstream's picker; without any destination it comes back.
    private func destination(_ candidate: CaptureDestination) -> Binding<Bool> {
        Binding(
            get: { store.value.destinations.contains(candidate) },
            set: { on in store.update { $0.setDestination(candidate, on: on) } })
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

    private static let patternHelp = """
        ${capturetime:d"yyyy-MM-dd HH_mm_ss"}  capture time, .NET date format
        ${title}  window title    ${user}  user name    ${hostname}  computer name
        ${YYYY} ${MM} ${DD} ${hh} ${mm} ${ss}  date and time parts
        ${NUM}  counter (000001)    ${RRRR}  random characters
        ${Desktop} ${MyPictures} ${MyDocuments}  folders    ${HOME} or any environment variable
        Options after a colon, separated by ';': p<width>[,char] pad, s<start>[,length] substring, r<old>,<new> replace
        A '/' in the pattern makes sub folders, e.g. ${YYYY}/${MM}/${title}
        """
}
