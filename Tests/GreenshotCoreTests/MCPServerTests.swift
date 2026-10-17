// Greenshot for Mac (Community) - an unofficial macOS port of Greenshot
// Copyright (C) 2026 Greenshot for Mac (Community) contributors
// Based on Greenshot, Copyright (C) 2007-2026 Thomas Braun, Jens Klingen, Robin Krom
// SPDX-License-Identifier: GPL-3.0-or-later

import Foundation
import Testing
@testable import GreenshotCore

/// The messages the server wrote.
final class MCPOutbox: @unchecked Sendable {
    private let lock = NSLock()
    private var messages: [JSONObject] = []

    func add(_ value: JSONValue) {
        guard let object = value.objectValue else { return }
        lock.withLock { messages.append(object) }
    }

    var all: [JSONObject] { lock.withLock { messages } }

    func response(_ id: Double) -> JSONObject? {
        all.first { $0["id"]?.doubleValue == id }
    }

    func notifications(_ method: String) -> [JSONObject] {
        all.filter { $0["method"]?.stringValue == method }
    }
}

/// A backend that answers tool calls itself; `gate` holds a call until the test opens it.
final class FakeMCPBackend: MCPServerBackend, @unchecked Sendable {
    private let lock = NSLock()
    private var calls: [(String, JSONObject, String?)] = []

    var received: [(String, JSONObject, String?)] { lock.withLock { calls } }

    func callTool(_ name: String, arguments: JSONObject, client: String?) async -> JSONObject {
        lock.withLock { calls.append((name, arguments, client)) }
        if name == "slow" {
            try? await Task.sleep(nanoseconds: 2_000_000_000)
        }
        return MCPTools.textResult("called \(name)")
    }

    func readResource(_ uri: String) async -> String? {
        uri == MCPTools.schemaURI ? "{\"title\":\"schema\"}" : nil
    }
}

private let modernMeta: JSONObject = [
    MCPServer.protocolVersionKey: .string("2026-07-28"),
    MCPServer.clientCapabilitiesKey: .object([:]),
    MCPServer.clientInfoKey: .object(["name": .string("Modern Client"), "version": .string("3")]),
]

/// The MCP server engine in both eras (spec 2026-07-28 and the initialize-based revisions).
@Suite struct MCPServerTests {
    private func server(_ outbox: MCPOutbox, backend: FakeMCPBackend = FakeMCPBackend()) -> MCPServer {
        let slow = MCPTool(name: "slow", definition: ["name": .string("slow"), "inputSchema": .object(["type": .string("object")])])
        return MCPServer(info: MCPServer.Info(name: "greenshot", title: "Greenshot for Mac (Community)", version: "1.2.3",
                                              instructions: "Use it"),
                         tools: MCPTools.fixedTools + [slow], resources: [MCPTools.schemaResource], backend: backend,
                         send: { outbox.add($0) })
    }

    private func line(_ object: JSONObject) -> String {
        JSONValue.object(object).serialized(indented: false)
    }

    private func request(_ id: Int, _ method: String, _ params: JSONObject? = nil) -> String {
        var message: JSONObject = ["jsonrpc": .string("2.0"), "id": .number(Double(id)), "method": .string(method)]
        if let params { message["params"] = .object(params) }
        return line(message)
    }

    @Test func legacyHandshake() async throws {
        let outbox = MCPOutbox()
        let server = server(outbox)
        await server.handle(line: request(1, "initialize", ["protocolVersion": .string("2025-06-18"), "capabilities": .object([:]),
                                                            "clientInfo": .object(["name": .string("claude-code"), "title": .string("Claude Code"),
                                                                                   "version": .string("2.1")])]))
        let result = try #require(outbox.response(1)?["result"]?.objectValue)
        #expect(result.string("protocolVersion") == "2025-06-18")
        #expect(result["capabilities"]?.objectValue?["tools"]?.objectValue?["listChanged"]?.boolValue == true)
        #expect(result["serverInfo"]?.objectValue?.string("name") == "greenshot")
        #expect(result.string("instructions") == "Use it")
        #expect(result["resultType"] == nil)
        #expect(server.clientName == "Claude Code 2.1")

        await server.handle(line: request(2, "initialize", ["protocolVersion": .string("1999-01-01")]))
        #expect(outbox.response(2)?["result"]?.objectValue?.string("protocolVersion") == "2025-11-25")
    }

