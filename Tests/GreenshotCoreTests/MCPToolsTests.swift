// Greenshot for Mac (Community) - an unofficial macOS port of Greenshot
// Copyright (C) 2026 Greenshot for Mac (Community) contributors
// Based on Greenshot, Copyright (C) 2007-2026 Thomas Braun, Jens Klingen, Robin Krom
// SPDX-License-Identifier: GPL-3.0-or-later

import Foundation
import Testing
@testable import GreenshotCore

/// The requests a fake app got, and its replies.
final class FakeGreenshot: @unchecked Sendable {
    private let lock = NSLock()
    private var log: [JSONObject] = []
    private(set) var syncs = 0
    var reply: JSONObject = ["status": .string("ok"), "exit_code": .number(0), "stdout": .string("done")]
    var failure: String?

    var requests: [JSONObject] { lock.withLock { log } }

    func backend() -> MCPGreenshotBackend {
        MCPGreenshotBackend(call: { [self] request, _ in
            lock.withLock { log.append(request) }
            if let failure { throw GreenshotTestError(message: failure) }
            return reply
        }, schemaText: { "SCHEMA" }, resourceText: { _ in nil }, requestSync: { [self] in lock.withLock { syncs += 1 } })
    }
}

struct GreenshotTestError: LocalizedError {
    var message: String
    var errorDescription: String? { message }
}

/// Upstream RecipeTool / RecipeToolSync / ToolCalls.
@Suite struct MCPToolsTests {
    private let entry: JSONObject = [
        "name": .string("capture_window"), "title": .string("Capture window"), "description": .string("Screenshot of one window."),
        "recipe": .string("recipe_ai_capture_window"), "read_only": .bool(true), "destructive": .bool(false),
        "arguments": .array([
            .object(["name": .string("window"), "description": .string("The id of the window from list_windows, e.g. w7"),
                     "required": .bool(true), "type": .string("Window")]),
            .object(["name": .string("ocr"), "description": .string("true to also return the text"), "required": .bool(false),
                     "default_value": .string("false"), "type": .string("Boolean")]),
            .object(["name": .string("area"), "description": .string("Where"), "type": .string("Region")]),
            .object(["name": .string("count"), "type": .string("Integer"), "default_value": .string("3")]),
            .object(["name": .string("mode"), "type": .string("Enum"), "allowed_values": .array([.string("a"), .string("b")])]),
        ]),
    ]

    @Test func recipeToolSchema() throws {
        let tool = try #require(MCPTools.recipeTool(from: entry))
        #expect(tool.name == "capture_window")
        #expect(tool.definition.string("title") == "Capture window")
        let schema = try #require(tool.definition["inputSchema"]?.objectValue)
        #expect(schema["required"]?.arrayValue == [.string("window")])
        let properties = try #require(schema["properties"]?.objectValue)
        let window = try #require(properties["window"]?.objectValue)
        #expect(window.string("type") == "string")
        // The description says list_windows already: no hint added
        #expect(window.string("description") == "The id of the window from list_windows, e.g. w7")
        let ocr = try #require(properties["ocr"]?.objectValue)
        #expect(ocr.string("type") == "boolean")
        #expect(ocr["default"]?.boolValue == false)
        let area = try #require(properties["area"]?.objectValue)
        #expect(area.string("pattern") != nil)
        #expect(area.string("description") == "Where (x,y,width,height in screen coordinates.)")
        #expect(properties["count"]?.objectValue?["default"]?.doubleValue == 3)
        #expect(properties["mode"]?.objectValue?["enum"]?.arrayValue == [.string("a"), .string("b")])
        let annotations = try #require(tool.definition["annotations"]?.objectValue)
        #expect(annotations["readOnlyHint"]?.boolValue == true)
        #expect(annotations["destructiveHint"]?.boolValue == false)
        #expect(annotations["openWorldHint"]?.boolValue == false)
    }

    @Test func destructiveOnlyWhenNotReadOnly() throws {
        var writing = entry
        writing["read_only"] = .bool(false)
        writing["destructive"] = .bool(true)
        let tool = try #require(MCPTools.recipeTool(from: writing))
        let annotations = try #require(tool.definition["annotations"]?.objectValue)
        #expect(annotations["destructiveHint"]?.boolValue == true)
        #expect(annotations["openWorldHint"]?.boolValue == true)
        #expect(MCPTools.recipeTool(from: ["name": .string(" ")]) == nil)
    }

    @Test func toolsOfAListReplyAndTheirSignature() {
        let reply: JSONObject = ["status": .string("ok"), "tools": .array([.object(entry), .object(["title": .string("no name")])])]
        let tools = MCPTools.recipeTools(fromListReply: reply)
        #expect(tools.map(\.name) == ["capture_window"])
        var changed = entry
        changed["description"] = .string("Other")
        #expect(MCPTools.recipeTool(from: changed)?.signature != tools.first?.signature)
    }

    @Test func argumentValuesAreText() {
        #expect(MCPTools.argumentValue(.string("w7")) == "w7")
        #expect(MCPTools.argumentValue(.bool(true)) == "true")
        #expect(MCPTools.argumentValue(.number(12)) == "12")
        #expect(MCPTools.argumentValue(.number(1.5)) == "1.5")
        #expect(MCPTools.argumentValue(.null) == nil)
        #expect(MCPTools.argumentValue(.array([.number(0), .number(10), .number(800), .number(600)])) == "0,10,800,600")
    }

