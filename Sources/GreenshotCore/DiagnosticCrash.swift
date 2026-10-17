// Greenshot for Mac (Community) - an unofficial macOS port of Greenshot
// Copyright (C) 2026 Greenshot for Mac (Community) contributors
// Based on Greenshot, Copyright (C) 2007-2026 Thomas Braun, Jens Klingen, Robin Krom
// SPDX-License-Identifier: GPL-3.0-or-later

import CryptoKit
import Foundation

/// One line of a stack: the binary and, when known, the function.
public struct CrashFrame: Codable, Equatable, Sendable {
    /// "GreenshotMac", "AppKit", "libswiftCore.dylib".
    public var image: String
    public var symbol: String?
    /// The offset in the image, when there is no symbol (a stripped build).
    public var imageOffset: UInt64?

    public init(image: String, symbol: String?, imageOffset: UInt64? = nil) {
        self.image = image
        self.symbol = symbol
        self.imageOffset = imageOffset
    }

    /// A line of `NSException.callStackSymbols` / `Thread.callStackSymbols`:
    /// `3   GreenshotMac   0x0000000100a2c3f0 $s12GreenshotMac11AppDelegateC... + 120`.
    public init?(callStackSymbol line: String) {
        let parts = line.split(separator: " ", omittingEmptySubsequences: true)
        guard parts.count >= 4, Int(parts[0]) != nil, parts[2].hasPrefix("0x") else { return nil }
        image = String(parts[1])
        var symbolParts = parts[3...]
        if symbolParts.count >= 3, symbolParts[symbolParts.endIndex - 2] == "+", Int(symbolParts.last ?? "") != nil {
            symbolParts = symbolParts.dropLast(2)
        }
        let joined = symbolParts.joined(separator: " ")
        symbol = joined.isEmpty ? nil : joined
        imageOffset = nil
    }

    /// "GreenshotMac  AppDelegate.applicationDidFinishLaunching(_:)" for the stack shown to the user.
    public var text: String {
        if let symbol { return "\(image)  \(symbol)" }
        return "\(image)  +0x\(String(imageOffset ?? 0, radix: 16))"
    }
}

/// An error worth a bug report: an exception AppKit caught, an exception that ended the app, or a crash found at the
/// next launch. Upstream's `BugReportViewModel` gets the same from an `Exception`.
public struct CrashDetails: Codable, Equatable, Sendable {
    public enum Kind: String, Codable, Sendable {
        /// An Objective-C exception AppKit caught; the app went on (upstream `Application.ThreadException`).
        case caughtException
        /// An exception nothing caught: the app ended (upstream `UnhandledException` with `IsTerminating`).
        case uncaughtException
        /// A crash report of macOS (a Swift runtime error, a bad memory access, ...), found at the next launch.
        case crashReport
    }

    public var kind: Kind
    /// "NSInvalidArgumentException", "EXC_BREAKPOINT (SIGTRAP)".
    public var type: String
    /// The reason of the exception, or the message of the crash report ("Fatal error: Unexpectedly found nil ...").
    public var message: String
    public var frames: [CrashFrame]
    public var date: Date?
    /// The crash report file name, for a crash report.
    public var reportFile: String?

    public init(kind: Kind, type: String, message: String, frames: [CrashFrame], date: Date? = nil, reportFile: String? = nil) {
        self.kind = kind
        self.type = type
        self.message = message
        self.frames = frames
        self.date = date
        self.reportFile = reportFile
    }

    /// The stack as shown and copied ("Copy Stack Trace").
    public var stackText: String {
        frames.enumerated().map { "\($0.offset)  \($0.element.text)" }.joined(separator: "\n")
    }

    /// The error part of a report (upstream `EnvironmentInfo.ExceptionToString`: "Exception:", "Message:", "Stack:").
    public func reportText(home: String = NSHomeDirectory()) -> String {
        var text = "Exception: \(type)\nMessage: \(DiagnosticReport.abbreviatingHome(message, home: home))\n"
        if let reportFile { text += "Crash report: \(reportFile)\n" }
        text += "\nStack:\n" + stackText
        return text
    }
}

/// Issue identifiers and links, port of upstream `Greenshot.Base/Core/ExceptionHelper.cs` for this port's repository.
public enum IssueLinks {
    public static let stackTraceHashMarker = "[stack-trace-hash:"
    public static let repository = "HengYpinn/greenshot-mac"

    /// The images of the app itself; Core is linked into the executable.
    public static let ownImages: Set<String> = ["GreenshotMac", "GreenshotCore"]

