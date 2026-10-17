// Greenshot for Mac (Community) - an unofficial macOS port of Greenshot
// Copyright (C) 2026 Greenshot for Mac (Community) contributors
// Based on Greenshot, Copyright (C) 2007-2026 Thomas Braun, Jens Klingen, Robin Krom
// SPDX-License-Identifier: GPL-3.0-or-later

import Foundation

/// greenshot-mcp's tools and how a call becomes a request to the app (upstream `Greenshot.Mcp/GreenshotTools.cs`,
/// `RecipeAuthoringTools.cs`, `RecipeTool.cs`): `list_windows` and the recipe authoring tools are fixed; the recipes
/// with an AI tool trigger (LIST_AI_TOOLS) are the other tools, run with RUN_AI_TOOL.
public enum MCPTools {
    public static let serverName = "greenshot"
    public static let serverTitle = "Greenshot for Mac (Community)"
    public static let schemaURI = "greenshot-mcp://recipes/schema"
    /// The examples sent with the schema (upstream `RecipeAuthoringTools.ExampleNames`).
    public static let exampleNames = ["region_blue_border.gsrecipe.json", "window_regex_redact.gsrecipe.json", "cli_ocr_extract.gsrecipe.json"]

    public static let instructions = "Greenshot for Mac is the screenshot tool running on the user's Mac. "
        + "Use list_windows to see the open windows and displays, then capture_window with a window id to see the exact contents of a window "
        + "(also when it is covered by other windows), capture_region to zoom in on details and capture_screen for all displays; "
        + "ocr=true adds the text. Screen coordinates are points with the origin at the top left of the main display. "
        + "The other tools are Greenshot recipes the user offers to AI tools. "
        + "When the user wants Greenshot to do something new (a hotkey that captures and uploads, a tool for you, ...), write a recipe: "
        + "get_recipe_schema and get_recipe_catalog show what is possible, validate_recipe checks it, propose_recipe or update_recipe "
        + "show it to the user, who decides whether it is saved and which triggers and permissions are switched on. "
        + "The user has to switch on AI tools in Greenshot, allow each AI tool the first time, and can exclude applications."

    public static let schemaResource = MCPResource(uri: schemaURI, name: "recipe_schema", title: "Greenshot recipe JSON schema",
                                                   description: "The JSON schema of Greenshot recipes", mimeType: "application/schema+json")

    // MARK: The fixed tools

    public static var fixedTools: [MCPTool] {
        [
            tool("list_windows", title: "List windows",
                 description: "Lists the open windows on the screen (front to back, topmost first) with an id, title, application, bundle id, "
                    + "bounds in screen coordinates (points, origin at the top left of the main display) and whether it is active, and the displays "
                    + "with their bounds and scale. Minimized windows and windows on other Spaces are not listed. Pass a window id (e.g. w7) to tools "
                    + "with a window argument, such as capture_window. Ids only work in this session and expire after some minutes, then call "
                    + "list_windows again.",
                 properties: [:], required: [], readOnly: true, destructive: false, idempotent: true),
            tool("get_recipe_schema", title: "Get the recipe schema",
                 description: "Returns the JSON schema of Greenshot recipes and some example recipes. A recipe is a capture workflow: triggers "
                    + "(hotkey, menu entry, command line, AI tool, ...) start a flow of steps (capture source, selection, effects, OCR, "
                    + "destinations such as file, clipboard, editor or an upload). Use it with get_recipe_catalog to write a recipe the user asked for.",
                 properties: [:], required: [], readOnly: true, destructive: false, idempotent: true),
            tool("get_recipe_catalog", title: "Get the recipe catalog",
                 description: "Returns what recipes can use in this Greenshot: the trigger types, the step types with their parameters, the "
                    + "destinations (uploads=true sends the capture to the internet), the processors, the user's recipes (id, name, triggers), the slots "
                    + "and the automatic steps (steps Greenshot adds to other recipes, like a border on every capture), and the option types. "
                    + "With recipe_id it returns the JSON of that recipe or automatic step instead, to change it with update_recipe.",
                 properties: ["recipe_id": stringProperty("Optional: the id of a recipe to get its JSON")], required: [],
                 readOnly: true, destructive: false, idempotent: true),
            tool("validate_recipe", title: "Validate a recipe",
                 description: "Checks a recipe or an automatic step (\"kind\": \"extension\") without saving or showing it: errors, warnings, what it does in "
                    + "plain words, its triggers or which recipes it changes, and what the user will be asked to allow (uploads, files, external "
                    + "commands). Fix the errors before propose_recipe.",
                 properties: ["recipe_json": stringProperty("The recipe as a JSON object")], required: ["recipe_json"],
                 readOnly: true, destructive: false, idempotent: true),
            tool("propose_recipe", title: "Propose a new recipe",
                 description: "Shows a new recipe to the user in Greenshot, marked as written by you, with what it does and what it needs. "
                    + "Greenshot saves it only when the user approves it; the user decides which triggers are switched on (they start off) "
                    + "and allows uploads, files and external commands. Waits for the user's decision. The id must not be used by another recipe. "
                    + "It can also be an automatic step (\"kind\": \"extension\"): the user sees which recipes it changes, and it starts switched off.",
                 properties: ["recipe_json": stringProperty("The recipe as a JSON object, checked with validate_recipe"),
                              "request": stringProperty("What the user asked for, in a sentence; shown to the user as your words"),
                              "explanation": stringProperty("How the recipe does that, in a few sentences; shown to the user as your words")],
                 required: ["recipe_json", "request", "explanation"], readOnly: false, destructive: false, idempotent: false),
            tool("update_recipe", title: "Propose a change to a recipe",
                 description: "Shows a changed version of an existing recipe or automatic step (also a built-in one) to the user in Greenshot, with "
                    + "the changed lines. Get the current JSON with get_recipe_catalog(recipe_id). Greenshot saves it only when the user approves it; "
                    + "a built-in recipe can be restored in Greenshot's recipe manager. Waits for the user's decision.",
                 properties: ["recipe_id": stringProperty("The id of the recipe to change"),
                              "recipe_json": stringProperty("The complete changed recipe as a JSON object, checked with validate_recipe"),
                              "request": stringProperty("What the user asked for, in a sentence; shown to the user as your words"),
                              "explanation": stringProperty("What you changed and why, in a few sentences; shown to the user as your words")],
                 required: ["recipe_id", "recipe_json", "request", "explanation"], readOnly: false, destructive: true, idempotent: false),
        ]
    }

