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
    /// Whose secret it is: the app's, or that of the Jira or Confluence site on a host (nil while the URL has none),
    /// which is shown and kept for that host only (see `AtlassianSecrets`).
    enum Owner: Equatable {
        case app
        case site(host: String?)
    }

    @Published var text: String {
        didSet { if text != oldValue { save() } }
    }
    @Published var error: String?
    /// The stored secret couldn't be read (the Keychain is locked, or its prompt was cancelled): the field is disabled,
    /// so typing doesn't replace a secret nobody saw. Settings opened again reads it again.
    @Published private(set) var unreadable = false
    private let key: String
    private let owner: Owner

    init(key: String, owner: Owner = .app) {
        self.key = key
        self.owner = owner
        var stored: String?
        var problem: String?
        do {
            switch owner {
            case .app: stored = try Uploads.secrets.secret(for: key)
            case .site(let host): stored = try AtlassianSecrets(store: Uploads.secrets).secret(for: key, host: host)
            }
        } catch {
            problem = error.localizedDescription
        }
        text = stored ?? ""
        error = problem
        unreadable = problem != nil
    }

    private func save() {
        do {
            switch owner {
            case .app: try Uploads.secrets.setSecret(text, for: key)
            case .site(let host): try AtlassianSecrets(store: Uploads.secrets).setSecret(text, for: key, host: host)
            }
            error = nil
        } catch {
            self.error = error.localizedDescription
        }
    }
}

struct SecretField: View {
    let title: String
    @StateObject private var model: SecretFieldModel

    init(_ title: String, key: String, owner: SecretFieldModel.Owner = .app) {
        self.title = title
        _model = StateObject(wrappedValue: SecretFieldModel(key: key, owner: owner))
    }

    var body: some View {
        SecureField(title, text: $model.text)
            .disabled(model.unreadable)
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
        let configured: AtlassianSite?
        do {
            configured = try confluence ? Uploads.confluenceSite(settings) : Uploads.jiraSite(settings)
        } catch {
            result = error.localizedDescription
            return
        }
        guard let site = configured else {
            result = String(localized: "Enter the URL first.")
            return
        }
        guard site.hasCredentials else {
            switch site.login {
            case .serverPassword: result = String(localized: "Enter the user name and password first (or test at the first upload).")
            case .cloudAPIToken: result = String(localized: "Enter the email and API token first.")
            case .serverToken: result = String(localized: "Enter the personal access token first.")
            }
            return
        }
        running = true
        Task { @MainActor in
            switch await Uploads.testAtlassian(site, confluence: confluence) {
            case .success(let name): result = String(localized: "Connected as \(name).")
            case .failure(let error): result = error.localizedDescription
            }
            running = false
        }
    }
}

/// Signed in or not at Box and Dropbox, with Sign In and Sign Out; Retry while the Keychain can't be read.
@MainActor
final class CloudAccount: ObservableObject {
    @Published var signedIn = false
    /// The Keychain couldn't be read (locked, or its prompt cancelled): whether there is an account is unknown, so
    /// there is no Sign In that would replace it, only Retry.
    @Published var unreadable = false
    @Published var busy = false
    @Published var message: String?
    let destination: CaptureDestination

    init(destination: CaptureDestination) {
        self.destination = destination
    }

    func refresh(settings: AppSettings) {
        do {
            signedIn = try Uploads.oauthClient(for: destination, settings: settings).storedTokens() != nil
            if unreadable { message = nil }
            unreadable = false
        } catch {
            signedIn = false
            unreadable = true
            message = error.localizedDescription
        }
    }

    func signIn(settings: AppSettings) {
        let client: OAuthClient
        do {
            client = try Uploads.oauthClient(for: destination, settings: settings)
        } catch {
            message = error.localizedDescription
            return
        }
        busy = true
        message = nil
        Task { @MainActor in
            do {
                try await client.signIn(with: BrowserAuthorizer.shared)
                message = String(localized: "Signed in.")
            } catch UploadError.cancelled {
            } catch {
                message = error.localizedDescription
            }
            busy = false
            refresh(settings: settings)
        }
    }

