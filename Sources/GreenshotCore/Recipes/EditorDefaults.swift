// Greenshot for Mac (Community) - an unofficial macOS port of Greenshot
// Copyright (C) 2026 Greenshot for Mac (Community) contributors
// Based on Greenshot, Copyright (C) 2007-2026 Thomas Braun, Jens Klingen, Robin Krom
// SPDX-License-Identifier: GPL-3.0-or-later

import Foundation

/// One entry of the recipe editor's "Add Step" menu (upstream's step toolbox).
public struct RecipeToolboxItem: Sendable, Equatable {
    public var stepType: String
    public var title: String
    /// An SF Symbol name.
    public var symbol: String
}

/// A group of the "Add Step" menu.
public struct RecipeToolboxGroup: Sendable, Equatable {
    public var title: String
    public var items: [RecipeToolboxItem]
}

/// What the recipe editor creates: the toolbox (upstream RecipeEditorWindow.xaml:741-854), a new step's parameters
/// (`SetDefaultParametersForStep`, RecipeEditorViewModel.cs:2302), triggers (`AddTrigger` :1186), error routes
/// (`AddErrorTransition` :1663), options (RecipeEditorViewModel.Options.cs `AddOption`), a new recipe (`NewRecipe`
/// :1713) and a new automatic step (RecipeEditorViewModel.Extensions.cs `NewExtension`). Windows paths and commands are
/// replaced by Mac ones.
public enum RecipeEditorCatalog {
    private static func item(_ stepType: String, _ title: String, _ symbol: String) -> RecipeToolboxItem {
        RecipeToolboxItem(stepType: stepType, title: title, symbol: symbol)
    }

    public static let toolbox: [RecipeToolboxGroup] = [
        RecipeToolboxGroup(title: "Acquisition", items: [
            item(WellKnownStepType.source, "Source (Acquisition)", "camera.viewfinder"),
            item(WellKnownStepType.interactiveSelection, "Interactive Selection", "rectangle.dashed"),
            item(WellKnownStepType.recordVideo, "Record Video", "record.circle")
        ]),
        RecipeToolboxGroup(title: "Filters & Effects", items: [
            item(WellKnownStepType.effect, "Effect (Border/Shadow/Filters)", "wand.and.stars"),
            item(WellKnownStepType.textEffect, "Text Effect / DLP", "eye.slash")
        ]),
        RecipeToolboxGroup(title: "Annotations & Data", items: [
            item(WellKnownStepType.annotation, "Annotation", "pencil.tip.crop.circle"),
            item(WellKnownStepType.setVariable, "Set Variable", "dollarsign.square")
        ]),
        RecipeToolboxGroup(title: "Flow & Feedback", items: [
            item(WellKnownStepType.userPrompt, "User Decision Prompt", "questionmark.bubble"),
            item(WellKnownStepType.conditional, "Conditional Branch", "arrow.triangle.branch"),
            item(WellKnownStepType.slot, "Slot for Automatic Steps", "puzzlepiece.extension"),
            item(WellKnownStepType.immediateFeedback, "Shutter Sound", "speaker.wave.2"),
            item(WellKnownStepType.notification, "Notification", "bell"),
            item(WellKnownStepType.processors, "Processors / OCR", "text.viewfinder"),
            item(WellKnownStepType.stdout, "Standard Output (CLI)", "text.alignleft"),
            item(WellKnownStepType.stderr, "Standard Error / Exit Code (CLI)", "exclamationmark.octagon")
        ]),
        RecipeToolboxGroup(title: "Output & Destinations", items: [
            item(WellKnownStepType.dynamicDestination, "Dynamic Destination", "square.grid.2x2"),
            item(WellKnownStepType.saveFile, "Save to File", "square.and.arrow.down"),
            item(WellKnownStepType.clipboard, "Clipboard", "doc.on.clipboard"),
            item(WellKnownStepType.editor, "Image Editor", "photo.on.rectangle"),
            item(WellKnownStepType.printer, "Printer", "printer"),
            item(WellKnownStepType.email, "Email", "envelope"),
            item(WellKnownStepType.customDestination, "Custom Destination", "arrow.up.forward.app"),
            item(WellKnownStepType.destinations, "Multi-Destinations", "square.and.arrow.up.on.square")
        ]),
        RecipeToolboxGroup(title: "Integrations", items: [
            item(WellKnownStepType.externalCommand, "External Command", "terminal"),
            item(WellKnownStepType.jira, "Atlassian Jira", "ticket"),
            item(WellKnownStepType.confluence, "Confluence Page", "doc.richtext"),
            item(WellKnownStepType.office, "Microsoft Office", "doc.text"),
            item(WellKnownStepType.pdf, "Save as PDF", "doc"),
            item(WellKnownStepType.barcodeScan, "Barcode / QR Scanner", "qrcode.viewfinder"),
            item(WellKnownStepType.box, "Box", "shippingbox"),
            item(WellKnownStepType.dropbox, "Dropbox", "archivebox")
        ])
    ]

