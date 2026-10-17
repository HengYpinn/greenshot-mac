// Greenshot for Mac (Community) - an unofficial macOS port of Greenshot
// Copyright (C) 2026 Greenshot for Mac (Community) contributors
// Based on Greenshot, Copyright (C) 2007-2026 Thomas Braun, Jens Klingen, Robin Krom
// SPDX-License-Identifier: GPL-3.0-or-later

import AppKit
import GreenshotCore

/// The start of the app before AppKit (upstream `Shell/GreenshotApplication.Start` and `Helpers/GreenshotCommandLine`):
/// `--help`, the command after the startup options, and one running instance per user. LaunchServices already keeps
/// one instance of a bundle; this also covers the binary run from a terminal and a second copy of the app. A second
/// start forwards its command to the running instance and quits; without a command it says that the app runs already.
@MainActor
enum AutomationStartup {
    /// What the app was started with; `--snapshot` skips everything here.
    private(set) static var options = IPCCommandLine.StartupOptions()
    /// The socket and locks of this build.
    static let endpoint = IPCEndpoint.forExecutable(IPCEndpoint.currentExecutablePath)
    /// Held while the app runs; nil when the lock couldn't be used (then the app runs without the automation server).
    private(set) static var instanceLock: IPCFileLock?
    private static let log = Log("Automation")

    /// Called first in main.swift; returns only when this process runs the app.
    static func run(arguments: [String] = CommandLine.arguments) {
        options = IPCCommandLine.scanStartup(Array(arguments.dropFirst()))
        if options.snapshot { return }
        if options.help {
            FileHandle.standardOutput.write(Data(IPCCommandLine.appUsage.utf8))
            exit(0)
        }
        if !options.command.isEmpty {
            // Checked with the same parser as later, so a mistake shows on the caller's terminal
            let parsed = IPCCommandLine.parse(options.command, source: .cli, cwd: FileManager.default.currentDirectoryPath)
            if let error = parsed.error {
                FileHandle.standardError.write(Data("greenshot: \(error)\n".utf8))
                exit(IPCExitCode.usage)
            }
        }

        switch IPCFileLock.acquire(endpoint.instanceLockURL) {
        case .acquired(let lock):
            instanceLock = lock
            // Nothing to quit or to reload when the app wasn't running
            if !options.command.isEmpty, !IPCClient.startsApp(for: options.command) { exit(0) }
        case .heldByOther(let pid):
            if !options.command.isEmpty { exit(forwardCommand()) }
            // Started by greenshot-cli or a script while the app runs: nobody needs to be told
            if options.background { exit(0) }
            showAlreadyRunning(pid: pid)
            exit(0)
        case .failed(let message):
            log.warn("The instance lock can't be used (\(message)); the app runs without command line and link support")
        }
    }

    /// The command of this start, run by the app itself once it listens.
    static var startupCommand: [String] { options.command }

    /// Sends the command to the running instance like greenshot-cli does (upstream: `NamedPipeClient.SendMessage` of
    /// the startup command) and shows nothing of the reply; its exit code becomes this process's.
    private static func forwardCommand() -> Int32 {
        guard let client = IPCClient.connect(to: endpoint.socketPath, waitingUpTo: 10) else {
            FileHandle.standardError.write(Data("greenshot: Greenshot for Mac runs but doesn't answer.\n".utf8))
            return IPCExitCode.unavailable
        }
        defer { client.close() }
        client.setReadTimeout(30)
        do {
            try client.send(.hello(source: .cli, replyFormat: .text, client: "GreenshotMac", clientVersion: AutomationCommands.appVersion))
            try client.send(.commandLine(options.command, cwd: FileManager.default.currentDirectoryPath))
        } catch {
            return IPCExitCode.failure
        }
        return client.receiveTextReply(stdout: { _ in }, stderr: { _ in })
    }

    /// Upstream `InstanceRunningWindow`: which copy runs, with a way to find it.
    private static func showAlreadyRunning(pid: pid_t?) {
        let path = pid.flatMap(processPath)
        // A plain NSApplication: this process quits right after the alert.
        _ = NSApplication.shared
        NSApp.setActivationPolicy(.accessory)
        NSApp.activate()
        let alert = alreadyRunningAlert(path: path)
        if alert.runModal() == .alertSecondButtonReturn, let path {
            NSWorkspace.shared.activateFileViewerSelecting([URL(fileURLWithPath: bundlePath(ofExecutable: path))])
        }
    }

    /// The alert (also for the snapshots).
    static func alreadyRunningAlert(path: String?) -> NSAlert {
        let alert = NSAlert()
        alert.messageText = "An instance of \(AppInfo.name) is already running."
        if let path {
            alert.informativeText = "It runs from \(DiagnosticReport.abbreviatingHome(bundlePath(ofExecutable: path))). Quit it first to start this copy."
        } else {
            alert.informativeText = "Quit it first to start this copy."
        }
        alert.addButton(withTitle: "OK")
        if path != nil { alert.addButton(withTitle: "Show in Finder") }
        return alert
    }

    private static func bundlePath(ofExecutable path: String) -> String {
        IPCPeerPolicy.appBundle(ofExecutable: path) ?? path
    }

    private static func processPath(_ pid: pid_t) -> String? {
        var buffer = [CChar](repeating: 0, count: 4 * Int(MAXPATHLEN))
        let length = proc_pidpath(pid, &buffer, UInt32(buffer.count))
        return length > 0 ? String(cString: buffer) : nil
    }
}
