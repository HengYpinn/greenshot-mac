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

    static let hub = LogHub(level: defaultLevel, unifiedLog: true)

    /// What is written. A change applies until the app quits (upstream `LogHelper.RootLevel`).
    public static var level: LogLevel {
        get { hub.level }
        set { hub.level = newValue }
    }

    public static func isEnabled(_ level: LogLevel) -> Bool {
        hub.isEnabled(level)
    }

    /// The log file, after `startFile(at:)`.
    public static var fileURL: URL? {
        hub.fileURL
    }

    /// From now on also writes to the file at `url` (created with its folder when missing), rolling it over at 1 MB
    /// (`LogFile`). Called once by the app at launch, not by tests or `--snapshot` runs.
    public static func startFile(at url: URL) {
        hub.startFile(at: url)
    }

    /// Writes one entry whose level was checked. `Log` calls this; other code uses `Log`.
    public static func write(_ level: LogLevel, category: String, message: String, error: Error?) {
        hub.write(level, category: category, message: message, error: error)
    }

    /// Changes the level and logs the change (upstream `LogViewerWindow.SelectedLogLevel`): before the change when the
    /// old level writes it, else right after, so the line is there in both directions. `note` ends the sentence, e.g.
    /// "in the log viewer, until the app restarts".
    public static func changeLevel(to newLevel: LogLevel, note: String) {
        hub.changeLevel(to: newLevel, note: note)
    }

    /// Collects the entries written from now on, as the file has them, until `end()` (upstream `LogViewerAppender`,
    /// attached while the log viewer is open).
    public static func beginLiveTail() -> LogLiveTail {
        hub.beginLiveTail()
    }
}

/// The entries written while it is open, for the log viewer: `take()` returns those since the last call.
public final class LogLiveTail: @unchecked Sendable {
    private let lock = NSLock()
    private var buffer = ""
    private var isEnded = false
    private weak var hub: LogHub?

    init(hub: LogHub) {
        self.hub = hub
    }

    deinit {
        hub?.remove(self)
    }

    /// The entries written since the last call, empty when there are none.
    public func take() -> String {
        lock.lock()
        defer { lock.unlock() }
        let text = buffer
        buffer = ""
        return text
    }

    /// Stops collecting.
    public func end() {
        lock.lock()
        isEnded = true
        buffer = ""
        lock.unlock()
        hub?.remove(self)
    }

    func append(_ entry: String) {
        lock.lock()
        defer { lock.unlock() }
        guard !isEnded else { return }
        buffer += entry
    }
}

/// The level, the file and the live tails behind `LogCenter`; tests make their own.
final class LogHub: @unchecked Sendable {
    private let lock = NSLock()
    private var currentLevel: LogLevel
    private var writer: LogFileWriter?
    private var tails: [ObjectIdentifier: Weak] = [:]
    private let unifiedLog: Bool

    private struct Weak {
        weak var tail: LogLiveTail?
    }

    init(level: LogLevel, unifiedLog: Bool) {
        currentLevel = level
        self.unifiedLog = unifiedLog
    }

    var level: LogLevel {
        get { locked { currentLevel } }
        set { locked { currentLevel = newValue } }
    }

    func isEnabled(_ level: LogLevel) -> Bool {
        level >= self.level
    }

    var fileURL: URL? {
        locked { writer?.url }
    }

    func startFile(at url: URL) {
        locked {
            writer?.close()
            writer = LogFileWriter(url: url)
        }
    }

    func write(_ level: LogLevel, category: String, message: String, error: Error?, date: Date = Date(),
               thread: String = LogHub.threadName) {
        let raw = LogFile.entry(date: date, thread: thread, level: level, category: category, message: message, error: error)
        let entry = LogSanitizer.fileEntry(raw)
        let liveTails: [LogLiveTail] = locked {
            writer?.append(entry)
            return tails.values.compactMap(\.tail)
        }
        liveTails.forEach { $0.append(entry) }
        if unifiedLog {
            let logger = Logger(subsystem: LogCenter.subsystem, category: category)
            let text = error.map { "\(message)\n\(LogFile.describe($0))" } ?? message
            switch level {
            case .debug: logger.debug("\(text, privacy: .public)")
            case .info: logger.info("\(text, privacy: .public)")
            case .warn: logger.warning("\(text, privacy: .public)")
            case .error: logger.error("\(text, privacy: .public)")
            }
        }
    }

    func changeLevel(to newLevel: LogLevel, note: String, category: String = "LogViewer") {
        let oldLevel = level
        guard newLevel != oldLevel else { return }
        let message = "Log level changed from \(oldLevel.name) to \(newLevel.name) \(note)"
        if isEnabled(.info) {
            write(.info, category: category, message: message, error: nil)
            level = newLevel
        } else {
            level = newLevel
            if isEnabled(.info) { write(.info, category: category, message: message, error: nil) }
        }
    }

    func beginLiveTail() -> LogLiveTail {
        let tail = LogLiveTail(hub: self)
        locked { tails[ObjectIdentifier(tail)] = Weak(tail: tail) }
        return tail
    }

    func remove(_ tail: LogLiveTail) {
        locked { _ = tails.removeValue(forKey: ObjectIdentifier(tail)) }
    }

    /// "main", or the thread's number (log4net `%thread`).
    static var threadName: String {
        if Thread.isMainThread { return "main" }
        var id: UInt64 = 0
        pthread_threadid_np(nil, &id)
        return String(id)
    }

    private func locked<T>(_ body: () -> T) -> T {
        lock.lock()
        defer { lock.unlock() }
        return body()
    }
}