    /// A stable text of an error, without the message, addresses or line numbers (upstream `NormalizeStackTrace`): the
    /// type, then the app's own frames as `at Image!function`; frames without a function as `at Image+0xoffset` (stable
    /// for one build only). Without own frames, every frame with a function.
    public static func normalized(_ details: CrashDetails, ownImages: Set<String> = ownImages) -> String {
        var lines: [String] = []
        let type = details.type.trimmingCharacters(in: .whitespaces)
        if !type.isEmpty { lines.append(type) }
        let own = details.frames.filter { ownImages.contains($0.image) }.map { frame -> String in
            if let symbol = frame.symbol { return "at \(frame.image)!\(symbol)" }
            return "at \(frame.image)+0x\(String(frame.imageOffset ?? 0, radix: 16))"
        }
        if own.isEmpty {
            lines += details.frames.compactMap { frame in frame.symbol.map { "at \(frame.image)!\($0)" } }
        } else {
            lines += own
        }
        return lines.joined(separator: "\n")
    }

    /// 12 lowercase hex digits: the first 6 bytes of the SHA-256 of the normalized text (upstream `ComputeHash`);
    /// empty for an empty text.
    public static func hash(of normalizedText: String) -> String {
        let text = normalizedText.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !text.isEmpty else { return "" }
        return SHA256.hash(data: Data(text.utf8)).prefix(6).map { String(format: "%02x", $0) }.joined()
    }

    public static func hash(of details: CrashDetails) -> String {
        hash(of: normalized(details))
    }

    /// The issues of the repository that mention the hash (upstream `GetGitHubSearchUrl`).
    public static func searchURL(hash: String) -> URL {
        let issues = "https://github.com/\(repository)/issues"
        guard !hash.isEmpty else { return URL(string: issues)! }
        let query = "is:issue \"\(stackTraceHashMarker) \(hash)]\""
        return URL(string: "\(issues)?q=\(encode(query))")!
    }

    /// A new issue with the hash and type in the title and the hash marker in the body, so the search finds it
    /// (upstream `GetNewIssueUrl`; this repository has no issue template).
    public static func newIssueURL(hash: String, type: String, environment: String) -> URL {
        let title = type.isEmpty ? "[\(hash)] Error report" : "[\(hash)] \(type)"
        let body = """
            **What happened?**
            <!-- What did you do just before? Paste the details from "Copy Details" below if you like. -->


            **Environment**
            \(environment)

            \(stackTraceHashMarker) \(hash)]
            """
        return URL(string: "https://github.com/\(repository)/issues/new?title=\(encode(title))&body=\(encode(body))")!
    }

    /// Percent-encoding of a query value: everything but letters, digits and `-._~`.
    static func encode(_ text: String) -> String {
        let allowed = CharacterSet(charactersIn: "abcdefghijklmnopqrstuvwxyzABCDEFGHIJKLMNOPQRSTUVWXYZ0123456789-._~")
        return text.addingPercentEncoding(withAllowedCharacters: allowed) ?? text
    }
}

/// A crash report of macOS (`~/Library/Logs/DiagnosticReports/<process>-<date>.ips`): a JSON header line, then the
/// JSON of the report. Only what the bug report needs is read.
public struct CrashReportFile: Equatable, Sendable {
    public var fileName: String
    public var bugType: String
    public var processName: String
    public var pid: Int?
    public var appVersion: String
    public var captureTime: Date?
    public var exceptionType: String
    public var signal: String
    /// How it ended, e.g. "Trace/BPT trap: 5" (`termination.indicator`).
    public var termination: String
    /// The application specific information: Swift's "Fatal error: ..." or "*** Terminating app due to uncaught
    /// exception ...".
    public var messages: [String]
    /// The frames of the thread that crashed, or of the exception's backtrace when the report has one.
    public var frames: [CrashFrame]

