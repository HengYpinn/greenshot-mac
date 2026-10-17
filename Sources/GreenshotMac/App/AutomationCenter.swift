// Greenshot for Mac (Community) - an unofficial macOS port of Greenshot
// Copyright (C) 2026 Greenshot for Mac (Community) contributors
// Based on Greenshot, Copyright (C) 2007-2026 Thomas Braun, Jens Klingen, Robin Krom
// SPDX-License-Identifier: GPL-3.0-or-later

import AppKit
import GreenshotCore

/// Everything that drives the app from outside (upstream `GreenshotShell`'s pipe server and `IpcSecurityDispatcher`):
/// the automation socket for greenshot-cli, `greenshotmac:` links, files from Finder, AppleScript, Services and
/// Shortcuts. They all go through one dispatcher with their own source, so the same whitelist, checks and log apply.
@MainActor
final class AutomationCenter {
    let dispatcher = IPCDispatcher()
    private weak var app: AppDelegate?
    private var server: IPCServer?
    private var ready = false
    private var pending: [(IPCEnvelope, IPCSource)] = []
    private var readyWaiters: [CheckedContinuation<Void, Never>] = []
    private var rebindTimer: Timer?
    private var sessionEnding = false
    private var captureLinkNoticeShown = false
    private let log = Log("Automation")

    /// Starts listening and runs what waited for the launch: requests that came before it, and the command the app was
    /// started with (upstream runs it "now that the pipe server listens").
    func start(app: AppDelegate) {
        self.app = app
        AutomationCommands.register(in: dispatcher.table, app: app)
        dispatcher.accessCheck = { [weak self] command, context in
            await self?.refusal(of: command, context: context)
        }
        startServer()
        NSWorkspace.shared.notificationCenter.addObserver(forName: NSWorkspace.willPowerOffNotification, object: nil,
                                                          queue: .main) { [weak self] _ in
            MainActor.assumeIsolated { self?.sessionEnding = true }
        }
        ready = true
        readyWaiters.forEach { $0.resume() }
        readyWaiters.removeAll()
        let waiting = pending
        pending.removeAll()
        waiting.forEach { submit($0.0, source: $0.1) }
        let command = AutomationStartup.startupCommand
        if !command.isEmpty {
            log.info("Running the command the app was started with")
            submit(.commandLine(command, cwd: FileManager.default.currentDirectoryPath), source: .cli)
        }
    }

    private func startServer() {
        guard AutomationStartup.instanceLock != nil else { return }
        var configuration = IPCServer.Configuration(socketPath: AutomationStartup.endpoint.socketPath)
        configuration.verifier = AutomationPeerVerifier.make(hostExecutable: IPCEndpoint.currentExecutablePath)
        let server = IPCServer(configuration: configuration, dispatcher: dispatcher)
        do {
            try server.start()
            self.server = server
        } catch {
            log.error("The automation socket couldn't be opened; greenshot-cli can't reach the app", error: error)
            return
        }
        // The system may clean the temporary folder of a long-running app
        let timer = Timer(timeInterval: 5 * 60, repeats: true) { [weak server] _ in server?.rebindIfNeeded() }
        timer.tolerance = 30
        RunLoop.main.add(timer, forMode: .common)
        rebindTimer = timer
    }

    /// Tells watching clients that the app quits and closes the socket (upstream: at most a second for the clients).
    func shutdown() {
        rebindTimer?.invalidate()
        guard let server else { return }
        server.notifyShutdown(reason: sessionEnding ? IPCServer.shutdownReasonSessionEnd : IPCServer.shutdownReasonExit, timeout: 1)
        server.stop()
        self.server = nil
    }

    /// Sends an event to the watching clients (wave 4: `tools_changed`).
    func broadcast(_ event: JSONObject) {
        server?.broadcast(event)
    }

    // MARK: The app's own callers

    /// Files and links LaunchServices hands to the app (`application(_:open:)`): files from Finder, the Dock or
    /// `open -a`, and `greenshotmac:` links. They may come before the app finished launching; then they wait.
    func open(_ urls: [URL]) {
        let files = urls.filter(\.isFileURL)
        if !files.isEmpty {
            var envelope = IPCEnvelope(command: IPCCommand.openFile)
            envelope.files = files.map(\.path)
            submit(envelope, source: .openWith)
        }
        for url in urls where !url.isFileURL {
            guard URLActionParser.isActionLink(url.absoluteString) else {
                log.warn("Ignored a link of another kind: \(url.scheme ?? "")")
                continue
            }
            var envelope = IPCEnvelope(command: IPCCommand.urlScheme)
            envelope.rawInput = url.absoluteString
            submit(envelope, source: .urlScheme)
        }
    }

    /// Dispatches a request of the app's own callers and returns its reply (AppleScript, Shortcuts, Services).
    func perform(_ envelope: IPCEnvelope, source: IPCSource) async -> IPCReply {
        // Shortcuts may start the app for an action: it waits for the launch
        if !ready { await withCheckedContinuation { readyWaiters.append($0) } }
        let context = IPCReplyContext(envelope: envelope, source: source)
        await dispatcher.dispatch(context)
        return context.finalReply ?? .ok()
    }

    private func submit(_ envelope: IPCEnvelope, source: IPCSource) {
        guard ready else {
            pending.append((envelope, source))
            return
        }
        Task { @MainActor in
            let reply = await perform(envelope, source: source)
            guard reply.isError else { return }
            log.warn("\(source.rawValue) request failed: \(reply.stderr ?? "")")
            if source == .openWith {
                // Finder users see what they saw before: which file can't be opened (the others open)
                ErrorPresenter.show(message: "The image could not be opened",
                                    detail: AutomationCommands.refusedFileNames(reply, files: envelope.files))
            }
        }
    }

    // MARK: Checks

    /// Capture links from web pages only with the setting on (Mac only; upstream gates browser-started recipes with
    /// `AllowBrowserInvocation`).
    private func refusal(of command: String, context: IPCReplyContext) -> String? {
        guard context.source == .urlScheme, IPCWhitelist.captureLinkCommands.contains(command),
              let app, !app.settings.value.automationAllowCaptureLinks else { return nil }
        log.warn("[SECURITY] A capture link was refused: capture links are off")
        if !captureLinkNoticeShown {
            captureLinkNoticeShown = true
            app.saver.notify("A link wanted to take a screenshot",
                             detail: "Capture links are off. Turn them on in Settings › Expert › Automation.") { [weak app] in
                app?.showSettings(pane: .expert)
            }
        }
        return "[SECURITY] Capture links are off: turn on \"Allow links to take screenshots\" in Settings › Expert."
    }
}
