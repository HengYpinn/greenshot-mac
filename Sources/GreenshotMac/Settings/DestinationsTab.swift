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
            OfficeSettingsSection(store: store)
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
            if !store.value.isDestinationExcluded(.picker) {
                Toggle("Ask every time (destination menu)", isOn: destination(.picker))
                    .managed(\.destinations)
            }
            // Never disabled: with the menu on and nothing else chosen, there would be no way to switch. Only an
            // administrator locks them (upstream `FixedToEnabledConverter` on `OutputDestinations`), and the ones they
            // turned off aren't listed (`ExcludeDestinations`).
            ForEach(Self.choices.filter(Self.isOffered).filter { !store.value.isDestinationExcluded($0) }, id: \.self) { candidate in
                Toggle(candidate.displayName, isOn: destination(candidate))
                    .managed(\.destinations)
            }
        } header: {
            Text("After a capture")
        } footer: {
            Text("Turning on any of the others turns off the menu. Several can be on, e.g. copy and save.")
                .font(.caption).foregroundStyle(.secondary)
        }
    }

    /// The Office destinations only when their app is installed (or already chosen).
    @MainActor
    private static func isOffered(_ destination: CaptureDestination) -> Bool {
        guard let app = OfficeApplication(destination: destination) else { return true }
        return OfficeDestination.isInstalled(app)
    }

    private var emailSection: some View {
        Section {
            TextField("To", text: store.binding(\.email.to))
                .managed(\.email.to)
            TextField("CC", text: store.binding(\.email.cc))
                .managed(\.email.cc)
            TextField("BCC", text: store.binding(\.email.bcc))
                .managed(\.email.bcc)
            TextField("Subject", text: store.binding(\.email.subjectPattern))
                .managed(\.email.subjectPattern)
        } header: {
            Text("Email")
        } footer: {
            Text("Separate addresses with commas. The subject can use the file name pattern variables, e.g. ${title}. Outlook uses them too. With CC or BCC and Mail as your mail app, Mail writes the whole mail (macOS asks once whether Greenshot may control Mail); otherwise the macOS mail service fills in To and the subject, and CC and BCC are shown to add by hand.")
                .font(.caption).foregroundStyle(.secondary)
        }
    }

    private var pdfSection: some View {
        Section {
            Picker("Page size", selection: store.binding(\.pdf.pageSize)) {
                ForEach(PDFSettings.PageSize.allCases, id: \.self) { Text($0.displayName).tag($0) }
            }
            .managed(\.pdf.pageSize)
            Picker("Unit", selection: store.binding(\.pdf.unit)) {
                ForEach(PDFSettings.Unit.allCases, id: \.self) { Text($0.displayName).tag($0) }
            }
            .managed(\.pdf.unit)
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
            .managed(\.pdf.scaling)
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
            .managed(keyPath)
    }

    private var externalCommandsSection: some View {
        Section {
            ForEach(store.value.externalCommands) { command in
                ExternalCommandRow(command: command, edit: { edit(command) }, remove: { remove(command) })
                    .managed(\.externalCommands)
            }
            HStack {
                Spacer()
                Button("Add…") { add() }
            }
            .managed(\.externalCommands)
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

/// Upstream's Office settings (`OfficeConfigurationView`): Word and PowerPoint pictures, the Outlook mail format; the
/// subject and recipients are the Email section's.
struct OfficeSettingsSection: View {
    @ObservedObject var store: SettingsStore

    var body: some View {
        Section {
            Toggle("Word: lock aspect ratio of the image", isOn: store.binding(\.office.wordLockAspectRatio))
                .managed(\.office.wordLockAspectRatio)
            Toggle("PowerPoint: lock aspect ratio of the image", isOn: store.binding(\.office.powerpointLockAspectRatio))
                .managed(\.office.powerpointLockAspectRatio)
            Picker("PowerPoint: slide layout for exported captures", selection: store.binding(\.office.powerpointSlideLayout)) {
                ForEach(OfficeSettings.SlideLayout.allCases, id: \.self) { Text($0.displayName).tag($0) }
            }
            .managed(\.office.powerpointSlideLayout)
            Picker("Outlook: email format for new emails", selection: store.binding(\.office.outlookEmailFormat)) {
                ForEach(OfficeSettings.EmailFormat.allCases, id: \.self) { Text($0.displayName).tag($0) }
            }
            .managed(\.office.outlookEmailFormat)
            // Upstream `OutlookAllowExportInMeetings` ("Allow export in meeting items").
            Toggle("Outlook: allow export in meeting items", isOn: store.binding(\.office.outlookAllowExportInMeetings))
                .managed(\.office.outlookAllowExportInMeetings)
                .help("The destination menu also lists the open meetings you organise; the screenshot is attached to the meeting.")
            HStack {
                Text("Greenshot sends screenshots to these apps by AppleScript; macOS asks once per app.")
                    .font(.caption).foregroundStyle(.secondary)
                Spacer()
                Button("Privacy Settings…") { AppleScriptRunner.openAutomationSettings() }
            }
        } header: {
            Text("Microsoft Office and Notes")
        } footer: {
            Text("Word, PowerPoint and Outlook insert into a new document, presentation or mail, or one that is open (the destination menu lists them). Excel inserts into the active sheet of an open or a new workbook. Outlook attaches the screenshot and uses the Email section's subject, To, CC and BCC; with “allow export in meeting items” it also lists the open meetings you organise and attaches the screenshot to the meeting. New Outlook can't be scripted. OneNote for Mac can't be scripted either: Notes takes its place (or use Open With). On a layout without a picture placeholder the screenshot is centred on the slide; a layout PowerPoint refuses gives a blank slide.")
                .font(.caption).foregroundStyle(.secondary)
        }
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

    /// The Email and Office sections, for the snapshots.
    var officeForSnapshot: some View {
        Form {
            emailSection
            OfficeSettingsSection(store: store)
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