    private static func stringProperty(_ description: String) -> JSONValue {
        .object(["type": .string("string"), "description": .string(description)])
    }

    private static func tool(_ name: String, title: String, description: String, properties: JSONObject, required: [String],
                             readOnly: Bool, destructive: Bool, idempotent: Bool) -> MCPTool {
        var schema: JSONObject = ["type": .string("object"), "properties": .object(properties)]
        if !required.isEmpty { schema["required"] = .array(required.map(JSONValue.string)) }
        let annotations: JSONObject = ["title": .string(title), "readOnlyHint": .bool(readOnly), "destructiveHint": .bool(destructive),
                                       "idempotentHint": .bool(idempotent), "openWorldHint": .bool(false)]
        return MCPTool(name: name, definition: ["name": .string(name), "title": .string(title), "description": .string(description),
                                                "inputSchema": .object(schema), "annotations": .object(annotations)])
    }

    // MARK: Recipe tools

    /// The tools of a LIST_AI_TOOLS reply; entries without a name are left out (upstream `RecipeToolSync.SyncAsync`).
    public static func recipeTools(fromListReply reply: JSONObject) -> [MCPTool] {
        (reply["tools"]?.arrayValue ?? []).compactMap { $0.objectValue.flatMap(recipeTool(from:)) }
    }

    /// Upstream `RecipeTool.Create`: the input schema from the trigger's arguments.
    public static func recipeTool(from entry: JSONObject) -> MCPTool? {
        guard let name = entry["name"]?.stringValue?.trimmingCharacters(in: .whitespaces), !name.isEmpty else { return nil }
        var properties = JSONObject()
        var required: [JSONValue] = []
        for argument in entry["arguments"]?.arrayValue ?? [] {
            guard let object = argument.objectValue, let argumentName = object["name"]?.stringValue,
                  !argumentName.trimmingCharacters(in: .whitespaces).isEmpty else { continue }
            properties[argumentName] = .object(schema(for: object))
            if object["required"]?.boolValue == true { required.append(.string(argumentName)) }
        }
        var schema: JSONObject = ["type": .string("object"), "properties": .object(properties)]
        if !required.isEmpty { schema["required"] = .array(required) }
        let readOnly = entry["read_only"]?.boolValue ?? false
        let destructive = entry["destructive"]?.boolValue ?? false
        let title = entry["title"]?.stringValue
        var annotations: JSONObject = ["readOnlyHint": .bool(readOnly), "destructiveHint": .bool(!readOnly && destructive),
                                       "openWorldHint": .bool(!readOnly)]
        if let title { annotations["title"] = .string(title) }
        var definition: JSONObject = ["name": .string(name)]
        if let title { definition["title"] = .string(title) }
        if let description = entry["description"]?.stringValue { definition["description"] = .string(description) }
        definition["inputSchema"] = .object(schema)
        definition["annotations"] = .object(annotations)
        return MCPTool(name: name, definition: definition, signature: JSONValue.object(entry).serialized(indented: false))
    }

