// Greenshot for Mac (Community) - an unofficial macOS port of Greenshot
// Copyright (C) 2026 Greenshot for Mac (Community) contributors
// Based on Greenshot, Copyright (C) 2007-2026 Thomas Braun, Jens Klingen, Robin Krom
// SPDX-License-Identifier: GPL-3.0-or-later
// Owned by MCP after the wave 4 prep.

import AppKit
import GreenshotCore
import SwiftUI

extension Snapshots {
    /// Renders of Settings › AI Tools and the consent panel.
    static func renderAIToolsExtras(to folder: URL, sample: CGImage, settings: SettingsStore) throws {
        // Switched on, with programs, a refused one and recipes (sample values, no running app)
        let on = aiToolsStore("on", forced: [:])
        on.update { settings in
            settings.aiTools.enabled = true
            settings.aiTools.allowedClients = ["/Applications/Claude.app/Contents/MacOS/Claude | Team ID: Q6L2SF6YDW",
                                               "/opt/homebrew/bin/node | script: /opt/homebrew/lib/node_modules/@google/gemini-cli/dist/index.js"]
        }
        let approved = [
            AIToolApprovedRecipe(recipeId: "ai_region_to_jira", name: "Region to Jira", isExtension: false, details: sampleDetails(current: true)),
            AIToolApprovedRecipe(recipeId: "watermark", name: "Watermark", isExtension: true, details: sampleDetails(current: false)),
        ]
        let cursor = "/Applications/Cursor.app/Contents/Frameworks/Cursor Helper (Plugin).app/Contents/MacOS/Cursor Helper (Plugin)"
        let refused = AIToolClient(path: cursor, displayName: "Cursor (Cursor Helper (Plugin))",
                                   identity: AIToolIdentity(executable: cursor, script: "/Users/me/.cursor/extensions/mcp/server.js",
                                                            notes: ["as Node.js (ELECTRON_RUN_AS_NODE)"]))
        let model = AIToolsTabModel(serverPath: AIToolsTabModel.snapshotServerPath, denied: [refused], approved: approved)
        try write(tab(store: on, model: model, height: 1880), to: folder.appendingPathComponent("ai-tools-tab.png"))

        // As installed, the switch locked off by an administrator
        let off = aiToolsStore("off", forced: ["Greenshot.aiTools.enabled": false])
        try write(tab(store: off, model: AIToolsTabModel(serverPath: "", denied: [], approved: []), height: 1240),
                  to: folder.appendingPathComponent("ai-tools-tab-off.png"))

        // The question the first time a program connects: buttons still disarmed, then armed
        let client = AIToolClient(path: "/Applications/Claude.app/Contents/MacOS/Claude", displayName: "Claude",
                                  signer: "Developer ID Application: Anthropic PBC (Q6L2SF6YDW)")
        for (name, armed) in [("ai-tools-consent.png", false), ("ai-tools-consent-armed.png", true)] {
            let panel = AIToolsConsentPanel.makePanel(client: client, armed: armed) { _ in }
            if let content = panel.contentView {
                content.appearance = NSAppearance(named: .aqua)
                try write(capture(content), to: folder.appendingPathComponent(name))
            }
        }
        for name in ["on", "off"] { UserDefaults.standard.removePersistentDomain(forName: suiteName(name)) }
    }

    private static func suiteName(_ name: String) -> String { "greenshot-mac-snapshots-aitools-\(name)" }

    /// Settings on an empty suite of the user defaults, with these values forced by an administrator.
    private static func aiToolsStore(_ name: String, forced: [String: Any]) -> SettingsStore {
        let suite = suiteName(name)
        let defaults = UserDefaults(suiteName: suite)!
        defaults.removePersistentDomain(forName: suite)
        return SettingsStore(defaults: defaults, managed: ManagedValues(forced: forced))
    }

    private static func tab(store: SettingsStore, model: AIToolsTabModel, height: CGFloat) -> NSBitmapImageRep? {
        let root = AIToolsSettingsTab(store: store, model: model)
            .environment(\.managedPolicy, store.policy)
            .frame(width: 760, height: height)
        let hosting = NSHostingView(rootView: root)
        hosting.frame = NSRect(x: 0, y: 0, width: 760, height: height)
        hosting.appearance = NSAppearance(named: .aqua)
        let window = NSWindow(contentRect: hosting.frame, styleMask: [.titled], backing: .buffered, defer: false)
        window.contentView = hosting
        hosting.layoutSubtreeIfNeeded()
        return capture(hosting)
    }

    private static func sampleDetails(current: Bool) -> RecipeDetails {
        var details = RecipeDetails()
        details.approvedAt = Date(timeIntervalSince1970: 1_792_238_400)
        details.isApprovalCurrent = current
        details.proposedBy = current ? "Claude" : nil
        details.triggers = [RecipeTriggerDescription(key: "0:Hotkey", label: "Hotkey Ctrl + Shift + J (on)"),
                            RecipeTriggerDescription(key: "1:AiTool", label: "AI tool region_to_jira (off, not approved)")]
        return details
    }
}
