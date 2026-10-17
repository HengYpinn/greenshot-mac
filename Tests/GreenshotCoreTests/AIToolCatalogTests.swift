// Greenshot for Mac (Community) - an unofficial macOS port of Greenshot
// Copyright (C) 2026 Greenshot for Mac (Community) contributors
// Based on Greenshot, Copyright (C) 2007-2026 Thomas Braun, Jens Klingen, Robin Krom
// SPDX-License-Identifier: GPL-3.0-or-later

import CoreGraphics
import Foundation
import Testing
@testable import GreenshotCore

/// A recipe with an AI tool trigger (like upstream's built-in `recipe_ai_capture_window`, from fixtures here: RSTEPS
/// owns the built-in data).
func aiToolRecipe(id: String, toolName: String, title: String? = "Capture window", maxImageSize: Int? = nil,
                  arguments: [JSONValue]? = nil) -> CaptureRecipe {
    var recipe = CaptureRecipe(id: id, name: "AI tool: \(toolName)", description: "Captures a window for an AI tool")
    var parameters: JSONObject = ["ToolName": .string(toolName), "Description": .string("Screenshot of one window."), "ReadOnly": .bool(true)]
    if let title { parameters["Title"] = .string(title) }
    if let maxImageSize { parameters["MaxImageSize"] = .number(Double(maxImageSize)) }
    parameters["Arguments"] = .array(arguments ?? [
        .object(["name": .string("window"), "variable": .string("Window"), "type": .string("Window"), "required": .bool(true),
                 "description": .string("The id of the window from list_windows, e.g. w7")]),
        .object(["name": .string("ocr"), "variable": .string("Ocr"), "type": .string("Boolean"), "defaultValue": .string("false")]),
    ])
    recipe.triggers = [TriggerConfig(triggerType: "AiTool", parameters: parameters)]
    recipe.nodes = [RecipeNode(id: "acquire", stepType: "Source",
                               parameters: ["SourceType": .string("Window"), "WindowHandle": .string("${Window}")])]
    recipe.flow.startNodes = ["acquire"]
    return recipe
}

/// Upstream AiToolIpcHandler: LIST_AI_TOOLS and RUN_AI_TOOL.
@MainActor
@Suite struct AIToolCatalogTests {
    @Test func oneToolPerValidUniqueName() {
        let recipes = [aiToolRecipe(id: "a", toolName: "capture_window", maxImageSize: 800),
                       aiToolRecipe(id: "b", toolName: "capture_window"),
                       aiToolRecipe(id: "c", toolName: "list_windows"),
                       aiToolRecipe(id: "d", toolName: "bad name!"),
                       aiToolRecipe(id: "e", toolName: "screen", title: nil)]
        let fixture = LibraryFixture(builtIns: recipes)
        defer { fixture.cleanUp() }
        let tools = AIToolCatalog.tools(in: fixture.library)
        #expect(tools.map(\.toolName) == ["capture_window", "screen"])
        #expect(tools.first?.recipeId == "a")
        #expect(tools.first?.maxImageSize == 800)
        #expect(tools.last?.maxImageSize == AIToolImage.defaultMaxImageSize)
        // Without a Title the recipe's name
        #expect(tools.last?.title == "AI tool: screen")
        #expect(tools.first?.readOnly == true)
    }

    @Test func listReplyHasNamesAndArguments() throws {
        let fixture = LibraryFixture(builtIns: [aiToolRecipe(id: "a", toolName: "capture_window")])
        defer { fixture.cleanUp() }
        let reply = AIToolCatalog.listReply(AIToolCatalog.tools(in: fixture.library))
        #expect(reply.stdout == "1 AI tools.")
        let tool = try #require(reply.extra["tools"]?.arrayValue?.first?.objectValue)
        #expect(tool.string("name") == "capture_window")
        #expect(tool.string("recipe") == "a")
        #expect(tool["read_only"]?.boolValue == true)
        let window = try #require(tool["arguments"]?.arrayValue?.first?.objectValue)
        #expect(window.string("type") == "Window")
        #expect(window["required"]?.boolValue == true)
    }

    @Test func switchedOffRecipesAreNoTools() {
        let fixture = LibraryFixture(builtIns: [aiToolRecipe(id: "a", toolName: "capture_window")])
        defer { fixture.cleanUp() }
        fixture.library.setEnabled(false, recipeId: "a")
        #expect(AIToolCatalog.tools(in: fixture.library).isEmpty)
    }

