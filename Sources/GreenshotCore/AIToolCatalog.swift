// Greenshot for Mac (Community) - an unofficial macOS port of Greenshot
// Copyright (C) 2026 Greenshot for Mac (Community) contributors
// Based on Greenshot, Copyright (C) 2007-2026 Thomas Braun, Jens Klingen, Robin Krom
// SPDX-License-Identifier: GPL-3.0-or-later

import CoreGraphics
import Foundation

/// One tool greenshot-mcp offers besides its own: an enabled AiTool trigger of an enabled recipe (upstream
/// `AiToolIpcHandler.AiToolEntry`).
public struct AIToolEntry: Equatable, Sendable {
    public var toolName: String
    public var title: String
    public var description: String
    public var recipeId: String
    public var triggerIndex: Int
    public var readOnly: Bool
    public var destructive: Bool
    public var arguments: [CommandlineArgument]
    /// The longest side of the returned picture (trigger parameter `MaxImageSize`, default 1568, 0 = original size).
    public var maxImageSize: Int
}

/// LIST_AI_TOOLS and RUN_AI_TOOL (upstream `Ai/AiToolIpcHandler.cs`): the recipes with an AI tool trigger are the AI
/// tools' tools; everything an AI tool captures goes through such a recipe (the built-in capture_window, capture_region
/// and capture_screen too).
@MainActor
public enum AIToolCatalog {
    /// Tool names greenshot-mcp has itself.
    public static let reservedNames: Set<String> = ["list_windows"]

    /// One tool per active AI tool trigger; a name used twice belongs to the first recipe, an invalid name isn't offered.
    public static func tools(in library: RecipeLibrary, client: String = "") -> [AIToolEntry] {
        var names = Set(reservedNames)
        var result: [AIToolEntry] = []
        for command in library.commands(for: .aiTool(client: client)) {
            guard let loaded = library.recipe(id: command.recipeId), loaded.recipe.triggers.indices.contains(command.triggerIndex) else { continue }
            let trigger = loaded.recipe.triggers[command.triggerIndex]
            let toolName = trigger.toolName?.trimmingCharacters(in: .whitespaces) ?? ""
            guard BuiltInTriggerContracts.isValidToolName(toolName) else {
                log.warn("The AI tool trigger of recipe '\(loaded.recipe.id)' has no valid ToolName ('\(toolName)'), it is not offered.")
                continue
            }
            guard names.insert(toolName.lowercased()).inserted else {
                log.warn("The AI tool '\(toolName)' of recipe '\(loaded.recipe.id)' is not offered, another recipe (or greenshot-mcp) uses that name.")
                continue
            }
            let title = trigger.toolTitle.flatMap { $0.isEmpty ? nil : $0 } ?? loaded.recipe.name
            let description = trigger.commandDescription.flatMap { $0.isEmpty ? nil : $0 }
                ?? loaded.recipe.description.flatMap { $0.isEmpty ? nil : $0 } ?? loaded.recipe.name
            let maxImageSize = max(0, trigger.parameters.int("MaxImageSize") ?? AIToolImage.defaultMaxImageSize)
            result.append(AIToolEntry(toolName: toolName, title: title, description: description, recipeId: loaded.recipe.id,
                                      triggerIndex: command.triggerIndex, readOnly: trigger.toolReadOnly,
                                      destructive: trigger.toolDestructive, arguments: trigger.arguments.filter { !$0.name.isEmpty },
                                      maxImageSize: maxImageSize))
        }
        return result
    }

    /// LIST_AI_TOOLS's reply: names and descriptions only, no screen contents (no consent needed).
    public static func listReply(_ tools: [AIToolEntry]) -> IPCReply {
        let entries = tools.map { tool -> JSONValue in
            let arguments = tool.arguments.map { argument -> JSONValue in
                .object(["name": .string(argument.name), "description": .string(argument.description ?? ""),
                         "required": .bool(argument.required), "default_value": argument.defaultValue.map(JSONValue.string) ?? .null,
                         "type": .string(argument.type.rawValue),
                         "allowed_values": argument.allowedValues.map { .array($0.map(JSONValue.string)) } ?? .null])
            }
            return .object(["name": .string(tool.toolName), "title": .string(tool.title), "description": .string(tool.description),
                            "recipe": .string(tool.recipeId), "read_only": .bool(tool.readOnly), "destructive": .bool(tool.destructive),
                            "arguments": .array(arguments)])
        }
        return .ok("\(entries.count) AI tools.", extra: ["tools": .array(entries)])
    }

    /// The tool of a RUN_AI_TOOL request, by its exact name (any case).
    public static func tool(named name: String, in tools: [AIToolEntry]) -> AIToolEntry? {
        let wanted = name.trimmingCharacters(in: .whitespaces)
        return tools.first { $0.toolName.caseInsensitiveCompare(wanted) == .orderedSame }
    }

