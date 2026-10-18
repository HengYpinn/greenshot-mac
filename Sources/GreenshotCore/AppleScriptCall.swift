// Greenshot for Mac (Community) - an unofficial macOS port of Greenshot
// Copyright (C) 2026 Greenshot for Mac (Community) contributors
// SPDX-License-Identifier: GPL-3.0-or-later

import Foundation

// AppleScript is the Mac's way to drive Word, Excel, PowerPoint, Outlook, Mail, Notes and the browsers (upstream uses
// COM on Windows). The app runs a script with `/usr/bin/osascript` off the main thread (NSAppleScript is for the main
// thread only, and a script waiting for Word to start must be cancellable); here are the scripts and their answers as
// plain values, so tests can check them.

/// A script for `osascript -`: fixed source text, read from standard input, and the arguments its `on run argv`
/// handler reads. Text from the user or the capture (paths, titles, subjects, addresses, document names) only ever goes
/// into `arguments`, never into `source`, so nothing has to be escaped and nothing can change what the script does.
public struct AppleScriptCall: Equatable, Sendable {
    public var source: String
    public var arguments: [String]
    /// The app the script talks to, for the permission check and the messages.
    public var bundleID: String

    public init(source: String, arguments: [String] = [], bundleID: String) {
        self.source = source
        self.arguments = arguments
        self.bundleID = bundleID
    }

    /// The command line of `/usr/bin/osascript`: the script from standard input, then the arguments.
    public var processArguments: [String] { ["-"] + arguments }

    /// Several values for one argument, e.g. the recipients: one per line (the script splits with `paragraphs of`).
    public static func lines(_ values: [String]) -> String {
        values.map { $0.replacingOccurrences(of: "\r", with: " ").replacingOccurrences(of: "\n", with: " ") }
            .joined(separator: "\n")
    }
}

/// How a script failed, from the error `osascript` writes ("12:34: execution error: Word got an error: … (-1728)").
public struct AppleScriptFailure: Error, Equatable, LocalizedError {
    public enum Kind: Equatable, Sendable {
        /// The user didn't allow Greenshot to control the app (System Settings › Privacy & Security › Automation).
        case notAllowed
        /// macOS would have to ask the user first (the non-asking permission check).
        case needsConsent
        /// The app isn't running or could not be started.
        case notRunning
        case timedOut
        /// The app doesn't know the command or the object: another version of the app, or New Outlook.
        case notSupported
        /// The user cancelled a dialog the app showed.
        case cancelled
        case other
    }

    public var number: Int?
    public var message: String

    public init(number: Int?, message: String) {
        self.number = number
        self.message = message
    }

    /// Parses what `osascript` wrote to standard error.
    public static func parse(_ errorOutput: String) -> AppleScriptFailure {
        let text = errorOutput.trimmingCharacters(in: .whitespacesAndNewlines)
        let pattern = #"(?:execution|syntax) error: (.*) \((-?\d+)\)$"#
        guard let regex = try? NSRegularExpression(pattern: pattern, options: [.dotMatchesLineSeparators]),
              let match = regex.firstMatch(in: text, range: NSRange(text.startIndex..., in: text)),
              let messageRange = Range(match.range(at: 1), in: text), let numberRange = Range(match.range(at: 2), in: text) else {
            return AppleScriptFailure(number: nil, message: text)
        }
        return AppleScriptFailure(number: Int(text[numberRange]), message: String(text[messageRange]))
    }

    public var kind: Kind {
        switch number {
        case -1743: return .notAllowed
        case -1744: return .needsConsent
        case -600, -609, -10810, -10660: return .notRunning
        case -1712: return .timedOut
        case -1708, -1728, -1700, -10000, -2753, -1719: return .notSupported
        case -128: return .cancelled
        default: return .other
        }
    }

    public var errorDescription: String? { message.isEmpty ? String(localized: "The script failed.") : message }

    /// What to tell the user, naming the app.
    public func explanation(appName: String) -> String {
        switch kind {
        case .notAllowed, .needsConsent:
            return String(localized: "Greenshot isn't allowed to control \(appName). Allow it in System Settings › Privacy & Security › Automation › Greenshot.",
                          comment: "%@ is an app such as Microsoft Word")
        case .notRunning:
            return String(localized: "\(appName) isn't running and could not be started.", comment: "%@ is an app such as Microsoft Word")
        case .timedOut:
            return String(localized: "\(appName) didn't answer in time.", comment: "%@ is an app such as Microsoft Word")
        case .notSupported:
            return String(localized: "\(appName) can't do this: its version doesn't support it by AppleScript (\(message)).",
                          comment: "The first %@ is an app such as Microsoft Word, the second the app's error message")
        case .cancelled:
            return String(localized: "Cancelled.")
        case .other:
            return String(localized: "\(appName) reported a problem: \(message)",
                          comment: "The first %@ is an app such as Microsoft Word, the second the app's error message")
        }
    }
}

/// The answers of the scripts: values joined with linefeeds and tabs.
public enum AppleScriptOutput {
    /// The non-blank lines of a list the script returned with linefeeds between the items, as they are (a document
    /// name is looked up again by its exact text).
    public static func lines(_ output: String) -> [String] {
        output.components(separatedBy: "\n")
            .map { $0.hasSuffix("\r") ? String($0.dropLast()) : $0 }
            .filter { !$0.trimmingCharacters(in: .whitespaces).isEmpty }
    }

    /// Lines of tab-separated fields.
    public static func records(_ output: String) -> [[String]] {
        lines(output).map { $0.components(separatedBy: "\t") }
    }
}
