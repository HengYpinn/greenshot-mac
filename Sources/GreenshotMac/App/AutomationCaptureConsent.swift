// Greenshot for Mac (Community) - an unofficial macOS port of Greenshot
// Copyright (C) 2026 Greenshot for Mac (Community) contributors
// SPDX-License-Identifier: GPL-3.0-or-later

import AppKit
import Darwin
import GreenshotCore

/// The question before a capture greenshot-cli asks for without the user on the capture screen (see
/// `AutomationConsent`): "<program> asks Greenshot for Mac to take a screenshot of the whole screen." Don't Allow is the
/// default (Return); Allow reacts only after a second, so a click or key meant for something else doesn't answer it;
/// without an answer it counts as Don't Allow after a minute. Another program can't click it without the Accessibility
/// permission. One question at a time: while one is open, other such requests are refused.
@MainActor
enum AutomationCaptureConsent {
    static let answerTimeout: TimeInterval = 60
    private static var asking = false
    private static let log = Log("Automation")

    /// True when the user allowed the capture.
    static func ask(_ mode: AutomationCaptureMode, peer: IPCPeer?) -> Bool {
        guard !asking else {
            log.warn("[SECURITY] A command line capture was refused: another one waits for an answer")
            return false
        }
        asking = true
        defer { asking = false }
        let caller = callerName(peer: peer)
        let allowed = run(makeAlert(caller: caller, mode: mode))
        log.info("A command line capture of \(AutomationConsent.subject(of: mode)) by \(caller) was \(allowed ? "allowed" : "not allowed")")
        return allowed
    }

    /// RUN_RECIPE from greenshot-cli: "<program> asks Greenshot for Mac to run the recipe '<name>', which takes
    /// <subject>." The same rules as for CAPTURE.
    static func ask(recipe: String, subject: String, peer: IPCPeer?) -> Bool {
        guard !asking else {
            log.warn("[SECURITY] A command line recipe was refused: another question waits for an answer")
            return false
        }
        asking = true
        defer { asking = false }
        let caller = callerName(peer: peer)
        let alert = NSAlert()
        alert.alertStyle = .warning
        alert.messageText = "\(caller) asks \(AppInfo.name) to run the recipe \u{201C}\(recipe)\u{201D}, which takes \(subject)."
        alert.informativeText = "The request came through greenshot-cli. Allow it only if you started it: the recipe's result goes where the recipe sends it."
        alert.addButton(withTitle: "Don't Allow")
        alert.addButton(withTitle: "Allow")
        let allowed = run(alert)
        log.info("The command line recipe '\(recipe)' (\(subject)) by \(caller) was \(allowed ? "allowed" : "not allowed")")
        return allowed
    }

    /// Runs the alert with the arming delay and the time limit; true for Allow.
    private static func run(_ alert: NSAlert) -> Bool {
        alert.window.level = .floating
        let allow = alert.buttons[1]
        allow.isEnabled = false
        let enable = Timer(timeInterval: 1, repeats: false) { _ in
            MainActor.assumeIsolated { allow.isEnabled = true }
        }
        let expire = Timer(timeInterval: answerTimeout, repeats: false) { _ in
            MainActor.assumeIsolated { NSApp.abortModal() }
        }
        RunLoop.main.add(enable, forMode: .modalPanel)
        RunLoop.main.add(expire, forMode: .modalPanel)
        NSApp.activate()
        let response = alert.runModal()
        enable.invalidate()
        expire.invalidate()
        return response == .alertSecondButtonReturn
    }

    /// The alert (also for the snapshots).
    static func makeAlert(caller: String, mode: AutomationCaptureMode) -> NSAlert {
        let alert = NSAlert()
        alert.alertStyle = .warning
        alert.messageText = "\(caller) asks \(AppInfo.name) to take a screenshot of \(AutomationConsent.subject(of: mode))."
        alert.informativeText = "The request came through greenshot-cli. Allow it only if you started it: the screenshot goes to your destinations."
        alert.addButton(withTitle: "Don't Allow")
        alert.addButton(withTitle: "Allow")
        return alert
    }

    /// The program behind the request: the processes above the requester (greenshot-cli or a second start of the
    /// app, identified by the connection's audit token; for the command the app was started with, the app itself) up to
    /// the first app, e.g. "zsh in Terminal".
    static func callerName(peer: IPCPeer?) -> String {
        let requester = peer.map(processID(of:)) ?? getpid()
        var names: [String?] = []
        var appName: String?
        var current = parent(of: requester)
        for _ in 0..<6 {
            guard let pid = current, pid > 1 else { break }
            if let app = NSRunningApplication(processIdentifier: pid), let name = app.localizedName {
                if names.isEmpty { names.append(name) }
                appName = name
                break
            }
            names.append(executableName(of: pid))
            current = parent(of: pid)
        }
        return AutomationConsent.callerName(processNames: names, appName: appName)
    }

    /// The process id in the audit token (race-free), else the one of `LOCAL_PEERPID`.
    private static func processID(of peer: IPCPeer) -> pid_t {
        guard let token = peer.auditToken, token.count == MemoryLayout<audit_token_t>.size else { return peer.pid }
        let audit = token.withUnsafeBytes { $0.loadUnaligned(as: audit_token_t.self) }
        return pid_t(bitPattern: audit.val.5)
    }

    private static func parent(of pid: pid_t) -> pid_t? {
        var info = proc_bsdinfo()
        let size = Int32(MemoryLayout<proc_bsdinfo>.size)
        guard proc_pidinfo(pid, PROC_PIDTBSDINFO, 0, &info, size) == size else { return nil }
        return pid_t(info.pbi_ppid)
    }

    private static func executableName(of pid: pid_t) -> String? {
        var buffer = [CChar](repeating: 0, count: 4 * Int(MAXPATHLEN))
        guard proc_pidpath(pid, &buffer, UInt32(buffer.count)) > 0 else { return nil }
        return (String(cString: buffer) as NSString).lastPathComponent
    }
}
