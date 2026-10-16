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

    /// The arguments with `{0}` replaced by the image file's path. The replacement happens after splitting, so a
    /// path with spaces stays one argument even when `{0}` isn't quoted.
    public static func arguments(_ line: String, file: String) -> [String] {
        split(line).map { $0.replacingOccurrences(of: "{0}", with: file) }
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
