// Greenshot for Mac (Community) - an unofficial macOS port of Greenshot
// Copyright (C) 2026 Greenshot for Mac (Community) contributors
// Based on Greenshot, Copyright (C) 2007-2026 Thomas Braun, Jens Klingen, Robin Krom
// SPDX-License-Identifier: GPL-3.0-or-later

import AppKit
import GreenshotCore
import SwiftUI

/// Settings › Destinations: upstream's Destination tab (where a capture goes) with the settings of the
/// destinations that have some (mail, PDF, external commands, and the uploads in `DestinationsTab+Uploads.swift`).
struct DestinationsSettings: View {
    @ObservedObject var store: SettingsStore
    static let choices: [CaptureDestination] = CaptureDestination.allCases.filter { $0 != .picker }

    var body: some View {
        Form {
            afterCaptureSection
            emailSection
            pdfSection
            externalCommandsSection
            JiraSettingsSection(store: store)
            ConfluenceSettingsSection(store: store)
            CertificateExceptionsSection(store: store)
            BoxSettingsSection(store: store)
            DropboxSettingsSection(store: store)
        }
        .formStyle(.grouped)
    }

    private var afterCaptureSection: some View {
        Section {
            Toggle("Ask every time (destination menu)", isOn: destination(.picker))
            // Never disabled: with the menu on and nothing else chosen, there would be no way to switch.
            ForEach(Self.choices, id: \.self) { candidate in
                Toggle(candidate.displayName, isOn: destination(candidate))
            }
        } header: {
            Text("After a capture")
        } footer: {
            Text("Turning on any of the others turns off the menu. Several can be on, e.g. copy and save.")
                .font(.caption).foregroundStyle(.secondary)
        }
    }

    private var emailSection: some View {
        Section {
            TextField("To", text: store.binding(\.email.to))
            TextField("CC", text: store.binding(\.email.cc))
            TextField("BCC", text: store.binding(\.email.bcc))
            TextField("Subject", text: store.binding(\.email.subjectPattern))
        } header: {
            Text("Email")
        } footer: {
            Text("Separate addresses with commas. The subject can use the file name pattern variables, e.g. ${title}. The macOS mail service fills in To and the subject; CC and BCC are shown to add by hand.")
                .font(.caption).foregroundStyle(.secondary)
        }
    }

    private var pdfSection: some View {
        Section {
            Picker("Page size", selection: store.binding(\.pdf.pageSize)) {
                ForEach(PDFSettings.PageSize.allCases, id: \.self) { Text($0.displayName).tag($0) }
            }
            Picker("Unit", selection: store.binding(\.pdf.unit)) {
                ForEach(PDFSettings.Unit.allCases, id: \.self) { Text($0.displayName).tag($0) }
            }
            if store.value.pdf.pageSize == .custom {
                LabeledContent("Custom size") {
                    HStack {
                        numberField("Width", \.pdf.customWidth)
                        Text("×")
                        numberField("Height", \.pdf.customHeight)
                    }
                }
            }
            LabeledContent("Margins") {
                HStack {
                    numberField("Top", \.pdf.marginTop)
                    numberField("Left", \.pdf.marginLeft)
                    numberField("Right", \.pdf.marginRight)
                    numberField("Bottom", \.pdf.marginBottom)
                }
            }
            Picker("Scaling", selection: store.binding(\.pdf.scaling)) {
                ForEach(PDFSettings.Scaling.allCases, id: \.self) { Text($0.displayName).tag($0) }
            }
            .disabled(store.value.pdf.pageSize == .image)
        } header: {
            Text("PDF")
        } footer: {
            Text("“Image size” makes the page as big as the screenshot plus the margins. The image is centred on the page.")
                .font(.caption).foregroundStyle(.secondary)
        }
    }

