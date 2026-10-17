// Greenshot for Mac (Community) - an unofficial macOS port of Greenshot
// Copyright (C) 2026 Greenshot for Mac (Community) contributors
// Based on Greenshot, Copyright (C) 2007-2026 Thomas Braun, Jens Klingen, Robin Krom
// SPDX-License-Identifier: GPL-3.0-or-later
// Owned by REDITOR after the wave 4 prep.

import AppKit
import GreenshotCore
import SwiftUI

extension Snapshots {
    /// Renders of the recipe editor (without a running recipe runtime): the step list with the generated forms, the tabs,
    /// the Flow view in light and dark, the pending bar's three texts, validation problems and the annotation import.
    static func renderRecipeEditorExtras(to folder: URL, sample: CGImage, settings: SettingsStore) throws {
        func file(_ name: String) -> URL { folder.appendingPathComponent(name) }
        let branching = sampleBranchingRecipe()
        try write(recipeEditor(branching, select: "border"), to: file("recipe-editor.png"))
        let decision = sampleDecisionRecipe()
        try write(recipeEditor(decision, select: "decide"), to: file("recipe-editor-conditional.png"))
        try write(recipeEditor(decision, select: "confirm"), to: file("recipe-editor-prompt.png"))
        try write(recipeEditor(branching, select: "watermark", height: 1500), to: file("recipe-editor-annotation.png"))
        try write(recipeEditor(decision, tab: .triggers, height: 1300), to: file("recipe-editor-triggers.png"))
        try write(recipeEditor(decision, tab: .options), to: file("recipe-editor-options.png"))
        try write(recipeEditor(decision, tab: .recipe), to: file("recipe-editor-recipe.png"))
        try write(recipeEditor(RecipeEditorCatalog.newExtension(), tab: .recipe), to: file("recipe-editor-extension.png"))
        try write(recipeEditor(decision, tab: .errors), to: file("recipe-editor-errors.png"))
        try write(recipeEditor(decision, tab: .json), to: file("recipe-editor-json.png"))
        try write(jsonDraftEditor(decision), to: file("recipe-editor-json-draft.png"))
        try write(recipeEditor(branching, tab: .flow), to: file("recipe-editor-flow.png"))
        try write(recipeEditor(decision, tab: .flow, dark: true), to: file("recipe-editor-flow-dark.png"))
        try writeText(RecipeMermaid.text(of: decision), to: file("recipe-editor-mermaid.txt"))
        var broken = branching
        broken.nodes[0].parameters["SourceType"] = .string("Everywhere")
        broken.flow.addTransition(from: "export", to: "ghost")
        try write(recipeEditor(broken, select: "capture"), to: file("recipe-editor-issues.png"))
        let notices: [(String, String, Bool)] = [
            ("pending-save", "Saving asks for your approval: Runs when another app copies an image (Clipboard). It needs network access (uploads).", false),
            ("pending-changed", "This recipe file changed outside Greenshot. Greenshot asks for your approval before it runs.", true),
            ("pending-off", "1 trigger was left off when this recipe was approved: \"Runs when another app copies an image\". Review the approval to switch it on.", true)
        ]
        for (name, text, review) in notices {
            let model = RecipeEditorModel(environment: .offline)
            model.open(decision, fileURL: URL(fileURLWithPath: "/Users/me/Recipes/\(decision.id).gsrecipe.json"), saved: name != "pending-save")
            model.showNotice(text, canReview: review)
            keepAlive.append(model)
            try write(hosted(RecipeEditorTop(model: model), size: NSSize(width: 1120, height: 130)), to: file("recipe-editor-\(name).png"))
        }
        let editors = sampleImportEditors(sample: sample)
        try write(hosted(RecipeSelectEditorView(editors: editors, choose: { _ in }, cancel: {}).frame(width: 760, height: 520),
                         size: NSSize(width: 760, height: 520)), to: file("recipe-select-editor.png"))
        let model = RecipeEditorModel(environment: .offline)
        model.open(branching, fileURL: nil, saved: true)
        keepAlive.append(model)
        try write(hosted(RecipeAnnotationImportForm(model: model, nodeId: "watermark", editor: editors[0], done: {}).frame(width: 760, height: 520),
                         size: NSSize(width: 760, height: 520)), to: file("recipe-import-annotations.png"))
    }

    /// The JSON tab with unapplied text, after the recipe changed in a form (the stale-draft warning).
    private static func jsonDraftEditor(_ recipe: CaptureRecipe) -> NSBitmapImageRep? {
        let model = RecipeEditorModel(environment: .offline)
        model.open(recipe, fileURL: URL(fileURLWithPath: "/Users/me/Recipes/\(recipe.id).gsrecipe.json"), saved: true)
        model.tab = .json
        model.setJSONDraft((model.content ?? "").replacingOccurrences(of: "Route by Screen Size", with: "Route by Size (draft)"))
        model.edit("Changed the description") { $0.description = "Changed in the Recipe tab" }
        keepAlive.append(model)
        return hosted(RecipeEditorView(model: model), size: NSSize(width: 1120, height: 740))
    }

