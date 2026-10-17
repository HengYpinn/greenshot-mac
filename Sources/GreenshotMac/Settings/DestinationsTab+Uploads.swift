// Greenshot for Mac (Community) - an unofficial macOS port of Greenshot
// Copyright (C) 2026 Greenshot for Mac (Community) contributors
// Based on Greenshot, Copyright (C) 2007-2026 Thomas Braun, Jens Klingen, Robin Krom
// SPDX-License-Identifier: GPL-3.0-or-later

import AppKit
import GreenshotCore
import SwiftUI

// Settings › Destinations: the upload destinations (upstream's Jira, Confluence, Box and Dropbox plugin settings).

/// A secret in the Keychain, edited like a setting.
@MainActor
final class SecretFieldModel: ObservableObject {
    @Published var text: String {
        didSet { if text != oldValue { save() } }
    }
    @Published var error: String?
    private let key: String

    init(key: String) {
        self.key = key
        text = (try? Uploads.secrets.secret(for: key)) ?? ""
    }

    private func save() {
        do {
            try Uploads.secrets.setSecret(text, for: key)
            error = nil
        } catch {
            self.error = error.localizedDescription
        }
    }
}

struct SecretField: View {
    let title: String
    @StateObject private var model: SecretFieldModel

    init(_ title: String, key: String) {
        self.title = title
        _model = StateObject(wrappedValue: SecretFieldModel(key: key))
    }

    var body: some View {
        SecureField(title, text: $model.text)
        if let error = model.error {
            Text(error).font(.caption).foregroundStyle(.red)
        }
    }
}

/// The "Test" button of an Atlassian site: tries the credentials and shows who they belong to.
@MainActor
final class ConnectionTest: ObservableObject {
    @Published var result: String?
    @Published var running = false

    func run(confluence: Bool, settings: AppSettings) {
        guard let site = confluence ? Uploads.confluenceSite(settings) : Uploads.jiraSite(settings) else {
            result = "Enter the URL first."
            return
        }
        running = true
        Task { @MainActor in
            switch await Uploads.testAtlassian(site, confluence: confluence) {
            case .success(let name): result = "Connected as \(name)."
            case .failure(let error): result = error.localizedDescription
            }
            running = false
        }
    }
}

/// Signed in or not at Box and Dropbox, with Sign In and Sign Out.
@MainActor
final class CloudAccount: ObservableObject {
    @Published var signedIn = false
    @Published var busy = false
    @Published var message: String?
    let destination: CaptureDestination

    init(destination: CaptureDestination) {
        self.destination = destination
    }

    func refresh(settings: AppSettings) {
        signedIn = Uploads.oauthClient(for: destination, settings: settings).isSignedIn
    }

    func signIn(settings: AppSettings) {
        let client = Uploads.oauthClient(for: destination, settings: settings)
        busy = true
        message = nil
        Task { @MainActor in
            do {
                try await client.signIn(with: BrowserAuthorizer.shared)
                message = "Signed in."
            } catch UploadError.cancelled {
            } catch {
                message = error.localizedDescription
            }
            busy = false
            refresh(settings: settings)
        }
    }

    func signOut(settings: AppSettings) {
        try? Uploads.oauthClient(for: destination, settings: settings).signOut()
        message = nil
        refresh(settings: settings)
    }
}

struct JiraSettingsSection: View {
    @ObservedObject var store: SettingsStore
    @StateObject private var test = ConnectionTest()

    var body: some View {
        Section {
            TextField("URL", text: store.binding(\.jira.url), prompt: Text("https://yourcompany.atlassian.net"))
            TextField("Email", text: store.binding(\.jira.email))
            SecretField("API token", key: SecretKey.jiraToken)
            UploadFormatRow(format: store.binding(\.jira.uploadFormat), quality: store.binding(\.jira.jpegQuality),
                            reduceColors: store.binding(\.jira.reduceColors))
            ConnectionTestRow(test: test) { test.run(confluence: false, settings: store.value) }
        } header: {
            Text("Jira")
        } footer: {
            Text("Create an API token for your Atlassian account at [id.atlassian.com › Security › API tokens](https://id.atlassian.com/manage-profile/security/api-tokens). The token is kept in your Keychain. The upload asks for the issue: a key, one of the last ten, a favourite filter or a search. Issues in the titles of open windows (e.g. the browser) are offered in the destination menu.")
                .font(.caption).foregroundStyle(.secondary)
        }
    }
}

struct ConfluenceSettingsSection: View {
    @ObservedObject var store: SettingsStore
    @StateObject private var test = ConnectionTest()