    func signOut(settings: AppSettings) {
        do {
            try Uploads.oauthClient(for: destination, settings: settings).signOut()
            message = nil
        } catch {
            message = error.localizedDescription
        }
        refresh(settings: settings)
    }
}

struct JiraSettingsSection: View {
    @ObservedObject var store: SettingsStore
    @StateObject private var test = ConnectionTest()

    var body: some View {
        let login = store.value.jira.login
        Section {
            Picker("Sign in with", selection: store.binding(\.jira.login)) {
                ForEach(AtlassianLogin.allCases, id: \.self) { Text($0.displayName).tag($0) }
            }
            .managed(\.jira.login)
            TextField("URL", text: store.binding(\.jira.url),
                      prompt: Text(login.isCloud ? "https://yourcompany.atlassian.net" : "https://jira.yourcompany.com"))
                .managed(\.jira.url)
            UnencryptedURLWarning(url: store.value.jira.url)
            if let userLabel = login.userLabel {
                TextField(userLabel, text: store.binding(\.jira.email))
                    .managed(\.jira.email)
            }
            let host = AtlassianSite.host(ofURL: store.value.jira.url)
            SecretField(login.secretLabel, key: SecretKey.jiraToken, owner: .site(host: host))
                .id(host ?? "")
            UploadFormatRow(store: store, format: \.jira.uploadFormat, quality: \.jira.jpegQuality, reduceColors: \.jira.reduceColors)
            ConnectionTestRow(test: test) { test.run(confluence: false, settings: store.value) }
        } header: {
            Text("Jira")
        } footer: {
            Text(AtlassianFooter.text(login, service: "Jira") + " "
                 + String(localized: "The upload asks for the issue: a key, one of the last ten, a favourite filter or a search. Issues in the titles of open windows (e.g. the browser) are offered in the destination menu."))
                .font(.caption).foregroundStyle(.secondary)
        }
    }
}

struct ConfluenceSettingsSection: View {
    @ObservedObject var store: SettingsStore
    @StateObject private var test = ConnectionTest()

    var body: some View {
        let login = store.value.confluence.login
        Section {
            Picker("Sign in with", selection: store.binding(\.confluence.login)) {
                ForEach(AtlassianLogin.allCases, id: \.self) { Text($0.displayName).tag($0) }
            }
            .managed(\.confluence.login)
            TextField("URL", text: store.binding(\.confluence.url),
                      prompt: Text(login.isCloud ? "https://yourcompany.atlassian.net/wiki" : "https://confluence.yourcompany.com"))
                .managed(\.confluence.url)
            UnencryptedURLWarning(url: store.value.confluence.url)
            if let userLabel = login.userLabel {
                TextField(userLabel, text: store.binding(\.confluence.email))
                    .managed(\.confluence.email)
            }
            let host = AtlassianSite.host(ofURL: store.value.confluence.url)
            SecretField(login.secretLabel, key: SecretKey.confluenceToken, owner: .site(host: host))
                .id(host ?? "")
            UploadFormatRow(store: store, format: \.confluence.uploadFormat, quality: \.confluence.jpegQuality,
                            reduceColors: \.confluence.reduceColors)
            Toggle("Open the page after the upload", isOn: store.binding(\.confluence.openPageAfterUpload))
                .managed(\.confluence.openPageAfterUpload)
            Picker("Copy to the clipboard", selection: store.binding(\.confluence.clipboardContent)) {
                ForEach(ConfluenceSettings.ClipboardContent.allCases, id: \.self) { Text($0.displayName).tag($0) }
            }
            .managed(\.confluence.clipboardContent)
            Toggle("Include personal spaces in search and browsing", isOn: store.binding(\.confluence.includePersonalSpaces))
                .managed(\.confluence.includePersonalSpaces)
            ConnectionTestRow(test: test) { test.run(confluence: true, settings: store.value) }
        } header: {
            Text("Confluence")
        } footer: {
            Text(footer(login))
                .font(.caption).foregroundStyle(.secondary)
        }
    }
}

