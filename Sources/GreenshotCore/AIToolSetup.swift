// Greenshot for Mac (Community) - an unofficial macOS port of Greenshot
// Copyright (C) 2026 Greenshot for Mac (Community) contributors
// Based on Greenshot, Copyright (C) 2007-2026 Thomas Braun, Jens Klingen, Robin Krom
// SPDX-License-Identifier: GPL-3.0-or-later

import Foundation

/// How an AI tool is connected to greenshot-mcp (upstream docs/mcp-server.md "Connect an AI tool", with the Mac's paths):
/// Settings › AI Tools copies the command or the configuration for the client the user picks. Nothing is written into
/// another program's configuration.
public enum AIToolSetupClient: String, CaseIterable, Sendable {
    case claudeCode, claudeDesktop, cursor, vsCode, geminiCLI, codex, windsurf, antigravity

    public var name: String {
        switch self {
        case .claudeCode: return "Claude Code"
        case .claudeDesktop: return "Claude Desktop"
        case .cursor: return "Cursor"
        case .vsCode: return "VS Code"
        case .geminiCLI: return "Gemini CLI"
        case .codex: return "OpenAI Codex"
        case .windsurf: return "Windsurf"
        case .antigravity: return "Google Antigravity"
        }
    }

    /// The Terminal command, or the JSON to add to the configuration file.
    public func snippet(serverPath path: String) -> String {
        let command = JSONValue.string(path).serialized(indented: false)
        switch self {
        case .claudeCode: return "claude mcp add --scope user greenshot -- \(Self.shellQuoted(path))"
        case .geminiCLI: return "gemini mcp add --scope user greenshot \(Self.shellQuoted(path))"
        case .codex: return "codex mcp add greenshot -- \(Self.shellQuoted(path))"
        case .vsCode:
            return "{\n  \"servers\": {\n    \"greenshot\": {\n      \"type\": \"stdio\",\n      \"command\": \(command)\n    }\n  }\n}"
        case .antigravity:
            return "{\n  \"mcpServers\": {\n    \"greenshot\": {\n      \"command\": \(command),\n      \"args\": []\n    }\n  }\n}"
        case .claudeDesktop, .cursor, .windsurf:
            return "{\n  \"mcpServers\": {\n    \"greenshot\": { \"command\": \(command) }\n  }\n}"
        }
    }

    /// Where it goes.
    public var instructions: String {
        switch self {
        case .claudeCode: return String(localized: "Run it in Terminal (--scope user: in all projects). Check it with claude mcp list or /mcp.")
        case .claudeDesktop: return String(localized: "Settings › Developer › Edit Config opens ~/Library/Application Support/Claude/claude_desktop_config.json; add the server and restart Claude.")
        case .cursor: return String(localized: "In ~/.cursor/mcp.json (all projects) or .cursor/mcp.json (one project).")
        case .vsCode: return String(localized: "Run \"MCP: Add Server\" (Command (stdio)), or put it in .vscode/mcp.json of the workspace.")
        case .geminiCLI: return String(localized: "Run it in Terminal, or add the mcpServers entry to ~/.gemini/settings.json. Check it with /mcp.")
        case .codex: return String(localized: "Run it in Terminal, or add [mcp_servers.greenshot] with command = the path to ~/.codex/config.toml.")
        case .windsurf: return String(localized: "In ~/.codeium/windsurf/mcp_config.json.")
        case .antigravity: return String(localized: "In ~/.gemini/config/mcp_config.json (… › MCP Servers › Manage MCP Servers › View raw config), then Refresh.")
        }
    }

    /// A path for a POSIX shell: in single quotes, a single quote as '\''.
    public static func shellQuoted(_ text: String) -> String {
        "'" + text.replacingOccurrences(of: "'", with: "'\\''") + "'"
    }
}

/// A recipe from a file in Settings › AI Tools › Approved recipes (upstream `ApprovedRecipeViewModel`): its approval in a
/// line, and whether it needs the user's attention.
public struct AIToolApprovedRecipe: Equatable, Sendable {
    public var recipeId: String
    /// An automatic step: its approval is the extension store's (`extensionDetails`, `reviewExtensionApproval`, …).
    public var isExtension: Bool
    public var title: String
    public var subtitle: String
    /// Not approved, changed since its approval, or triggers left off.
    public var needsAttention: Bool

    public init(recipeId: String, name: String, isExtension: Bool, details: RecipeDetails?) {
        self.recipeId = recipeId
        self.isExtension = isExtension
        var parts: [String] = []
        if let approvedAt = details?.approvedAt {
            parts.append((details?.isApprovalCurrent ?? false) ? String(localized: "approved \(Self.day(approvedAt))")
                                                                : String(localized: "changed since its approval"))
        } else {
            parts.append(String(localized: "not approved"))
        }
        if let proposedBy = details?.proposedBy {
            parts.append(String(localized: "written by \(AIToolText.displayed(proposedBy, limit: 80))"))
        }
        // The label of a trigger made in Core's recipe texts (English by design), not a text of this list
        let off = details?.triggers.filter { $0.label.hasSuffix("(off, not approved)") }.count ?? 0
        if off == 1 {
            parts.append(String(localized: "1 trigger off"))
        } else if off > 1 {
            parts.append(String(localized: "\(off) triggers off"))
        }
        title = isExtension ? String(localized: "Automatic step: \(name)") : name
        subtitle = parts.joined(separator: " · ")
        needsAttention = details?.approvedAt == nil || !(details?.isApprovalCurrent ?? false) || off > 0
    }

    /// "2026-10-17", like upstream's `yyyy-MM-dd`.
    static func day(_ date: Date) -> String {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.dateFormat = "yyyy-MM-dd"
        return formatter.string(from: date)
    }
}
