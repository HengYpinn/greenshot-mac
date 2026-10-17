// Greenshot for Mac (Community) - an unofficial macOS port of Greenshot
// Copyright (C) 2026 Greenshot for Mac (Community) contributors
// Based on Greenshot, Copyright (C) 2007-2026 Thomas Braun, Jens Klingen, Robin Krom
// SPDX-License-Identifier: GPL-3.0-or-later

import Foundation
import os

/// How much goes into the log, from the most to the fewest entries: upstream's log4net levels
/// (`Greenshot.Base/Core/LogHelper.cs` `RootLevel`).
public enum LogLevel: Int, CaseIterable, Comparable, Sendable {
    case debug, info, warn, error

    /// The level as the log file writes it (log4net `%level`).
    public var name: String {
        switch self {
        case .debug: return "DEBUG"
        case .info: return "INFO"
        case .warn: return "WARN"
        case .error: return "ERROR"
        }
    }

    public static func < (lhs: LogLevel, rhs: LogLevel) -> Bool { lhs.rawValue < rhs.rawValue }
}

/// A logger for one part of the app (upstream `LogManager.GetLogger(typeof(X))`):
///
///     private let log = Log("Capture")
///     log.info("Captured \(width)x\(height)")
///     log.error("Saving failed", error: error)
///
/// A message is only built when its level is written. Thread-safe. Entries go to the unified log (Console.app,
/// subsystem `LogCenter.subsystem`, the category given here) and, once the app started it, to the log file that
/// the log viewer shows.
public struct Log: Sendable {
    public let category: String

    public init(_ category: String) {
        self.category = category
    }

    public func debug(_ message: @autoclosure () -> String) {
        guard LogCenter.isEnabled(.debug) else { return }
        LogCenter.write(.debug, category: category, message: message(), error: nil)
    }

    public func info(_ message: @autoclosure () -> String) {
        guard LogCenter.isEnabled(.info) else { return }
        LogCenter.write(.info, category: category, message: message(), error: nil)
    }

    public func warn(_ message: @autoclosure () -> String, error: Error? = nil) {
        guard LogCenter.isEnabled(.warn) else { return }
        LogCenter.write(.warn, category: category, message: message(), error: error)
    }

    public func error(_ message: @autoclosure () -> String, error: Error? = nil) {
        guard LogCenter.isEnabled(.error) else { return }
        LogCenter.write(.error, category: category, message: message(), error: error)
    }
}

/// The log of the app: its level and its file. `Log` writes through it; the app starts the file at launch, the log
/// viewer reads it and changes the level.
public enum LogCenter {
    /// The unified log's subsystem: the bundle identifier, or the name of a bare `swift build` executable.
    public static let subsystem = Bundle.main.bundleIdentifier ?? ProcessInfo.processInfo.processName

    #if DEBUG
    /// Like upstream's log4net-debug.xml.
    public static let defaultLevel = LogLevel.debug
    #else
    /// Like upstream's log4net-release.xml.
    public static let defaultLevel = LogLevel.info
    #endif

    private struct State: Sendable {
        var level = LogCenter.defaultLevel
        var fileURL: URL?
    }

    private static let state = OSAllocatedUnfairLock(initialState: State())

    /// What is written. A change applies until the app quits (upstream `LogHelper.RootLevel`).
    public static var level: LogLevel {
        get { state.withLock { $0.level } }
        set { state.withLock { $0.level = newValue } }
    }

    public static func isEnabled(_ level: LogLevel) -> Bool {
        level >= self.level
    }

    /// The log file, after `startFile(at:)`.
    public static var fileURL: URL? {
        state.withLock { $0.fileURL }
    }

    /// From now on also writes to the file at `url` (created with its folder when missing). Called once by the app at
    /// launch, not by tests or `--snapshot` runs. (Prep stub: only remembers the file; package D adds the writer.)
    public static func startFile(at url: URL) {
        state.withLock { $0.fileURL = url }
    }

    /// Writes one entry whose level was checked. `Log` calls this; other code uses `Log`.
    public static func write(_ level: LogLevel, category: String, message: String, error: Error?) {
        let logger = Logger(subsystem: subsystem, category: category)
        let text = error.map { "\(message)\n\(String(describing: $0))" } ?? message
        switch level {
        case .debug: logger.debug("\(text, privacy: .public)")
        case .info: logger.info("\(text, privacy: .public)")
        case .warn: logger.warning("\(text, privacy: .public)")
        case .error: logger.error("\(text, privacy: .public)")
        }
    }
}