    private func numberField(_ title: String, _ keyPath: WritableKeyPath<AppSettings, Double>) -> some View {
        TextField(title, value: store.binding(keyPath), format: .number)
            .frame(width: 56)
            .multilineTextAlignment(.trailing)
            .help(title)
    }

    private var externalCommandsSection: some View {
        Section {
            ForEach(store.value.externalCommands) { command in
                ExternalCommandRow(command: command, edit: { edit(command) }, remove: { remove(command) })
            }
            HStack {
                Spacer()
                Button("Add…") { add() }
            }
        } header: {
            Text("External commands")
        } footer: {
            Text("Each command is a destination of its own (\u{201C}External: name\u{201D}). {0} in the arguments is the screenshot's file (the saved file when the editor's screenshot is saved and unchanged); the command and the arguments can use the file name pattern variables. A command whose program is missing is left out of the destination menu.")
                .font(.caption).foregroundStyle(.secondary)
        }
    }

    private func add() {
        guard let command = ExternalCommandEditor.edit(nil, others: store.value.externalCommands) else { return }
        store.update { $0.externalCommands.append(command) }
    }

    private func edit(_ command: ExternalCommand) {
        guard let changed = ExternalCommandEditor.edit(command, others: store.value.externalCommands) else { return }
        store.update { settings in
            if let index = settings.externalCommands.firstIndex(where: { $0.id == command.id }) {
                settings.externalCommands[index] = changed
            }
        }
    }

    private func remove(_ command: ExternalCommand) {
        store.update { $0.externalCommands.removeAll { $0.id == command.id } }
    }

    /// "Ask every time" excludes the others, like upstream's picker; without any destination it comes back.
    private func destination(_ candidate: CaptureDestination) -> Binding<Bool> {
        Binding(
            get: { store.value.destinations.contains(candidate) },
            set: { on in store.update { $0.setDestination(candidate, on: on) } })
    }
}

/// One external command in Settings › Destinations.
private struct ExternalCommandRow: View {
    let command: ExternalCommand
    let edit: () -> Void
    let remove: () -> Void

    var body: some View {
        HStack {
            VStack(alignment: .leading, spacing: 2) {
                HStack(spacing: 6) {
                    if let icon = ExternalCommandRunner.icon(for: command) { Image(nsImage: icon) }
                    Text(command.name).fontWeight(.medium)
                }
                Text("\(command.command) \(command.arguments)")
                    .font(.caption).foregroundStyle(.secondary).lineLimit(1).truncationMode(.middle)
                Text(options).font(.caption2).foregroundStyle(.secondary)
                if !ExternalCommandRunner.isAvailable(command) {
                    // Upstream drops such commands at startup; here the entry stays, in case the program comes back.
                    Text("Program not found").font(.caption).foregroundStyle(.red)
                }
            }
            Spacer()
            Button("Edit…", action: edit)
            Button(role: .destructive, action: remove) { Image(systemName: "minus.circle") }
                .buttonStyle(.borderless)
                .help("Remove \(command.name)")
        }
    }

    private var options: String {
        var parts: [String] = [command.format.displayName, command.runInBackground ? "In the background" : "Waits, errors in a dialog"]
        if command.copyURLFromOutput { parts.append("copies a URL") }
        if command.copyOutputToClipboard { parts.append("copies the output") }
        return parts.joined(separator: " · ")
    }
}

extension DestinationsSettings {
    /// The sections below the destination list, for the snapshots (the tab's own snapshot shows its top only).
    var commandsAndUploadsForSnapshot: some View {
        Form {
            externalCommandsSection
            JiraSettingsSection(store: store)
            ConfluenceSettingsSection(store: store)
        }
        .formStyle(.grouped)
    }

    /// Jira, Confluence and Your own servers, for the snapshots.
    var serversForSnapshot: some View {
        Form {
            JiraSettingsSection(store: store)
            ConfluenceSettingsSection(store: store)
            CertificateExceptionsSection(store: store)
        }
        .formStyle(.grouped)
    }
}