    @Test func recipeResultSplitsThePicture() throws {
        let reply: JSONObject = ["status": .string("ok"), "exit_code": .number(0), "tool": .string("capture_screen"),
                                 "image": .object(["mime_type": .string("image/png"), "data": .string("AAAA"), "width": .number(4)]),
                                 "text": .string("Hello"), "variables": .object([:]), "ocr_lines": .array([]), "stderr": .null]
        let result = MCPTools.recipeResult(reply)
        let content = try #require(result["content"]?.arrayValue)
        #expect(content.count == 2)
        let image = try #require(content.first?.objectValue)
        #expect(image.string("type") == "image")
        #expect(image.string("data") == "AAAA")
        #expect(image.string("mimeType") == "image/png")
        let text = try #require(content.last?.objectValue?.string("text"))
        let details = try #require(try JSONValue.parse(text).objectValue)
        #expect(details["status"] == nil)
        #expect(details["variables"] == nil)
        #expect(details["ocr_lines"] == nil)
        #expect(details["image"]?.objectValue?["data"] == nil)
        #expect(details.string("text") == "Hello")
    }

    @Test func failuresAreToolErrors() {
        #expect(MCPTools.failure(of: ["status": .string("ok")]) == nil)
        #expect(MCPTools.failure(of: ["status": .string("error"), "stderr": .string("AI tools are off")]) == "AI tools are off")
        #expect(MCPTools.failure(of: ["status": .string("error"), "streamed_stderr": .string("x")]) == "x")
        #expect(MCPTools.errorResult("no")["isError"]?.boolValue == true)
    }

    @Test func backendRequests() async throws {
        let app = FakeGreenshot()
        let backend = app.backend()
        _ = await backend.callTool("list_windows", arguments: [:], client: nil)
        _ = await backend.callTool("get_recipe_catalog", arguments: ["recipe_id": .string("r1")], client: nil)
        _ = await backend.callTool("validate_recipe", arguments: ["recipe_json": .object(["id": .string("x")])], client: nil)
        _ = await backend.callTool("update_recipe", arguments: ["recipe_id": .string("r1"), "recipe_json": .string("{}"),
                                                                "request": .string("Do it"), "explanation": .string("Because")], client: nil)
        _ = await backend.callTool("capture_window", arguments: ["window": .string("w7"), "ocr": .bool(true)], client: nil)
        let requests = app.requests
        #expect(requests.map { $0.string("command") ?? "" } == ["LIST_WINDOWS", "RECIPE_CATALOG", "VALIDATE_RECIPE", "PROPOSE_RECIPE", "RUN_AI_TOOL"])
        #expect(requests[1]["parameters"]?.objectValue?.string("recipe") == "r1")
        // A recipe sent as an object becomes JSON text
        let validated = try #require(requests[2]["parameters"]?.objectValue?.string("recipe"))
        #expect(try JSONValue.parse(validated).objectValue?.string("id") == "x")
        let proposed = try #require(requests[3]["parameters"]?.objectValue)
        #expect(proposed.string("replaces") == "r1")
        #expect(proposed.string("explanation") == "Because")
        #expect(requests[4].string("recipe") == "capture_window")
        #expect(requests[4]["parameters"]?.objectValue?.string("ocr") == "true")
        // list_windows, update_recipe and the recipe tool sync the tools afterwards
        #expect(app.syncs == 3)
        let schema = await backend.callTool("get_recipe_schema", arguments: [:], client: nil)
        #expect(schema["content"]?.arrayValue?.first?.objectValue?.string("text") == "SCHEMA")
        #expect(app.requests.count == 5)
    }

    @Test func connectionProblemsAreToolErrors() async {
        let app = FakeGreenshot()
        app.failure = "Greenshot for Mac is not running."
        let result = await app.backend().callTool("list_windows", arguments: [:], client: nil)
        #expect(result["isError"]?.boolValue == true)
        #expect(result["content"]?.arrayValue?.first?.objectValue?.string("text") == "Greenshot for Mac is not running.")
        app.failure = nil
        app.reply = ["status": .string("error"), "exit_code": .number(1), "stderr": .string(AIToolAccess.disabledMessage)]
        let refused = await app.backend().callTool("capture_screen", arguments: [:], client: nil)
        #expect(refused["content"]?.arrayValue?.first?.objectValue?.string("text") == AIToolAccess.disabledMessage)
    }

    @Test func fixedToolsHaveSchemasAndAnnotations() {
        for tool in MCPTools.fixedTools {
            #expect(tool.definition["inputSchema"]?.objectValue?.string("type") == "object", "\(tool.name)")
            #expect(tool.definition["annotations"]?.objectValue?["readOnlyHint"] != nil, "\(tool.name)")
            #expect(tool.definition.string("description")?.isEmpty == false, "\(tool.name)")
        }
        let update = MCPTools.fixedTools.first { $0.name == "update_recipe" }
        #expect(update?.definition["annotations"]?.objectValue?["destructiveHint"]?.boolValue == true)
    }
}