    /// Reads a report; nil when it isn't one (a hang or spin report, or not JSON).
    public static func parse(_ text: String, fileName: String) -> CrashReportFile? {
        guard let newline = text.firstIndex(of: "\n"),
              let header = json(String(text[..<newline])),
              let body = json(String(text[text.index(after: newline)...])) else { return nil }
        let bugType = (header["bug_type"] as? String) ?? ""
        // 309: a crash. 109 is the older crash format; hangs and spins have other types.
        guard bugType == "309" || bugType == "109" else { return nil }
        let exception = body["exception"] as? [String: Any] ?? [:]
        let images = (body["usedImages"] as? [[String: Any]] ?? []).map { image -> String in
            if let name = image["name"] as? String, !name.isEmpty { return name }
            return ((image["path"] as? String) as NSString?)?.lastPathComponent ?? "?"
        }
        func frames(_ list: [[String: Any]]) -> [CrashFrame] {
            list.map { frame in
                let index = frame["imageIndex"] as? Int ?? -1
                let image = images.indices.contains(index) ? images[index] : "?"
                let offset = (frame["imageOffset"] as? NSNumber)?.uint64Value
                return CrashFrame(image: image, symbol: frame["symbol"] as? String, imageOffset: offset)
            }
        }
        var crashFrames: [CrashFrame] = []
        if let backtrace = body["lastExceptionBacktrace"] as? [[String: Any]], !backtrace.isEmpty {
            crashFrames = frames(backtrace)
        } else if let threads = body["threads"] as? [[String: Any]] {
            let faulting = body["faultingThread"] as? Int
            let thread = faulting.flatMap { threads.indices.contains($0) ? threads[$0] : nil }
                ?? threads.first { $0["triggered"] as? Bool == true }
            crashFrames = frames(thread?["frames"] as? [[String: Any]] ?? [])
        }
        var messages: [String] = []
        if let asi = body["asi"] as? [String: Any] {
            for key in asi.keys.sorted() {
                if let lines = asi[key] as? [String] { messages += lines } else if let line = asi[key] as? String { messages.append(line) }
            }
        }
        let processName = (body["procName"] as? String) ?? (header["app_name"] as? String) ?? (header["name"] as? String) ?? ""
        let termination = ((body["termination"] as? [String: Any])?["indicator"] as? String) ?? ""
        return CrashReportFile(fileName: fileName, bugType: bugType, processName: processName, pid: body["pid"] as? Int,
                               appVersion: (header["app_version"] as? String) ?? "",
                               captureTime: (body["captureTime"] as? String).flatMap(date),
                               exceptionType: (exception["type"] as? String) ?? "", signal: (exception["signal"] as? String) ?? "",
                               termination: termination,
                               messages: messages.map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }.filter { !$0.isEmpty },
                               frames: crashFrames)
    }

    /// "EXC_BREAKPOINT (SIGTRAP)".
    public var typeText: String {
        switch (exceptionType.isEmpty, signal.isEmpty) {
        case (false, false): return "\(exceptionType) (\(signal))"
        case (false, true): return exceptionType
        case (true, false): return signal
        case (true, true): return "Crash"
        }
    }

    /// The messages of the report; without them how it ended, with a hint for a Swift runtime error (a trap).
    public var message: String {
        if !messages.isEmpty { return messages.joined(separator: "\n") }
        var text = "\(processName) quit unexpectedly"
        if !termination.isEmpty { text += " (\(termination))" }
        if exceptionType == "EXC_BREAKPOINT" || signal == "SIGTRAP" || signal == "SIGILL" {
            text += ": a runtime error of the app, see the stack"
        }
        return text + "."
    }

    public var details: CrashDetails {
        return CrashDetails(kind: .crashReport, type: typeText, message: message, frames: frames, date: captureTime,
                            reportFile: fileName)
    }

    private static func json(_ text: String) -> [String: Any]? {
        guard let data = text.data(using: .utf8) else { return nil }
        return (try? JSONSerialization.jsonObject(with: data)) as? [String: Any]
    }

    /// "2026-10-17 12:42:16.0843 +0800".
    static func date(_ text: String) -> Date? {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX")
        for format in ["yyyy-MM-dd HH:mm:ss.SSSS Z", "yyyy-MM-dd HH:mm:ss.SS Z", "yyyy-MM-dd HH:mm:ss Z"] {
            formatter.dateFormat = format
            if let date = formatter.date(from: text) { return date }
        }
        return nil
    }
}

/// What the running app writes when it starts and removes when it quits: left behind, the run ended without quitting.
public struct RunMarker: Codable, Equatable, Sendable {
    public var pid: Int32
    public var launched: Date
    public var version: String
    /// The executable's name, which macOS's crash reports start with.
    public var processName: String

    public init(pid: Int32, launched: Date, version: String, processName: String) {
        self.pid = pid
        self.launched = launched
        self.version = version
        self.processName = processName
    }
}

/// How the previous run ended, from the marker it left, the note of an exception that ended it, and macOS's crash
/// reports.
public enum PreviousRun: Equatable, Sendable {
    /// It quit normally (no marker), or another copy of the app is still running.
    case clean
    /// It ended without quitting and without a report: a forced quit, a power cut, or a crash report still being written.
    case endedAbnormally(RunMarker)
    case crashed(RunMarker, CrashDetails)

    public var endedAbnormally: Bool {
        self != .clean
    }

    /// `isRunning` tells whether a process with that id is a running copy of the app.
    public static func evaluate(marker: RunMarker?, currentPID: Int32, isRunning: (Int32) -> Bool,
                                exceptionNote: CrashDetails?, reports: [CrashReportFile]) -> PreviousRun {
        guard let marker, marker.pid != currentPID, !isRunning(marker.pid) else { return .clean }
        // A minute of slack: the clocks of the marker and the note are the same, the report's may be rounded.
        let since = marker.launched.addingTimeInterval(-60)
        if let note = exceptionNote, (note.date ?? .distantFuture) >= since {
            return .crashed(marker, note)
        }
        if let report = reports.first(where: { $0.pid.map(Int32.init) == marker.pid && $0.processName == marker.processName
            && ($0.captureTime ?? .distantFuture) >= since }) {
            return .crashed(marker, report.details)
        }
        return .endedAbnormally(marker)
    }
}
