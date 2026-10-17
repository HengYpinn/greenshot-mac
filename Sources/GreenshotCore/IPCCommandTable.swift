// Greenshot for Mac (Community) - an unofficial macOS port of Greenshot
// Copyright (C) 2026 Greenshot for Mac (Community) contributors
// Based on Greenshot, Copyright (C) 2007-2026 Thomas Braun, Jens Klingen, Robin Krom
// SPDX-License-Identifier: GPL-3.0-or-later

import Foundation

/// Which sources may use which command (upstream `IpcSecurityDispatcher.AllowedCommands` and `SourceAllowedCommands`).
/// `cli` may use every command, like upstream. Anything a web page can reach (`url_scheme`) only shows windows or, with
/// the capture-link setting, starts a capture; it never quits, reloads or opens a file (docs §3.1, §3.2 "URL Scheme
/// Local File Block").
public enum IPCWhitelist {
    public static let standard: [String: Set<IPCSource>] = [
        IPCCommand.cli: [.cli],
        IPCCommand.urlScheme: [.cli, .urlScheme],
        IPCCommand.openFile: [.cli, .openWith, .appleScript, .shortcuts, .services],
        IPCCommand.exit: [.cli],
        IPCCommand.reloadConfig: [.cli, .appleScript],
        IPCCommand.firstLaunch: [.cli],
        // greenshot-mcp's version check also works while AI tools are switched off
        IPCCommand.version: [.cli, .mcp],
        IPCCommand.settings: [.cli, .urlScheme, .appleScript],
        IPCCommand.about: [.cli, .urlScheme, .appleScript],
        IPCCommand.selfService: [.cli, .urlScheme],
        IPCCommand.logViewer: [.cli, .urlScheme],
        IPCCommand.capture: [.cli, .urlScheme, .appleScript, .shortcuts],
        IPCCommand.openClipboard: [.cli, .urlScheme, .appleScript, .shortcuts],
        IPCCommand.runRecipe: [.cli, .urlScheme],
        IPCCommand.recipeEditor: [.cli, .urlScheme],
        IPCCommand.recipeManager: [.cli, .urlScheme],
        IPCCommand.listRecipes: [.cli],
        IPCCommand.describeRecipe: [.cli],
        // AI tools: greenshot-mcp only, never the command line, a web page or the browser extension (docs/mcp-server.md
        // "Safety"); AI tools can't run command line recipes (no RUN_RECIPE for mcp).
        IPCCommand.listWindows: [.mcp],
        IPCCommand.listAITools: [.mcp],
        IPCCommand.runAITool: [.mcp],
        IPCCommand.recipeCatalog: [.mcp],
        IPCCommand.validateRecipe: [.mcp],
        IPCCommand.proposeRecipe: [.mcp],
    ]

    /// Commands a link from a web page may only run with the capture-link setting on (Mac only).
    public static let captureLinkCommands: Set<String> = [IPCCommand.capture, IPCCommand.openClipboard]
}

/// A command's handler: returns the final reply, or nil when it replied itself (or has nothing to say). A thrown error
/// becomes the reply "Error: Greenshot failed to handle the command: ...".
public typealias IPCHandler = @Sendable (IPCReplyContext) async throws -> IPCReply?

/// The commands the app handles, each with the sources allowed to use it. Wave 4 registers the recipe, browser
/// extension and MCP commands here (with their sources) in place of the "not available" entries.
public final class IPCCommandTable: @unchecked Sendable {
    private struct Entry {
        var sources: Set<IPCSource>
        var handler: IPCHandler
    }

    private let lock = NSLock()
    private var entries: [String: Entry] = [:]

    public init() {}

    /// Registers (or replaces) a command. Without `sources`, those of `IPCWhitelist.standard`, else only `cli`.
    public func register(_ command: String, sources: Set<IPCSource>? = nil, handler: @escaping IPCHandler) {
        let key = command.uppercased()
        let allowed = sources ?? IPCWhitelist.standard[key] ?? [.cli]
        lock.lock()
        entries[key] = Entry(sources: allowed, handler: handler)
        lock.unlock()
    }

    /// Commands that exist upstream but not yet here: they answer `message` (exit code 1).
    public func registerUnavailable(_ commands: [String], message: String) {
        for command in commands {
            register(command) { _ in .error(message) }
        }
    }

