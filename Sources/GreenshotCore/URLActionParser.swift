// Greenshot for Mac (Community) - an unofficial macOS port of Greenshot
// Copyright (C) 2026 Greenshot for Mac (Community) contributors
// Based on Greenshot, Copyright (C) 2007-2026 Thomas Braun, Jens Klingen, Robin Krom
// SPDX-License-Identifier: GPL-3.0-or-later

import Foundation

/// What a link asks for.
public enum URLAction: Equatable, Sendable {
    /// A command with its parameters (`tab`, `section`, `search`, `recipe`, `mode`, ...).
    case command(String, parameters: [String: String])
    /// A sign-in callback (`greenshotmac://oauth/...`) no sign-in waited for: nothing to do.
    case ignored
    /// Not a link of the app, or one that leads nowhere.
    case invalid
}

/// The `greenshotmac:` links (upstream `IpcSecurityDispatcher.ParseUrlSchemeCommand`, docs §2.3). The opaque
/// (`greenshotmac:settings`) and hierarchical (`greenshotmac://settings`) forms are the same; upstream's `greenshot:`
/// links are understood too when given to greenshot-cli (the app registers only `greenshotmac`, so links meant for
/// Greenshot for Windows don't open it).
///
/// | Link | Command |
/// |---|---|
/// | `settings?tab=<tab>&plugin=<name>` | SETTINGS |
/// | `about` | ABOUT |
/// | `self-service?section=<id>` | SELF_SERVICE |
/// | `log?search=<text>` | LOG_VIEWER |
/// | `recipe-editor?recipe=<id>`, `recipe-manager`, `recipe/<id>?<variables>` | RECIPE_EDITOR, RECIPE_MANAGER, RUN_RECIPE |
/// | `capture/<mode>` or `capture?mode=<mode>` (Mac) | CAPTURE |
/// | `clipboard` (Mac) | OPEN_CLIPBOARD |
///
/// Any other path is taken as a command name, so the whitelist of the source decides (`greenshotmac://exit` is refused
/// for links from web pages, accepted from greenshot-cli).
public enum URLActionParser {
    /// The schemes, the Mac's first.
    public static let schemes = ["greenshotmac", "greenshot"]

    /// True for text starting with one of the schemes and a colon, any case.
    public static func isActionLink(_ text: String) -> Bool {
        let lowered = text.lowercased()
        return schemes.contains { lowered.hasPrefix($0 + ":") }
    }

    public static func parse(_ raw: String) -> URLAction {
        var text = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        let lowered = text.lowercased()
        guard let scheme = schemes.first(where: { lowered.hasPrefix($0 + ":") }) else { return .invalid }
        text = String(text.dropFirst(scheme.count + 1))
        if text.hasPrefix("//") { text = String(text.dropFirst(2)) }
        // A "#" is an ordinary character, as upstream reads links (a recipe's Color argument is "#RRGGBB")

        var path = text
        var parameters: [String: String] = [:]
        if let question = text.firstIndex(of: "?") {
            path = String(text[..<question])
            let query = text[text.index(after: question)...]
            for pair in query.split(separator: "&", omittingEmptySubsequences: true) {
                let parts = pair.split(separator: "=", maxSplits: 1, omittingEmptySubsequences: false)
                let key = decode(String(parts[0])).trimmingCharacters(in: .whitespaces)
                let value = parts.count > 1 ? decode(String(parts[1])) : ""
                set(&parameters, key, value)
            }
        }
        path = path.trimmingCharacters(in: CharacterSet(charactersIn: "/"))
        let lowerPath = path.lowercased()

        if lowerPath == "oauth" || lowerPath.hasPrefix("oauth/") { return .ignored }
        // Mac: the recipe and the mode are decoded like the query's values (upstream takes them as written, so
        // "recipe/Save%20to%20Desktop" finds no recipe); the command is chosen on the path as written
        if lowerPath.hasPrefix("recipe/") {
            set(&parameters, "recipe", decode(String(path.dropFirst("recipe/".count))))
            return .command(IPCCommand.runRecipe, parameters: parameters)
        }
        if lowerPath.hasPrefix("capture/") {
            set(&parameters, "mode", decode(String(path.dropFirst("capture/".count))))
            return .command(IPCCommand.capture, parameters: parameters)
        }
        switch lowerPath {
        case "settings": return .command(IPCCommand.settings, parameters: parameters)
        case "about": return .command(IPCCommand.about, parameters: parameters)
        case "self-service": return .command(IPCCommand.selfService, parameters: parameters)
        case "log": return .command(IPCCommand.logViewer, parameters: parameters)
        case "recipe-editor": return .command(IPCCommand.recipeEditor, parameters: parameters)
        case "recipe-manager": return .command(IPCCommand.recipeManager, parameters: parameters)
        case "capture": return .command(IPCCommand.capture, parameters: parameters)
        case "clipboard": return .command(IPCCommand.openClipboard, parameters: parameters)
        default:
            // The commands which carry a link are never its target
            let command = path.uppercased()
            if command.isEmpty || command == IPCCommand.cli || command == IPCCommand.urlScheme { return .invalid }
            return .command(command, parameters: parameters)
        }
    }

    /// Percent-decoding like .NET's `Uri.UnescapeDataString`: `+` stays a plus; a broken escape keeps the text.
    private static func decode(_ text: String) -> String {
        text.removingPercentEncoding ?? text
    }

    /// The last value of a name wins, any case (upstream's case-insensitive dictionary).
    private static func set(_ parameters: inout [String: String], _ key: String, _ value: String) {
        for existing in parameters.keys where existing.caseInsensitiveCompare(key) == .orderedSame {
            parameters.removeValue(forKey: existing)
        }
        parameters[key] = value
    }
}
