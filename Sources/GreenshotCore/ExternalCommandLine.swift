// Greenshot for Mac (Community) - an unofficial macOS port of Greenshot
// Copyright (C) 2026 Greenshot for Mac (Community) contributors
// Based on Greenshot, Copyright (C) 2007-2026 Thomas Braun, Jens Klingen, Robin Krom
// SPDX-License-Identifier: GPL-3.0-or-later

import Foundation

/// The command line of an external command: port of the argument handling and URI parsing in upstream
/// `Greenshot.Plugin.ExternalCommand/Destinations/ExternalCommandDestination.cs`. Windows passes one argument
/// string with `{0}` formatted in; the Mac starts a process with separate arguments, so the line is split like a
/// shell would: spaces separate, double or single quotes group, a backslash escapes the next character.
public enum ExternalCommandLine {
    public static func split(_ line: String) -> [String] {
        var result: [String] = []
        var current = ""
        var inToken = false
        var quote: Character?
        var escaped = false
        for char in line {
            if escaped {
                current.append(char)
                escaped = false
                continue
            }
            if let open = quote {
                if char == open {
                    quote = nil
                } else if char == "\\" && open == "\"" {
                    escaped = true
                } else {
                    current.append(char)
                }
                continue
            }
            switch char {
            case "\"", "'":
                quote = char
                inToken = true
            case "\\":
                escaped = true
                inToken = true
            case " ", "\t", "\n":
                if inToken {
                    result.append(current)
                    current = ""
                    inToken = false
                }
            default:
                current.append(char)
                inToken = true
            }
        }
        if inToken { result.append(current) }
        return result
    }

    /// The arguments with `{0}` replaced by the image file's path, after `fill` filled the pattern variables of each
    /// (upstream `FillVariables` + `FillCmdVariables`). Both happen after splitting, so a path or a title with spaces
    /// stays one argument even when it isn't quoted.
    public static func arguments(_ line: String, file: String, fill: (String) -> String = { $0 }) -> [String] {
        split(line).map { fill($0).replacingOccurrences(of: "{0}", with: file) }
    }

    /// How a command's program is started.
    public enum Program: Equatable, Sendable {
        /// An app bundle (`….app`): `open -a` opens the file with it.
        case application(String)
        /// A path to an executable file.
        case executable(String)
        /// A bare name, looked up in the PATH by `/usr/bin/env`.
        case searchPath(String)
    }

    /// The program of a command: its pattern variables filled (`fill`) and `~` expanded. Nil when it is empty.
    public static func program(_ command: String, fill: (String) -> String = { $0 }) -> Program? {
        let filled = fill(command.trimmingCharacters(in: .whitespaces)).trimmingCharacters(in: .whitespaces)
        let path = (filled as NSString).expandingTildeInPath
        // A program name that starts with "-" would be read as an option (e.g. by /usr/bin/env), for instance when a
        // window title fills it.
        guard !path.isEmpty, !path.hasPrefix("-") else { return nil }
        let lower = path.lowercased()
        if lower.hasSuffix(".app") || lower.hasSuffix(".app/") { return .application(path) }
        if path.contains("/") { return .executable(path) }
        return .searchPath(path)
    }

    /// Whether the program is there (upstream `ExternalCommandPlugin.IsCommandValid` checks that the file exists).
    public static func isAvailable(_ program: Program, fileExists: (String) -> Bool, isExecutable: (String) -> Bool,
                                   searchPath: [String]) -> Bool {
        switch program {
        case .application(let path): return fileExists(path)
        case .executable(let path): return isExecutable(path)
        case .searchPath(let name):
            return searchPath.contains { folder in isExecutable((folder as NSString).appendingPathComponent(name)) }
        }
    }

    /// The application named after `-a` in the arguments (`open -a Preview "{0}"` → "Preview"), for the command's icon.
    public static func applicationName(inArguments line: String) -> String? {
        let tokens = split(line)
        guard let index = tokens.firstIndex(of: "-a"), index + 1 < tokens.count else { return nil }
        let name = tokens[index + 1].trimmingCharacters(in: .whitespaces)
        return name.isEmpty ? nil : name
    }

    /// Whether another command already has the name, ignoring case and surrounding spaces (upstream
    /// `tooltip_duplicate_name`). `id` is the command being edited, nil for a new one.
    public static func isDuplicate(name: String, of id: UUID?, among commands: [ExternalCommand]) -> Bool {
        let wanted = name.trimmingCharacters(in: .whitespaces).lowercased()
        guard !wanted.isEmpty else { return false }
        return commands.contains { $0.id != id && $0.name.trimmingCharacters(in: .whitespaces).lowercased() == wanted }
    }

    private static let urlRegex = try! NSRegularExpression(pattern: #"[A-Za-z][A-Za-z0-9+.\-]{2,9}://[^\s"'<>]+"#)

    /// The first URL in a command's output (upstream `URI_REGEXP`), without trailing punctuation.
    public static func firstURL(in output: String) -> String? {
        let ns = output as NSString
        guard let match = urlRegex.firstMatch(in: output, range: NSRange(location: 0, length: ns.length)) else { return nil }
        var url = ns.substring(with: match.range)
        while let last = url.last, ".,;:!?)]}".contains(last) { url.removeLast() }
        return url
    }
}
