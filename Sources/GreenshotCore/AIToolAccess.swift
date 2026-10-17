// Greenshot for Mac (Community) - an unofficial macOS port of Greenshot
// Copyright (C) 2026 Greenshot for Mac (Community) contributors
// Based on Greenshot, Copyright (C) 2007-2026 Thomas Braun, Jens Klingen, Robin Krom
// SPDX-License-Identifier: GPL-3.0-or-later

import Foundation

/// The program that uses Greenshot through greenshot-mcp (Claude, VS Code, Cursor, ...), identified by the app itself
/// (upstream `AiToolClient`), never by what the connection says.
public struct AIToolClient: Sendable, Equatable {
    /// The program's executable: what the user allows (`AIToolsSettings.allowedClients`).
    public var path: String
    /// Its name for people, e.g. "Claude" or "Claude (disclaimer)" for a helper of an app.
    public var displayName: String
    /// Who signed it ("Developer ID Application: …"), nil when it isn't signed by a developer.
    public var signer: String?
    /// greenshot-mcp's process and when it started: one MCP session of the AI tool (window ids belong to it).
    public var serverProcessID: Int32
    public var serverStartTime: UInt64

    public init(path: String, displayName: String, signer: String? = nil, serverProcessID: Int32 = 0, serverStartTime: UInt64 = 0) {
        self.path = path
        self.displayName = displayName
        self.signer = signer
        self.serverProcessID = serverProcessID
        self.serverStartTime = serverStartTime
    }

    /// The scope of its window ids: this greenshot-mcp process and this program.
    public var scopeKey: String { "\(serverProcessID):\(serverStartTime)|\(path.lowercased())" }

    public var signerText: String { signer.map { "Signed by: \($0)" } ?? "This program is not signed by a developer." }

    /// For the log and the approval sheet: "Claude (/Applications/Claude.app/Contents/MacOS/Claude)".
    public var logText: String { "\(displayName) (\(path))" }
}

/// Who may do what (upstream `AiToolsIpcExtension.CheckAccessAsync`, `AiToolAccess`): AI tools are opt-in; the AI tool
/// commands are only for greenshot-mcp; everything greenshot-mcp asks for, except its version and the names of its tools,
/// needs the user's consent for the program behind it.
public enum AIToolAccess {
    public static let notAllowedMessage = "The user did not allow this program to use Greenshot for Mac. It doesn't ask again until it is restarted; the user can allow it in Settings › AI Tools (\"Allow\" or \"Ask Again\")."
    public static let disabledMessage = "AI tools are switched off in Greenshot for Mac. To use it from an AI tool, switch on \"Let AI tools use Greenshot\" in Settings › AI Tools."
    public static let proposalsDisabledMessage = "The user switched off recipe proposals by AI tools in Greenshot for Mac (Settings › AI Tools)."
    public static let managedMessage = "Your administrator decides which AI tools may use Greenshot for Mac; this program isn't one of them."
    public static let unidentifiedMessage = "Greenshot for Mac could not identify the program which started greenshot-mcp."

    /// Upstream `GetAiToolsOptInError`: why a request of greenshot-mcp is refused by the switches, nil when it isn't.
    /// While AI tools are off only the version check answers, so the AI tool can tell the user how to switch them on.
    public static func optInRefusal(command: String, source: IPCSource, settings: AIToolsSettings) -> String? {
        guard source == .mcp else { return nil }
        let name = command.uppercased()
        guard settings.enabled else { return name == IPCCommand.version ? nil : disabledMessage }
        if name == IPCCommand.proposeRecipe, !settings.allowRecipeProposals { return proposalsDisabledMessage }
        return nil
    }

    /// Upstream `RequiresAiToolConsent`: every command of greenshot-mcp except VERSION and LIST_AI_TOOLS (names and
    /// descriptions only, so the AI tool can show its tools before the user is asked), and the AI tool commands from any
    /// source (the whitelist keeps them to greenshot-mcp anyway).
    public static func requiresConsent(command: String, source: IPCSource) -> Bool {
        let name = command.uppercased()
        if name == IPCCommand.version || name == IPCCommand.listAITools { return false }
        return IPCCommand.aiToolCommands.contains(name) || source == .mcp
    }

    /// Upstream `IsAllowed`: the program's path is in the allowed list (case doesn't matter).
    public static func isAllowed(_ client: AIToolClient, settings: AIToolsSettings) -> Bool {
        let path = client.path.trimmingCharacters(in: .whitespaces)
        guard !path.isEmpty else { return false }
        return settings.allowedClients.contains { $0.trimmingCharacters(in: .whitespaces).caseInsensitiveCompare(path) == .orderedSame }
    }

    /// Upstream `NotifyCapture`'s text.
    public static func captureNotice(client: String?, what: String) -> String {
        let name = client.flatMap { $0.trimmingCharacters(in: .whitespaces).isEmpty ? nil : $0.trimmingCharacters(in: .whitespaces) }
        return "\(name ?? "An AI tool") captured \(what) with Greenshot."
    }
}

/// The user's answers in this run of the app (upstream `AiToolAccess.EnsureAllowedAsync`, `DeniedClients`): asked once per
/// program, one question at a time; "Don't Allow" is remembered until the app quits or the user clicks "Ask Again".
@MainActor
public final class AIToolConsent {
    /// Shows the question; true = Allow.
    public typealias Prompt = @MainActor (AIToolClient) async -> Bool

    private var denied: [String: String] = [:]
    private var busy = false
    private var waiters: [CheckedContinuation<Void, Never>] = []

    public init() {}

    /// The programs answered with "Don't Allow" in this run, by path.
    public var deniedClients: [String] { denied.values.sorted { $0.localizedStandardCompare($1) == .orderedAscending } }

    public func isDenied(_ path: String) -> Bool { denied[path.lowercased()] != nil }

    /// "Ask Again" (and "Allow" in the settings): the next request asks again, or passes when it is allowed meanwhile.
    public func forgetDenied(_ path: String) {
        denied.removeValue(forKey: path.lowercased())
    }

    /// True when the program may use Greenshot. `settings` is read again after waiting for another question; `managed`:
    /// an administrator manages the allowed list, so nobody is asked; `allow` adds the program to the list.
    public func ensureAllowed(_ client: AIToolClient?, settings: () -> AIToolsSettings, managed: Bool, prompt: Prompt,
                              allow: @MainActor (String) -> Void) async -> Bool {
        guard let client, !client.path.isEmpty else { return false }
        if AIToolAccess.isAllowed(client, settings: settings()) { return true }
        if managed { return false }
        await acquire()
        defer { release() }
        // Another request may have been answered while this one waited
        if AIToolAccess.isAllowed(client, settings: settings()) { return true }
        if isDenied(client.path) { return false }
        guard await prompt(client) else {
            denied[client.path.lowercased()] = client.path
            log.info("The user did not allow \(client.logText) to use Greenshot.")
            return false
        }
        allow(client.path)
        log.info("The user allowed \(client.logText) to use Greenshot.")
        return true
    }

    private func acquire() async {
        guard busy else {
            busy = true
            return
        }
        await withCheckedContinuation { waiters.append($0) }
    }

    private func release() {
        if waiters.isEmpty {
            busy = false
        } else {
            waiters.removeFirst().resume()
        }
    }
}

/// Why an AI tool's request can't be served, in words for the AI tool.
public struct AIToolError: Error, Equatable, Sendable {
    public var message: String

    public init(_ message: String) {
        self.message = message
    }
}

private let log = Log("AITools")
