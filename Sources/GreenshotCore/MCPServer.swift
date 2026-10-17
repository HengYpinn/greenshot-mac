// Greenshot for Mac (Community) - an unofficial macOS port of Greenshot
// Copyright (C) 2026 Greenshot for Mac (Community) contributors
// Based on Greenshot, Copyright (C) 2007-2026 Thomas Braun, Jens Klingen, Robin Krom
// SPDX-License-Identifier: GPL-3.0-or-later

import Foundation

/// A tool of the MCP server: its definition as `tools/list` sends it (name, title, description, inputSchema,
/// annotations) and a signature to see whether it changed.
public struct MCPTool: Sendable, Equatable {
    public var name: String
    public var definition: JSONObject
    /// The data the tool was made from (upstream `RecipeTool.Signature`); a changed one replaces the tool.
    public var signature: String

    public init(name: String, definition: JSONObject, signature: String? = nil) {
        self.name = name
        self.definition = definition
        self.signature = signature ?? JSONValue.object(definition).serialized(indented: false)
    }
}

/// A resource of the MCP server (`resources/list`).
public struct MCPResource: Sendable, Equatable {
    public var uri: String
    public var name: String
    public var title: String
    public var description: String
    public var mimeType: String

    public init(uri: String, name: String, title: String, description: String, mimeType: String) {
        self.uri = uri
        self.name = name
        self.title = title
        self.description = description
        self.mimeType = mimeType
    }
}

/// What the server does for a tool call or a resource (greenshot-mcp: requests to the app).
public protocol MCPServerBackend: Sendable {
    /// The `CallToolResult` (content, isError) of a tool; `client` is the name the AI tool gave itself.
    func callTool(_ name: String, arguments: JSONObject, client: String?) async -> JSONObject
    /// The text of a resource, nil when there is none with this URI.
    func readResource(_ uri: String) async -> String?
}

/// A Model Context Protocol server over newline-delimited JSON-RPC 2.0 (the stdio transport), for both eras of the
/// protocol (spec "Versioning and Compatibility", checked 2026-10-17):
/// - **legacy** (2025-11-25 and earlier): `initialize` / `notifications/initialized` set up a session for the process;
///   tool list changes go out as `notifications/tools/list_changed` after `initialized`;
/// - **modern** (2026-07-28): every request carries `_meta` with `io.modelcontextprotocol/protocolVersion` and
///   `io.modelcontextprotocol/clientCapabilities`, results carry `resultType`, `server/discover` describes the server and
///   `subscriptions/listen` streams tool list changes.
/// upstream greenshot-mcp uses the ModelContextProtocol SDK (legacy era); this port has no dependency.
public final class MCPServer: @unchecked Sendable {
    public static let modernVersions = ["2026-07-28"]
    public static let legacyVersions = ["2025-11-25", "2025-06-18", "2025-03-26", "2024-11-05"]
    public static var supportedVersions: [String] { modernVersions + legacyVersions }

    public static let protocolVersionKey = "io.modelcontextprotocol/protocolVersion"
    public static let clientCapabilitiesKey = "io.modelcontextprotocol/clientCapabilities"
    public static let clientInfoKey = "io.modelcontextprotocol/clientInfo"
    public static let serverInfoKey = "io.modelcontextprotocol/serverInfo"
    public static let subscriptionIdKey = "io.modelcontextprotocol/subscriptionId"

    /// JSON-RPC and MCP error codes.
    public enum ErrorCode {
        public static let parseError = -32700
        public static let invalidRequest = -32600
        public static let methodNotFound = -32601
        public static let invalidParams = -32602
        public static let internalError = -32603
        /// Resource not found of the legacy revisions (2025-11-25 and earlier); the modern one uses invalidParams.
        public static let legacyResourceNotFound = -32002
        public static let unsupportedProtocolVersion = -32022
    }

    public struct Info: Sendable {
        public var name: String
        public var title: String
        public var version: String
        public var instructions: String

        public init(name: String, title: String, version: String, instructions: String) {
            self.name = name
            self.title = title
            self.version = version
            self.instructions = instructions
        }
    }

