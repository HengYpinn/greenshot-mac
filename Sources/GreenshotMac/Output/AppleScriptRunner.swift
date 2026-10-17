// Greenshot for Mac (Community) - an unofficial macOS port of Greenshot
// Copyright (C) 2026 Greenshot for Mac (Community) contributors
// SPDX-License-Identifier: GPL-3.0-or-later

import AppKit
import CoreServices
import GreenshotCore

private let log = Log("AppleScript")

/// Runs the scripts of `OfficeScripts` with `/usr/bin/osascript`, off the main thread, cancellable and with a time
/// limit (NSAppleScript is for the main thread only). macOS asks the first time whether Greenshot may control the app
/// (Privacy & Security › Automation; the reason is `NSAppleEventsUsageDescription` in Info.plist).
enum AppleScriptRunner {
    /// Whether Greenshot may send Apple events to an app.
    enum Permission: Equatable {
        case allowed
        /// macOS would ask the user first.
        case notAsked
        case denied
        case notRunning
        case unknown
    }

    /// Runs the script and gives its answer (standard output without the last line break). Throws `AppleScriptFailure`,
    /// or `CancellationError` when the task is cancelled (the script is stopped).
    static func run(_ call: AppleScriptCall, timeout: TimeInterval = 90) async throws -> String {
        let box = ProcessBox()
        return try await withTaskCancellationHandler {
            try await withCheckedThrowingContinuation { (continuation: CheckedContinuation<String, Error>) in
                DispatchQueue.global(qos: .userInitiated).async {
                    continuation.resume(with: Result { try runBlocking(call, timeout: timeout, box: box) })
                }
            }
        } onCancel: {
            box.cancel()
        }
    }

    /// The process of a running script, so a cancelled task can stop it.
    private final class ProcessBox: @unchecked Sendable {
        private let lock = NSLock()
        private var process: Process?
        private(set) var cancelled = false

        func start(_ process: Process) -> Bool {
            lock.lock()
            defer { lock.unlock() }
            guard !cancelled else { return false }
            self.process = process
            return true
        }

        func cancel() {
            lock.lock()
            defer { lock.unlock() }
            cancelled = true
            if process?.isRunning == true { process?.terminate() }
        }
    }

    private static func runBlocking(_ call: AppleScriptCall, timeout: TimeInterval, box: ProcessBox) throws -> String {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/usr/bin/osascript")
        process.arguments = call.processArguments
        let input = Pipe()
        let output = Pipe()
        let errors = Pipe()
        process.standardInput = input
        process.standardOutput = output
        process.standardError = errors
        guard box.start(process) else { throw CancellationError() }
        try process.run()
        input.fileHandleForWriting.write(Data(call.source.utf8))
        try? input.fileHandleForWriting.close()
        var timedOut = false
        let timer = DispatchWorkItem {
            if process.isRunning {
                timedOut = true
                process.terminate()
            }
        }
        DispatchQueue.global().asyncAfter(deadline: .now() + timeout, execute: timer)
        // Both pipes are read before waiting, or a long answer blocks on a full pipe.
        var outData = Data()
        let reading = DispatchGroup()
        reading.enter()
        DispatchQueue.global(qos: .userInitiated).async {
            outData = output.fileHandleForReading.readDataToEndOfFile()
            reading.leave()
        }
        let errData = errors.fileHandleForReading.readDataToEndOfFile()
        reading.wait()
        process.waitUntilExit()
        timer.cancel()
        if box.cancelled { throw CancellationError() }
        if timedOut { throw AppleScriptFailure(number: -1712, message: "The script took longer than \(Int(timeout)) seconds.") }
        guard process.terminationStatus == 0 else {
            let failure = AppleScriptFailure.parse(String(decoding: errData, as: UTF8.self))
            log.warn("A script for \(call.bundleID) failed: \(failure.message) (\(failure.number.map(String.init) ?? "no number"))")
            throw failure
        }
        var answer = String(decoding: outData, as: UTF8.self)
        if answer.hasSuffix("\n") { answer.removeLast() }
        return answer
    }

    /// Whether Greenshot may control the app, without asking unless `ask` (`AEDeterminePermissionToAutomateTarget`;
    /// the app has to run).
    static func permission(for bundleID: String, ask: Bool = false) async -> Permission {
        await Task.detached(priority: .userInitiated) {
            let target = NSAppleEventDescriptor(bundleIdentifier: bundleID)
            guard let descriptor = target.aeDesc else { return Permission.unknown }
            let status = AEDeterminePermissionToAutomateTarget(descriptor, typeWildCard, typeWildCard, ask)
            switch Int(status) {
            case Int(noErr): return .allowed
            case -1744: return .notAsked
            case -1743: return .denied
            case Int(procNotFound): return .notRunning
            default: return .unknown
            }
        }.value
    }

    @MainActor
    static func isRunning(_ bundleID: String) -> Bool {
        !NSRunningApplication.runningApplications(withBundleIdentifier: bundleID).isEmpty
    }

    @MainActor
    static func applicationURL(_ bundleID: String) -> URL? {
        NSWorkspace.shared.urlForApplication(withBundleIdentifier: bundleID)
    }

    /// System Settings › Privacy & Security › Automation.
    @MainActor
    static func openAutomationSettings() {
        if let url = URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_Automation") {
            NSWorkspace.shared.open(url)
        }
    }

    /// Explains a failed script; for a missing permission with a button to the Automation settings.
    @MainActor
    static func present(_ error: Error, appName: String, title: String) {
        guard let failure = error as? AppleScriptFailure else {
            ErrorPresenter.show(error, title: title)
            return
        }
        let alert = NSAlert()
        alert.alertStyle = .warning
        alert.messageText = title
        alert.informativeText = failure.explanation(appName: appName)
        let permission = failure.kind == .notAllowed || failure.kind == .needsConsent
        if permission {
            alert.addButton(withTitle: "Open Privacy Settings")
            alert.addButton(withTitle: "Cancel")
        }
        NSApp.activate()
        if alert.runModal() == .alertFirstButtonReturn, permission {
            openAutomationSettings()
        }
    }
}
