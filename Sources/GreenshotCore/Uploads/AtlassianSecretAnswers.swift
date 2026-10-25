// Greenshot for Mac (Community) - an unofficial macOS port of Greenshot
// Copyright (C) 2026 Greenshot for Mac (Community) contributors
// SPDX-License-Identifier: GPL-3.0-or-later

import Foundation

/// Who wants a Jira or Confluence secret kept without its server (`AtlassianSecrets.SiteSecret.unbound`) to go there.
public enum AtlassianSecretRequest: Equatable, Sendable {
    /// Test Connection in Settings › Destinations: it always asks, so an earlier Don't Allow can be changed there.
    case test
    /// An upload the user started: a destination, the menus, the editor, a capture or recipe started at the computer,
    /// or a destination the user picked in the destination menu or a recipe's flyout.
    case upload
    /// A capture or recipe that another program or a trigger started (a command line, a link, AppleScript, Shortcuts,
    /// an AI tool, the clipboard, a file, the browser extension), for a destination the user didn't pick: it isn't
    /// asked about, as nobody may be at the screen; the upload fails, and the recipe log (every time) and a message
    /// (once per server, `showsNotAskedMessage`) say how to allow the secret.
    case automation

    /// The request of a capture that didn't go through a recipe: `.automation` when automation started it.
    public init(capturedByAutomation byAutomation: Bool) {
        self = byAutomation ? .automation : .upload
    }

    /// The request of a recipe's upload: started by the user when the capture screen would take input at once
    /// (`OverlayInputArming.startedByUser`, as `ActiveWindowChoice.fallback` decides), or when the user picked the
    /// destination (the destination menu, the flyout) whoever started the recipe.
    public init(recipeTrigger triggerType: String?, markedByAutomation: Bool, pickedByUser: Bool = false) {
        let byUser = pickedByUser || OverlayInputArming.startedByUser(triggerType: triggerType, markedByAutomation: markedByAutomation)
        self = byUser ? .upload : .automation
    }
}

/// What happens before a Jira or Confluence secret kept without its server goes there, with the user's Don't Allow
/// answers of this session: an upload isn't asked again for a server (address and port) the user didn't allow it for,
/// until Greenshot quits; Test Connection asks again, and its Allow counts.
public struct AtlassianSecretAnswers: Sendable {
    public enum Decision: Equatable, Sendable {
        /// Nothing to ask: the site has its secret, none is kept without a server, or the login still lacks its user
        /// (email or user name), so the secret couldn't be used yet (the setup message or the login dialog asks for it).
        case proceed
        /// Ask the user about this secret.
        case ask(String)
        /// The user didn't allow it for this server in this session: not sent, not asked again.
        case notAllowed
        /// Started by automation: not asked, the upload fails.
        case notAsked
    }

    /// The servers (origins) the user didn't allow it for, by service.
    private var declined: [String: Set<String>] = [:]
    /// The servers (origins) whose message an upload that automation started showed, by service.
    private var toldAutomation: [String: Set<String>] = [:]

    public init() {}

    /// What to do with `stored` (from `AtlassianSecrets.site(_:key:)`) for `request`.
    public func decide(_ stored: AtlassianSecrets.SiteSecret, service: String, request: AtlassianSecretRequest) -> Decision {
        guard let secret = stored.unbound, stored.site.secret.isEmpty, let server = stored.site.server else { return .proceed }
        guard stored.site.login == .serverToken || !stored.site.user.isEmpty else { return .proceed }
        switch request {
        case .automation: return .notAsked
        case .upload where declined[service, default: []].contains(server.origin): return .notAllowed
        case .upload, .test: return .ask(secret)
        }
    }

    /// Whether an upload that automation started and that wasn't asked about (`.notAsked`) shows the message: once per
    /// service and server in a session, so a recipe that runs at every copy doesn't show it every time. Its recipe log,
    /// the export's outcome and the reply of greenshot-cli or the AI tool say it each time; an upload the user started
    /// after Don't Allow shows it each time.
    public mutating func showsNotAskedMessage(service: String, server: AtlassianServer) -> Bool {
        toldAutomation[service, default: []].insert(server.origin).inserted
    }

    /// The user's answer about `service`'s secret for `server`.
    public mutating func answered(allowed: Bool, service: String, server: AtlassianServer) {
        if allowed {
            declined[service, default: []].remove(server.origin)
        } else {
            declined[service, default: []].insert(server.origin)
        }
    }
}