    /// The symbol of a step type (the step list's icons); unknown types get a generic one.
    public static func symbol(for stepType: String) -> String {
        for group in toolbox {
            if let match = group.items.first(where: { recipeEquals($0.stepType, stepType) }) { return match.symbol }
        }
        return "square.dashed"
    }

    // MARK: Steps

    /// A new step of `stepType` with upstream's starting parameters, a unique id and the contract's name.
    public static func newNode(_ stepType: String, in recipe: CaptureRecipe, previous: String? = nil, next: String? = nil,
                               contracts: StepContractCatalog = .builtIn) -> RecipeNode {
        let contract = contracts.contract(for: stepType)
        let type = contract?.stepType ?? stepType
        var node = RecipeNode(id: RecipeFlowEditor.newNodeId(for: type, in: recipe), stepType: type, name: contract?.displayName ?? type,
                              parameters: defaultParameters(for: type))
        if recipeEquals(type, WellKnownStepType.slot) {
            let name = guessSlotName(previous: previous.flatMap(recipe.node), next: next.flatMap(recipe.node))
            node.parameters["Name"] = .string(name)
            node.name = name
        }
        return node
    }

    /// Upstream `GuessSlotName`: after an export AfterExport, before one BeforeExport, otherwise AfterCapture.
    static func guessSlotName(previous: RecipeNode?, next: RecipeNode?) -> String {
        if let previous, WellKnownStepType.isDestination(previous.stepType) { return RecipeSlots.afterExport }
        if let next, WellKnownStepType.isDestination(next.stepType) { return RecipeSlots.beforeExport }
        return RecipeSlots.afterCapture
    }