    @Test func listsAndCallsTools() async throws {
        let outbox = MCPOutbox()
        let backend = FakeMCPBackend()
        let server = server(outbox, backend: backend)
        await server.handle(line: request(1, "initialize", ["protocolVersion": .string("2025-11-25"),
                                                            "clientInfo": .object(["name": .string("cursor")])]))
        await server.handle(line: request(2, "tools/list"))
        let tools = outbox.response(2)?["result"]?.objectValue?["tools"]?.arrayValue ?? []
        let names = tools.compactMap { $0.objectValue?.string("name") }
        #expect(Array(names.prefix(6)) == ["list_windows", "get_recipe_schema", "get_recipe_catalog", "validate_recipe", "propose_recipe",
                                          "update_recipe"])
        await server.handle(line: request(3, "tools/call", ["name": .string("list_windows"), "arguments": .object([:])]))
        let content = outbox.response(3)?["result"]?.objectValue?["content"]?.arrayValue?.first?.objectValue
        #expect(content?.string("text") == "called list_windows")
        #expect(backend.received.first?.2 == "cursor")
        await server.handle(line: request(4, "tools/call", ["name": .string("nope")]))
        #expect(outbox.response(4)?["error"]?.objectValue?.int("code") == MCPServer.ErrorCode.invalidParams)
    }

    @Test func protocolErrors() async {
        let outbox = MCPOutbox()
        let server = server(outbox)
        await server.handle(line: "{not json")
        #expect(outbox.all.first?["error"]?.objectValue?.int("code") == MCPServer.ErrorCode.parseError)
        await server.handle(line: request(5, "prompts/list"))
        #expect(outbox.response(5)?["error"]?.objectValue?.int("code") == MCPServer.ErrorCode.methodNotFound)
        await server.handle(line: request(6, "ping"))
        #expect(outbox.response(6)?["result"]?.objectValue?.isEmpty == true)
        // Notifications get no answer
        let before = outbox.all.count
        await server.handle(line: line(["jsonrpc": .string("2.0"), "method": .string("notifications/whatever")]))
        #expect(outbox.all.count == before)
    }

    @Test func legacyListChangedOnlyAfterInitialized() async {
        let outbox = MCPOutbox()
        let server = server(outbox)
        await server.handle(line: request(1, "initialize", ["protocolVersion": .string("2025-11-25")]))
        let tool = MCPTool(name: "my_tool", definition: ["name": .string("my_tool")])
        #expect(server.setRecipeTools([tool]))
        #expect(outbox.notifications("notifications/tools/list_changed").isEmpty)
        await server.handle(line: line(["jsonrpc": .string("2.0"), "method": .string("notifications/initialized")]))
        #expect(!server.setRecipeTools([tool]))
        let changed = MCPTool(name: "my_tool", definition: ["name": .string("my_tool"), "title": .string("Mine")])
        #expect(server.setRecipeTools([changed]))
        #expect(outbox.notifications("notifications/tools/list_changed").count == 1)
        // A recipe tool can't take a name of the server's own
        server.setRecipeTools([MCPTool(name: "list_windows", definition: ["name": .string("list_windows"), "title": .string("Fake")])])
        #expect(server.tools.filter { $0.name == "list_windows" }.count == 1)
    }

    @Test func modernRequestsCarryTheirVersion() async throws {
        let outbox = MCPOutbox()
        let backend = FakeMCPBackend()
        let server = server(outbox, backend: backend)
        await server.handle(line: request(1, "tools/list", ["_meta": .object(modernMeta)]))
        let result = try #require(outbox.response(1)?["result"]?.objectValue)
        #expect(result.string("resultType") == "complete")
        #expect(result["_meta"]?.objectValue?[MCPServer.serverInfoKey]?.objectValue?.string("version") == "1.2.3")
        await server.handle(line: request(2, "tools/call", ["_meta": .object(modernMeta), "name": .string("get_recipe_schema")]))
        #expect(backend.received.last?.2 == "Modern Client 3")

        var noCapabilities = modernMeta
        noCapabilities.removeValue(forKey: MCPServer.clientCapabilitiesKey)
        await server.handle(line: request(3, "tools/list", ["_meta": .object(noCapabilities)]))
        #expect(outbox.response(3)?["error"]?.objectValue?.int("code") == MCPServer.ErrorCode.invalidParams)

        var old = modernMeta
        old[MCPServer.protocolVersionKey] = .string("2030-01-01")
        await server.handle(line: request(4, "tools/list", ["_meta": .object(old)]))
        let error = try #require(outbox.response(4)?["error"]?.objectValue)
        #expect(error.int("code") == MCPServer.ErrorCode.unsupportedProtocolVersion)
        let supported = error["data"]?.objectValue?["supported"]?.arrayValue?.compactMap(\.stringValue) ?? []
        #expect(supported.contains("2026-07-28"))
        #expect(supported.contains("2025-11-25"))
        #expect(error["data"]?.objectValue?.string("requested") == "2030-01-01")
    }

    @Test func discover() async throws {
        let outbox = MCPOutbox()
        let server = server(outbox)
        await server.handle(line: request(1, "server/discover", ["_meta": .object(modernMeta)]))
        let result = try #require(outbox.response(1)?["result"]?.objectValue)
        #expect(result["supportedVersions"]?.arrayValue == [.string("2026-07-28")])
        #expect(result["capabilities"]?.objectValue?["tools"] != nil)
        #expect(result.string("instructions") == "Use it")
        #expect(result.string("resultType") == "complete")
        // A legacy client probing without _meta gets an error (and falls back to initialize)
        await server.handle(line: request(2, "server/discover"))
        #expect(outbox.response(2)?["error"] != nil)
    }

    @Test func subscriptions() async throws {
        let outbox = MCPOutbox()
        let server = server(outbox)
        var params: JSONObject = ["_meta": .object(modernMeta)]
        params["notifications"] = .object(["toolsListChanged": .bool(true), "promptsListChanged": .bool(true)])
        await server.handle(line: request(7, "subscriptions/listen", params))
        let ack = try #require(outbox.notifications("notifications/subscriptions/acknowledged").first?["params"]?.objectValue)
        #expect(ack["_meta"]?.objectValue?[MCPServer.subscriptionIdKey]?.doubleValue == 7)
        #expect(ack["notifications"]?.objectValue?["toolsListChanged"]?.boolValue == true)
        #expect(ack["notifications"]?.objectValue?["promptsListChanged"] == nil)
        // Open: no response yet
        #expect(outbox.response(7) == nil)
        server.setRecipeTools([MCPTool(name: "x", definition: ["name": .string("x")])])
        let changed = try #require(outbox.notifications("notifications/tools/list_changed").first?["params"]?.objectValue)
        #expect(changed["_meta"]?.objectValue?[MCPServer.subscriptionIdKey]?.doubleValue == 7)

        // The client cancels it: silence, and no more notifications
        await server.handle(line: line(["jsonrpc": .string("2.0"), "method": .string("notifications/cancelled"),
                                         "params": .object(["requestId": .number(7)])]))
        server.setRecipeTools([])
        #expect(outbox.notifications("notifications/tools/list_changed").count == 1)
        #expect(outbox.response(7) == nil)

        // The server ends the others gracefully
        await server.handle(line: request(8, "subscriptions/listen", params))
        server.closeSubscriptions()
        let closing = try #require(outbox.response(8)?["result"]?.objectValue)
        #expect(closing.string("resultType") == "complete")
        #expect(closing["_meta"]?.objectValue?[MCPServer.subscriptionIdKey]?.doubleValue == 8)
    }

    @Test func cancelledCallsGetNoAnswer() async {
        let outbox = MCPOutbox()
        let server = server(outbox)
        async let call: Void = server.handle(line: request(9, "tools/call", ["name": .string("slow")]))
        // Let the call start, then cancel it
        try? await Task.sleep(nanoseconds: 100_000_000)
        await server.handle(line: line(["jsonrpc": .string("2.0"), "method": .string("notifications/cancelled"),
                                        "params": .object(["requestId": .number(9), "reason": .string("user")])]))
        await call
        #expect(outbox.response(9) == nil)
    }

    @Test func resources() async throws {
        let outbox = MCPOutbox()
        let server = server(outbox)
        await server.handle(line: request(1, "resources/list"))
        let resource = try #require(outbox.response(1)?["result"]?.objectValue?["resources"]?.arrayValue?.first?.objectValue)
        #expect(resource.string("uri") == MCPTools.schemaURI)
        #expect(resource.string("mimeType") == "application/schema+json")
        await server.handle(line: request(2, "resources/read", ["uri": .string(MCPTools.schemaURI)]))
        let contents = try #require(outbox.response(2)?["result"]?.objectValue?["contents"]?.arrayValue?.first?.objectValue)
        #expect(contents.string("text") == "{\"title\":\"schema\"}")
        await server.handle(line: request(3, "resources/read", ["uri": .string("greenshot-mcp://nope")]))
        #expect(outbox.response(3)?["error"]?.objectValue?.int("code") == MCPServer.ErrorCode.legacyResourceNotFound)
        await server.handle(line: request(4, "resources/read", ["_meta": .object(modernMeta), "uri": .string("greenshot-mcp://nope")]))
        #expect(outbox.response(4)?["error"]?.objectValue?.int("code") == MCPServer.ErrorCode.invalidParams)
    }

    @Test func messagesAreOneLine() {
        let message: JSONValue = .object(["text": .string("two\nlines \u{2028} and \"quotes\"")])
        #expect(!message.serialized(indented: false).contains("\n"))
    }
}