    public var commands: [String] {
        lock.lock()
        defer { lock.unlock() }
        return entries.keys.sorted()
    }

    /// The sources allowed to use the command; nil for an unknown command.
    public func sources(for command: String) -> Set<IPCSource>? {
        lock.lock()
        defer { lock.unlock() }
        return entries[command.uppercased()]?.sources
    }

    /// Upstream `IsCommandAllowedForSource`: a known command, and the source in its list.
    public func isAllowed(_ command: String, for source: IPCSource) -> Bool {
        sources(for: command)?.contains(source) ?? false
    }

    func handler(for command: String) -> IPCHandler? {
        lock.lock()
        defer { lock.unlock() }
        return entries[command.uppercased()]?.handler
    }
}

/// Checks and runs a request (upstream `IpcSecurityDispatcher.DispatchAsync`): a link is turned into its command, the
/// command must be in the whitelist of the source, the access check may veto it, then its handler runs. A command line
/// (`CLI`) is parsed for its source and dispatched again with the same reply.
public final class IPCDispatcher: @unchecked Sendable {
    public let table: IPCCommandTable
    /// After the whitelist: the error for the caller when the command may not run now (e.g. capture links switched off),
    /// nil to go ahead (upstream `IIpcCommandExtension.CheckAccessAsync`). Set once while the app starts.
    public var accessCheck: (@Sendable (String, IPCReplyContext) async -> String?)?
    private let log = Log("IPC")

    public init(table: IPCCommandTable = IPCCommandTable()) {
        self.table = table
        // Handled here; registered so the whitelist knows them.
        table.register(IPCCommand.cli) { _ in nil }
        table.register(IPCCommand.urlScheme) { _ in nil }
    }

    public func dispatch(_ request: IPCReplyContext) async {
        var context = request
        var command = context.envelope.command?.trimmingCharacters(in: .whitespaces)

        // A link (CliCommandParser creates URL_SCHEME for it) names the command it runs
        if command?.uppercased() == IPCCommand.urlScheme, let link = context.envelope.rawInput {
            switch URLActionParser.parse(link) {
            case .ignored:
                log.debug("Ignored a sign-in link that no sign-in waited for.")
                context.reply(.ok())
                return
            case .invalid:
                command = nil
            case .command(let name, let parameters):
                var envelope = context.envelope
                envelope.command = name
                for key in parameters.keys.sorted() { envelope.setParameter(key, parameters[key] ?? "") }
                context = context.with(envelope: envelope)
                command = name
            }
        }

        guard let command, !command.isEmpty else {
            log.warn("IPC message dropped: Missing command.")
            context.reply(.error("Missing command."))
            return
        }
        let name = command.uppercased()
        guard table.isAllowed(name, for: context.source) else {
            let message = "[SECURITY] IPC command rejected: '\(command)' is not in the allowed command whitelist for source '\(context.source.rawValue)'."
            log.warn(message)
            context.reply(.error(message))
            return
        }
        if let accessCheck, let refusal = await accessCheck(name, context) {
            context.reply(.error(refusal))
            return
        }
        log.info("Processing whitelisted IPC command: '\(name)' from source '\(context.source.rawValue)'")

        if name == IPCCommand.cli {
            await dispatchCommandLine(context)
            return
        }
        guard let handler = table.handler(for: name) else {
            context.reply(.error("Unhandled command '\(name)'."))
            return
        }
        do {
            if let reply = try await handler(context) { context.reply(reply) }
        } catch {
            log.error("Error handling IPC command '\(name)'", error: error)
            if !context.isCompleted {
                context.reply(.error("Error: Greenshot failed to handle the command: \(error.localizedDescription)"))
            }
        }
    }

    /// CLI: the raw command line of greenshot-cli or of a second start, parsed for the connection's source.
    private func dispatchCommandLine(_ context: IPCReplyContext) async {
        let result = IPCCommandLine.parse(context.envelope.argv ?? [], source: context.source, cwd: context.envelope.cwd)
        guard var parsed = result.envelope else {
            log.info("CLI command line rejected: \(result.error ?? "")")
            var envelope = context.envelope
            envelope.json = result.json
            context.with(envelope: envelope).reply(.error(result.error ?? "Error: invalid command line.", exitCode: IPCExitCode.usage))
            return
        }
        parsed.source = context.source.rawValue
        await dispatch(context.with(envelope: parsed))
    }
}