    /// Upstream `SetDefaultParametersForStep`.
    public static func defaultParameters(for stepType: String) -> JSONObject {
        func strings(_ values: [String]) -> JSONValue { .array(values.map { .string($0) }) }
        switch stepType.lowercased() {
        case WellKnownStepType.source.lowercased():
            return ["SourceType": .string("Region"), "DelayMs": .number(0)]
        case WellKnownStepType.recordVideo.lowercased():
            // Upstream also writes OutputFilePath %USERPROFILE%\Videos\…: the Mac uses Settings › Video's folder.
            return ["SourceType": .string("ActiveWindow"), "UntilWindowCloses": .bool(true), "Preset": .string("Balanced"),
                    "Format": .string("Mp4_H264"), "FrameRate": .number(30), "Bitrate": .number(2_500_000),
                    "CaptureMouseCursor": .bool(true), "ShowCaptureBorder": .bool(false),
                    "WindowResizeBehavior": .string("LetterboxFixedCanvas"), "AudioSource": .string("None"),
                    "PreventSleepWhileRecording": .bool(true), "AutoPauseOnSessionLock": .bool(true), "DelayMs": .number(0)]
        case WellKnownStepType.interactiveSelection.lowercased():
            return ["SelectionMode": .string("Region"), "AllowWindowSnapping": .bool(true)]
        case WellKnownStepType.effect.lowercased():
            return ["Effect": .string("DropShadow"), "ShadowSize": .number(10), "Darkness": .number(0.6)]
        case WellKnownStepType.textEffect.lowercased():
            return ["Effect": .string("Redact"), "FillColor": .string("#000000"),
                    "Patterns": strings(["\\b\\d{4}-\\d{4}-\\d{4}-\\d{4}\\b"])]
        case WellKnownStepType.annotation.lowercased():
            let text: JSONObject = ["Type": .string("Text"), "Text": .string("Captured: ${now:yyyy-MM-dd}"),
                                    "HorizontalAnchor": .string("Right"), "VerticalAnchor": .string("Bottom"),
                                    "OffsetX": .string("-15"), "OffsetY": .string("-10"), "FillColor": .string("rgba(0,0,0,160)"),
                                    "LineColor": .string("#0078D7"), "Width": .string("220"), "Height": .string("32")]
            return ["Annotations": .array([.object(text)])]
        case WellKnownStepType.setVariable.lowercased():
            return ["Variables": .object(["captured_by": .string("${user.username}"),
                                          "timestamp": .string("${now:yyyy-MM-dd_HH-mm-ss}")])]
        case WellKnownStepType.immediateFeedback.lowercased():
            return ["PlaySound": .bool(true)]
        case WellKnownStepType.destinations.lowercased():
            return ["DestinationDesignations": strings(["Editor"])]
        case WellKnownStepType.dynamicDestination.lowercased():
            return ["Title": .string("Export Capture"), "ShowPreview": .bool(true), "AllowRecipeForwarding": .bool(true),
                    "TimeoutSeconds": .number(0), "Destinations": .array([])]
        case WellKnownStepType.saveFile.lowercased():
            return ["FilenamePattern": .string("greenshot ${capturetime}"), "Format": .string("png"), "AllowOverwrite": .bool(false)]
        case WellKnownStepType.clipboard.lowercased():
            // Upstream's DIB, DIBV5 and Bitmap formats are Windows clipboard formats.
            return ["ClipboardMode": .string("ImageOnly"), "ClipboardFormatPNG": .bool(true), "ClipboardFormatHTML": .bool(true),
                    "ClipboardFormatHTMLDataUrl": .bool(false), "ClipboardFormatText": .bool(false),
                    "ClipboardCustomText": .string("${Payload.ExtractedText}")]
        case WellKnownStepType.printer.lowercased():
            return ["ShowPrintDialog": .bool(true)]
        case WellKnownStepType.customDestination.lowercased():
            return ["CustomDestinationId": .string("Clipboard")]
        case WellKnownStepType.notification.lowercased():
            return ["ShowNotification": .bool(true)]
        case WellKnownStepType.conditional.lowercased():
            return ["Branches": .array([.object(["key": .string("A"), "expression": .string("${payload.width > 800}")]),
                                        .object(["key": .string("B"), "expression": .string("else")])])]
        case WellKnownStepType.userPrompt.lowercased():
            let yes: JSONObject = ["Key": .string("Yes"), "Label": .string("Yes, Proceed"), "Style": .string("Primary"),
                                   "IsDefault": .bool(true), "IsCancel": .bool(false)]
            let no: JSONObject = ["Key": .string("No"), "Label": .string("No, Cancel"), "Style": .string("Secondary"),
                                  "IsDefault": .bool(false), "IsCancel": .bool(true)]
            return ["Title": .string("Greenshot decision"), "Message": .string("Please confirm the next step for this capture:"),
                    "ShowPreview": .bool(true), "TimeoutSeconds": .number(0), "Choices": .array([.object(yes), .object(no)])]
        case WellKnownStepType.stdout.lowercased():
            return ["Text": .string("${Payload.ExtractedText}")]
        case WellKnownStepType.stderr.lowercased():
            return ["Text": .string("The recipe failed."), "ExitCode": .number(1), "Abort": .bool(true)]
        case WellKnownStepType.processors.lowercased():
            return ["ProcessorIds": .array([])]
        case WellKnownStepType.slot.lowercased():
            return ["Name": .string(RecipeSlots.beforeExport)]
        case WellKnownStepType.externalCommand.lowercased():
            // Upstream: cmd.exe /c echo Processing {0}.
            return ["CommandLine": .string("/bin/echo"), "Arguments": .string("Processing {0}"), "Format": .string("png"),
                    "RunInBackground": .bool(false), "OutputToClipboard": .bool(false), "UriToClipboard": .bool(false),
                    "ReloadAfterExecution": .bool(false)]
        case WellKnownStepType.jira.lowercased():
            return ["IssueKey": .string("PROJECT-123"), "Format": .string("png"), "JpegQuality": .number(80)]
        case WellKnownStepType.confluence.lowercased():
            return ["PageId": .string("123456"), "Format": .string("png"), "JpegQuality": .number(80)]
        case WellKnownStepType.office.lowercased():
            return ["Application": .string("Word")]
        case WellKnownStepType.pdf.lowercased():
            return ["PageSize": .string("Image"), "MeasurementUnit": .string("Mm"), "PageWidthMm": .number(210),
                    "PageHeightMm": .number(297), "MarginTopMm": .number(0), "MarginBottomMm": .number(0),
                    "MarginLeftMm": .number(0), "MarginRightMm": .number(0), "ScalingMode": .string("OnlyShrinkToFit"),
                    "ShowSaveDialog": .bool(true)]
        case WellKnownStepType.barcodeScan.lowercased():
            return ["SetVariable": .string("barcode_text"), "CopyToClipboard": .bool(true)]
        default:
            return [:]
        }
    }