    var body: some View {
        Section {
            TextField("URL", text: store.binding(\.confluence.url), prompt: Text("https://yourcompany.atlassian.net/wiki"))
            TextField("Email", text: store.binding(\.confluence.email))
            SecretField("API token", key: SecretKey.confluenceToken)
            UploadFormatRow(format: store.binding(\.confluence.uploadFormat), quality: store.binding(\.confluence.jpegQuality),
                            reduceColors: store.binding(\.confluence.reduceColors))
            Toggle("Open the page after the upload", isOn: store.binding(\.confluence.openPageAfterUpload))
            Picker("Copy to the clipboard", selection: store.binding(\.confluence.clipboardContent)) {
                ForEach(ConfluenceSettings.ClipboardContent.allCases, id: \.self) { Text($0.displayName).tag($0) }
            }
            ConnectionTestRow(test: test) { test.run(confluence: true, settings: store.value) }
        } header: {
            Text("Confluence")
        } footer: {
            Text("Cloud sites end in /wiki. The same kind of API token as for Jira (one token works for both). The upload asks for the page: one of the last ten, or a search by title in one space or all. The last ten are in the destination menu too.")
                .font(.caption).foregroundStyle(.secondary)
        }
    }
}

struct BoxSettingsSection: View {
    @ObservedObject var store: SettingsStore
    @StateObject private var account = CloudAccount(destination: .box)

    var body: some View {
        Section {
            TextField("Client ID", text: store.binding(\.box.clientID))
            SecretField("Client secret", key: SecretKey.boxClientSecret)
            TextField("Folder ID", text: store.binding(\.box.folderID), prompt: Text("0 = All Files"))
            UploadFormatRow(format: store.binding(\.box.uploadFormat), quality: store.binding(\.box.jpegQuality))
            Toggle("Copy the link to the clipboard", isOn: store.binding(\.box.copyLinkToClipboard))
            Toggle("Shared link (anyone with the link), not the private one", isOn: store.binding(\.box.useSharedLink))
                .disabled(!store.value.box.copyLinkToClipboard)
            CloudAccountRow(account: account, store: store)
        } header: {
            Text("Box")
        } footer: {
            Text("Greenshot can't ship a Box app key, so register your own: in the [Box Developer Console](https://app.box.com/developers/console) create a Custom App with User Authentication (OAuth 2.0), set its redirect URI to `\(OAuthProvider.box.redirect.url.absoluteString)`, give it the Write all files scope, and paste its client ID and secret here. The secret and the sign-in are kept in your Keychain; the folder ID is the number in the folder's URL.")
                .font(.caption).foregroundStyle(.secondary)
        }
    }
}

struct DropboxSettingsSection: View {
    @ObservedObject var store: SettingsStore
    @StateObject private var account = CloudAccount(destination: .dropbox)

    var body: some View {
        Section {
            TextField("App key", text: store.binding(\.dropbox.appKey))
            TextField("Folder", text: store.binding(\.dropbox.folder), prompt: Text("e.g. Screenshots; empty = the app's folder"))
            UploadFormatRow(format: store.binding(\.dropbox.uploadFormat), quality: store.binding(\.dropbox.jpegQuality))
            Toggle("Copy a shared link to the clipboard", isOn: store.binding(\.dropbox.copyLinkToClipboard))
            CloudAccountRow(account: account, store: store)
        } header: {
            Text("Dropbox")
        } footer: {
            Text("Register your own app in the [Dropbox App Console](https://www.dropbox.com/developers/apps): Scoped access, App folder or Full Dropbox, the permissions files.content.write, sharing.write and sharing.read, and the redirect URI `\(OAuthProvider.dropbox.redirect.url.absoluteString)`. Paste its App key here; no secret is needed. The sign-in is kept in your Keychain.")
                .font(.caption).foregroundStyle(.secondary)
        }
    }
}

/// Format and JPEG quality of an upload, and "reduce colours" where upstream has it (`UploadReduceColors` of Jira and
/// Confluence).
private struct UploadFormatRow: View {
    @Binding var format: UploadFormat
    @Binding var quality: Int
    var reduceColors: Binding<Bool>? = nil

    var body: some View {
        Picker("Format", selection: $format) {
            ForEach(UploadFormat.allCases, id: \.self) { Text($0.displayName).tag($0) }
        }
        if format == .jpg {
            LabeledContent("JPEG quality") {
                HStack {
                    Slider(value: Binding(get: { Double(quality) }, set: { quality = Int($0.rounded()) }), in: 10...100, step: 5)
                    Text("\(quality)").monospacedDigit().frame(width: 32, alignment: .trailing)
                }
            }
        }
        if let reduceColors, format == .png {
            Toggle("Reduce the amount of colours to a maximum of 256", isOn: reduceColors)
        }
    }
}

private struct ConnectionTestRow: View {
    @ObservedObject var test: ConnectionTest
    let run: () -> Void

    var body: some View {
        HStack {
            Text(test.result ?? "").font(.caption).foregroundStyle(.secondary).lineLimit(2)
            Spacer()
            Button("Test Connection", action: run).disabled(test.running)
        }
    }
}

private struct CloudAccountRow: View {
    @ObservedObject var account: CloudAccount
    @ObservedObject var store: SettingsStore

    var body: some View {
        HStack {
            Text(account.message ?? (account.signedIn ? "Signed in." : "Not signed in; the first upload asks."))
                .font(.caption).foregroundStyle(.secondary).lineLimit(2)
            Spacer()
            if account.signedIn {
                Button("Sign Out") { account.signOut(settings: store.value) }
            } else {
                Button("Sign In…") { account.signIn(settings: store.value) }.disabled(account.busy)
            }
        }
        .onAppear { account.refresh(settings: store.value) }
    }
}
