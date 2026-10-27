// Greenshot for Mac (Community) - an unofficial macOS port of Greenshot
// Copyright (C) 2026 Greenshot for Mac (Community) contributors
// SPDX-License-Identifier: GPL-3.0-or-later

import AppKit
import Darwin
import GreenshotCore

/// The question before a capture greenshot-cli or a link asks for without the user on the capture screen (see
/// `AutomationConsent`): "<program> asks Greenshot for Mac to take a screenshot of the whole screen." Don't Allow is the
/// default (Return); Allow takes no keyboard focus, so only a click answers Allow, and it reacts only after a second, so
/// a click meant for something else doesn't answer it; without an answer it counts as Don't Allow after a minute, once
/// no other modal window of the app is on top of it.
/// Another program can't click it without the Accessibility permission. One question at a time: while one is open,
/// other such requests are refused.
@MainActor
enum AutomationCaptureConsent {
    static let answerTimeout: TimeInterval = 60
    private static var asking = false
    private static let log = Log("Automation")

    /// True when the user allowed the capture. greenshot-cli's question names the program behind it; a link's says
    /// "A link": Greenshot doesn't know which program or page opened it.
    static func ask(_ mode: AutomationCaptureMode, source: IPCSource, peer: IPCPeer?) -> Bool {
        let request = source == .urlScheme ? "link" : "command line"
        guard !asking else {
            log.warn("[SECURITY] A \(request) capture was refused: another one waits for an answer")
            return false
        }
        asking = true
        defer { asking = false }
        let caller = source == .urlScheme ? linkCaller : callerName(peer: peer)
        let allowed = run(makeAlert(caller: caller, mode: mode, source: source))
        log.info("A \(request) capture of \(AutomationConsent.subject(of: mode)) by \(caller) was \(allowed ? "allowed" : "not allowed")")
        return allowed
    }

    /// The program in a link's question.
    static var linkCaller: String {
        String(localized: "A link", comment: "Starts the sentence of a capture question when a greenshotmac:// link asks for the capture")
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
        alert.messageText = recipeQuestion(caller: caller, recipe: recipe, subject: subject)
        alert.informativeText = String(localized: "The request came through greenshot-cli. Allow it only if you started it: the recipe's result goes where the recipe sends it.")
        alert.addButton(withTitle: String(localized: "Don't Allow"))
        alert.addButton(withTitle: String(localized: "Allow"))
        let allowed = run(alert)
        log.info("The command line recipe '\(recipe)' (\(subject)) by \(caller) was \(allowed ? "allowed" : "not allowed")")
        return allowed
    }