    // MARK: Recipes

    /// Upstream `NewRecipe`: Region capture → camera sound → export, with the standard slots so automatic steps apply.
    public static func newRecipe() -> CaptureRecipe {
        let hex = UUID().uuidString.replacingOccurrences(of: "-", with: "").prefix(6).lowercased()
        var recipe = CaptureRecipe(id: "recipe_\(hex)", name: "New Custom Workflow", description: "Custom visual capture recipe")
        recipe.nodes = [
            RecipeNode(id: "acquire", stepType: WellKnownStepType.source, name: "Acquire Region", parameters: ["SourceType": .string("Region")]),
            RecipeNode(id: "feedback", stepType: WellKnownStepType.immediateFeedback, name: "Capture Feedback"),
            RecipeNode(id: "export", stepType: WellKnownStepType.destinations, name: "Export Destinations")
        ]
        recipe.flow = RecipeFlow(startNodes: ["acquire"])
        recipe.flow.addTransition(from: "acquire", to: "feedback")
        recipe.flow.addTransition(from: "feedback", to: "export")
        RecipeSlotNodes.addStandardSlots(to: &recipe, afterCaptureBefore: "export", exportNode: "export")
        return recipe
    }

    /// Upstream `NewExtension`: an automatic step with an "On" option (quick settings) and a 2 px black border, before
    /// every capture's destinations.
    public static func newExtension() -> CaptureRecipe {
        let hex = UUID().uuidString.replacingOccurrences(of: "-", with: "").prefix(6).lowercased()
        var ext = CaptureRecipe(id: "ext_\(hex)", name: "New Automatic Step", description: "Changes every capture before it goes to a destination")
        ext.kind = .extension
        ext.extends = ExtensionTarget(recipes: ["*capture"], slot: RecipeSlots.beforeDestination, order: 500)
        var enabled = RecipeOption(key: "enabled", type: .boolean, defaultValue: .bool(true))
        enabled.label = "On"
        enabled.quickSettings = true
        ext.options = [enabled]
        ext.nodes = [RecipeNode(id: "border", stepType: WellKnownStepType.effect, name: "Add Border",
                                parameters: ["Effect": .string("Border"), "Width": .number(2), "Color": .string("#000000")])]
        ext.flow = RecipeFlow(startNodes: ["border"])
        ext.flow.addTransition(from: "border", to: "Out")
        return ext
    }

    /// The slot names (upstream `RecipeSlots.All`): where an automatic step goes.
    public static var slotNames: [String] { RecipeSlots.all }

    // MARK: Triggers, error routes, options