    private let info: Info
    private let backend: any MCPServerBackend
    private let send: @Sendable (JSONValue) -> Void
    private let lock = NSLock()
    private var staticTools: [MCPTool]
    private var recipeTools: [MCPTool] = []
    private let resources: [MCPResource]
    // The legacy session of this process
    private var legacyVersion: String?
    private var initialized = false
    private var legacyClientName: String?
    /// Open `subscriptions/listen` requests that want tool list changes, by their id.
    private var subscriptions: [String: JSONValue] = [:]
    private var inFlight: [String: Task<JSONValue?, Never>] = [:]
    private var cancelled: Set<String> = []

    /// - Parameter send: writes one message (the transport serializes; the server may call it from any thread).
    public init(info: Info, tools: [MCPTool], resources: [MCPResource], backend: any MCPServerBackend,
                send: @escaping @Sendable (JSONValue) -> Void) {
        self.info = info
        self.staticTools = tools
        self.resources = resources
        self.backend = backend
        self.send = send
    }

    /// The tools now: the server's own, then the recipe tools (a recipe tool can't take a name of the server's own).
    public var tools: [MCPTool] {
        lock.withLock {
            let own = Set(staticTools.map { $0.name.lowercased() })
            return staticTools + recipeTools.filter { !own.contains($0.name.lowercased()) }
        }
    }

    /// The name the AI tool gave itself in `initialize` (legacy), for the app's notification and the log.
    public var clientName: String? { lock.withLock { legacyClientName } }

    /// Replaces the recipe tools (upstream `RecipeToolSync.Apply`); unchanged tools stay, and only a change tells the
    /// client, once for all changes. True when something changed.
    @discardableResult
    public func setRecipeTools(_ newTools: [MCPTool]) -> Bool {
        var unique: [MCPTool] = []
        var names = Set<String>()
        for tool in newTools where names.insert(tool.name.lowercased()).inserted { unique.append(tool) }
        let (changed, notifyLegacy, listeners): (Bool, Bool, [JSONValue]) = lock.withLock {
            let old = Dictionary(recipeTools.map { ($0.name, $0.signature) }, uniquingKeysWith: { first, _ in first })
            let new = Dictionary(unique.map { ($0.name, $0.signature) }, uniquingKeysWith: { first, _ in first })
            guard old != new else { return (false, false, []) }
            recipeTools = unique
            return (true, initialized && legacyVersion != nil, Array(subscriptions.values))
        }
        guard changed else { return false }
        if notifyLegacy { send(notification("notifications/tools/list_changed", params: [:])) }
        for id in listeners {
            send(notification("notifications/tools/list_changed", params: ["_meta": .object([Self.subscriptionIdKey: id])]))
        }
        return true
    }

    /// The server ends: every open subscription gets its completion result (spec "Graceful Closure").
    public func closeSubscriptions() {
        let open: [JSONValue] = lock.withLock {
            defer { subscriptions = [:] }
            return Array(subscriptions.values)
        }
        for id in open {
            let result: JSONObject = ["resultType": .string("complete"), "_meta": .object([Self.subscriptionIdKey: id])]
            send(response(id: id, result: result))
        }
    }

    // MARK: Messages

    /// Handles one line of the input stream; returns when the answer (if any) was sent. Call it concurrently for
    /// concurrent requests: a tool call can wait for the user.
    public func handle(line: String) async {
        let text = line.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !text.isEmpty else { return }
        guard let value = try? JSONValue.parse(text), let message = value.objectValue else {
            send(errorResponse(id: .null, code: ErrorCode.parseError, message: "Parse error"))
            return
        }
        let id = message["id"]
        guard let method = message["method"]?.stringValue else {
            // A response (the server sends no requests) or garbage
            if id == nil || message["result"] != nil || message["error"] != nil { return }
            send(errorResponse(id: id ?? .null, code: ErrorCode.invalidRequest, message: "Invalid Request"))
            return
        }
        let params = message["params"]?.objectValue ?? [:]
        guard let id, !id.isNull else {
            handleNotification(method, params: params)
            return
        }
        let key = Self.key(of: id)
        let task = Task { await self.process(method, id: id, params: params) }
        lock.withLock { inFlight[key] = task }
        let reply = await task.value
        let wasCancelled = lock.withLock { () -> Bool in
            inFlight.removeValue(forKey: key)
            return cancelled.remove(key) != nil
        }
        // A cancelled request gets no answer at all (spec: stdio cancellation)
        if let reply, !wasCancelled { send(reply) }
    }

