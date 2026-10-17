// Greenshot for Mac (Community) - an unofficial macOS port of Greenshot
// Copyright (C) 2026 Greenshot for Mac (Community) contributors
// Based on Greenshot, Copyright (C) 2007-2026 Thomas Braun, Jens Klingen, Robin Krom
// SPDX-License-Identifier: GPL-3.0-or-later

import AppKit
import Darwin
import GreenshotCore

/// The app's NSApplication (created in main.swift): AppKit catches an exception in the event loop, logs it and goes
/// on; here it is also logged to the app's log and shown in a bug report, like upstream's
/// `Application.ThreadException` handler (`Greenshot/GreenshotMain.cs`).
final class GreenshotApplication: NSApplication {
    override func reportException(_ exception: NSException) {
        super.reportException(exception)
        CrashReporting.caught(exception)
    }
}

/// The note an uncaught exception leaves for the next launch (the app ends right after the handler). Not on the main
/// actor: the handler runs on the thread of the exception.
enum ExceptionNote {
    nonisolated(unsafe) static var url: URL?

    static func details(_ exception: NSException, kind: CrashDetails.Kind) -> CrashDetails {
        CrashDetails(kind: kind, type: exception.name.rawValue, message: exception.reason ?? "",
                     frames: exception.callStackSymbols.compactMap(CrashFrame.init(callStackSymbol:)), date: Date())
    }

    static func write(_ details: CrashDetails) {
        guard let url, let data = try? JSONEncoder().encode(details) else { return }
        try? FileManager.default.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
        try? data.write(to: url, options: .atomic)
    }
}

/// Errors, crashes and how the last run ended (upstream's exception handlers in `GreenshotMain.cs` and
/// `BugReportWindow.ShowReport`). Swift runtime errors (traps) can't be caught: a marker is written at the start and
/// removed when the app quits, and when it is still there at the next start, the crash report macOS wrote for that
/// process (in ~/Library/Logs/DiagnosticReports) is shown as a bug report.
@MainActor
enum CrashReporting {
    private static let log = Log("Crash")

    static var markerURL: URL { AppInfo.logsFolder.appendingPathComponent("running.json") }
    static var noteURL: URL { AppInfo.logsFolder.appendingPathComponent("exception.json") }
    static var reportsFolder: URL {
        FileManager.default.homeDirectoryForCurrentUser.appendingPathComponent("Library/Logs/DiagnosticReports", isDirectory: true)
    }

    static var processName: String { ProcessInfo.processInfo.processName }

    /// Writes the note of an exception that ends the app (upstream `CurrentDomain_UnhandledException`).
    static func install() {
        ExceptionNote.url = noteURL
        NSSetUncaughtExceptionHandler { exception in
            let details = ExceptionNote.details(exception, kind: .uncaughtException)
            Log("Crash").error("Uncaught exception: \(details.type): \(details.message)\n\(details.stackText)")
            ExceptionNote.write(details)
            // Usually the app ends now and the next launch reports the note. AppKit keeps the app running after some
            // exceptions on the main thread (e.g. in a notification at launch): then the report comes right away.
            DispatchQueue.main.async {
                MainActor.assumeIsolated { CrashReporting.survived(details) }
            }
        }
    }

    /// The app is still running after an uncaught exception: reported now instead of at the next launch.
    static func survived(_ details: CrashDetails) {
        try? FileManager.default.removeItem(at: noteURL)
        var reported = details
        reported.kind = .caughtException
        log.warn("The app goes on after the uncaught exception \(details.type)")
        BugReportWindowController.show(reported)
    }

    /// How the previous run ended; writes this run's marker.
    static func checkPreviousRun() -> PreviousRun {
        let decoder = JSONDecoder()
        let marker = (try? Data(contentsOf: markerURL)).flatMap { try? decoder.decode(RunMarker.self, from: $0) }
        let note = (try? Data(contentsOf: noteURL)).flatMap { try? decoder.decode(CrashDetails.self, from: $0) }
        let reports = marker.map { crashReports(since: $0.launched) } ?? []
        let outcome = PreviousRun.evaluate(marker: marker, currentPID: getpid(), isRunning: isRunningCopy,
                                           exceptionNote: note, reports: reports)
        try? FileManager.default.removeItem(at: noteURL)
        writeMarker()
        switch outcome {
        case .clean:
            break
        case .endedAbnormally(let marker):
            log.warn("The previous run (version \(marker.version), started \(LogFile.timestamp(marker.launched))) did not end normally; no crash report was found")
        case .crashed(_, let details):
            log.error("The previous run crashed: \(details.type): \(details.message)\n\(details.stackText)")
        }
        return outcome
    }

