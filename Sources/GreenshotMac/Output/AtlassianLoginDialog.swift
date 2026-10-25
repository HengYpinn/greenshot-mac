// Greenshot for Mac (Community) - an unofficial macOS port of Greenshot
// Copyright (C) 2026 Greenshot for Mac (Community) contributors
// Based on Greenshot, Copyright (C) 2007-2026 Thomas Braun, Jens Klingen, Robin Krom
// SPDX-License-Identifier: GPL-3.0-or-later

import AppKit
import GreenshotCore

private let log = Log("Atlassian")

/// Jira or Confluence: which settings, which Keychain entry.
enum AtlassianService {
    case jira, confluence

    var name: String { self == .jira ? "Jira" : "Confluence" }

    var secretKey: String { self == .jira ? SecretKey.jiraToken : SecretKey.confluenceToken }

    func login(_ settings: AppSettings) -> AtlassianLogin {
        self == .jira ? settings.jira.login : settings.confluence.login
    }

    func url(_ settings: AppSettings) -> String {
        self == .jira ? settings.jira.url : settings.confluence.url
    }

    func user(_ settings: AppSettings) -> String {
        self == .jira ? settings.jira.email : settings.confluence.email
    }
}

/// Signing in to a Server / Data Center site with a user name and password: port of upstream's `LoginAsync`
/// (`JiraConnector.cs`, `Confluence.cs`), which shows Windows' credentials dialog until the login works or is cancelled.
/// A password not kept in the Keychain lives here until Greenshot quits, like upstream's logged-in client.
@MainActor
enum AtlassianSignIn {
    /// Passwords typed without "Remember in Keychain", by service, URL and user.
    private static var sessionPasswords: [String: String] = [:]
    /// The sites whose login was checked in this session (upstream logs in once per session), with their password.
    private static var verified = VerifiedLogins()

    private static func key(_ service: AtlassianService, _ site: AtlassianSite) -> String {
        "\(service.name)|\(site.baseURL.absoluteString)|\(site.user)"
    }

    /// The site of the settings with its secret: a password typed in this session, else the one the Keychain keeps for
    /// the site's server (address and port), none otherwise (`AtlassianSecrets.site(_:key:)`). A Keychain that can't be
    /// read (locked, or its prompt cancelled) throws: an empty secret would ask for the token or password again.
    static func site(_ service: AtlassianService, settings: AppSettings) throws -> AtlassianSite? {
        try stored(service, settings: settings)?.site
    }

    /// `site(_:settings:)` with the secret the Keychain keeps without a server, if any: it goes to the site only when the
    /// user allows it (`AtlassianSecretQuestion`).
    static func stored(_ service: AtlassianService, settings: AppSettings) throws -> AtlassianSecrets.SiteSecret? {
        let login = service.login(settings)
        guard let bare = AtlassianSite(url: service.url(settings), login: login, user: service.user(settings), secret: "") else {
            return nil
        }
        if login == .serverPassword, let typed = sessionPasswords[key(service, bare)] {
            return AtlassianSecrets.SiteSecret(site: bare.with(user: bare.user, secret: typed))
        }
        return try AtlassianSecrets(store: Uploads.secrets).site(bare, key: service.secretKey)
    }

    /// The site ready for an upload, nil when the user cancelled the login, didn't allow a token or password kept
    /// without its server (`AtlassianSecretQuestion`, asked only for what the user started: `request`), or the setup is
    /// missing (explained then). A password login is checked once per session; a missing or wrong password brings up the
    /// login dialog. Throws, after showing it, when the Keychain can't be read or can't keep an allowed token for the
    /// server: the upload failed (not declined, so a recipe flow records it), as Box and Dropbox say then. Throws
    /// `AtlassianSecretQuestion.NotAllowedYet` without showing it for `.automation` (nobody may be at the screen: the
    /// recipe step records and logs it).
    static func ready(_ service: AtlassianService, settings: SettingsStore,
                      request: AtlassianSecretRequest = .upload) async throws -> AtlassianSite? {
        Uploads.applyCertificateExceptions(settings.value)
        let configured: AtlassianSecrets.SiteSecret?
        do {
            configured = try stored(service, settings: settings.value)
        } catch {
            throw failed(error, service)
        }
        guard let configured else {
            Uploads.explainMissingSetup(service.name, detail: String(localized: "Enter the \(service.name) URL in Settings › Destinations."))
            return nil
        }
        // A token or password kept without its server goes to this one only when the user allows it.
        var site: AtlassianSite
        do {
            guard let confirmed = try await AtlassianSecretQuestion.confirmed(configured, service, request: request,
                                                                              settings: settings.value) else { return nil }
            site = confirmed
        } catch let error as AtlassianSecretQuestion.NotAllowedYet {
            throw error
        } catch {
            throw failed(error, service)
        }
        guard site.login == .serverPassword else {
            guard site.hasCredentials else {
                let detail = site.login == .serverToken
                    ? String(localized: "Enter a personal access token for \(service.name) in Settings › Destinations.")
                    : String(localized: "Enter your email and an API token for \(service.name) in Settings › Destinations.")
                Uploads.explainMissingSetup(service.name, detail: detail)
                return nil
            }
            return site
        }
        var problem: String?
        if site.hasCredentials {
            if verified.contains(site, service: service.name) { return site }
            switch await check(site, service: service) {
            case .success: return markVerified(site, service)
            case .failure(let error):
                guard isLoginError(error) else {
                    ErrorPresenter.show(error, title: String(localized: "\(service.name) could not be reached"))
                    return nil
                }
                problem = error.localizedDescription
            }
        }
        while true {
            let dialog = AtlassianLoginDialog(service: service, site: site, problem: problem)
            guard let answer = dialog.run() else { return nil }
            let candidate = site.with(user: answer.user, secret: answer.password)
            switch await check(candidate, service: service) {
            case .success:
                remember(candidate, service: service, inKeychain: answer.remember, settings: settings)
                return markVerified(candidate, service)
            case .failure(let error):
                guard isLoginError(error) else {
                    ErrorPresenter.show(error, title: String(localized: "\(service.name) could not be reached"))
                    return nil
                }
                site = candidate.with(user: candidate.user, secret: "")
                problem = error.localizedDescription
            }
        }
    }