    /// The trigger types the Triggers tab adds, in upstream's order (xaml:3311-3330), with their button titles.
    public static let triggerTypes: [(type: String, title: String)] = [
        (WellKnownTriggerType.hotkey, "Hotkey"), (WellKnownTriggerType.contextMenu, "Menu Entry"), (WellKnownTriggerType.editor, "Editor"),
        (WellKnownTriggerType.clipboard, "Clipboard"), (WellKnownTriggerType.commandline, "Command Line"),
        (WellKnownTriggerType.openFile, "Open With"), (WellKnownTriggerType.extension, "Browser Extension"),
        (WellKnownTriggerType.aiTool, "AI Tool"), (WellKnownTriggerType.manual, "Manual")
    ]

    /// Upstream `AddTrigger`.
    public static func newTrigger(_ type: String, for recipe: CaptureRecipe) -> TriggerConfig {
        var trigger = TriggerConfig(triggerType: type, name: "\(type) Trigger")
        switch type.lowercased() {
        case WellKnownTriggerType.hotkey.lowercased():
            trigger.parameters["Hotkey"] = .string("Ctrl + Alt + R")
        case WellKnownTriggerType.contextMenu.lowercased():
            trigger.parameters["MenuItemText"] = .string(recipe.name.isEmpty ? "Capture with Recipe" : recipe.name)
            trigger.parameters["Group"] = .string("Recipes")
        case WellKnownTriggerType.editor.lowercased():
            trigger.parameters["MenuItemText"] = .string(recipe.name.isEmpty ? "Apply Recipe" : recipe.name)
            trigger.parameters["Group"] = .string("Recipes")
        case WellKnownTriggerType.clipboard.lowercased():
            trigger.parameters["FormatFilter"] = .string("")
        case WellKnownTriggerType.commandline.lowercased():
            trigger.parameters["Command"] = .string(recipe.id.isEmpty ? "custom" : recipe.id)
            trigger.parameters["Description"] = .string(recipe.description ?? "Custom commandline recipe")
            trigger.parameters["FireAndForget"] = .bool(false)
        case WellKnownTriggerType.openFile.lowercased():
            trigger.parameters["Filter"] = .string("")
            trigger.parameters["FireAndForget"] = .bool(false)
        case WellKnownTriggerType.extension.lowercased():
            trigger.parameters["Browser"] = .string("")
            trigger.parameters["FireAndForget"] = .bool(false)
        case WellKnownTriggerType.aiTool.lowercased():
            trigger.parameters["ToolName"] = .string(toolName(from: recipe.id))
            trigger.parameters["Title"] = .string(recipe.name.isEmpty ? "My tool" : recipe.name)
            trigger.parameters["Description"] = .string(recipe.description ?? "")
            trigger.parameters["ReadOnly"] = .bool(true)
        default:
            break
        }
        return trigger
    }

    /// Upstream: the recipe id with every character but letters, digits and '-' replaced by '_', at most 64.
    static func toolName(from id: String) -> String {
        let source = id.isEmpty ? "my_tool" : id
        let mapped = source.unicodeScalars.map { scalar -> Character in
            let isLetter = (scalar >= "a" && scalar <= "z") || (scalar >= "A" && scalar <= "Z")
            let isDigit = scalar >= "0" && scalar <= "9"
            return isLetter || isDigit || scalar == "-" ? Character(scalar) : "_"
        }
        return String(mapped.prefix(64))
    }

    /// Upstream `AddErrorTransition`: from any step to the first Dynamic Destination, else the first Editor step, else
    /// the first step.
    public static func newErrorTransition(for recipe: CaptureRecipe) -> ErrorTransition {
        let target = recipe.firstNode(ofType: WellKnownStepType.dynamicDestination)?.id
            ?? recipe.firstNode(ofType: WellKnownStepType.editor)?.id
            ?? recipe.nodes.first?.id
        return ErrorTransition(from: "*", to: target)
    }

    /// Upstream `AddOption`: "option", "option2", … a Boolean that is off, labelled "New option".
    public static func newOption(for recipe: CaptureRecipe) -> RecipeOption {
        var key = "option"
        var number = 2
        while recipe.option(key) != nil {
            key = "option\(number)"
            number += 1
        }
        var option = RecipeOption(key: key, type: .boolean, defaultValue: .bool(false))
        option.label = "New option"
        return option
    }
}
