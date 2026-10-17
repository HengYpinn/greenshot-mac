// Greenshot for Mac (Community) - an unofficial macOS port of Greenshot
// Copyright (C) 2026 Greenshot for Mac (Community) contributors
// Based on Greenshot, Copyright (C) 2007-2026 Thomas Braun, Jens Klingen, Robin Krom
// SPDX-License-Identifier: GPL-3.0-or-later

import AppKit
import GreenshotCore

/// The handlers of the automation commands (upstream `IpcSecurityDispatcher.Handle*Async`). Requests arrive off the
/// main thread; every handler runs on it. The replies use upstream's texts.
@MainActor
enum AutomationCommands {
    static var appVersion: String {
        Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? "development build"
    }

    static func register(in table: IPCCommandTable, app: AppDelegate) {
        func on(_ command: String, _ body: @escaping @MainActor @Sendable (AppDelegate, IPCReplyContext) -> IPCReply?) {
            // The app delegate lives as long as the process
            table.register(command) { [app] context in
                await MainActor.run { body(app, context) }
            }
        }

        on(IPCCommand.version) { _, _ in version() }
        on(IPCCommand.settings) { settings($0, $1) }
        on(IPCCommand.about) { app, _ in
            app.showAbout(nil)
            return .ok("About window displayed.")
        }
        on(IPCCommand.selfService) { app, context in
            app.showSelfService(section: context.envelope.parameter("section").flatMap(SelfServiceSection.init(name:)))
            return .ok("Self-Service window displayed.")
        }
        on(IPCCommand.logViewer) { app, context in
            app.showLogViewer(search: context.envelope.parameter("search"))
            return .ok("Log viewer displayed.")
        }
        on(IPCCommand.firstLaunch) { app, _ in
            app.showWelcome()
            return .ok("First launch completed.")
        }
        on(IPCCommand.openFile) { openFiles($0, $1) }
        on(IPCCommand.reloadConfig) { app, _ in
            // Upstream ReloadConfig: read the configuration again and register the hotkeys again
            app.settings.reloadFromDisk()
            app.reregisterHotkeys()
            return .ok("Greenshot configuration reloaded.")
        }
        on(IPCCommand.exit) { _, _ in
            // The reply goes out first; quitting may still ask about unsaved screenshots
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.1) { NSApp.terminate(nil) }
            return .ok("Greenshot exiting.")
        }
        on(IPCCommand.capture) { capture($0, $1) }
        on(IPCCommand.openClipboard) { app, _ in
            DispatchQueue.main.async { app.editors.openClipboard() }
            return .ok("Opening the clipboard in the editor.")
        }
        // Wave 4: a recipe started by greenshot-cli or a link that captures without the user on the capture screen must
        // ask first, like CAPTURE does (`AutomationConsent`, `AutomationCaptureConsent`).
        table.registerUnavailable([IPCCommand.runRecipe, IPCCommand.listRecipes, IPCCommand.describeRecipe,
                                   IPCCommand.recipeEditor, IPCCommand.recipeManager],
                                  message: IPCCommandLine.recipesUnavailable)
    }

    /// Upstream `HandleVersionAsync`.
    static func version() -> IPCReply {
        let build = Bundle.main.object(forInfoDictionaryKey: "CFBundleVersion") as? String ?? "0"
        return .ok("\(AppInfo.name) version \(appVersion)",
                   extra: ["version": .string(appVersion), "build": .string(build),
                           "protocol_version": .number(Double(ipcProtocolVersion))])
    }

    /// Upstream `HandleSettingsAsync` (`ShowSetting(plugin, tab)`).
    private static func settings(_ app: AppDelegate, _ context: IPCReplyContext) -> IPCReply {
        let pane = AutomationLinks.settingsPane(tab: context.envelope.parameter("tab"), plugin: context.envelope.parameter("plugin"))
        app.showSettings(pane: pane)
        return .ok("Settings window displayed.")
    }

    /// Upstream `HandleOpenFileAsync`: the paths are checked, then the files open in the editor. greenshot-cli,
    /// AppleScript and Shortcuts: one refused path refuses the request. Finder, the Dock and the Services menu: the
    /// files that pass open, an image the editor reads passes whatever its extension, and the reply names the refused
    /// ones (`refused`). Wave 4 runs the recipes of OpenFile triggers here.
    private static func openFiles(_ app: AppDelegate, _ context: IPCReplyContext) -> IPCReply {
        let raw = context.envelope.files
        guard !raw.isEmpty else { return .error("OPEN_FILE rejected: No file path provided.") }
        let lenient = context.source == .openWith || context.source == .services
        let batch = IPCPathValidator.resolve(raw, cwd: context.envelope.cwd, allowedExtensions: IPCPathValidator.editorImageExtensions,
                                             lenient: lenient)
        for refusal in batch.refused {
            Log("Automation").warn("[SECURITY] OPEN_FILE rejected '\(DiagnosticReport.abbreviatingHome(refusal.path))': \(refusal.message)")
        }
        batch.accepted.forEach(app.editors.open(fileURL:))
        if !lenient, let refusal = batch.refused.first { return .error("OPEN_FILE rejected: \(refusal.message)") }
        guard !batch.refused.isEmpty else { return .ok("Opened \(batch.accepted.count) file(s).") }
        let stderr = batch.refused.map { "OPEN_FILE rejected '\($0.path)': \($0.message)" }.joined(separator: "\n")
        return IPCReply(status: "error", exitCode: IPCExitCode.failure, stdout: "Opened \(batch.accepted.count) file(s).",
                        stderr: stderr, extra: ["refused": .array(batch.refused.map { .string($0.path) })])
    }

    /// The names of the files a lenient OPEN_FILE refused, for the alert; all of the request's files when the reply
    /// doesn't say.
    static func refusedFileNames(_ reply: IPCReply, files: [String]) -> String {
        let refused = reply.extra["refused"]?.arrayValue?.compactMap(\.stringValue) ?? files
        return refused.map { ($0 as NSString).lastPathComponent }.joined(separator: ", ")
    }

    /// The Mac's CAPTURE: the hotkeys' captures, started after the reply went out. From the command line, a capture
    /// without the user on the capture screen asks first (`AutomationConsent`): any program could run greenshot-cli.
    private static func capture(_ app: AppDelegate, _ context: IPCReplyContext) -> IPCReply {
        let mode: AutomationCaptureMode
        if let name = context.envelope.parameter("mode"), !name.isEmpty {
            guard let named = AutomationCaptureMode(name: name) else {
                return .error("Unknown capture mode '\(name)'. Use \(AutomationCaptureMode.namesForHelp).")
            }
            mode = named
        } else {
            mode = .region
        }
        if AutomationConsent.captureNeedsConfirmation(mode, source: context.source),
           !AutomationCaptureConsent.ask(mode, peer: context.peer) {
            return .error("The screenshot wasn't taken: it wasn't allowed.")
        }
        DispatchQueue.main.async {
            switch mode {
            case .region: app.capture.captureRegion()
            case .window: app.capture.captureWindowFromHotkey()
            case .fullScreen: app.capture.captureFullScreenFromHotkey()
            case .lastRegion: app.capture.captureLastRegion()
            case .text: app.capture.captureText()
            }
        }
        return .ok("Capture started.")
    }
}