    private func handleNotification(_ method: String, params: JSONObject) {
        switch method {
        case "notifications/initialized":
            lock.withLock { initialized = true }
        case "notifications/cancelled":
            guard let requestId = params["requestId"] else { return }
            let key = Self.key(of: requestId)
            let task: Task<JSONValue?, Never>? = lock.withLock {
                // A cancelled subscription ends silently
                subscriptions.removeValue(forKey: key)
                guard let running = inFlight[key] else { return nil }
                cancelled.insert(key)
                return running
            }
            task?.cancel()
        default:
            break
        }
    }

    private func process(_ method: String, id: JSONValue, params: JSONObject) async -> JSONValue? {
        let meta = params["_meta"]?.objectValue
        if method == "initialize" { return initialize(id: id, params: params) }
        var modern = false
        var client = lock.withLock { legacyClientName }
        if let version = meta?[Self.protocolVersionKey]?.stringValue {
            guard Self.modernVersions.contains(version) else {
                let data: JSONObject = ["supported": .array(Self.supportedVersions.map(JSONValue.string)), "requested": .string(version)]
                return errorResponse(id: id, code: ErrorCode.unsupportedProtocolVersion, message: "Unsupported protocol version",
                                     data: .object(data))
            }
            guard meta?[Self.clientCapabilitiesKey]?.objectValue != nil else {
                return errorResponse(id: id, code: ErrorCode.invalidParams,
                                     message: "Invalid params: _meta needs \(Self.clientCapabilitiesKey)")
            }
            modern = true
            client = meta?[Self.clientInfoKey]?.objectValue.flatMap(Self.clientName(of:)) ?? client
        } else if method == "server/discover" || method == "subscriptions/listen" {
            return errorResponse(id: id, code: ErrorCode.invalidParams, message: "Invalid params: _meta needs \(Self.protocolVersionKey)")
        }

        switch method {
        case "ping":
            return result(id: id, [:], modern: modern)
        case "server/discover":
            var body = serverDescription()
            body["supportedVersions"] = .array(Self.modernVersions.map(JSONValue.string))
            return result(id: id, body, modern: true)
        case "tools/list":
            return result(id: id, ["tools": .array(tools.map { .object($0.definition) })], modern: modern)
        case "tools/call":
            guard let name = params["name"]?.stringValue, !name.isEmpty else {
                return errorResponse(id: id, code: ErrorCode.invalidParams, message: "Invalid params: the tool name is missing")
            }
            guard tools.contains(where: { $0.name == name }) else {
                return errorResponse(id: id, code: ErrorCode.invalidParams, message: "Unknown tool: \(name)")
            }
            let arguments = params["arguments"]?.objectValue ?? [:]
            let outcome = await backend.callTool(name, arguments: arguments, client: client)
            return result(id: id, outcome, modern: modern)
        case "resources/list":
            let list = resources.map { resource -> JSONValue in
                .object(["uri": .string(resource.uri), "name": .string(resource.name), "title": .string(resource.title),
                         "description": .string(resource.description), "mimeType": .string(resource.mimeType)])
            }
            return result(id: id, ["resources": .array(list)], modern: modern)
        case "resources/templates/list":
            return result(id: id, ["resourceTemplates": .array([])], modern: modern)
        case "resources/read":
            let uri = params["uri"]?.stringValue ?? ""
            guard let resource = resources.first(where: { $0.uri == uri }), let text = await backend.readResource(uri) else {
                let code = modern ? ErrorCode.invalidParams : ErrorCode.legacyResourceNotFound
                return errorResponse(id: id, code: code, message: "Resource not found", data: .object(["uri": .string(uri)]))
            }
            let contents: JSONObject = ["uri": .string(uri), "mimeType": .string(resource.mimeType), "text": .string(text)]
            return result(id: id, ["contents": .array([.object(contents)])], modern: modern)
        case "subscriptions/listen":
            return subscribe(id: id, params: params)
        default:
            return errorResponse(id: id, code: ErrorCode.methodNotFound, message: "Method not found: \(method)")
        }
    }