    @Test func windowIdsBecomeWindowNumbers() throws {
        let fixture = LibraryFixture(builtIns: [aiToolRecipe(id: "a", toolName: "capture_window")])
        defer { fixture.cleanUp() }
        let tool = try #require(AIToolCatalog.tools(in: fixture.library).first)
        let prepared = try AIToolCatalog.prepareArguments(tool, supplied: ["Window": "w7", "ocr": "true"]) { reference in
            reference == "w7" ? .success(4321) : .failure(AIToolError("unknown"))
        }.get()
        #expect(prepared["Window"] == "4321")
        #expect(prepared["ocr"] == "true")
        let stale = AIToolCatalog.prepareArguments(tool, supplied: ["window": "w8"]) { _ in .failure(AIToolError("'w8' is not a current window id.")) }
        if case .failure(let error) = stale {
            #expect(error.message == "Error: argument 'window': 'w8' is not a current window id.")
        } else {
            Issue.record("A stale window id must fail")
        }
    }

    @Test func runsTheRecipeWithTheWindowAndReturnsThePicture() async throws {
        let harness = RecipeCommandHarness()
        defer { harness.cleanUp() }
        let fixture = LibraryFixture(builtIns: [aiToolRecipe(id: "recipe_ai_capture_window", toolName: "capture_window", maxImageSize: 4)])
        defer { fixture.cleanUp() }
        let tool = try #require(AIToolCatalog.tools(in: fixture.library).first)
        let arguments = try AIToolCatalog.prepareArguments(tool, supplied: ["window": "w1"]) { _ in .success(77) }.get()
        var request = try AIToolCatalog.runRequest(tool, arguments: arguments, library: fixture.library, client: "Claude").get()
        #expect(request.trigger?.triggerType == "AiTool")
        let output = RecipeRunOutput(context: nil, streamStdout: false, streamStderr: false)
        request.output = output
        let result = await harness.runner.start(request).result
        #expect(result.isSuccess)
        // The Source step got the window number, and the AI tool run added no destination
        #expect(harness.recorder.all == ["Source:Window", "Window:77"])
        let picture = await AIToolCatalog.picture(of: result.payload, maxImageSize: tool.maxImageSize, ocr: false)
        let reply = AIToolCatalog.runReply(result, tool: tool, stdout: output.collected.stdout, stderr: output.collected.stderr, picture: picture)
        #expect(reply.status == "ok")
        #expect(reply.extra["tool"]?.stringValue == "capture_window")
        let image = try #require(reply.extra["image"]?.objectValue)
        #expect(image.string("mime_type") == "image/png")
        #expect(image.int("width") == 4)
        #expect(image.int("original_width") == 8)
        let data = try #require(image.string("data"))
        #expect(Data(base64Encoded: data) != nil)
        #expect(reply.extra["title"]?.stringValue == "Test capture")
    }

    @Test func failedRunsSayWhy() {
        let tool = AIToolEntry(toolName: "t", title: "T", description: "", recipeId: "r", triggerIndex: 0, readOnly: true, destructive: false,
                               arguments: [], maxImageSize: 0)
        let result = RecipeFlowResult(flowId: UUID(), recipeId: "r", recipeName: "R", state: .failed, reason: "No window")
        let reply = AIToolCatalog.runReply(result, tool: tool, stdout: [], stderr: [], picture: nil)
        #expect(reply.status == "error")
        #expect(reply.exitCode == 1)
        #expect(reply.stderr == "No window")
        #expect(reply.extra["image"] == nil)
    }

    @Test func theTextIsNotRepeatedInTheVariables() {
        let tool = AIToolEntry(toolName: "t", title: "T", description: "", recipeId: "r", triggerIndex: 0, readOnly: true, destructive: false,
                               arguments: [], maxImageSize: 0)
        var payload = RecipePayload(image: recipeTestImage(), scale: 1, title: "x")
        payload.extractedText = "words"
        let result = RecipeFlowResult(flowId: UUID(), recipeId: "r", recipeName: "R", state: .completed,
                                      variables: RecipeVariables(["OcrText": .string("words"), "Ocr": .bool(true)]), payload: payload)
        let reply = AIToolCatalog.runReply(result, tool: tool, stdout: [], stderr: [], picture: nil)
        #expect(reply.extra["text"]?.stringValue == "words")
        let variables = reply.extra["variables"]?.objectValue
        #expect(variables?["OcrText"] == nil)
        #expect(variables?["Ocr"]?.boolValue == true)
    }
}