    /// Upstream `RecipeTool.CreateSchema`: the JSON schema of one argument by its declared type.
    static func schema(for argument: JSONObject) -> JSONObject {
        let type = argument["type"]?.stringValue ?? "String"
        var description = argument["description"]?.stringValue ?? ""
        let defaultValue = argument["default_value"]?.stringValue
        var schema = JSONObject()
        switch type.lowercased() {
        case "integer":
            schema["type"] = .string("integer")
            if let defaultValue, let number = Int(defaultValue.trimmingCharacters(in: .whitespaces)) { schema["default"] = .number(Double(number)) }
        case "decimal":
            schema["type"] = .string("number")
            if let defaultValue, let number = Double(defaultValue.trimmingCharacters(in: .whitespaces)) { schema["default"] = .number(number) }
        case "boolean":
            schema["type"] = .string("boolean")
            if let defaultValue {
                switch defaultValue.trimmingCharacters(in: .whitespaces).lowercased() {
                case "true": schema["default"] = .bool(true)
                case "false": schema["default"] = .bool(false)
                default: break
                }
            }
        case "window":
            schema["type"] = .string("string")
            description = addHint(description, keyword: "list_windows", hint: "A window id from list_windows, e.g. w7.")
        case "region":
            schema["type"] = .string("string")
            schema["pattern"] = .string(#"^\s*-?\d+\s*,\s*-?\d+\s*,\s*\d+\s*,\s*\d+\s*$"#)
            description = addHint(description, keyword: "x,y,width,height", hint: "x,y,width,height in screen coordinates.")
        default:
            schema["type"] = .string("string")
            if let defaultValue, !defaultValue.isEmpty { schema["default"] = .string(defaultValue) }
        }
        if let allowed = argument["allowed_values"]?.arrayValue, !allowed.isEmpty {
            schema["enum"] = .array(allowed.compactMap { $0.stringValue.map(JSONValue.string) })
        }
        if !description.trimmingCharacters(in: .whitespaces).isEmpty { schema["description"] = .string(description) }
        return schema
    }

    /// How to pass the value, unless the description already says it.
    private static func addHint(_ description: String, keyword: String, hint: String) -> String {
        if description.trimmingCharacters(in: .whitespaces).isEmpty { return hint }
        return description.range(of: keyword, options: .caseInsensitive) != nil ? description : "\(description) (\(hint))"
    }

    /// Upstream `RecipeTool.ToArgumentValue`: recipe arguments are text; numbers and booleans as JSON writes them, a
    /// region given as `[x, y, width, height]` as "x,y,width,height"; null is left out.
    public static func argumentValue(_ value: JSONValue) -> String? {
        switch value {
        case .string(let text): return text
        case .bool(let flag): return flag ? "true" : "false"
        case .null: return nil
        case .array(let items) where !items.isEmpty && items.allSatisfy({ $0.doubleValue != nil }):
            return AIToolRegion.text(of: items.compactMap(\.doubleValue))
        default: return value.serialized(indented: false)
        }
    }

    // MARK: Results

    /// A tool result with one text block.
    public static func textResult(_ text: String) -> JSONObject {
        ["content": .array([.object(["type": .string("text"), "text": .string(text)])])]
    }

    /// An error the AI tool sees (`isError`), not a protocol error.
    public static func errorResult(_ message: String) -> JSONObject {
        ["content": .array([.object(["type": .string("text"), "text": .string(message)])]), "isError": .bool(true)]
    }

    /// The app's reply without some members, as JSON text (upstream `ToolCalls.TextResult(Without(...))`).
    public static func replyResult(_ reply: JSONObject, without names: [String]) -> JSONObject {
        var copy = reply
        for name in names { copy.removeValue(forKey: name) }
        return textResult(JSONValue.object(copy).serialized(indented: false))
    }

    /// Upstream `ToolCalls.RecipeResult`: the recipe's picture as an image block (when it made one) and the rest of the
    /// reply as JSON text, empty members left out.
    public static func recipeResult(_ reply: JSONObject) -> JSONObject {
        var details = reply
        var content: [JSONValue] = []
        if var image = reply["image"]?.objectValue, let data = image["data"]?.stringValue, !data.isEmpty {
            content.append(.object(["type": .string("image"), "data": .string(data),
                                    "mimeType": .string(image["mime_type"]?.stringValue ?? "image/png")]))
            image.removeValue(forKey: "data")
            details["image"] = .object(image)
        }
        for name in ["status", "exit_code"] { details.removeValue(forKey: name) }
        for member in details {
            switch member.value {
            case .null: details.removeValue(forKey: member.key)
            case .object(let object) where object.isEmpty: details.removeValue(forKey: member.key)
            case .array(let items) where items.isEmpty: details.removeValue(forKey: member.key)
            default: break
            }
        }
        content.append(.object(["type": .string("text"), "text": .string(JSONValue.object(details).serialized(indented: false))]))
        return ["content": .array(content)]
    }

    /// The error of a failed reply (upstream `ToolCalls.CallAsync`); nil for a successful one.
    public static func failure(of reply: JSONObject) -> String? {
        guard reply["status"]?.stringValue?.lowercased() != "ok" else { return nil }
        return reply["stderr"]?.stringValue ?? reply["streamed_stderr"]?.stringValue ?? "Greenshot reported an error."
    }
}

/// greenshot-mcp's backend: each tool call is one request to the app (upstream `ToolCalls.CallAsync`).
public struct MCPGreenshotBackend: MCPServerBackend {
    /// Sends a request (`command`, `recipe`, `parameters`) to the app and returns its final reply, with streamed text in
    /// `streamed_stdout` / `streamed_stderr`; throws an error whose description is for the AI tool.
    public typealias Call = @Sendable (_ request: JSONObject, _ client: String?) async throws -> JSONObject