    /// Legacy `initialize`: the client's version when the server has it, else the newest legacy one.
    private func initialize(id: JSONValue, params: JSONObject) -> JSONValue {
        let requested = params["protocolVersion"]?.stringValue ?? ""
        let version = Self.legacyVersions.contains(requested) ? requested : Self.legacyVersions[0]
        let name = params["clientInfo"]?.objectValue.flatMap(Self.clientName(of:))
        lock.withLock {
            legacyVersion = version
            initialized = false
            legacyClientName = name
        }
        var body = serverDescription()
        body["protocolVersion"] = .string(version)
        body.removeValue(forKey: "_meta")
        body["serverInfo"] = .object(serverInfo)
        return response(id: id, result: body)
    }

    /// `subscriptions/listen`: acknowledged with what the server honours (tool list changes); stays open until the client
    /// cancels it or the server ends.
    private func subscribe(id: JSONValue, params: JSONObject) -> JSONValue? {
        let wanted = params["notifications"]?.objectValue ?? [:]
        let tools = wanted["toolsListChanged"]?.boolValue == true
        var honoured: JSONObject = [:]
        if tools {
            honoured["toolsListChanged"] = .bool(true)
            lock.withLock { subscriptions[Self.key(of: id)] = id }
        }
        send(notification("notifications/subscriptions/acknowledged",
                          params: ["_meta": .object([Self.subscriptionIdKey: id]), "notifications": .object(honoured)]))
        guard tools else {
            // Nothing to listen to: the subscription ends at once
            return response(id: id, result: ["resultType": .string("complete"), "_meta": .object([Self.subscriptionIdKey: id])])
        }
        return nil
    }

    private var serverInfo: JSONObject {
        ["name": .string(info.name), "title": .string(info.title), "version": .string(info.version)]
    }

    private func serverDescription() -> JSONObject {
        let capabilities: JSONObject = ["tools": .object(["listChanged": .bool(true)]), "resources": .object([:])]
        return ["capabilities": .object(capabilities), "_meta": .object([Self.serverInfoKey: .object(serverInfo)]),
                "instructions": .string(info.instructions)]
    }

    // MARK: JSON-RPC

    private func result(id: JSONValue, _ body: JSONObject, modern: Bool) -> JSONValue {
        var result = body
        if modern {
            if result["resultType"] == nil { result["resultType"] = .string("complete") }
            var meta = result["_meta"]?.objectValue ?? [:]
            meta[Self.serverInfoKey] = .object(serverInfo)
            result["_meta"] = .object(meta)
        }
        return response(id: id, result: result)
    }

    private func response(id: JSONValue, result: JSONObject) -> JSONValue {
        .object(["jsonrpc": .string("2.0"), "id": id, "result": .object(result)])
    }

    private func errorResponse(id: JSONValue, code: Int, message: String, data: JSONValue? = nil) -> JSONValue {
        var error: JSONObject = ["code": .number(Double(code)), "message": .string(message)]
        if let data { error["data"] = data }
        return .object(["jsonrpc": .string("2.0"), "id": id, "error": .object(error)])
    }

    private func notification(_ method: String, params: JSONObject) -> JSONValue {
        .object(["jsonrpc": .string("2.0"), "method": .string(method), "params": .object(params)])
    }

    private static func key(of id: JSONValue) -> String {
        id.serialized(indented: false)
    }

    /// "Claude Code 2.1" from `clientInfo` (upstream `ToolCalls.GetClientName`: the title, else the name, and the version).
    static func clientName(of info: JSONObject) -> String? {
        let title = info["title"]?.stringValue?.trimmingCharacters(in: .whitespaces) ?? ""
        let name = title.isEmpty ? (info["name"]?.stringValue?.trimmingCharacters(in: .whitespaces) ?? "") : title
        guard !name.isEmpty else { return nil }
        let version = info["version"]?.stringValue?.trimmingCharacters(in: .whitespaces) ?? ""
        return version.isEmpty ? name : "\(name) \(version)"
    }
}
