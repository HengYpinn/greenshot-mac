// Greenshot for Mac (Community) - an unofficial macOS port of Greenshot
// Copyright (C) 2026 Greenshot for Mac (Community) contributors
// SPDX-License-Identifier: GPL-3.0-or-later

import Foundation

/// Who wants a Jira or Confluence secret kept without its server (`AtlassianSecrets.SiteSecret.unbound`) to go there.
public enum AtlassianSecretRequest: Equatable, Sendable {
    /// Test Connection in Settings › Destinations: it always asks, so an earlier Don't Allow can be changed there.
    case test
    /// An upload the user started: a destination, the menus, the editor, a recipe started at the computer.
    case upload
    /// A recipe step that another program or a trigger started (a command line, a link, an AI tool, the clipboard, a
    /// file, the browser extension): nobody may be at the screen, so it isn't asked; the step fails and says how to
    /// allow the secret.
    case automation

    /// The request of a recipe's upload: started by the user when the capture screen would take input at once
    /// (`OverlayInputArming.startedByUser`, as `ActiveWindowChoice.fallback` decides).
    public init(recipeTrigger triggerType: String?, markedByAutomation: Bool) {
        self = OverlayInputArming.startedByUser(triggerType: triggerType, markedByAutomation: markedByAutomation)
            ? .upload : .automation
    }
}

/// What happens before a Jira or Confluence secret kept without its server goes there, with the user's Don't Allow
/// answers of this session: an upload isn't asked again for the server (address and port) the user didn't allow it
/// for, until the URL's server changes or Greenshot quits; Test Connection asks again.
public struct AtlassianSecretAnswers: Sendable {
    public enum Decision: Equatable, Sendable {
        /// Nothing to ask: the site has its secret, none is kept without a server, or the login still lacks its user
        /// (email or user name), so the secret couldn't be used yet and the setup message says what to enter.
        case proceed
        /// Ask the user about this secret.
        case ask(String)
        /// The user didn't allow it for this server in this session: not sent, not asked again.
        case notAllowed
        /// Started by automation: not asked, the step fails.
        case notAsked
    }

    /// The server (origin) the user didn't allow it for, by service.
    private var declined: [String: String] = [:]

    public init() {}

    /// What to do with `stored` (from `AtlassianSecrets.site(_:key:)`) for `request`.
    public mutating func decide(_ stored: AtlassianSecrets.SiteSecret, service: String,
                                request: AtlassianSecretRequest) -> Decision {
        guard let secret = stored.unbound, stored.site.secret.isEmpty, let server = stored.site.server else { return .proceed }
        guard stored.site.login == .serverToken || !stored.site.user.isEmpty else { return .proceed }
        // Another URL's server: the answer about the old one doesn't count.
        if declined[service] != server.origin { declined[service] = nil }
        switch request {
        case .automation: return .notAsked
        case .upload where declined[service] != nil: return .notAllowed
        case .upload, .test: return .ask(secret)
        }
    }

    /// The user's answer about `service`'s secret for `server`.
    public mutating func answered(allowed: Bool, service: String, server: AtlassianServer) {
        declined[service] = allowed ? nil : server.origin
    }
}