    /// A crash report can still be being written when the app is started again right away: one more look.
    static func lookAgain(for marker: RunMarker, after delay: TimeInterval, found: @escaping (CrashDetails) -> Void) {
        DispatchQueue.main.asyncAfter(deadline: .now() + delay) {
            MainActor.assumeIsolated {
                let outcome = PreviousRun.evaluate(marker: marker, currentPID: getpid(), isRunning: { _ in false },
                                                   exceptionNote: nil, reports: crashReports(since: marker.launched))
                guard case .crashed(_, let details) = outcome else { return }
                log.error("The crash report of the previous run turned up: \(details.type): \(details.message)\n\(details.stackText)")
                found(details)
            }
        }
    }

    static func removeMarker() {
        try? FileManager.default.removeItem(at: markerURL)
    }

    private static func writeMarker() {
        let version = Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? "0"
        let marker = RunMarker(pid: getpid(), launched: SystemInfo.processStart() ?? Date(), version: version, processName: processName)
        guard let data = try? JSONEncoder().encode(marker) else { return }
        do {
            try FileManager.default.createDirectory(at: markerURL.deletingLastPathComponent(), withIntermediateDirectories: true)
            try data.write(to: markerURL, options: .atomic)
        } catch {
            log.warn("The marker of the running app could not be written", error: error)
        }
    }

    /// This app's crash reports written since `date` (a minute of slack), newest first.
    static func crashReports(since date: Date) -> [CrashReportFile] {
        let manager = FileManager.default
        guard let names = try? manager.contentsOfDirectory(atPath: reportsFolder.path) else { return [] }
        let prefix = processName + "-"
        return names.filter { $0.hasPrefix(prefix) && $0.hasSuffix(".ips") }.compactMap { name -> (Date, CrashReportFile)? in
            let url = reportsFolder.appendingPathComponent(name)
            let values = try? url.resourceValues(forKeys: [.contentModificationDateKey, .fileSizeKey])
            guard let modified = values?.contentModificationDate, modified >= date.addingTimeInterval(-60),
                  (values?.fileSize ?? 0) < 8 << 20,
                  let text = try? String(contentsOf: url, encoding: .utf8),
                  let report = CrashReportFile.parse(text, fileName: name) else { return nil }
            return (modified, report)
        }
        .sorted { $0.0 > $1.0 }
        .map(\.1)
    }

    /// The number of this app's crash reports, for Self-Service › Files.
    static func crashReportCount() -> Int {
        let names = (try? FileManager.default.contentsOfDirectory(atPath: reportsFolder.path)) ?? []
        return names.filter { $0.hasPrefix(processName + "-") && $0.hasSuffix(".ips") }.count
    }

    /// A process with that id is a running copy of this app (then its marker is not a crash).
    private static func isRunningCopy(_ pid: Int32) -> Bool {
        guard kill(pid, 0) == 0 || errno == EPERM else { return false }
        var buffer = [CChar](repeating: 0, count: 256)
        guard proc_name(pid, &buffer, UInt32(buffer.count)) > 0 else { return false }
        return String(cString: buffer) == String(processName.prefix(Int(MAXCOMLEN)))
    }

    /// An exception AppKit caught: logged and reported; the app goes on.
    static func caught(_ exception: NSException) {
        let details = ExceptionNote.details(exception, kind: .caughtException)
        log.error("Exception caught by AppKit: \(details.type): \(details.message)\n\(details.stackText)")
        BugReportWindowController.show(details)
    }

    #if DEBUG
    /// Development checks of the crash detection without any window: `--diagnostics-test crash` ends with a Swift
    /// runtime error, `exception` with an uncaught exception, `caught` reports an exception like AppKit does, and
    /// `check` prints how the previous run ended, then quits (removing the marker).
    static func runDebugTest(previousRun: PreviousRun) {
        let arguments = CommandLine.arguments
        guard let index = arguments.firstIndex(of: "--diagnostics-test"), index + 1 < arguments.count else { return }
        switch arguments[index + 1] {
        case "crash":
            let nothing: Int? = Int("not a number")
            print("Crashing now: \(nothing!)")
        case "exception":
            NSException(name: .genericException, reason: "Diagnostics test exception", userInfo: nil).raise()
        case "caught":
            NSApp.reportException(NSException(name: .rangeException, reason: "Diagnostics test of a caught exception", userInfo: nil))
        default:
            switch previousRun {
            case .clean: print("previous run: clean")
            case .endedAbnormally(let marker): print("previous run: ended abnormally, pid \(marker.pid)")
            case .crashed(let marker, let details):
                print("previous run: crashed, pid \(marker.pid), \(details.kind.rawValue), \(details.type), hash \(IssueLinks.hash(of: details))")
                print("message: \(details.message)")
                print(details.stackText.split(separator: "\n").prefix(6).joined(separator: "\n"))
            }
            removeMarker()
            exit(0)
        }
    }
    #endif
}