    /// Runs the alert with the arming delay and the time limit; true for Allow. "Allow" answers only a click: it takes
    /// no keyboard focus, so with keyboard navigation on, Tab and Space (in text typed into another app a moment
    /// earlier) can't press it. It reacts a second after the alert was last shown unchanged and only when no other
    /// program's window lies over it (`ConsentArming`, SM-M2). Also for the question before a Jira or Confluence token
    /// goes to a server (`AtlassianSecretQuestion`).
    static func run(_ alert: NSAlert) -> Bool {
        alert.window.level = .floating
        // A link or greenshot-cli asks from whatever Space the user is on, also a full screen one, and the question
        // blocks every Greenshot window: it shows on that Space instead of out of sight on another one.
        alert.window.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary]
        let allow = alert.buttons[1]
        // Only a click answers Allow; Return stays Don't Allow's. NSAlert puts the keyboard focus on its second button
        // (Space would press Allow), so the focus starts on Don't Allow, and Tab skips Allow.
        allow.refusesFirstResponder = true
        alert.layout()
        alert.window.initialFirstResponder = alert.buttons[0]
        let arming = ConsentArming(window: alert.window, buttons: [allow])
        let handler = AllowHandler(arming: arming)
        allow.target = handler
        allow.action = #selector(AllowHandler.allow(_:))
        // Only this alert's own session ends: while another modal window of the app is on top of it, that one is the
        // innermost modal session, which `abortModal` would end instead; this one ends once it is on top again.
        let deadline = Date().addingTimeInterval(answerTimeout)
        let own = ObjectIdentifier(alert.window)
        let expire = Timer(timeInterval: 0.5, repeats: true) { _ in
            MainActor.assumeIsolated {
                guard Date() >= deadline, let modal = NSApp.modalWindow, ObjectIdentifier(modal) == own else { return }
                NSApp.abortModal()
            }
        }
        RunLoop.main.add(expire, forMode: .modalPanel)
        NSApp.activate()
        arming.start()
        let response = withExtendedLifetime(handler) { alert.runModal() }
        arming.stop()
        expire.invalidate()
        return response == .alertSecondButtonReturn
    }

    /// "Allow" of the alert: ends it only when the click counts.
    private final class AllowHandler: NSObject {
        let arming: ConsentArming

        init(arming: ConsentArming) {
            self.arming = arming
        }

        @objc func allow(_ sender: Any?) {
            MainActor.assumeIsolated {
                // Should the focus reach Allow after all, a key still doesn't answer it
                if let event = NSApp.currentEvent, event.type == .keyDown || event.type == .keyUp {
                    Log("Automation").warn("[SECURITY] A key on Allow was ignored: only a click answers it.")
                    return
                }
                if arming.confirmAllow() { NSApp.stopModal(withCode: .alertSecondButtonReturn) }
            }
        }
    }

    /// The alert (also for the snapshots).
    static func makeAlert(caller: String, mode: AutomationCaptureMode, source: IPCSource) -> NSAlert {
        let alert = NSAlert()
        alert.alertStyle = .warning
        alert.messageText = captureQuestion(caller: caller, mode: mode)
        alert.informativeText = source == .urlScheme
            ? String(localized: "The request came through a greenshotmac:// link, which any program or web page can open. Allow it only if you opened it: the screenshot goes to your destinations.")
            : String(localized: "The request came through greenshot-cli. Allow it only if you started it: the screenshot goes to your destinations.")
        alert.addButton(withTitle: String(localized: "Don't Allow"))
        alert.addButton(withTitle: String(localized: "Allow"))
        return alert
    }

    /// "<program> asks Greenshot for Mac to take a screenshot of the whole screen.", a sentence per mode
    /// (`AutomationConsent.subject(of:)` words the same in English, for the log).
    private static func captureQuestion(caller: String, mode: AutomationCaptureMode) -> String {
        let app = AppInfo.name
        switch mode {
        case .region: return String(localized: "\(caller) asks \(app) to take a screenshot of a region.")
        case .window: return String(localized: "\(caller) asks \(app) to take a screenshot of a window.")
        case .fullScreen: return String(localized: "\(caller) asks \(app) to take a screenshot of the whole screen.")
        case .lastRegion: return String(localized: "\(caller) asks \(app) to take a screenshot of the last captured region.")
        case .text: return String(localized: "\(caller) asks \(app) to take a screenshot of the text in a region.")
        }
    }

    /// "<program> asks Greenshot for Mac to run the recipe “<name>”, which takes a screenshot of the whole screen.", a
    /// sentence per subject. The subjects come in English from Core (`AutomationConsent.recipeCaptureSubject`,
    /// `RecipeCaptureConsent`), where they are also compared; an unknown one is shown as it is.
    private static func recipeQuestion(caller: String, recipe: String, subject: String) -> String {
        let app = AppInfo.name
        switch subject {
        case "a screen recording":
            return String(localized: "\(caller) asks \(app) to run the recipe \u{201C}\(recipe)\u{201D}, which takes a screen recording.")
        case "a screenshot of the whole screen":
            return String(localized: "\(caller) asks \(app) to run the recipe \u{201C}\(recipe)\u{201D}, which takes a screenshot of the whole screen.")
        case "a screenshot of the active window":
            return String(localized: "\(caller) asks \(app) to run the recipe \u{201C}\(recipe)\u{201D}, which takes a screenshot of the active window.")
        case "a screenshot of the last captured region":
            return String(localized: "\(caller) asks \(app) to run the recipe \u{201C}\(recipe)\u{201D}, which takes a screenshot of the last captured region.")
        case "a screenshot of a window":
            return String(localized: "\(caller) asks \(app) to run the recipe \u{201C}\(recipe)\u{201D}, which takes a screenshot of a window.")
        case "a screenshot of a region":
            return String(localized: "\(caller) asks \(app) to run the recipe \u{201C}\(recipe)\u{201D}, which takes a screenshot of a region.")
        default:
            return String(localized: "\(caller) asks \(app) to run the recipe \u{201C}\(recipe)\u{201D}, which takes \(subject).")
        }
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