    /// The arguments with each Window argument's id from `list_windows` replaced by the window number (decimal text, what
    /// the Source step's `WindowHandle` takes); an id that isn't the AI tool's, has expired or whose window is gone fails.
    /// Region arguments must be "x,y,width,height".
    public static func prepareArguments(_ tool: AIToolEntry, supplied: [String: String],
                                        resolveWindow: (String) -> Result<CGWindowID, AIToolError>) -> Result<[String: String], AIToolError> {
        if let refusal = IPCRecipeCommands.argumentRefusal(declared: tool.arguments, supplied: supplied, aiTool: true) {
            return .failure(AIToolError(refusal))
        }
        var prepared = supplied
        for argument in tool.arguments where argument.type == .window {
            guard let key = prepared.keys.first(where: { $0.caseInsensitiveCompare(argument.name) == .orderedSame }),
                  let reference = prepared[key], !reference.trimmingCharacters(in: .whitespaces).isEmpty else { continue }
            switch resolveWindow(reference) {
            case .success(let window): prepared[key] = String(window)
            case .failure(let error): return .failure(AIToolError("Error: argument '\(argument.name)': \(error.message)"))
            }
        }
        return .success(prepared)
    }

    /// The run request of the tool's recipe: declared arguments only, by their types (upstream `CommandlineArgumentBinder`
    /// with the AI tool's window ids already resolved). Paths must be absolute: an AI tool has no working directory.
    public static func runRequest(_ tool: AIToolEntry, arguments: [String: String], library: RecipeLibrary,
                                  client: String) -> Result<RecipeRunRequest, AIToolError> {
        do {
            let request = try library.runRequest(command: tool.toolName, arguments: arguments, source: .aiTool(client: client)) { raw, _ in
                switch IPCPathValidator.sanitize(raw, cwd: nil) {
                case .success(let url): return url.path
                case .failure(let failure): throw RecipeStepError("[SECURITY] \(failure.message)")
                }
            }
            return .success(request)
        } catch {
            return .failure(AIToolError((error as? RecipeStepError)?.message ?? error.localizedDescription))
        }
    }

    /// What a run gives back besides its text: the final picture as PNG and the lines OCR found.
    public struct Picture: Sendable {
        public var png: Data
        public var width: Int
        public var height: Int
        public var originalWidth: Int
        public var originalHeight: Int
        public var ocrLines: [RecognizedLine]?
    }

    /// The flow's final picture (with what the recipe drew on it) scaled for the tool, and with `ocr` the lines of text
    /// with their bounds in pixels of the unscaled picture. Runs off the cooperative threads (image work and Vision).
    public nonisolated static func picture(of payload: RecipePayload?, maxImageSize: Int, ocr: Bool, language: String = "") async -> Picture? {
        guard let payload else { return nil }
        return await withCheckedContinuation { continuation in
            DispatchQueue.global(qos: .userInitiated).async {
                let image = payload.flattened() ?? payload.image
                guard let encoded = AIToolImage.encodePNG(image, maxSize: maxImageSize) else {
                    continuation.resume(returning: nil)
                    return
                }
                let lines = ocr ? (try? TextRecognizer.recognizeLines(in: image, language: language)) : nil
                continuation.resume(returning: Picture(png: encoded.data, width: encoded.width, height: encoded.height,
                                                       originalWidth: image.width, originalHeight: image.height, ocrLines: lines))
            }
        }
    }

    /// RUN_AI_TOOL's reply (upstream `HandleRunAiToolAsync`): status, the recipe's stdout / stderr, its variables (without
    /// the copies of the text, it is in "text" once), the picture (PNG, base64) and the text found by OCR.
    public static func runReply(_ result: RecipeFlowResult, tool: AIToolEntry, stdout: [String], stderr: [String],
                                picture: Picture?) -> IPCReply {
        let failed = result.state == .failed || result.state == .cancelled
        let exitCode = result.exitCode != 0 ? Int32(clamping: result.exitCode) : (failed ? IPCExitCode.failure : IPCExitCode.ok)
        var stderrText = stderr.isEmpty ? nil : stderr.joined(separator: "\n")
        if failed, stderrText == nil { stderrText = result.reason ?? result.errorDescription ?? "The recipe failed." }
        let text = result.payload?.extractedText.flatMap { $0.isEmpty ? nil : $0 }
        var variables = JSONObject()
        for member in result.variables {
            if let text, member.value.stringValue == text { continue }
            variables[member.key] = member.value
        }
        var extra: JSONObject = ["tool": .string(tool.toolName), "recipe": .string(tool.recipeId), "variables": .object(variables)]
        if let picture {
            let image: JSONObject = ["mime_type": .string("image/png"), "data": .string(picture.png.base64EncodedString()),
                                     "width": .number(Double(picture.width)), "height": .number(Double(picture.height)),
                                     "original_width": .number(Double(picture.originalWidth)),
                                     "original_height": .number(Double(picture.originalHeight))]
            extra["image"] = .object(image)
        }
        if let payload = result.payload {
            extra["title"] = .string(payload.title)
            if let source = payload.sourceType { extra["source"] = .string(source) }
        }
        if let text { extra["text"] = .string(text) }
        if let lines = picture?.ocrLines, !lines.isEmpty { extra["ocr_lines"] = AIToolImage.ocrLines(lines) }
        let stdoutText = stdout.isEmpty ? nil : stdout.joined(separator: "\n")
        return IPCReply(status: failed ? "error" : "ok", exitCode: exitCode, stdout: stdoutText, stderr: stderrText, extra: extra)
    }
}

private let log = Log("AITools")
