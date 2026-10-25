// Greenshot for Mac (Community) - an unofficial macOS port of Greenshot
// Copyright (C) 2026 Greenshot for Mac (Community) contributors
// SPDX-License-Identifier: GPL-3.0-or-later

import AppKit
import GreenshotCore

/// The question before a Jira or Confluence token or password that the Keychain keeps without its server (saved by an
/// older version, or before the URL was entered) goes to the server of the settings: "Send the Jira token or password
/// in the Keychain to this server?" with the URL. Such a token doesn't say which server it was saved for, so the URL of
/// the settings alone doesn't get it (see `AtlassianSecrets`). Don't Allow is the default (Return); Allow reacts only a
/// second after the question shows and not while another program's window covers it (`AutomationCaptureConsent.run`).
/// Allowed, it is kept for that server and isn't asked about again.
@MainActor
enum AtlassianSecretQuestion {
    private static let log = Log("Atlassian")

    /// `site` (from `AtlassianSignIn.site`) with the secret kept without a server, when the user allows it for the
    /// site's host; `site` as it is when it has a secret or there is nothing to ask about; nil when the user didn't
    /// allow it. Throws when the Keychain can't be read (nothing is asked then) or can't keep the allowed secret for the
    /// host; the caller shows it.
    static func confirmed(_ site: AtlassianSite, _ service: AtlassianService) throws -> AtlassianSite? {
        guard site.secret.isEmpty, let host = site.baseURL.host else { return site }
        let answer = try AtlassianSecrets(store: Uploads.secrets).confirmUnbound(service.secretKey, host: host) {
            AutomationCaptureConsent.run(makeAlert(service, site: site))
        }
        switch answer {
        case .nothingToAsk:
            return site
        case .allowed(let secret):
            log.info("The \(service.name) secret kept without a server was allowed for \(host)")
            return site.with(user: site.user, secret: secret)
        case .declined:
            log.info("The \(service.name) secret kept without a server was not allowed for \(host)")
            return nil
        }
    }

    /// The question (also for the snapshots).
    static func makeAlert(_ service: AtlassianService, site: AtlassianSite) -> NSAlert {
        let alert = NSAlert()
        alert.alertStyle = .warning
        alert.messageText = String(localized: "Send the \(service.name) token or password in the Keychain to this server?")
        var info = site.baseURL.absoluteString + "\n\n"
            + String(localized: "It was saved without the server it belongs to, by an older version of Greenshot or before the URL was entered. Allow it only if this is your \(service.name) server: from then on it goes to this server only.")
        if site.isUnencrypted { info += "\n\n" + String(localized: "This address starts with http://: the password travels unencrypted.") }
        alert.informativeText = info
        alert.addButton(withTitle: String(localized: "Don't Allow"))
        alert.addButton(withTitle: String(localized: "Allow"))
        return alert
    }
}
