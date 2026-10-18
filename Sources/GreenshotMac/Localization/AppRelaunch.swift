// Greenshot for Mac (Community) - an unofficial macOS port of Greenshot
// Copyright (C) 2026 Greenshot for Mac (Community) contributors
// SPDX-License-Identifier: GPL-3.0-or-later

import AppKit
import GreenshotCore

/// Quits and starts the app again, for a new language (upstream switches the texts of its open windows at once; on
/// macOS a process keeps the localization it started with, and System Settings' per-app language relaunches apps too).
@MainActor
enum AppRelaunch {
    private static var observer: NSObjectProtocol?
    private static var beforeRestart: (() -> Void)?
    private static let log = Log("Language")

    /// Quits like the Quit menu item (unsaved screenshots are asked about first); once the app really ends,
    /// `beforeRestart` runs (the welcome asks to come back) and the app starts again with the same `--settings-dir`.
    ///
    /// `NSApp.terminate` returns only when quitting was cancelled (an unsaved screenshot, a running recipe): then
    /// nothing is left behind, and a later Quit is an ordinary quit. A quit that waits (`.terminateLater` while a
    /// recording is saved, VideoRecordingController.terminateReply) stays inside `terminate` in AppKit's modal loop
    /// until the reply, which always lets the app end; a second request meanwhile changes nothing.
    static func relaunch(beforeRestart: (() -> Void)? = nil) {
        guard observer == nil else { return }
        self.beforeRestart = beforeRestart
        observer = NotificationCenter.default.addObserver(forName: NSApplication.willTerminateNotification,
                                                          object: nil, queue: nil) { _ in
            MainActor.assumeIsolated {
                AppRelaunch.beforeRestart?()
                startAgainAfterExit()
            }
        }
        log.info("Relaunching for the language")
        NSApp.terminate(nil)
        // Still running: quitting was cancelled.
        log.info("Quitting was cancelled; no relaunch")
        cancel()
    }

    private static func cancel() {
        if let observer { NotificationCenter.default.removeObserver(observer) }
        observer = nil
        beforeRestart = nil
    }

    /// A shell waits for this process to end (the single-instance lock is free then), then opens the app again: the
    /// bundle with `open -n`, a development build by its executable.
    private static func startAgainAfterExit() {
        let pid = ProcessInfo.processInfo.processIdentifier
        let launch = AppLaunchOptions.parse(arguments: CommandLine.arguments, environment: ProcessInfo.processInfo.environment)
        let keep = launch.settingsDirectory.map { ["--settings-dir", $0.path] } ?? []
        let bundle = Bundle.main.bundleURL
        let command: [String]
        if bundle.pathExtension == "app" {
            command = ["/usr/bin/open", "-n", bundle.path] + (keep.isEmpty ? [] : ["--args"] + keep)
        } else {
            command = [Bundle.main.executablePath ?? CommandLine.arguments[0]] + keep
        }
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/bin/sh")
        process.arguments = ["-c", "while /bin/kill -0 \"$1\" 2>/dev/null; do /bin/sleep 0.2; done; shift; exec \"$@\"",
                             "sh", String(pid)] + command
        do {
            try process.run()
        } catch {
            log.error("The app can't start itself again", error: error)
        }
    }
}
