// Greenshot for Mac (Community) - an unofficial macOS port of Greenshot
// Copyright (C) 2026 Greenshot for Mac (Community) contributors
// Based on Greenshot, Copyright (C) 2007-2026 Thomas Braun, Jens Klingen, Robin Krom
// SPDX-License-Identifier: GPL-3.0-or-later
// Owned by MCP after the wave 4 prep.

import Foundation

/// The AI tools settings (Settings › AI Tools): upstream `ICoreConfiguration` `AiTools*` (greenshot.ini `[Core]`).
/// Upstream `AiToolsMcpServerPaths` (Debug builds only) has no counterpart: a development build accepts the greenshot-mcp
/// next to it.
public struct AIToolsSettings: Codable, Equatable, Sendable {
    /// Upstream's password managers plus the Mac's own (Keychain Access, Passwords) and Mac-only ones. Names are matched
    /// without case, spaces or ".app" against the app name, its executable and its bundle identifier.
    public static let defaultExcludedApplications = [
        "KeePass", "KeePassXC", "KeePassium", "MacPass", "Strongbox", "1Password", "Bitwarden", "LastPass", "Dashlane",
        "Enpass", "RoboForm", "NordPass", "ProtonPass", "Keychain Access", "Passwords",
    ]

    /// Let AI tools use Greenshot through greenshot-mcp (upstream `AiToolsEnabled`, opt-in). Off: every greenshot-mcp
    /// request except the version check is refused without asking.
    public var enabled = false
    /// Allowed AI tools may propose new or changed recipes; each is still shown for approval (upstream
    /// `AiToolsAllowRecipeProposals`).
    public var allowRecipeProposals = true
    /// The programs (full executable paths) the user allowed to list windows, take screenshots and run recipes through
    /// greenshot-mcp; asked the first time a program connects (upstream `AiToolsAllowedClients`).
    public var allowedClients: [String] = []
    /// Applications whose windows are never listed or captured for AI tools and are blacked out in what an AI tool's
    /// recipe takes from the screen (upstream `AiToolsExcludedProcesses`).
    public var excludedApplications: [String] = AIToolsSettings.defaultExcludedApplications
    /// Show a notification every time an AI tool takes a screenshot (upstream `AiToolsNotifyOnCapture`).
    public var notifyOnCapture = true

    public init() {}

    enum CodingKeys: String, CodingKey { case enabled, allowRecipeProposals, allowedClients, excludedApplications, notifyOnCapture }

    // Every value falls back to its default, so settings written by another version still load.
    public init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        let d = AIToolsSettings()
        func value<T: Decodable>(_ key: CodingKeys, _ fallback: T) -> T {
            (try? c.decodeIfPresent(T.self, forKey: key)) ?? fallback
        }
        enabled = value(.enabled, d.enabled)
        allowRecipeProposals = value(.allowRecipeProposals, d.allowRecipeProposals)
        allowedClients = value(.allowedClients, d.allowedClients)
        excludedApplications = value(.excludedApplications, d.excludedApplications)
        notifyOnCapture = value(.notifyOnCapture, d.notifyOnCapture)
    }
}
