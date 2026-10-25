// Greenshot for Mac (Community) - an unofficial macOS port of Greenshot
// Copyright (C) 2026 Greenshot for Mac (Community) contributors
// SPDX-License-Identifier: GPL-3.0-or-later

import AppKit
import GreenshotCore

/// The question before a Jira or Confluence token or password that the Keychain keeps without its server (saved by an
/// older version, or before the URL was entered) goes to the server of the settings: "Send the Jira token or password
/// in the Keychain to this server?" with the URL and the server (address and port) it would go to. Such a token doesn't
/// say which server it was saved for, so the URL of the settings alone doesn't get it (see `AtlassianSecrets`). Don't
/// Allow is the default (Return); Allow reacts only a second after the question shows and not while another program's
/// window covers it (`AutomationCaptureConsent.run`). Allowed, it is kept for that server and isn't asked about again.
/// Only what the user started asks (`AtlassianSecretRequest`, `AtlassianSecretAnswers`): an upload, a capture or recipe
/// started at the computer, a destination the user picked, Test Connection. After Don't Allow, uploads to that server
/// aren't asked again until Greenshot quits. One question at a time: a few more uploads wait for its answer.
@MainActor
enum AtlassianSecretQuestion {
    private static let log = Log("Atlassian")
    private static var answers = AtlassianSecretAnswers()
    private static var asking = false
    /// The uploads waiting for the open question's answer.
    private static var waiting: [CheckedContinuation<Void, Never>] = []
    /// More uploads than this while a question is open aren't sent (with the message): only what the user started gets
    /// here, so a few are plenty (Jira and Confluence as destinations, an editor's upload).
    private static let maxWaiting = 4

    /// A capture or recipe another program or a trigger started found a secret kept without its server: not asked,
    /// the upload fails with this (and, once per server in a session, the message: `notSent`).
    struct NotAllowedYet: LocalizedError {
        let service: AtlassianService

        var errorDescription: String? {
            String(localized: "The \(service.name) token or password in the Keychain isn't allowed for this server yet. If this is your server, allow it with Test Connection in Settings › Destinations; otherwise check the URL there.")
        }
    }

    /// `stored.site` (from `AtlassianSignIn.stored`) with the secret kept without a server, when the user allows it for
    /// the site's server; the site as it is when there is nothing to ask about; nil when the user didn't allow it, now or
    /// earlier in this session (an upload says so with a message, which `settings` filters). Throws `NotAllowedYet` for
    /// `.automation`, after the same message the first time for that server in this session. Throws when the Keychain
    /// can't be read (before the question: nothing is asked then; after the answer: nothing is kept) or can't keep the
    /// allowed secret for the server; the caller shows it.
    static func confirmed(_ stored: AtlassianSecrets.SiteSecret, _ service: AtlassianService, request: AtlassianSecretRequest,
                          settings: AppSettings?) async throws -> AtlassianSite? {
        var stored = stored
        while true {
            switch answers.decide(stored, service: service.name, request: request) {
            case .proceed:
                return stored.site
            case .notAsked:
                log.info("The \(service.name) secret kept without a server wasn't sent: an automation started the upload")
                if let server = stored.site.server, answers.showsNotAskedMessage(service: service.name, server: server) {
                    notSent(service, request: request, settings: settings)
                }
                throw NotAllowedYet(service: service)
            case .notAllowed:
                notSent(service, request: request, settings: settings)
                return nil
            case .ask(let secret):
                guard asking else { return try ask(about: secret, stored.site, service, request: request, settings: settings) }
                guard waiting.count < maxWaiting else {
                    log.warn("The \(service.name) secret kept without a server wasn't sent: too many uploads wait for the question")
                    notSent(service, request: request, settings: settings)
                    return nil
                }
                // One question at a time; its answer may have kept the secret for this server, or not.
                await withCheckedContinuation { waiting.append($0) }
                stored = try AtlassianSecrets(store: Uploads.secrets).site(stored.site, key: service.secretKey)
            }
        }
    }

    private static func ask(about secret: String, _ site: AtlassianSite, _ service: AtlassianService,
                            request: AtlassianSecretRequest, settings: AppSettings?) throws -> AtlassianSite? {
        guard let server = site.server else { return site }
        asking = true
        defer {
            asking = false
            let resumed = waiting
            waiting = []
            resumed.forEach { $0.resume() }
        }
        var said: Bool?
        let answer = try AtlassianSecrets(store: Uploads.secrets).confirmUnbound(service.secretKey, server: server,
                                                                                 known: .unbound(secret)) {
            said = AutomationCaptureConsent.run(makeAlert(service, site: site))
            return said == true
        }
        if let said { answers.answered(allowed: said, service: service.name, server: server) }
        switch answer {
        case .nothingToAsk:
            return site
        case .allowed(let allowed):
            log.info("The \(service.name) secret kept without a server was allowed for \(server.origin)")
            return site.with(user: site.user, secret: allowed)
        case .declined:
            log.info("The \(service.name) secret kept without a server was not allowed for \(server.origin)")
            notSent(service, request: request, settings: settings)
            return nil
        }
    }

    /// An upload not sent (Don't Allow, now or before; started by automation, once per server; too many waiting) says so
    /// and how to allow it, also when automation started it: the message doesn't wait for an answer. Test Connection
    /// says it in its row.
    private static func notSent(_ service: AtlassianService, request: AtlassianSecretRequest, settings: AppSettings?) {
        guard request != .test, settings?.notificationLevel.shows(.warning) ?? true else { return }
        Toast.show(String(localized: "Not sent to \(service.name)"),
                   detail: String(localized: "The token or password in the Keychain isn't allowed for this server yet. If this is your server, allow it with Test Connection in Settings › Destinations; otherwise check the URL there."),
                   kind: .warning, action: { (NSApp.delegate as? AppDelegate)?.showSettings(pane: .destinations) }, mustBeSeen: true)
    }

    /// The question (also for the snapshots).
    static func makeAlert(_ service: AtlassianService, site: AtlassianSite) -> NSAlert {
        let alert = NSAlert()
        alert.alertStyle = .warning
        alert.messageText = String(localized: "Send the \(service.name) token or password in the Keychain to this server?")
        var info = site.baseURL.absoluteString
        if let server = site.server { info += "\n" + String(localized: "Server (address and port): \(server.origin)") }
        info += "\n\n" + String(localized: "It was saved without the server it belongs to, by an older version of Greenshot or before the URL was entered. Allow it only if this is your \(service.name) server: from then on it goes to this server (address and port) only.")
        if site.isUnencrypted {
            info += "\n\n" + String(localized: "This URL starts with http://: the token or password would travel unencrypted. Use https:// if the server offers it.")
        }
        alert.informativeText = info
        alert.addButton(withTitle: String(localized: "Don't Allow"))
        alert.addButton(withTitle: String(localized: "Allow"))
        return alert
    }
}