    /// Shows `error` (from the Keychain) as the failed upload; returned to be thrown.
    private static func failed(_ error: Error, _ service: AtlassianService) -> Error {
        ErrorPresenter.show(error, title: service == .jira ? String(localized: "The upload to Jira failed")
                                : String(localized: "The upload to Confluence failed"))
        return error
    }

    /// Who the credentials belong to (upstream checks the login with the current user).
    static func check(_ site: AtlassianSite, service: AtlassianService) async -> Result<String, Error> {
        await Uploads.testAtlassian(site, confluence: service == .confluence)
    }

    /// 401 and 403 are a wrong user name or password (or a CAPTCHA the server wants solved in the browser first).
    static func isLoginError(_ error: Error) -> Bool {
        VerifiedLogins.isLoginError(error)
    }

    private static func markVerified(_ site: AtlassianSite, _ service: AtlassianService) -> AtlassianSite {
        verified.insert(site, service: service.name)
        return site
    }

    /// An upload the server refused with 401 or 403: the password may have changed on the server since it was checked,
    /// so the next upload checks it again and brings up the login dialog when it is wrong.
    static func uploadFailed(_ error: Error, _ service: AtlassianService, _ site: AtlassianSite) {
        verified.uploadFailed(error, site: site, service: service.name)
    }

    private static func remember(_ site: AtlassianSite, service: AtlassianService, inKeychain: Bool, settings: SettingsStore) {
        settings.update { s in
            if service == .jira { s.jira.email = site.user } else { s.confluence.email = site.user }
        }
        if inKeychain {
            do {
                try AtlassianSecrets(store: Uploads.secrets).setSecret(site.secret, for: service.secretKey, server: site.server)
                return
            } catch {
                // Said, not only logged: "Remember in Keychain" was on, and the next start would ask again.
                log.error("The \(service.name) password could not be kept in the Keychain", error: error)
                ErrorPresenter.show(message: String(localized: "The \(service.name) password could not be kept in the Keychain"),
                                    detail: error.localizedDescription + "\n\n"
                                        + String(localized: "Greenshot uses it until it quits. To keep it, enter it in Settings › Destinations."))
            }
        }
        sessionPasswords[key(service, site)] = site.secret
    }
}

/// "Please enter your Jira login data" (upstream `login_title`): user name, password and "Remember in Keychain", with
/// the problem of the last try (upstream `login_error`).
@MainActor
final class AtlassianLoginDialog {
    struct Answer {
        var user: String
        var password: String
        var remember: Bool
    }

    let alert = NSAlert()
    private let userField = NSTextField()
    private let passwordField = NSSecureTextField()
    private let rememberBox = NSButton(checkboxWithTitle: String(localized: "Remember in Keychain"), target: nil, action: nil)

    init(service: AtlassianService, site: AtlassianSite, problem: String?) {
        // One text per service, like upstream's `login_title` of each plug-in.
        alert.messageText = service == .jira ? String(localized: "Please enter your Jira login data")
            : String(localized: "Please enter your Confluence login data")
        var info = site.baseURL.absoluteString
        if site.isUnencrypted { info += "\n\n" + String(localized: "This address starts with http://: the password travels unencrypted.") }
        if let problem { info += "\n\n" + String(localized: "There was a problem during the login: \(problem)") }
        alert.informativeText = info
        alert.alertStyle = problem == nil ? .informational : .warning
        alert.addButton(withTitle: String(localized: "Log In"))
        alert.addButton(withTitle: String(localized: "Cancel"))
        userField.stringValue = site.user
        userField.placeholderString = String(localized: "User name")
        passwordField.placeholderString = String(localized: "Password")
        for field in [userField, passwordField] as [NSTextField] {
            field.translatesAutoresizingMaskIntoConstraints = false
            field.widthAnchor.constraint(equalToConstant: 220).isActive = true
        }
        rememberBox.state = .off
        let grid = NSGridView(views: [
            [NSTextField(labelWithString: String(localized: "User name:")), userField],
            [NSTextField(labelWithString: String(localized: "Password:")), passwordField],
            [NSView(), rememberBox],
        ])
        grid.column(at: 0).xPlacement = .trailing
        grid.rowSpacing = 8
        grid.columnSpacing = 8
        grid.frame = NSRect(origin: .zero, size: grid.fittingSize)
        alert.accessoryView = grid
        alert.window.initialFirstResponder = site.user.isEmpty ? userField : passwordField
    }

    /// nil when cancelled.
    func run() -> Answer? {
        NSApp.activate()
        guard alert.runModal() == .alertFirstButtonReturn else { return nil }
        return Answer(user: userField.stringValue.trimmingCharacters(in: .whitespaces), password: passwordField.stringValue,
                      remember: rememberBox.state == .on)
    }
}