    /// The editor window's content with a recipe, a selected step or tab, a pending-bar text.
    private static func recipeEditor(_ recipe: CaptureRecipe, select nodeId: String? = nil, tab: RecipeEditorModel.Tab = .step,
                                     notice: (String, Bool)? = nil, dark: Bool = false, height: CGFloat = 740) -> NSBitmapImageRep? {
        let model = RecipeEditorModel(environment: .offline)
        model.open(recipe, fileURL: URL(fileURLWithPath: "/Users/me/Library/Application Support/Greenshot/Recipes/\(recipe.id).gsrecipe.json"),
                   saved: true)
        if let nodeId { model.select(nodeId: nodeId) }
        model.tab = tab
        if let notice { model.showNotice(notice.0, canReview: notice.1) }
        model.status = "Loaded: \(recipe.id).gsrecipe.json"
        keepAlive.append(model)
        return hosted(RecipeEditorView(model: model), size: NSSize(width: 1120, height: height), dark: dark)
    }

    private static func hosted<V: View>(_ view: V, size: NSSize, dark: Bool = false) -> NSBitmapImageRep? {
        let hosting = NSHostingView(rootView: view.frame(width: size.width, height: size.height))
        hosting.frame = NSRect(origin: .zero, size: size)
        let window = NSWindow(contentRect: hosting.frame, styleMask: [.titled, .resizable], backing: .buffered, defer: false)
        window.appearance = NSAppearance(named: dark ? .darkAqua : .aqua)
        window.contentView = hosting
        hosting.layoutSubtreeIfNeeded()
        RunLoop.current.run(until: Date().addingTimeInterval(0.05))
        hosting.layoutSubtreeIfNeeded()
        keepAlive.append(window)
        return capture(hosting)
    }

    /// Capture → selection → (camera sound ‖ variables → watermark) → border → export.
    private static func sampleBranchingRecipe() -> CaptureRecipe {
        var recipe = CaptureRecipe(id: "recipe_dag_watermark", name: "Watermarked Region",
                                   description: "Region capture with a parallel camera sound, a watermark and a border")
        recipe.triggers = [TriggerConfig(triggerType: WellKnownTriggerType.hotkey, name: "Watermark hotkey",
                                         parameters: ["Hotkey": .string("Ctrl + Shift + W")])]
        recipe.nodes = [
            RecipeNode(id: "capture", stepType: WellKnownStepType.source, name: "Capture Region", parameters: ["SourceType": .string("Region")]),
            RecipeNode(id: "select", stepType: WellKnownStepType.interactiveSelection, name: "Select Area",
                       parameters: ["SelectionMode": .string("Region"), "AllowWindowSnapping": .bool(true)]),
            RecipeNode(id: "feedback", stepType: WellKnownStepType.immediateFeedback, name: "Camera Sound", parameters: ["PlaySound": .bool(true)]),
            RecipeNode(id: "vars", stepType: WellKnownStepType.setVariable, name: "Watermark Text",
                       parameters: ["Variables": .object(["watermark_text": .string("Captured by ${user.username} [${now:yyyy-MM-dd HH:mm}]")])]),
            RecipeNode(id: "watermark", stepType: WellKnownStepType.annotation, name: "Stamp Watermark", parameters: [
                "Annotations": .array([
                    .object(["Type": .string("QRCode"), "QrType": .string("WiFi"), "WifiSsid": .string("Office"),
                             "WifiPassword": .string("secret"), "HorizontalAnchor": .string("Left"), "VerticalAnchor": .string("Bottom"),
                             "Size": .number(96)]),
                    .object(["Type": .string("Text"), "Text": .string("${context.watermark_text}"), "HorizontalAnchor": .string("Right"),
                             "VerticalAnchor": .string("Bottom"), "OffsetX": .number(-20), "OffsetY": .number(-20), "Width": .number(370),
                             "Height": .number(30), "LineColor": .string("#FFFFFF"), "FontSize": .number(9.5), "Bold": .bool(true)])
                ])]),
            RecipeNode(id: "border", stepType: WellKnownStepType.effect, name: "Blue Border",
                       parameters: ["Effect": .string("Border"), "Width": .number(4), "Color": .string("#0078D7")]),
            RecipeNode(id: "export", stepType: WellKnownStepType.destinations, name: "Export",
                       parameters: ["DestinationDesignations": .array([.string("Editor"), .string("Clipboard")])])
        ]
        recipe.flow = RecipeFlow(startNodes: ["capture"])
        for (from, to) in [("capture", "select"), ("select", "feedback"), ("select", "vars"), ("vars", "watermark"),
                           ("feedback", "border"), ("watermark", "border"), ("border", "export")] {
            recipe.flow.addTransition(from: from, to: to)
        }
        return recipe
    }