    private let call: Call
    /// The schema and the examples, read from the app bundle.
    private let schemaText: @Sendable () -> String
    private let resourceText: @Sendable (String) -> String?
    /// After calls that may change the tools (Greenshot was started, a recipe was approved, a recipe ran).
    private let requestSync: @Sendable () -> Void

    public init(call: @escaping Call, schemaText: @escaping @Sendable () -> String, resourceText: @escaping @Sendable (String) -> String?,
                requestSync: @escaping @Sendable () -> Void) {
        self.call = call
        self.schemaText = schemaText
        self.resourceText = resourceText
        self.requestSync = requestSync
    }

    public func readResource(_ uri: String) async -> String? {
        resourceText(uri)
    }

    public func callTool(_ name: String, arguments: JSONObject, client: String?) async -> JSONObject {
        switch name {
        case "list_windows":
            defer { requestSync() }
            return await request(["command": .string(IPCCommand.listWindows)], client: client) {
                MCPTools.replyResult($0, without: ["stdout", "status", "exit_code"])
            }
        case "get_recipe_schema":
            return MCPTools.textResult(schemaText())
        case "get_recipe_catalog":
            var request: JSONObject = ["command": .string(IPCCommand.recipeCatalog)]
            if let id = text(arguments["recipe_id"]), !id.trimmingCharacters(in: .whitespaces).isEmpty {
                request["parameters"] = .object(["recipe": .string(id)])
            }
            return await self.request(request, client: client) { MCPTools.replyResult($0, without: ["status", "exit_code"]) }
        case "validate_recipe":
            let request: JSONObject = ["command": .string(IPCCommand.validateRecipe),
                                       "parameters": .object(["recipe": .string(text(arguments["recipe_json"]) ?? "")])]
            return await self.request(request, client: client) { MCPTools.replyResult($0, without: ["status", "exit_code"]) }
        case "propose_recipe", "update_recipe":
            var parameters: JSONObject = ["recipe": .string(text(arguments["recipe_json"]) ?? ""),
                                          "request": .string(text(arguments["request"]) ?? ""),
                                          "explanation": .string(text(arguments["explanation"]) ?? "")]
            if name == "update_recipe", let id = text(arguments["recipe_id"]) { parameters["replaces"] = .string(id) }
            defer { requestSync() }
            return await request(["command": .string(IPCCommand.proposeRecipe), "parameters": .object(parameters)], client: client) {
                MCPTools.replyResult($0, without: ["status", "exit_code"])
            }
        default:
            var parameters = JSONObject()
            for member in arguments {
                if let value = MCPTools.argumentValue(member.value) { parameters[member.key] = .string(value) }
            }
            defer { requestSync() }
            return await request(["command": .string(IPCCommand.runAITool), "recipe": .string(name), "parameters": .object(parameters)],
                                 client: client, onSuccess: MCPTools.recipeResult)
        }
    }

    /// A string argument; an AI tool may send the recipe as an object instead of JSON text.
    private func text(_ value: JSONValue?) -> String? {
        guard let value, !value.isNull else { return nil }
        if let text = value.stringValue { return text }
        return value.serialized(indented: true)
    }

    private func request(_ request: JSONObject, client: String?, onSuccess: (JSONObject) -> JSONObject) async -> JSONObject {
        let reply: JSONObject
        do {
            reply = try await call(request, client)
        } catch {
            return MCPTools.errorResult(error.localizedDescription)
        }
        if let failure = MCPTools.failure(of: reply) { return MCPTools.errorResult(failure) }
        return onSuccess(reply)
    }
}
