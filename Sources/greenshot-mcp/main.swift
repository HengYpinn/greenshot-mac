// Greenshot for Mac (Community) - an unofficial macOS port of Greenshot
// Copyright (C) 2026 Greenshot for Mac (Community) contributors
// Based on Greenshot, Copyright (C) 2007-2026 Thomas Braun, Jens Klingen, Robin Krom
// SPDX-License-Identifier: GPL-3.0-or-later

// greenshot-mcp: the MCP server for AI tools (upstream src/Greenshot.Mcp/Program.cs), bundled into the app
// (Contents/Helpers). An AI tool (Claude Code, Claude Desktop, VS Code, Cursor, ...) starts it and talks MCP over stdio;
// each tool call is a request to the running app over its automation socket, with the source `mcp`. Stdout carries the
// protocol: everything else goes to stderr.

import Darwin
import Foundation
import GreenshotCore

signal(SIGPIPE, SIG_IGN)
setvbuf(stderr, nil, _IOLBF, 0)

let executable = IPCEndpoint.currentExecutablePath
let endpoint = IPCEndpoint.forExecutable(executable)
let version: String = {
    guard let bundle = endpoint.appBundlePath,
          let value = IPCEndpoint.infoDictionary(ofBundle: bundle)?["CFBundleShortVersionString"] as? String else { return "0.0.0-dev" }
    return value
}()

if let first = CommandLine.arguments.dropFirst().first?.lowercased() {
    switch first {
    case "--version", "-v":
        print("greenshot-mcp \(version) (Greenshot for Mac (Community))")
        exit(0)
    default:
        let text = """
            greenshot-mcp: the MCP server of Greenshot for Mac (Community), for AI tools.
            An AI tool starts it and talks to it over stdin/stdout; it takes no arguments.
            Connect your AI tool with this path:
              \(executable)
            and switch on "Let AI tools use Greenshot" in Settings › AI Tools.

            """
        FileHandle.standardError.write(Data(text.utf8))
        exit(first == "--help" || first == "-h" ? 0 : 2)
    }
}

let output = StdioOutput()
let connection = GreenshotConnection(endpoint: endpoint, executable: executable, version: version)
let resources = MCPResourceFiles(executable: executable, bundle: endpoint.appBundlePath)
let sync = RecipeToolSync()
let backend = MCPGreenshotBackend(
    call: { request, client in try await connection.send(request, client: client) },
    schemaText: { resources.schemaWithExamples() },
    resourceText: { uri in uri == MCPTools.schemaURI ? resources.schema() : nil },
    requestSync: { sync.request() })
let server = MCPServer(info: MCPServer.Info(name: MCPTools.serverName, title: MCPTools.serverTitle, version: version,
                                            instructions: MCPTools.instructions),
                       tools: MCPTools.fixedTools, resources: [MCPTools.schemaResource], backend: backend,
                       send: { output.write($0) })

/// Ends greenshot-mcp: open subscriptions get their completion result first.
func shutDown(_ code: Int32, _ reason: String? = nil) -> Never {
    if let reason { MCPLog.info(reason) }
    server.closeSubscriptions()
    output.flush()
    exit(code)
}

sync.start(connection: connection, server: server)
GreenshotWatch(connection: connection, executable: executable, sync: sync, shutDown: { shutDown(0, $0) }).start()

// stdin: one JSON-RPC message per line; requests run concurrently (a tool call can wait for the user)
let reader = Thread {
    while let line = readLine(strippingNewline: true) {
        Task { await server.handle(line: line) }
    }
    // The AI tool closed stdin: the graceful end (spec "Shutdown")
    shutDown(0)
}
reader.name = "greenshot-mcp stdin"
reader.stackSize = 8 * 1024 * 1024
reader.start()

dispatchMain()