    /// Upstream docs Example 4 with a prompt, triggers, an option and error routes.
    private static func sampleDecisionRecipe() -> CaptureRecipe {
        var recipe = CaptureRecipe(id: "recipe_size_routing", name: "Route by Screen Size", description: "Large captures go to the editor, small ones to the clipboard")
        recipe.triggers = [
            TriggerConfig(triggerType: WellKnownTriggerType.hotkey, name: "Hotkey", parameters: ["Hotkey": .string("Ctrl + Shift + R")]),
            TriggerConfig(triggerType: WellKnownTriggerType.commandline, name: "CLI", parameters: [
                "Command": .string("route"), "Description": .string("Captures and routes by size"), "FireAndForget": .bool(false),
                "Arguments": .array([.object(["name": .string("region"), "type": .string("Region"), "description": .string("Area to capture")])])]),
            TriggerConfig(triggerType: WellKnownTriggerType.aiTool, name: "AI", parameters: [
                "ToolName": .string("route_capture"), "Title": .string("Route a capture"), "Description": .string("Captures the screen"),
                "ReadOnly": .bool(true)])
        ]
        var threshold = RecipeOption(key: "min_width", type: .integer, defaultValue: .number(800))
        threshold.label = "Large from (px)"
        threshold.min = 100
        threshold.max = 4000
        var ask = RecipeOption(key: "ask", type: .boolean, defaultValue: .bool(true))
        ask.label = "Ask before opening the editor"
        ask.quickSettings = true
        recipe.options = [threshold, ask]
        recipe.nodes = [
            RecipeNode(id: "source", stepType: WellKnownStepType.source, name: "Capture Screen", parameters: ["SourceType": .string("FullScreen")]),
            RecipeNode(id: "decide", stepType: WellKnownStepType.conditional, name: "Is it large?", parameters: [
                "Branches": .array([.object(["key": .string("A"), "expression": .string("${payload.width > option.min_width}")]),
                                    .object(["key": .string("B"), "expression": .string("else")])])]),
            RecipeNode(id: "confirm", stepType: WellKnownStepType.userPrompt, name: "Open the editor?", parameters: [
                "Title": .string("Large capture"), "Message": .string("Open it in the editor?"), "TimeoutSeconds": .number(10),
                "DefaultChoice": .string("Yes"),
                "Choices": .array([.object(["Key": .string("Yes"), "Label": .string("Open Editor"), "Style": .string("Primary"), "IsDefault": .bool(true)]),
                                   .object(["Key": .string("No"), "Label": .string("Clipboard"), "Style": .string("Secondary"), "IsCancel": .bool(true)])])]),
            RecipeNode(id: "large", stepType: WellKnownStepType.editor, name: "Image Editor"),
            RecipeNode(id: "small", stepType: WellKnownStepType.clipboard, name: "System Clipboard"),
            RecipeNode(id: "notify", stepType: WellKnownStepType.notification, name: "Notify")
        ]
        recipe.flow = RecipeFlow(startNodes: ["source"])
        recipe.flow.addTransition(from: "source", to: "decide")
        recipe.flow.addTransition(from: "large", to: "notify")
        recipe.flow.addTransition(from: "small", to: "notify")
        recipe.flow.conditionalTransitions = [
            ConditionalTransition(from: "decide", branch: "A", to: "confirm"), ConditionalTransition(from: "decide", branch: "B", to: "small"),
            ConditionalTransition(from: "confirm", branch: "Yes", to: "large"), ConditionalTransition(from: "confirm", branch: "No", to: "small")
        ]
        recipe.flow.errorTransitions = [ErrorTransition(from: "large", to: "small"), ErrorTransition(from: "*", targetRecipeId: "recipe_region")]
        recipe.nodes[3].onErrorNodeId = "small"
        return recipe
    }

    /// Two "open editors" for the import sheets.
    private static func sampleImportEditors(sample: CGImage) -> [RecipeAnnotationImportSource.Editor] {
        var arrow = Annotation(kind: .arrow, start: CGPoint(x: 400, y: 300), end: CGPoint(x: 800, y: 520))
        arrow.style.lineWidth = 4
        var label = Annotation(kind: .text, start: CGPoint(x: 900, y: 200), end: CGPoint(x: 1500, y: 280), text: "Look here")
        label.style.fontSize = 24
        var spec = BarcodeSpec()
        spec.text = "https://getgreenshot.org"
        var code = Annotation(kind: .barcode, start: CGPoint(x: 2100, y: 1100), end: CGPoint(x: 2380, y: 1380))
        code.barcode = spec
        let blur = Annotation(kind: .obfuscate, start: CGPoint(x: 200, y: 900), end: CGPoint(x: 900, y: 1000))
        let counter = Annotation(kind: .counter, start: CGPoint(x: 1200, y: 600), end: CGPoint(x: 1260, y: 660))
        let picture = Annotation.picture(sample, pictureScale: 8, at: CGPoint(x: 1700, y: 300), documentScale: 2)
        let first = RecipeAnnotationImportSource.Editor(id: UUID(), title: "Greenshot 2026-10-17 14-30-05", image: sample, scale: 2,
                                                        elements: [arrow, label, code, blur, counter] + (picture.map { [$0] } ?? []))
        let second = RecipeAnnotationImportSource.Editor(id: UUID(), title: "Release notes", image: sample, scale: 2, elements: [label])
        return [first, second]
    }
}