extension ConfluenceSettingsSection {
    /// The footer: where the sign-in comes from, then how the upload finds the page.
    fileprivate func footer(_ login: AtlassianLogin) -> String {
        let signIn = AtlassianFooter.text(login, service: "Confluence")
        let upload = String(localized: "The upload asks for the page: one open in Safari or Chrome, a search by title, or the page tree of a space. The last ten are in the destination menu too.")
        guard login.isCloud else { return signIn + " " + upload }
        return String(localized: "Cloud sites end in /wiki.") + " " + signIn + " " + upload
    }
}

/// Under a Jira or Confluence URL that starts with `http://`: the credentials would travel unencrypted.
struct UnencryptedURLWarning: View {
    let url: String

    var body: some View {
        if AtlassianSite.isUnencrypted(url: url) {
            Text("This URL starts with http://: the token or password would travel unencrypted. Use https:// if the server offers it.")
                .font(.caption).foregroundStyle(.orange)
        }
    }
}

/// How the sign-in of Jira and Confluence works, for the sections' footers.
private enum AtlassianFooter {
    static func text(_ login: AtlassianLogin, service: String) -> String {
        switch login {
        case .cloudAPIToken:
            return String(localized: "Create an API token for your Atlassian account at [id.atlassian.com › Security › API tokens](https://id.atlassian.com/manage-profile/security/api-tokens) (one token works for Jira and Confluence). It is kept in your Keychain.")
        case .serverToken:
            return String(localized: "Create a personal access token in \(service) under your profile › Personal Access Tokens (Data Center, and Server 8.14 or later). It is kept in your Keychain.")
        case .serverPassword:
            return String(localized: "Leave the password empty to be asked at the first upload; the login dialog can keep it in your Keychain. A server with a certificate of its own can be trusted under Your own servers.")
        }
    }
}

/// "Your own servers": certificate exceptions for self-hosted Jira and Confluence with a self-signed certificate or a
/// private CA (upstream `AllowedUntrustedCertificateHosts`, `AllowedCertificateThumbprints`, only in greenshot.ini there).
struct CertificateExceptionsSection: View {
    @ObservedObject var store: SettingsStore

    var body: some View {
        Section {
            LinesField(title: String(localized: "Trust these hosts despite certificate errors"), prompt: "jira.mycompany.local\n*.mycompany.local",
                       lines: store.binding(\.allowedUntrustedCertificateHosts))
                .managed(\.allowedUntrustedCertificateHosts)
            LinesField(title: String(localized: "Trust certificates with these fingerprints"),
                       prompt: String(localized: "SHA-256 or SHA-1, e.g. 2F:D2:CC:…"),
                       lines: store.binding(\.allowedCertificateThumbprints))
                .managed(\.allowedCertificateThumbprints)
        } header: {
            Text("Your own servers")
        } footer: {
            Text("Only for the Jira and Confluence servers above whose certificate macOS doesn't trust; every other server gets the macOS checks alone. One host per line; * and ? are wildcards, a port is ignored. A fingerprint trusts exactly one certificate and is safer than a host; an upload that fails because of a certificate shows the server's fingerprint. Empty lists use the macOS checks alone.")
                .font(.caption).foregroundStyle(.secondary)
        }
    }
}

