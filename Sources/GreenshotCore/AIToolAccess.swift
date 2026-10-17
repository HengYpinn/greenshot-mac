// Greenshot for Mac (Community) - an unofficial macOS port of Greenshot
// Copyright (C) 2026 Greenshot for Mac (Community) contributors
// Based on Greenshot, Copyright (C) 2007-2026 Thomas Braun, Jens Klingen, Robin Krom
// SPDX-License-Identifier: GPL-3.0-or-later

import Foundation

/// The program that uses Greenshot through greenshot-mcp (Claude, VS Code, Cursor, ...), identified by the app itself
/// (upstream `AiToolClient`), never by what the connection says.
public struct AIToolClient: Sendable, Equatable {
    /// The program's executable.
    public var path: String
    /// What the user allows: the executable, and for a runtime (node, python, ...) its script (`AIToolIdentity`).
    public var identity: AIToolIdentity
    /// Its name for people, e.g. "Claude" or "Claude (disclaimer)" for a helper of an app.
    public var displayName: String
    /// Who signed the running program ("Developer ID Application: …"), nil when it isn't signed by a developer.
    public var signer: String?
    /// The developer's Team ID of the running program's signature; kept with an allowed program.
    public var teamID: String?
    /// greenshot-mcp's process and when it started: one MCP session of the AI tool (window ids belong to it).
    public var serverProcessID: Int32
    public var serverStartTime: UInt64

    public init(path: String, displayName: String, signer: String? = nil, teamID: String? = nil, identity: AIToolIdentity? = nil,
                serverProcessID: Int32 = 0, serverStartTime: UInt64 = 0) {
        self.path = path
        self.identity = identity ?? AIToolIdentity(executable: path)
        self.displayName = displayName
        self.signer = signer
        self.teamID = teamID
        self.serverProcessID = serverProcessID
        self.serverStartTime = serverStartTime
    }

    /// The identity text kept in the allowed list (without the Team ID).
    public var key: String { identity.key }

    /// The line the allowed list gets when the user allows it: the identity and the Team ID of its signature.
    public var allowedEntry: AIToolAllowedEntry { AIToolAllowedEntry(key: key, teamID: teamID) }

    /// The scope of its window ids: this greenshot-mcp process and this program.
    public var scopeKey: String { "\(serverProcessID):\(serverStartTime)|\(key.lowercased())" }

    public var signerText: String {
        signer.map { String(localized: "Signed by: \(AIToolText.displayed($0, limit: 120))") }
            ?? String(localized: "This program is not signed by a developer.")
    }

    /// For the log: "Claude (/Applications/Claude.app/Contents/MacOS/Claude)".
    public var logText: String { "\(displayName) (\(key))" }
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

    /// Upstream `IsAllowed`: the program is in the allowed list (`AIToolAllowedEntry.matches`: its identity, any case, and
    /// the Team ID when the entry has one).
    public static func isAllowed(_ client: AIToolClient, settings: AIToolsSettings) -> Bool {
        guard !client.path.trimmingCharacters(in: .whitespaces).isEmpty else { return false }
        return settings.allowedClients.contains { AIToolAllowedEntry(parsing: $0).matches(client) }
    }

    /// The allowed list with `client` in it: an entry for the same identity (another Team ID, a plain path) is replaced.
    public static func allowing(_ client: AIToolClient, in list: [String]) -> [String] {
        var result = list.filter { AIToolAllowedEntry(parsing: $0).key.caseInsensitiveCompare(client.key) != .orderedSame }
        result.append(client.allowedEntry.line)
        return result
    }

    /// Upstream `NotifyCapture`'s text.
    public static func captureNotice(client: String?, what: String) -> String {
        let name = client.flatMap { $0.trimmingCharacters(in: .whitespaces).isEmpty ? nil : $0.trimmingCharacters(in: .whitespaces) }
        guard let name else { return String(localized: "An AI tool captured \(what) with Greenshot.") }
        return String(localized: "\(name) captured \(what) with Greenshot.")
    }
}

/// The user's answers in this run of the app (upstream `AiToolAccess.EnsureAllowedAsync`, `DeniedClients`): asked once per
/// program, one question at a time; "Don't Allow" is remembered until the app quits or the user clicks "Ask Again". Mac
/// addition (security review): at most `promptLimit` questions in `promptWindow` seconds, so a program copying itself to
/// new paths can't fill the screen with questions.
@MainActor
public final class AIToolConsent {
    /// Shows the question; true = Allow.
    public typealias Prompt = @MainActor (AIToolClient) async -> Bool

    public static let promptLimit = 3
    public static let promptWindow: TimeInterval = 60
    public static let tooManyMessage = "Too many programs asked to use Greenshot for Mac in a short time, so it doesn't ask for a minute. Try again later."

    private var denied: [String: AIToolClient] = [:]
    private var busy = false
    private var waiters: [CheckedContinuation<Void, Never>] = []
    private var promptTimes: [Date] = []
    private let now: () -> Date

    public init(now: @escaping () -> Date = { Date() }) {
        self.now = now
    }

    /// The programs answered with "Don't Allow" in this run.
    public var deniedClients: [AIToolClient] {
        denied.values.sorted { $0.key.localizedStandardCompare($1.key) == .orderedAscending }
    }

    public func isDenied(_ key: String) -> Bool { denied[key.lowercased()] != nil }

    /// "Ask Again" (and "Allow" in the settings): the next request asks again, or passes when it is allowed meanwhile.
    public func forgetDenied(_ key: String) {
        denied.removeValue(forKey: key.lowercased())
    }

    /// Nil when the program may use Greenshot, else the message for the AI tool. `settings` is read again after waiting
    /// for another question; `managed`: an administrator manages the allowed list, so nobody is asked; `allow` adds the
    /// program to the list.
    public func ensureAllowed(_ client: AIToolClient?, settings: @MainActor () -> AIToolsSettings, managed: Bool, prompt: Prompt,
                              allow: @MainActor (AIToolClient) -> Void) async -> String? {
        guard let client, !client.path.isEmpty else { return AIToolAccess.unidentifiedMessage }
        if AIToolAccess.isAllowed(client, settings: settings()) { return nil }
        if managed { return AIToolAccess.managedMessage }
        await acquire()
        defer { release() }
        // Another request may have been answered while this one waited
        if AIToolAccess.isAllowed(client, settings: settings()) { return nil }
        if isDenied(client.key) { return AIToolAccess.notAllowedMessage }
        let time = now()
        promptTimes = promptTimes.filter { time.timeIntervalSince($0) < Self.promptWindow }
        guard promptTimes.count < Self.promptLimit else {
            log.warn("[SECURITY] Not asking about \(client.logText): too many questions in a short time.")
            return Self.tooManyMessage
        }
        promptTimes.append(time)
        guard await prompt(client) else {
            denied[client.key.lowercased()] = client
            log.info("The user did not allow \(client.logText) to use Greenshot.")
            return AIToolAccess.notAllowedMessage
        }
        allow(client)
        log.info("The user allowed \(client.logText) to use Greenshot.")
        return nil
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
