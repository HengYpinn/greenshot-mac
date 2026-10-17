// Greenshot for Mac (Community) - an unofficial macOS port of Greenshot
// Copyright (C) 2026 Greenshot for Mac (Community) contributors
// Based on Greenshot, Copyright (C) 2007-2026 Thomas Braun, Jens Klingen, Robin Krom
// SPDX-License-Identifier: GPL-3.0-or-later

import Foundation

/// The recipes Greenshot brings along (upstream `RecipeManager.InitializeDefaultRecipes`, RecipeManager.cs:238-372, and
/// the built-in recipe providers `NotificationRecipes`, `BrowserExtensionRecipes`, `AiToolRecipes`). Ids, names, nodes and
/// flows as upstream; a file with the same id replaces one (the recipe manager's "Reset Default" brings it back).
public enum BuiltInRecipes {
    public static let regionId = "recipe_region"
    public static let windowId = "recipe_window"
    public static let activeWindowId = "recipe_active_window"
    public static let fullScreenId = "recipe_fullscreen"
    public static let lastRegionId = "recipe_lastregion"
    public static let clipboardId = "recipe_clipboard"
    public static let fileId = "recipe_file"
    public static let ocrId = "recipe_ocr"
    public static let notificationId = "recipe_notification"
    public static let browserExtensionId = "recipe_browser_extension"
    public static let aiCaptureWindowId = "recipe_ai_capture_window"
    public static let aiCaptureRegionId = "recipe_ai_capture_region"
    public static let aiCaptureScreenId = "recipe_ai_capture_screen"

    /// The built-ins the app also does without recipes (hotkeys, menus, a notification click): they run as recipes
    /// only when they differ from the stock recipe (`BuiltInCaptureRoute`).
    public static let directCaptureIds: Set<String> = [regionId, windowId, activeWindowId, fullScreenId, lastRegionId, clipboardId,
                                                        fileId, ocrId, notificationId]

    /// Every built-in recipe, in upstream's order.
    public static var all: [CaptureRecipe] {
        [region, window, activeWindow, fullScreen, lastRegion, clipboard, file, ocr, notification, browserExtension,
         aiCaptureWindow, aiCaptureRegion, aiCaptureScreen]
    }

    /// The stock built-in recipe with this id (case-insensitive).
    public static func recipe(id: String) -> CaptureRecipe? {
        all.first { recipeEquals($0.id, id) }
    }

    public static func isDirectCapture(_ id: String) -> Bool {
        directCaptureIds.contains { recipeEquals($0, id) }
    }

    // MARK: The capture recipes

    /// 1. Interactive region capture.
    public static var region: CaptureRecipe {
        interactive(regionId, "Capture region", "Interactively select a region on the screen", source: "Region", mode: "Region")
    }

    /// 2. Interactive window capture.
    public static var window: CaptureRecipe {
        interactive(windowId, "Capture window", "Interactively select a window on the screen", source: "Window", mode: "Window")
    }

    /// 3. The active window.
    public static var activeWindow: CaptureRecipe {
        direct(activeWindowId, "Capture active window", "Directly capture the active window", source: "ActiveWindow")
    }

    /// 4. Full screen.
    public static var fullScreen: CaptureRecipe {
        direct(fullScreenId, "Capture full screen", "Capture the entire screen or monitor", source: "FullScreen")
    }

    /// 5. The last region again.
    public static var lastRegion: CaptureRecipe {
        direct(lastRegionId, "Capture last region", "Re-capture the coordinates of the previous region", source: "LastRegion")
    }

    /// 6. The image on the clipboard, to the editor.
    public static var clipboard: CaptureRecipe {
        var recipe = CaptureRecipe(id: clipboardId, name: "Capture from clipboard", description: "Import and process image from system clipboard")
        recipe.nodes = [source("acquire", "Clipboard", captureMouse: false), destinations("export", ["Editor"])]
        recipe.flow = flow(start: "acquire", ["acquire", "export"])
        RecipeSlotNodes.addStandardSlots(to: &recipe, afterCaptureBefore: "export", exportNode: "export")
        return recipe
    }

    /// 7. An image or .greenshot file, to the editor; the OpenFile trigger is "Open with Greenshot".
    public static var file: CaptureRecipe {
        var recipe = CaptureRecipe(id: fileId, name: "Open file", description: "Import an image or .greenshot file from disk")
        recipe.nodes = [source("acquire", "File", captureMouse: false), destinations("export", ["Editor"])]
        recipe.flow = flow(start: "acquire", ["acquire", "export"])
        recipe.triggers = [TriggerConfig(triggerType: WellKnownTriggerType.openFile, name: "Default Open With File Trigger",
                                         parameters: ["FireAndForget": .bool(false)])]
        return recipe
    }

    /// 8. Text of a region to the clipboard.
    public static var ocr: CaptureRecipe {
        var recipe = CaptureRecipe(id: ocrId, name: "OCR text to clipboard", description: "Select a region and extract text directly to clipboard")
        recipe.nodes = [
            source("acquire", "TextOcr", captureMouse: false),
            selection("select", "Text"),
            feedback("feedback"),
            processors("ocr", ids: ["Windows10OcrProcessor"]),
            RecipeNode(id: "export", stepType: WellKnownStepType.clipboard, name: "Copy to Clipboard",
                       parameters: ["ClipboardMode": .string("TextOnly")])
        ]
        recipe.flow = flow(start: "acquire", ["acquire", "select", "feedback", "ocr", "export"])
        return recipe
    }