/// A list of strings edited as text, one per line; empty lines are dropped when saved.
struct LinesField: View {
    let title: String
    let prompt: String
    @Binding var lines: [String]
    @State private var text = ""
    @State private var loaded = false

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(title)
            TextField(title, text: $text, prompt: Text(prompt), axis: .vertical)
                .labelsHidden()
                .lineLimit(2...6)
                .font(.system(.body, design: .monospaced))
                .onChange(of: text) { _, new in
                    let parsed = Self.lines(of: new)
                    if parsed != lines { lines = parsed }
                }
        }
        .onAppear {
            guard !loaded else { return }
            loaded = true
            text = lines.joined(separator: "\n")
        }
    }

    static func lines(of text: String) -> [String] {
        text.split(whereSeparator: \.isNewline).map { $0.trimmingCharacters(in: .whitespaces) }.filter { !$0.isEmpty }
    }
}

struct BoxSettingsSection: View {
    @ObservedObject var store: SettingsStore
    @StateObject private var account = CloudAccount(destination: .box)

    var body: some View {
        Section {
            TextField("Client ID", text: store.binding(\.box.clientID))
                .managed(\.box.clientID)
            SecretField(String(localized: "Client secret"), key: SecretKey.boxClientSecret)
            TextField("Folder ID", text: store.binding(\.box.folderID), prompt: Text("0 = All Files"))
                .managed(\.box.folderID)
            UploadFormatRow(store: store, format: \.box.uploadFormat, quality: \.box.jpegQuality)
            Toggle("Copy the link to the clipboard", isOn: store.binding(\.box.copyLinkToClipboard))
                .managed(\.box.copyLinkToClipboard)
            Toggle("Shared link (anyone with the link), not the private one", isOn: store.binding(\.box.useSharedLink))
                .disabled(!store.value.box.copyLinkToClipboard)
                .managed(\.box.useSharedLink)
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
                .managed(\.dropbox.appKey)
            TextField("Folder", text: store.binding(\.dropbox.folder), prompt: Text("e.g. Screenshots; empty = the app's folder"))
                .managed(\.dropbox.folder)
            UploadFormatRow(store: store, format: \.dropbox.uploadFormat, quality: \.dropbox.jpegQuality)
            Toggle("Copy a shared link to the clipboard", isOn: store.binding(\.dropbox.copyLinkToClipboard))
                .managed(\.dropbox.copyLinkToClipboard)
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
/// Confluence). Takes the settings' key paths, so each control can be locked on its own.
private struct UploadFormatRow: View {
    @ObservedObject var store: SettingsStore
    let format: WritableKeyPath<AppSettings, UploadFormat>
    let quality: WritableKeyPath<AppSettings, Int>
    var reduceColors: WritableKeyPath<AppSettings, Bool>? = nil

    var body: some View {
        Picker("Format", selection: store.binding(format)) {
            ForEach(UploadFormat.allCases, id: \.self) { Text($0.displayName).tag($0) }
        }
        .managed(format)
        if store.value[keyPath: format] == .jpg {
            LabeledContent("JPEG quality") {
                HStack {
                    Slider(value: qualityBinding, in: 10...100, step: 5)
                    Text("\(store.value[keyPath: quality])").monospacedDigit().frame(width: 32, alignment: .trailing)
                }
            }
            .managed(quality)
        }
        if let reduceColors, store.value[keyPath: format] == .png {
            Toggle("Reduce the amount of colours to a maximum of 256", isOn: store.binding(reduceColors))
                .managed(reduceColors)
        }
    }

    private var qualityBinding: Binding<Double> {
        Binding(get: { Double(store.value[keyPath: quality]) },
                set: { value in store.update { $0[keyPath: quality] = Int(value.rounded()) } })
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
            Text(account.message ?? (account.signedIn ? String(localized: "Signed in.") : String(localized: "Not signed in; the first upload asks.")))
                .font(.caption).foregroundStyle(.secondary).lineLimit(2)
            Spacer()
            if account.unreadable {
                Button("Retry") { account.refresh(settings: store.value) }
            } else if account.signedIn {
                Button("Sign Out") { account.signOut(settings: store.value) }
            } else {
                Button("Sign In…") { account.signIn(settings: store.value) }.disabled(account.busy)
            }
        }
        .onAppear { account.refresh(settings: store.value) }
    }
}
