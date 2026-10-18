// Greenshot for Mac (Community) - an unofficial macOS port of Greenshot
// Copyright (C) 2026 Greenshot for Mac (Community) contributors
// Based on Greenshot, Copyright (C) 2007-2026 Thomas Braun, Jens Klingen, Robin Krom
// SPDX-License-Identifier: GPL-3.0-or-later

import Foundation

/// What of an external command's output goes into the log (upstream `ExternalCommandDestination.RunCommandAsync`, which
/// logs the errors always and the output with `ShowStandardOutputInLog`). The Mac is stricter, because the log goes to
/// the unified log and into bug reports and a command like `curl -v` writes its `Authorization` header to its errors:
/// - the output only with "Write the output to the log",
/// - the errors only then or when the command failed,
/// - both at most `maxLength` characters (like the error dialog), with credential-looking values replaced by `***`.
public enum ExternalCommandLog {
    /// The most characters of the output or the errors that are logged.
    public static let maxLength = 600

    public enum Level: Equatable, Sendable {
        case info, warning
    }

    public struct Entry: Equatable, Sendable {
        public var level: Level
        public var message: String
    }

    /// The log entries for a command `name` that ended with `status` (nil: unknown, it ran in the background and its end
    /// wasn't waited for). `showOutput` is the command's "Write the output to the log".
    public static func entries(name: String, output: String, errors: String, status: Int32?, showOutput: Bool) -> [Entry] {
        var result: [Entry] = []
        let shownOutput = output.trimmingCharacters(in: .whitespacesAndNewlines)
        if showOutput, !shownOutput.isEmpty {
            result.append(Entry(level: .info, message: "\(name) wrote:\n\(shown(shownOutput))"))
        }
        let shownErrors = errors.trimmingCharacters(in: .whitespacesAndNewlines)
        let failed = status.map { $0 != 0 } ?? false
        if !shownErrors.isEmpty, showOutput || failed {
            result.append(Entry(level: failed ? .warning : .info, message: "\(name) wrote errors:\n\(shown(shownErrors))"))
        }
        return result
    }

    /// `text` with credentials replaced, then cut after `maxLength` characters.
    public static func shown(_ text: String) -> String {
        let clean = redacted(text)
        guard clean.count > maxLength else { return clean }
        return String(clean.prefix(maxLength)) + "…"
    }

    /// Values that look like credentials replaced by `***` (case-insensitive): the rest of an `Authorization:` line, the
    /// word after `Bearer`, and the value of `token=`, `access_token=`, `password=`, `apikey=` and their relatives (also
    /// with `:` and quotes, as in JSON).
    public static func redacted(_ text: String) -> String {
        var result = text
        for (pattern, template) in rules {
            let range = NSRange(result.startIndex..., in: result)
            result = pattern.stringByReplacingMatches(in: result, range: range, withTemplate: template)
        }
        return result
    }

    private static let rules: [(NSRegularExpression, String)] = [
        // "Authorization: Basic …", "> authorization: Bearer …": the whole value.
        (regex(#"(authorization\s*:\s*)[^\r\n]+"#), "$1***"),
        // A bearer token anywhere else.
        (regex(#"(bearer\s+)[A-Za-z0-9\-._~+/]+=*"#), "$1***"),
        // key=value, key: value, "key": "value".
        (regex(#"\b((?:access_token|refresh_token|id_token|client_secret|api_key|apikey|api-key|token|password|passwd|pwd|secret)"?\s*[=:]\s*"?)[^\s"&,;]+"#),
         "$1***"),
    ]

    private static func regex(_ pattern: String) -> NSRegularExpression {
        // The patterns are fixed text: a mistake shows in the first test run.
        try! NSRegularExpression(pattern: pattern, options: [.caseInsensitive])
    }
}
