// Greenshot for Mac (Community) - an unofficial macOS port of Greenshot
// Copyright (C) 2026 Greenshot for Mac (Community) contributors
// Based on Greenshot, Copyright (C) 2007-2026 Thomas Braun, Jens Klingen, Robin Krom
// SPDX-License-Identifier: GPL-3.0-or-later

import Darwin
import Foundation
import GreenshotCore

/// Stdout: one message per line, one writer at a time (the MCP stdio transport).
final class StdioOutput: @unchecked Sendable {
    private let queue = DispatchQueue(label: "greenshot-mcp stdout")

    func write(_ message: JSONValue) {
        // Compact JSON has no newline of its own: strings escape theirs
        let line = message.serialized(indented: false) + "\n"
        queue.async {
            do {
                try FileHandle.standardOutput.write(contentsOf: Data(line.utf8))
            } catch {
                // The AI tool is gone; stdin's end follows
            }
        }
    }

    /// Waits until everything written went out (before exit).
    func flush() {
        queue.sync {}
    }
}

/// Logging to stderr (stdout is the protocol); warnings and errors only, like upstream's `LogLevel.Warning`, unless
/// GREENSHOT_MCP_DEBUG is set.
enum MCPLog {
    static let verbose = ProcessInfo.processInfo.environment["GREENSHOT_MCP_DEBUG"] != nil

    static func info(_ message: String) {
        if verbose { write("info", message) }
    }

    static func warn(_ message: String) {
        write("warning", message)
    }

    private static func write(_ level: String, _ message: String) {
        FileHandle.standardError.write(Data("greenshot-mcp \(level): \(message)\n".utf8))
    }
}

/// The recipe schema and the examples for AI tools (upstream embeds them from docs/): in the app bundle's Resources; a
/// development build looks for the package's `Resources` folder above it.
struct MCPResourceFiles: Sendable {
    let folder: URL?

    init(executable: String, bundle: String?) {
        if let bundle {
            folder = URL(fileURLWithPath: bundle).appendingPathComponent("Contents/Resources")
            return
        }
        var directory = URL(fileURLWithPath: executable).deletingLastPathComponent()
        var found: URL?
        for _ in 0..<6 {
            let candidate = directory.appendingPathComponent("Resources")
            if FileManager.default.fileExists(atPath: candidate.appendingPathComponent("recipe.schema.json").path) {
                found = candidate
                break
            }
            directory.deleteLastPathComponent()
        }
        folder = found
    }

    func schema() -> String {
        read("recipe.schema.json")
    }

    /// Upstream `GetRecipeSchema`: the schema, then each example.
    func schemaWithExamples() -> String {
        var text = "# Greenshot recipe JSON schema\n" + schema() + "\n"
        for name in MCPTools.exampleNames {
            text += "\n# Example: \(name)\n" + read("RecipeExamples/" + name) + "\n"
        }
        return text
    }

    private func read(_ name: String) -> String {
        guard let folder, let text = try? String(contentsOf: folder.appendingPathComponent(name), encoding: .utf8) else {
            return "(missing: \((name as NSString).lastPathComponent))"
        }
        return text
    }
}

/// Keeps the tools in step with the recipes the user offers to AI tools (upstream `RecipeToolSync`): asks the app at the
/// start, after each tool call, when the app says so and every 30 seconds. Never starts the app.
final class RecipeToolSync: @unchecked Sendable {
    static let interval: TimeInterval = 30
    private let wake = DispatchSemaphore(value: 0)
    private let lock = NSLock()
    private var requested = false

    /// Sync soon (a tool call may have started the app, a recipe was approved, the app said tools changed).
    func request() {
        let signal: Bool = lock.withLock {
            defer { requested = true }
            return !requested
        }
        if signal { wake.signal() }
    }

    func start(connection: GreenshotConnection, server: MCPServer) {
        // Its own thread: the waits and the blocking requests never take a cooperative thread
        let thread = Thread { [self] in
            while true {
                sync(connection: connection, server: server)
                _ = wake.wait(timeout: .now() + Self.interval)
                lock.withLock { requested = false }
            }
        }
        thread.name = "greenshot-mcp tool sync"
        thread.start()
    }

    private func sync(connection: GreenshotConnection, server: MCPServer) {
        let reply: JSONObject
        do {
            reply = try connection.sendBlocking(["command": .string(IPCCommand.listAITools)], client: nil, startApp: false, readTimeout: 30)
        } catch {
            // The app isn't running: keep the tools, calling one starts the app
            MCPLog.info("No AI tools from Greenshot for Mac: \(error.localizedDescription)")
            return
        }
        guard MCPTools.failure(of: reply) == nil else {
            // AI tools switched off: no recipe tools
            server.setRecipeTools([])
            return
        }
        if server.setRecipeTools(MCPTools.recipeTools(fromListReply: reply)) {
            MCPLog.info("The recipe tools changed.")
        }
    }
}

/// Keeps a watch connection to the app (upstream `GreenshotWatch`): tool changes are synced at once; when the app quits,
/// greenshot-mcp waits for its next start ("exit", "session_end") or exits ("update", "uninstall"). Mac addition: it
/// exits when its own executable was replaced or removed (the app was updated or deleted), so the AI tool starts the new
/// one.
final class GreenshotWatch: @unchecked Sendable {
    static let retryInterval: TimeInterval = 3
    /// An app without WATCH: the 30 s sync still works.
    static let oldAppRetryInterval: TimeInterval = 60

    private let connection: GreenshotConnection
    private let executable: String
    private let sync: RecipeToolSync
    private let shutDown: @Sendable (String) -> Void
    private let identity: [UInt64]?

    init(connection: GreenshotConnection, executable: String, sync: RecipeToolSync, shutDown: @escaping @Sendable (String) -> Void) {
        self.connection = connection
        self.executable = executable
        self.sync = sync
        self.shutDown = shutDown
        identity = IPCSocket.fileIdentity(executable)
    }

    func start() {
        let thread = Thread { [self] in run() }
        thread.name = "greenshot-mcp watch"
        thread.start()
    }

    private func run() {
        while true {
            if let identity, IPCSocket.fileIdentity(executable) != identity {
                shutDown("greenshot-mcp was replaced or removed (Greenshot for Mac was updated or deleted); exiting.")
            }
            var wait = Self.retryInterval
            let (watch, isRunning) = connection.openWatch()
            if let watch {
                GreenshotState.shared.connected()
                sync.request()
                readEvents(watch)
                watch.close()
            } else if isRunning {
                wait = Self.oldAppRetryInterval
            }
            Thread.sleep(forTimeInterval: wait)
        }
    }

    private func readEvents(_ watch: IPCClient) {
        while true {
            guard let frame = try? watch.readObject() else { return }
            let event = frame["event"]?.stringValue?.lowercased()
            if event == "tools_changed" {
                sync.request()
            } else if event == "shutdown" {
                let reason = frame["reason"]?.stringValue ?? IPCServer.shutdownReasonExit
                GreenshotState.shared.shuttingDown(reason: reason)
                if ["update", "uninstall"].contains(reason.lowercased()) {
                    shutDown("Greenshot for Mac is being updated or removed, greenshot-mcp exits.")
                }
                MCPLog.info("Greenshot for Mac quit (\(reason)), waiting for it to be started again.")
                return
            }
        }
    }
}