    // MARK: The recipes of the optional parts

    /// The capture of a clicked notification, offered in the destination flyout (upstream `NotificationRecipes`).
    public static var notification: CaptureRecipe {
        var recipe = CaptureRecipe(id: notificationId, name: "Capture of a notification",
                                   description: "Offer the capture of a clicked notification in the destination flyout")
        // The click hands over the kept capture, the source passes it on (it reads the variable Filename otherwise).
        recipe.nodes = [source("acquire", "File", captureMouse: false), dynamicDestination("export", title: "Export Capture")]
        recipe.flow = flow(start: "acquire", ["acquire", "export"])
        return recipe
    }

    /// Captures of the browser extension (upstream `BrowserExtensionRecipes`).
    public static var browserExtension: CaptureRecipe {
        var recipe = CaptureRecipe(id: browserExtensionId, name: "Capture from browser extension",
                                   description: "Process screenshots received from the browser extension and choose destination interactively")
        recipe.nodes = [source("acquire", "Extension", captureMouse: false), dynamicDestination("export", title: "Export Browser Capture")]
        recipe.flow = flow(start: "acquire", ["acquire", "export"])
        recipe.triggers = [TriggerConfig(triggerType: WellKnownTriggerType.extension, name: "Default Browser Extension Trigger",
                                         parameters: ["FireAndForget": .bool(false)])]
        RecipeSlotNodes.addStandardSlots(to: &recipe, afterCaptureBefore: "export", exportNode: "export")
        return recipe
    }

    /// AI tools: one window, with its exact contents, without activating it (upstream `AiToolRecipes`).
    public static var aiCaptureWindow: CaptureRecipe {
        var acquire = source("acquire", "Window", captureMouse: false, delayMs: 0)
        acquire.parameters["WindowHandle"] = .string("${Window}")
        let window = argument("window", variable: "Window", type: .window, required: true,
                              description: "The id of the window from list_windows, e.g. w7")
        return aiTool(aiCaptureWindowId, "AI tool: capture window",
                      "Captures a window for an AI tool, with its exact contents (also when it is covered), without activating it",
                      acquire: acquire, tool: "capture_window", title: "Capture window",
                      toolDescription: "Screenshot of one window, with its exact contents even when other windows cover it. The window is not activated. Use list_windows first and pass the id of the window (e.g. w7).",
                      arguments: [window, ocrArgument])
    }

    /// AI tools: a part of the screen.
    public static var aiCaptureRegion: CaptureRecipe {
        let region = argument("region", variable: "PreSuppliedRegion", type: .region, required: true,
                              description: "x,y,width,height in screen coordinates, e.g. 0,0,800,600")
        return aiTool(aiCaptureRegionId, "AI tool: capture region", "Captures a part of the screen for an AI tool",
                      acquire: source("acquire", "Region", captureMouse: false, delayMs: 0), tool: "capture_region", title: "Capture region",
                      toolDescription: "Screenshot of a part of the screen, in screen coordinates (list_windows has the bounds of the windows and displays). Use it to see details at full resolution.",
                      arguments: [region, ocrArgument])
    }

    /// AI tools: every display.
    public static var aiCaptureScreen: CaptureRecipe {
        aiTool(aiCaptureScreenId, "AI tool: capture screen", "Captures all displays for an AI tool",
               acquire: source("acquire", "FullScreen", captureMouse: false, delayMs: 0, screenMode: "FullScreen"),
               tool: "capture_screen", title: "Capture screen",
               toolDescription: "Screenshot of all displays. For one display or a part of the screen use capture_region with the bounds from list_windows.",
               arguments: [ocrArgument])
    }

    // MARK: Building blocks (upstream `RecipeStepConfig.Create*`)

    /// Region and window: scan before the selection, select, feedback, process after it, export, notify; standard slots.
    private static func interactive(_ id: String, _ name: String, _ description: String, source sourceType: String, mode: String) -> CaptureRecipe {
        var recipe = CaptureRecipe(id: id, name: name, description: description)
        recipe.nodes = [
            source("acquire", sourceType),
            processors("scan_pre", timing: "PreSelection", name: "Scan Before Selection"),
            selection("select", mode),
            feedback("feedback"),
            processors("scan_post", timing: "PostSelection", name: "Process After Selection"),
            destinations("export"),
            notificationNode("notify")
        ]
        recipe.flow = flow(start: "acquire", ["acquire", "scan_pre", "select", "feedback", "scan_post", "export", "notify"])
        RecipeSlotNodes.addStandardSlots(to: &recipe, afterCaptureBefore: "scan_post", exportNode: "export")
        return recipe
    }

    /// Active window, full screen, last region: feedback, processors, export, notify; standard slots.
    private static func direct(_ id: String, _ name: String, _ description: String, source sourceType: String) -> CaptureRecipe {
        var recipe = CaptureRecipe(id: id, name: name, description: description)
        recipe.nodes = [source("acquire", sourceType), feedback("feedback"), processors("processors"), destinations("export"),
                        notificationNode("notify")]
        recipe.flow = flow(start: "acquire", ["acquire", "feedback", "processors", "export", "notify"])
        RecipeSlotNodes.addStandardSlots(to: &recipe, afterCaptureBefore: "processors", exportNode: "export")
        return recipe
    }

    /// The AI tool recipes: acquire, OCR when the `Ocr` argument is true; no destination (the result goes back to the AI).
    private static func aiTool(_ id: String, _ name: String, _ description: String, acquire: RecipeNode, tool: String, title: String,
                               toolDescription: String, arguments: [JSONValue]) -> CaptureRecipe {
        var recipe = CaptureRecipe(id: id, name: name, description: description)
        let condition = RecipeNode(id: "ocr_wanted", stepType: WellKnownStepType.conditional, name: "OCR wanted?",
                                   parameters: ["Branches": .array([.object(["Key": .string("ocr"), "Expression": .string("${Ocr}")])])])
        recipe.nodes = [acquire, condition, processors("ocr", ids: ["Windows10OcrProcessor"])]
        recipe.flow = flow(start: "acquire", ["acquire", "ocr_wanted"])
        recipe.flow.conditionalTransitions = [ConditionalTransition(from: "ocr_wanted", branch: "ocr", to: "ocr")]
        recipe.triggers = [TriggerConfig(triggerType: WellKnownTriggerType.aiTool, name: title, parameters: [
            "ToolName": .string(tool), "Title": .string(title), "Description": .string(toolDescription),
            "ReadOnly": .bool(true), "Destructive": .bool(false), "Arguments": .array(arguments)
        ])]
        return recipe
    }

    private static var ocrArgument: JSONValue {
        argument("ocr", variable: "Ocr", type: .boolean, defaultValue: "false",
                 description: "true to also return the text in the image (OCR) with the position of each line")
    }

    private static func argument(_ name: String, variable: String, type: ContractDataType, required: Bool = false,
                                 defaultValue: String? = nil, description: String) -> JSONValue {
        var object: JSONObject = ["name": .string(name), "variable": .string(variable), "type": .string(type.rawValue),
                                  "required": .bool(required), "description": .string(description)]
        if let defaultValue { object["defaultValue"] = .string(defaultValue) }
        return .object(object)
    }

    private static func source(_ id: String, _ sourceType: String, captureMouse: Bool? = nil, delayMs: Int? = nil,
                               screenMode: String? = nil) -> RecipeNode {
        var node = RecipeNode(id: id, stepType: WellKnownStepType.source, name: "Acquire \(sourceType)",
                              parameters: ["SourceType": .string(sourceType)])
        if let captureMouse { node.parameters["CaptureMouseCursor"] = .bool(captureMouse) }
        if let delayMs { node.parameters["DelayMs"] = .number(Double(delayMs)) }
        if let screenMode { node.parameters["ScreenCaptureMode"] = .string(screenMode) }
        return node
    }

    private static func selection(_ id: String, _ mode: String) -> RecipeNode {
        RecipeNode(id: id, stepType: WellKnownStepType.interactiveSelection, name: "Select \(mode)",
                   parameters: ["SelectionMode": .string(mode), "AllowWindowSnapping": .bool(true)])
    }

    private static func feedback(_ id: String) -> RecipeNode {
        RecipeNode(id: id, stepType: WellKnownStepType.immediateFeedback, name: "Capture Feedback")
    }

    private static func processors(_ id: String, ids: [String]? = nil, timing: String? = nil, name: String = "Run Processors") -> RecipeNode {
        var node = RecipeNode(id: id, stepType: WellKnownStepType.processors, name: name)
        if let ids { node.parameters["ProcessorIds"] = .array(ids.map(JSONValue.string)) }
        if let timing { node.parameters["Timing"] = .string(timing) }
        return node
    }

    private static func destinations(_ id: String, _ designations: [String]? = nil) -> RecipeNode {
        var node = RecipeNode(id: id, stepType: WellKnownStepType.destinations, name: "Export Destinations")
        if let designations { node.parameters["DestinationDesignations"] = .array(designations.map(JSONValue.string)) }
        return node
    }

    private static func notificationNode(_ id: String) -> RecipeNode {
        RecipeNode(id: id, stepType: WellKnownStepType.notification, name: "Completion Notification")
    }

    private static func dynamicDestination(_ id: String, title: String) -> RecipeNode {
        RecipeNode(id: id, stepType: WellKnownStepType.dynamicDestination, name: title,
                   parameters: ["Title": .string(title), "ShowPreview": .bool(true), "AllowRecipeForwarding": .bool(true)])
    }

    /// A linear flow through `chain` from `start`.
    private static func flow(start: String, _ chain: [String]) -> RecipeFlow {
        var flow = RecipeFlow(startNodes: [start])
        for (from, to) in zip(chain, chain.dropFirst()) { flow.addTransition(from: from, to: to) }
        return flow
    }
}
