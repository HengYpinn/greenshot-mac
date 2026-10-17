// Greenshot for Mac (Community) - an unofficial macOS port of Greenshot
// Copyright (C) 2026 Greenshot for Mac (Community) contributors
// Based on Greenshot, Copyright (C) 2007-2026 Thomas Braun, Jens Klingen, Robin Krom
// SPDX-License-Identifier: GPL-3.0-or-later

import Foundation

/// The contracts of every step type of upstream, transcribed from the `[StepInfo]`, `[StepParameter]`,
/// `[StepInputVariable]`, `[StepOutputVariable]` and `[StepPayload]` attributes of the step classes
/// (src/Greenshot/Recipes/Steps/*.cs and the plug-ins' Recipes/*Step.cs at 0aedcf04), and their gated actions
/// (`IRequiresRecipeAuthorization.GetGatedActions`) as pure functions of the node.
enum BuiltInStepContracts {
    static var all: [StepContract] {
        [source, interactiveSelection, immediateFeedback, processors, destinations]
            + destinationAliases
            + [notification, dynamicDestination, effect, conditional, textEffect, annotation, setVariable, userPrompt,
               recordVideo, stdout, stderr, slot, externalCommand, jira, confluence, box, dropbox, office, pdf, barcodeScan]
    }

    // MARK: Helpers

    private static func parameter(_ name: String, _ type: ContractDataType = .string, required: Bool = false,
                                  default value: JSONValue? = nil, _ description: String, allowed: [String] = [],
                                  expressions: Bool = true) -> ParameterContract {
        ParameterContract(name, type, required: required, defaultValue: value, description: description, allowedValues: allowed,
                          supportsExpressions: expressions)
    }

    /// A String parameter.
    private static func parameter(_ name: String, default value: JSONValue? = nil, _ description: String,
                                  expressions: Bool = true) -> ParameterContract {
        parameter(name, .string, default: value, description, expressions: expressions)
    }

    private static func input(_ name: String, _ type: ContractDataType = .string, _ description: String) -> VariableContract {
        VariableContract(name, type, description: description)
    }

    private static func output(_ name: String, _ type: ContractDataType = .string, _ description: String,
                               conditional: Bool = false, when parameter: String? = nil) -> VariableContract {
        VariableContract(name, type, description: description, conditional: conditional, whenParameter: parameter)
    }

    private static func input(_ name: String, _ description: String) -> VariableContract {
        input(name, .string, description)
    }

    private static func output(_ name: String, _ description: String, conditional: Bool = false, when parameter: String? = nil) -> VariableContract {
        output(name, .string, description, conditional: conditional, when: parameter)
    }

    /// The saveable file formats (upstream `SaveableFileFormatIds`).
    private static func fileFormats(_ description: String) -> ParameterContract {
        var format = parameter("Format", .enumeration, description)
        format.allowedValuesProvider = { ImageFormat.allCases.map(\.rawValue) + ["jpeg"] }
        return format
    }

    // MARK: Acquisition and interaction

    static let source = StepContract(
        stepType: WellKnownStepType.source, displayName: "Acquire Source",
        description: "Acquires the image: captures the screen, a region, a window, the clipboard, a file or the current editor. A capture handed to the flow (forwarded from another recipe, imported from the browser extension) is used instead of capturing.",
        category: "Acquisition",
        parameters: [
            parameter("SourceType", .enumeration, default: .string("Region"), "What to capture",
                      allowed: ["Region", "Window", "ActiveWindow", "FullScreen", "LastRegion", "Clipboard", "File", "TextOcr", "CurrentEditor", "Extension"],
                      expressions: false),
            parameter("Filename", .filePath, "File to load (SourceType File); default: variable Filename"),
            parameter("CaptureMouseCursor", .boolean, "Include the mouse cursor (default: settings)"),
            parameter("DelayMs", .integer, "Delay before capturing in milliseconds (default: settings)"),
            parameter("ScreenCaptureMode", .enumeration, "Which screen(s) to capture for FullScreen (default: settings)",
                      allowed: ["Auto", "FullScreen", "Fixed"]),
            parameter("WindowTitle", "Capture the window with this title (SourceType Window)"),
            parameter("WindowTitlePattern", "Capture the window whose title matches this regular expression (SourceType Window)"),
            parameter("ProcessName", "Capture the window of this process (SourceType Window)"),
            parameter("WindowHandle", .object, "Capture this window without asking or activating it (SourceType Window): the variable of a Window argument (e.g. ${Window}) or a window id"),
            parameter("MatchCase", .boolean, "Match WindowTitle / WindowTitlePattern case-sensitively"),
            parameter("AlignDpi", .boolean, default: .bool(true), "Set the image resolution to the screen DPI")
        ],
        inputVariables: [
            input("PreSuppliedRegion", .object, "Region to capture without asking (set by the caller)"),
            input("CaptureDelay", .integer, "Overrides DelayMs"),
            input("CaptureMouseCursor", .boolean, "Overrides the CaptureMouseCursor parameter"),
            input("ScreenCaptureMode", .enumeration, "Overrides the ScreenCaptureMode parameter"),
            input("TargetWindow", .object, "Window to capture (set by the caller)"),
            input("WindowTitle", "Window title, when the parameter is not set"),
            input("WindowTitlePattern", "Window title pattern, when the parameter is not set"),
            input("ProcessName", "Process name, when the parameter is not set"),
            input("MatchCase", .boolean, "Match case, when the parameter is not set"),
            input("Filename", .filePath, "File to load (SourceType File), when the parameter is not set"),
            input("EditorForm", .object, "The editor to take the image from (SourceType CurrentEditor, set by the editor trigger)")
        ],
        outputVariables: [output("SelectedWindow", .object, "The window of the last region (SourceType LastRegion)", conditional: true)],
        payload: PayloadContract(rawCapture: .created, surface: .created),
        gates: { node, _ in
            guard recipeEquals(node.parameters.string("SourceType") ?? "", "File") else { return [] }
            let filename = node.parameters.string("Filename")?.trimmingCharacters(in: .whitespaces) ?? ""
            return [RecipeGatedAction(.fileSystemAccess, target: filename.isEmpty
                ? "Reads the image file named in the variable Filename" : "Reads the image file \(filename)")]
        })

    static let interactiveSelection = StepContract(
        stepType: WellKnownStepType.interactiveSelection, displayName: "Interactive Selection",
        description: "Lets the user select a region, a window or text on a capture of the screen. A capture that was handed to the flow, or that is not a screen capture, is used as a whole.",
        category: "Interaction",
        parameters: [
            parameter("SelectionMode", .enumeration, default: .string("Region"), "Initial selection mode; Text also extracts the text of the selection",
                      allowed: ["Region", "Window", "Text"]),
            parameter("SelectionTool", "Id of the capture tool to start with, e.g. one of a plugin; when it is not there, the tool of the SelectionMode"),
            parameter("AllowWindowSnapping", .boolean, default: .bool(true), "Snap the selection to windows")
        ],
        inputVariables: [input("PreSuppliedRegion", .object, "When set, the selection is skipped")],
        outputVariables: [output("SelectedWindow", .object, "The window that was selected", conditional: true)],
        payload: PayloadContract(rawCapture: .required, surface: .optional, visualMutation: .mutatesPixels))

    static let immediateFeedback = StepContract(
        stepType: WellKnownStepType.immediateFeedback, displayName: "Immediate Feedback",
        description: "Plays the camera sound after a capture (not for a capture handed to the flow).", category: "Feedback",
        parameters: [
            parameter("PlaySound", .boolean, "Play the camera sound (default: settings)"),
            parameter("SoundFilePath", .filePath, "Sound file to play instead of the camera sound")
        ],
        inputVariables: [
            input("PlayShutterSound", .boolean, "Overrides PlaySound"),
            input("SoundFilePath", .filePath, "Overrides SoundFilePath")
        ])

    static let processors = StepContract(
        stepType: WellKnownStepType.processors, displayName: "Processors",
        description: "Runs image processors (e.g. OCR, title fix, plugin processors).", category: "Processing",
        parameters: [
            parameter("ProcessorIds", .object, "Only run these processors (type name, description or designation)"),
            parameter("ProcessorMode", "OCR runs OCR and stores the text"),
            parameter("Timing", .enumeration, default: .string("Any"), "Run the processors that belong before or after the selection",
                      allowed: ["Any", "PreSelection", "PostSelection"]),
            parameter("RunOcr", .boolean, default: .bool(true), "Run OCR processors"),
            parameter("RunTitleFix", .boolean, default: .bool(true), "Run the title fix processor"),
            parameter("RunPlugins", .boolean, default: .bool(true), "Run plugin processors")
        ],
        outputVariables: [
            output("OcrText", "Text found by OCR (also in Payload.ExtractedText)", conditional: true),
            output("Text", "Same as OcrText", conditional: true),
            output("CommandResult", "Same as OcrText", conditional: true)
        ],
        payload: PayloadContract(rawCapture: .required, surface: .optional, extractedText: .created))

    // MARK: Export

    private static let destinationParameters: [ParameterContract] = [
        parameter("DestinationDesignations", .object, "List of destination designations (default: settings)"),
        parameter("SaveDirectory", .directoryPath, "Directory to save to"),
        parameter("FilenamePattern", "File name pattern (default: settings)"),
        fileFormats("Image format (default: settings)"),
        parameter("JpegQuality", .integer, "JPEG quality (1-100)"),
        parameter("ReduceColors", .boolean, "Reduce the image to 256 colors"),
        parameter("PromptQuality", .boolean, "Ask for the JPEG quality"),
        parameter("AllowOverwrite", .boolean, "Overwrite an existing file"),
        parameter("CopyPathToClipboard", .boolean, "Copy the saved file's path to the clipboard"),
        parameter("TargetEditor", .enumeration, "Editor to use (Editor)", allowed: ["NewEditor", "AvailableEditor", "CurrentEditor"]),
        parameter("MatchSizeToCapture", .boolean, "Size the editor to the capture (Editor)"),
        parameter("PrinterName", "Printer to use (Printer)"),
        parameter("ShowPrintDialog", .boolean, "Show the print options (Printer)"),
        parameter("AllowRotate", .boolean, "Rotate to fit the page (Printer)"),
        parameter("AllowEnlarge", .boolean, "Enlarge to fit the page (Printer)"),
        parameter("AllowShrink", .boolean, "Shrink to fit the page (Printer)"),
        parameter("Center", .boolean, "Center on the page (Printer)"),
        parameter("ColorMode", .enumeration, "Print colors (Printer)", allowed: ["Color", "Grayscale", "Monochrome"]),
        parameter("PrintFooter", .boolean, "Print a footer (Printer)"),
        parameter("FooterPattern", "Footer text pattern (Printer)"),
        parameter("ClipboardMode", .enumeration, default: .string("ImageOnly"), "What to copy (Clipboard); TextOnly copies the extracted or OCR text",
                  allowed: ["ImageOnly", "TextOnly", "ImageAndText"]),
        parameter("ClipboardCustomText", "Text to copy instead of the OCR text; ${ocr_text} is the OCR text (Clipboard)"),
        parameter("ClipboardFormatPNG", .boolean, default: .bool(true), "Copy as PNG (Clipboard)"),
        parameter("ClipboardFormatDIB", .boolean, default: .bool(true), "Copy as DIB (Clipboard)"),
        parameter("ClipboardFormatDIBV5", .boolean, "Copy as DIBV5 (Clipboard)"),
        parameter("ClipboardFormatBitmap", .boolean, "Copy as bitmap (Clipboard)"),
        parameter("ClipboardFormatHTML", .boolean, "Copy as HTML (Clipboard)"),
        parameter("ClipboardFormatHTMLDataUrl", .boolean, "Copy as HTML with a data URL (Clipboard)"),
        parameter("ClipboardFormatText", .boolean, "Also copy the text (Clipboard)"),
        parameter("CustomDestinationId", "Destination designation (CustomDestination)")
    ]

    private static let destinationInputs: [VariableContract] = [
        input("OverrideDestinations", .object, "Destinations to use instead of the configured ones (set by the caller)"),
        input("EditorForm", .object, "The editor for TargetEditor CurrentEditor (set by the editor trigger)")
    ]

    private static let destinationOutputs: [VariableContract] = [
        output("Destination.Filename", .filePath, "Path of the file to save (with SaveDirectory)", conditional: true, when: "SaveDirectory"),
        output("Destination.SaveDirectory", .directoryPath, "The expanded SaveDirectory", conditional: true, when: "SaveDirectory"),
        output("Destination.SurfaceOutputSettings", .object, "Output settings for the destinations (with JpegQuality or ReduceColors)", conditional: true),
        output("Destination.PromptQuality", .boolean, "The PromptQuality parameter, for the destinations", conditional: true, when: "PromptQuality"),
        output("Destination.AllowOverwrite", .boolean, "The AllowOverwrite parameter, for the destinations", conditional: true, when: "AllowOverwrite"),
        output("Destination.CopyPathToClipboard", .boolean, "The CopyPathToClipboard parameter, for the destinations", conditional: true, when: "CopyPathToClipboard"),
        output("DestinationExportErrors", "Errors of destinations that failed", conditional: true)
    ]

    /// The designations a destination step exports to when it is checked (upstream `ResolveDestinationDesignations` with
    /// no flow): the step type's own, `CustomDestinationId`, `DestinationDesignations`, else the settings' destinations.
    static func designations(of node: RecipeNode, _ environment: GateEnvironment) -> [String] {
        switch node.stepType.lowercased() {
        case WellKnownStepType.saveFile.lowercased(): return ["FileNoDialog"]
        case WellKnownStepType.clipboard.lowercased(): return ["Clipboard"]
        case WellKnownStepType.editor.lowercased(): return ["Editor"]
        case WellKnownStepType.printer.lowercased(): return ["Printer"]
        case WellKnownStepType.email.lowercased(): return ["EMail"]
        case WellKnownStepType.customDestination.lowercased():
            if let custom = node.parameters.string("CustomDestinationId")?.trimmingCharacters(in: .whitespaces), !custom.isEmpty {
                return [custom]
            }
        default:
            break
        }
        if let listed = node.parameters.strings("DestinationDesignations"), !listed.isEmpty { return listed }
        return environment.defaultDestinations
    }

    private static func destinationGates(_ node: RecipeNode, _ environment: GateEnvironment) -> [RecipeGatedAction] {
        var actions: [RecipeGatedAction] = []
        if let directory = node.parameters.string("SaveDirectory")?.trimmingCharacters(in: .whitespaces), !directory.isEmpty {
            actions.append(RecipeGatedAction(.fileSystemAccess, target: "Writes files to \(directory)"))
        }
        for designation in designations(of: node, environment) where !designation.trimmingCharacters(in: .whitespaces).isEmpty {
            if let action = RecipeDestinationDesignation(designation).gatedAction(environment) { actions.append(action) }
        }
        return actions
    }

    static let destinations = StepContract(
        stepType: WellKnownStepType.destinations, displayName: "Export Destinations",
        description: "Exports the capture to one or more destinations (file, clipboard, editor, printer, email, plugins).",
        category: "Export", parameters: destinationParameters, inputVariables: destinationInputs, outputVariables: destinationOutputs,
        payload: PayloadContract(rawCapture: .required, surface: .required, extractedText: .optional), gates: { destinationGates($0, $1) })

    /// Upstream registers `DestinationExportStep` under these step types too (`CapturePipeline.RegisterBuiltInStepFactories`).
    static var destinationAliases: [StepContract] {
        let aliases: [(String, String, String)] = [
            (WellKnownStepType.saveFile, "Save to File", "Saves the capture to a file without asking."),
            (WellKnownStepType.clipboard, "Copy to Clipboard", "Copies the image and/or the extracted text to the clipboard."),
            (WellKnownStepType.editor, "Open in Editor", "Opens the capture in the Greenshot editor."),
            (WellKnownStepType.printer, "Printer", "Prints the capture."),
            (WellKnownStepType.email, "Send by Email", "Attaches the capture to a new email."),
            (WellKnownStepType.customDestination, "Custom Destination", "Exports to the destination named by CustomDestinationId.")
        ]
        return aliases.map { alias in
            var contract = destinations
            contract.stepType = alias.0
            contract.displayName = alias.1
            contract.description = alias.2
            return contract
        }
    }

    static let notification = StepContract(
        stepType: WellKnownStepType.notification, displayName: "Notification",
        description: "Shows the notification for the exports before it.", category: "Feedback",
        parameters: [parameter("ShowNotification", .boolean, "Show the completion notification (default: settings)")],
        inputVariables: [input("ShowNotification", .boolean, "Overrides the ShowNotification parameter")],
        outputVariables: [output("EnableCompletionNotification", .boolean, "Whether the completion notification is shown")])

    static let dynamicDestination = StepContract(
        stepType: WellKnownStepType.dynamicDestination, displayName: "Dynamic Destination Flyout",
        description: "Lets the user pick a destination, open the editor, or forward the capture to another recipe.", category: "Destination",
        parameters: [
            parameter("Title", "Title of the flyout"),
            parameter("Destinations", .object, "Destinations to offer (default: all)"),
            parameter("AllowRecipeForwarding", .boolean, default: .bool(true), "Offer to forward the capture to another recipe"),
            parameter("ShowPreview", .boolean, "Show a preview of the capture"),
            parameter("TimeoutSeconds", .integer, "Close the flyout after this many seconds")
        ],
        inputVariables: [input("LastError", "Shown when the flyout is used to pick another destination after a failed export")],
        payload: PayloadContract(rawCapture: .required, surface: .optional))

    // MARK: Effects, annotations, logic

    static let effect = StepContract(
        stepType: WellKnownStepType.effect, displayName: "Image Effect",
        description: "Applies an image effect (border, drop shadow, torn edge, grayscale, resize, ...) to the capture.", category: "Effects",
        parameters: [
            parameter("Effect", .enumeration, default: .string("Border"), "The effect",
                      allowed: ["Border", "DropShadow", "TornEdge", "Invert", "Grayscale", "Monochrome", "Adjust", "Rotate", "Resize",
                                "ResizeCanvas", "ReduceColors", "RemoveTransparency"]),
            parameter("Width", .integer, "Border width (Border), new width (Resize)"),
            parameter("Height", .integer, "New height (Resize)"),
            parameter("Color", "Border color (Border), background color (ResizeCanvas, RemoveTransparency)"),
            parameter("Darkness", .decimal, "Shadow darkness (DropShadow, TornEdge)"),
            parameter("ShadowSize", .integer, "Shadow size (DropShadow, TornEdge)"),
            parameter("ShadowOffsetX", .integer, "Shadow offset (DropShadow)"),
            parameter("ShadowOffsetY", .integer, "Shadow offset (DropShadow)"),
            parameter("ToothHeight", .integer, "Tooth height (TornEdge)"),
            parameter("HorizontalToothRange", .integer, "Horizontal tooth range (TornEdge)"),
            parameter("VerticalToothRange", .integer, "Vertical tooth range (TornEdge)"),
            parameter("GenerateShadow", .boolean, "Add a shadow (TornEdge)"),
            parameter("Edges", .object, "Torn edges: top, right, bottom, left (TornEdge)"),
            parameter("Threshold", .integer, default: .number(128), "Threshold (Monochrome)"),
            parameter("Brightness", .decimal, "Brightness (Adjust)"),
            parameter("Contrast", .decimal, "Contrast (Adjust)"),
            parameter("Gamma", .decimal, "Gamma (Adjust)"),
            parameter("Angle", .integer, default: .number(90), "Angle (Rotate)"),
            parameter("Percentage", .decimal, "Size in percent (Resize)"),
            parameter("MaintainAspectRatio", .boolean, default: .bool(true), "Keep the aspect ratio (Resize)"),
            parameter("Margin", .integer, "Margin on all sides (ResizeCanvas)"),
            parameter("Left", .integer, "Left margin (ResizeCanvas)"),
            parameter("Right", .integer, "Right margin (ResizeCanvas)"),
            parameter("Top", .integer, "Top margin (ResizeCanvas)"),
            parameter("Bottom", .integer, "Bottom margin (ResizeCanvas)"),
            parameter("BackgroundColor", "Background color (ResizeCanvas)"),
            parameter("Colors", .integer, "Number of colors (ReduceColors)")
        ],
        payload: PayloadContract(rawCapture: .required, surface: .required, visualMutation: .mutatesPixels))

    static let conditional = StepContract(
        stepType: WellKnownStepType.conditional, displayName: "Conditional",
        description: "Continues with the conditional transitions of the first branch whose expression is true.", category: "Logic",
        parameters: [
            parameter("Branches", .object, required: true,
                      "List of { Key, Expression }; the first branch whose expression is true is taken, an Expression of else/default always matches",
                      expressions: false)
        ])

    static let textEffect = StepContract(
        stepType: WellKnownStepType.textEffect, displayName: "Text Effect",
        description: "Finds text via OCR and applies an effect (pixelize, blur, highlight, redact, magnify) to the matches.", category: "Effects",
        parameters: [
            parameter("Patterns", .object, required: true, "Regular expressions to find"),
            parameter("Effect", .enumeration, default: .string("Pixelize"), "Effect to apply", allowed: ["Pixelize", "Blur", "Highlight", "Redact", "Magnify"]),
            parameter("Scope", .enumeration, default: .string("Auto"), "Apply to the matching words or whole lines"),
            parameter("MatchCase", .boolean, default: .bool(false), "Match case"),
            parameter("FillColor", "Color (Highlight: #FFFF00, Redact: #000000)"),
            parameter("BlurRadius", .integer, default: .number(10), "Blur radius (Blur)"),
            parameter("PixelSize", .integer, default: .number(5), "Pixel size (Pixelize)"),
            parameter("MagnificationFactor", .integer, default: .number(2), "Magnification (Magnify)"),
            parameter("Padding", .integer, "Padding around the matches"),
            parameter("PaddingHorizontal", .integer, "Horizontal padding"),
            parameter("PaddingVertical", .integer, "Vertical padding"),
            parameter("OffsetHorizontal", .integer, "Horizontal offset"),
            parameter("OffsetVertical", .integer, "Vertical offset")
        ],
        payload: PayloadContract(rawCapture: .required, surface: .required, visualMutation: .addsAnnotations))

    static let annotation = StepContract(
        stepType: WellKnownStepType.annotation, displayName: "Add Annotation",
        description: "Adds annotations (shapes, text, arrows, icons, blur, stamps) to the capture. The properties of an annotation depend on its type.",
        category: "Annotations",
        parameters: [
            parameter("Annotations", .object, "List of annotations; without it the node's own parameters describe one annotation"),
            parameter("Type", default: .string("Rectangle"), "Type of the annotation (Text, Rectangle, Arrow, Icon, Blur, SpeechBubble, ...)")
        ],
        payload: PayloadContract(rawCapture: .required, surface: .required, visualMutation: .addsAnnotations),
        acceptsUndeclaredParameters: true, evaluatesOwnParameters: true)

    static let setVariable = StepContract(
        stepType: WellKnownStepType.setVariable, displayName: "Set Variable",
        description: "Stores values in variables for the following steps.", category: "Logic",
        parameters: [
            parameter("Variable", "Name of the variable to set"),
            parameter("Value", "Value of the variable"),
            parameter("Variables", .object, "Several variables: name to value")
        ],
        outputVariables: [
            output("{Parameter:Variable}", "The variable named by the Variable parameter"),
            output("{ParameterKeys:Variables}", "The variables of the Variables parameter")
        ])

    static let userPrompt = StepContract(
        stepType: WellKnownStepType.userPrompt, displayName: "User Prompt",
        description: "Asks the user to choose; conditional transitions of this node follow the chosen key.", category: "Interaction",
        parameters: [
            parameter("Choices", .object, required: true, "The choices (key and text)"),
            parameter("Title", "Title of the prompt"),
            parameter("Message", "Message of the prompt"),
            parameter("DefaultChoice", "Choice used when the prompt times out"),
            parameter("ShowPreview", .boolean, default: .bool(true), "Show a preview of the capture"),
            parameter("TimeoutSeconds", .integer, default: .number(0), "Close the prompt after this many seconds (0: never)")
        ],
        outputVariables: [output("UserChoice.{NodeId}", "The key of the chosen choice")])

    static let recordVideo = StepContract(
        stepType: WellKnownStepType.recordVideo, displayName: "Record Video",
        description: "Records a video of a monitor, window or region.", category: "Video",
        parameters: [
            parameter("SourceType", .enumeration, default: .string("ActiveWindow"), "What to record", allowed: ["ActiveWindow", "Window", "Region", "Monitor"]),
            parameter("MonitorIndex", .integer, "Monitor to record (Monitor)"),
            parameter("WindowTitle", "Window to record (Window)"),
            parameter("WindowTitlePattern", "Window title regular expression (Window)"),
            parameter("ProcessName", "Process of the window (Window)"),
            parameter("MatchCase", .boolean, "Match the window title case-sensitively"),
            parameter("RegionX", .integer, "Region (Region)"),
            parameter("RegionY", .integer, "Region (Region)"),
            parameter("RegionWidth", .integer, "Region (Region)"),
            parameter("RegionHeight", .integer, "Region (Region)"),
            parameter("DelayMs", .integer, "Delay before recording in milliseconds"),
            parameter("DurationSeconds", .integer, "Length of the recording"),
            parameter("UntilWindowCloses", .boolean, "Record until the window closes (Window)"),
            parameter("Preset", "Quality preset"),
            parameter("Format", "Video format"),
            parameter("FrameRate", .integer, "Frames per second"),
            parameter("Bitrate", .integer, "Bitrate"),
            parameter("TargetWidth", .integer, "Output width"),
            parameter("TargetHeight", .integer, "Output height"),
            parameter("ScaleFactor", .decimal, "Output scale"),
            parameter("ColorMode", "Color mode"),
            parameter("CaptureMouseCursor", .boolean, default: .bool(true), "Record the mouse cursor"),
            parameter("ShowCaptureBorder", .boolean, default: .bool(false), "Show the capture border"),
            parameter("WindowResizeBehavior", "What to do when the window is resized"),
            parameter("AudioSource", default: .string("None"), "Audio to record"),
            parameter("PreventSleepWhileRecording", .boolean, default: .bool(true), "Keep the Mac awake while recording"),
            parameter("AutoPauseOnSessionLock", .boolean, default: .bool(true), "Pause while the Mac is locked"),
            parameter("OutputFilePath", .filePath, "File to write"),
            parameter("OutputDirectory", .directoryPath, "Directory to write to"),
            parameter("FilenamePattern", "File name pattern")
        ],
        inputVariables: [
            input("SourceType", .enumeration, "What to record, when the parameter is not set"),
            input("WindowHandle", .object, "Window to record (set by the caller)"),
            input("CaptureRegion", .object, "Region to record (set by the caller)")
        ],
        outputVariables: [
            output("VideoFilePath", .filePath, "Path of the recorded video"),
            output("VideoRecordingResult", .object, "Details of the recording")
        ],
        gates: { node, _ in
            let target = node.parameters.string("OutputFilePath") ?? node.parameters.string("OutputDirectory") ?? ""
            guard !target.trimmingCharacters(in: .whitespaces).isEmpty else { return [] }
            return [RecipeGatedAction(.fileSystemAccess, target: "Writes the video to \(target)")]
        })

    static let stdout = StepContract(
        stepType: WellKnownStepType.stdout, displayName: "Stdout Output",
        description: "Writes text to standard output of the caller (e.g. the greenshot command line tool).", category: "Diagnostics",
        parameters: [parameter("Text", "Text to write (default: the extracted text)")],
        outputVariables: [
            output("LastStdout", "The text that was written"),
            output("StdoutEmitted", .boolean, "True once text was written")
        ],
        payload: PayloadContract(extractedText: .optional))

    static let stderr = StepContract(
        stepType: WellKnownStepType.stderr, displayName: "Stderr Output",
        description: "Writes an error message to standard error of the caller, sets the exit code and (by default) ends the flow.",
        category: "Diagnostics",
        parameters: [
            parameter("Text", "Error message"),
            parameter("ExitCode", .integer, default: .number(1), "Exit code of the flow"),
            parameter("Abort", .boolean, default: .bool(true), "End the flow")
        ],
        outputVariables: [
            output("LastStderr", "The message that was written"),
            output("StderrEmitted", .boolean, "True once a message was written"),
            output("ExitCode", .integer, "The exit code")
        ])

    static let slot = StepContract(
        stepType: WellKnownStepType.slot, displayName: "Slot",
        description: "A place where extensions (border, drop shadow, caption, ...) add their steps; does nothing itself.", category: "Flow",
        parameters: [
            parameter("Name", .enumeration, required: true, "Which slot", allowed: RecipeSlots.all, expressions: false),
            parameter("Accept", .object, default: .string(RecipeSlots.acceptAll), "Which extensions: \"all\", \"none\" or a list of extension ids",
                      expressions: false)
        ])

    // MARK: Upstream plug-in steps (built in on the Mac)

    static let externalCommand = StepContract(
        stepType: WellKnownStepType.externalCommand, displayName: "External Command",
        description: "Saves the capture to a file and runs an external command with it: a command configured in the settings (Command) or an executable (CommandLine).",
        category: "Export",
        parameters: [
            parameter("Command", "Name of an external command configured in the settings"),
            parameter("CommandLine", .filePath, "Executable to run, instead of a configured command"),
            parameter("Arguments", "Arguments, {0} is replaced by the file"),
            parameter("WorkingDirectory", .directoryPath, "Working directory of the command"),
            parameter("Verb", "Shell verb to use instead of running the executable (e.g. open, print)"),
            fileFormats("Format of the file handed to the command"),
            parameter("JpegQuality", .integer, "JPEG quality (1-100) when saving as JPEG"),
            parameter("RunInBackground", .boolean, "Start the command without waiting for it (no output variables then)"),
            parameter("OutputToClipboard", .boolean, "Copy the command's output to the clipboard"),
            parameter("UriToClipboard", .boolean, "Copy a URI found in the command's output to the clipboard"),
            parameter("ReloadAfterExecution", .boolean, default: .bool(false), "Reload the image from the file after the command changed it"),
            parameter("SetOutputVariable", "Also store the command's output in this variable", expressions: false),
            parameter("SetExitCodeVariable", "Also store the command's exit code in this variable", expressions: false)
        ],
        inputVariables: [input("Destination.Filename", .filePath, "File saved by an earlier destination step, handed to the command instead of a new file")],
        outputVariables: [
            output("ExternalCommand.TargetFile", .filePath, "The file handed to the command"),
            output("ExternalCommand.ExitCode", .integer, "Exit code of the command", conditional: true),
            output("ExternalCommand.Output", "Standard output of the command", conditional: true),
            output("ExternalCommand.Error", "Standard error of the command", conditional: true),
            output("ExternalCommand.Uri", "First URI found in the output", conditional: true),
            output("{Parameter:SetOutputVariable}", "The command's output", conditional: true),
            output("{Parameter:SetExitCodeVariable}", .integer, "The command's exit code", conditional: true)
        ],
        payload: PayloadContract(rawCapture: .required, surface: .required),
        gates: { node, environment in
            let name = node.parameters.string("Command")?.trimmingCharacters(in: .whitespaces) ?? ""
            var commandLine = node.parameters.string("CommandLine")?.trimmingCharacters(in: .whitespaces) ?? ""
            if commandLine.isEmpty, !name.isEmpty { commandLine = environment.commandLine(name) ?? "" }
            let target = commandLine.isEmpty ? name : (name.isEmpty ? commandLine : "\(name) (\(commandLine))")
            return [RecipeGatedAction(.externalCommand, target: target)]
        })

    private static func upload(_ stepType: String, _ displayName: String, _ description: String, target: String,
                               parameters: [ParameterContract] = [], inputs: [VariableContract] = [],
                               outputs: [VariableContract]) -> StepContract {
        StepContract(stepType: stepType, displayName: displayName, description: description, category: "Export",
                     parameters: parameters, inputVariables: inputs, outputVariables: outputs,
                     payload: PayloadContract(rawCapture: .required, surface: .required),
                     gates: { _, _ in [RecipeGatedAction(.networkAccess, target: target)] })
    }

    private static let uploadFormatParameters: [ParameterContract] = [
        fileFormats("Image format of the upload"),
        parameter("JpegQuality", .integer, "JPEG quality (1-100) when uploading as JPEG"),
        parameter("ReduceColors", .boolean, "Reduce the image to 256 colors")
    ]

    static let jira = upload(
        WellKnownStepType.jira, "Attach to Jira", "Attaches the capture to a Jira issue.", target: "Jira",
        parameters: uploadFormatParameters + [parameter("IssueKey", "Issue to attach to (default: variable Jira.IssueKey)")],
        inputs: [input("Jira.IssueKey", "Issue to attach to, when the IssueKey parameter is not set")],
        outputs: [
            output("Jira.UploadUrl", "Link to the attachment", conditional: true),
            output("Jira.IssueKey", "The issue the capture was attached to", conditional: true)
        ])

    static let confluence = upload(
        WellKnownStepType.confluence, "Upload to Confluence", "Uploads the capture as attachment to a Confluence page.", target: "Confluence",
        parameters: uploadFormatParameters + [parameter("PageId", "Page to attach to")],
        outputs: [
            output("Confluence.PageId", "The page the capture was attached to", conditional: true),
            output("Confluence.UploadUrl", "Link to the attachment", conditional: true)
        ])

    static let box = upload(
        WellKnownStepType.box, "Upload to Box", "Uploads the capture to Box (configured account).", target: "Box (box.com)",
        outputs: [output("Box.UploadUrl", "Link to the uploaded file", conditional: true)])

    static let dropbox = upload(
        WellKnownStepType.dropbox, "Upload to Dropbox", "Uploads the capture to Dropbox (configured account).", target: "Dropbox (dropbox.com)",
        outputs: [output("Dropbox.UploadUrl", "Link to the uploaded file", conditional: true)])

    static let office = StepContract(
        stepType: WellKnownStepType.office, displayName: "Send to Office",
        description: "Sends the capture to an Office application (Excel, PowerPoint, Word, OneNote (Notes on the Mac), Outlook).", category: "Export",
        parameters: [parameter("Application", .enumeration, default: .string("Word"), "Office application",
                               allowed: ["Excel", "PowerPoint", "Word", "OneNote", "Outlook"])],
        payload: PayloadContract(rawCapture: .required, surface: .required))

    static let pdf = StepContract(
        stepType: WellKnownStepType.pdf, displayName: "Save as PDF", description: "Saves the capture as a PDF file.", category: "Export",
        parameters: [
            parameter("PageSize", .enumeration, "PDF page size (default: PDF settings)", allowed: ["Image", "Custom", "A3", "A4", "A5", "A6", "Letter"]),
            parameter("MeasurementUnit", .enumeration, "Measurement unit displayed in PDF settings (dimensions and margins are in mm)",
                      allowed: ["mm", "cm", "inch"]),
            parameter("PageWidthMm", .decimal, "Custom page width in millimeters (default: PDF settings)"),
            parameter("PageHeightMm", .decimal, "Custom page height in millimeters (default: PDF settings)"),
            parameter("MarginTopMm", .decimal, "Top margin in millimeters (default: PDF settings)"),
            parameter("MarginBottomMm", .decimal, "Bottom margin in millimeters (default: PDF settings)"),
            parameter("MarginLeftMm", .decimal, "Left margin in millimeters (default: PDF settings)"),
            parameter("MarginRightMm", .decimal, "Right margin in millimeters (default: PDF settings)"),
            parameter("ScalingMode", .enumeration, "How to scale the image on a fixed page (default: PDF settings)",
                      allowed: ["OnlyShrinkToFit", "FitToPage"]),
            parameter("ShowSaveDialog", .boolean, default: .bool(true), "Show the PDF save dialog")
        ],
        outputVariables: [output("Pdf.FilePath", .filePath, "Path of the saved PDF file", conditional: true)],
        payload: PayloadContract(rawCapture: .required, surface: .required))

    static let barcodeScan = StepContract(
        stepType: WellKnownStepType.barcodeScan, displayName: "Barcode Scanner",
        description: "Scans and decodes 1D/2D barcodes (such as QR codes) from the capture bitmap.", category: "Analysis",
        parameters: [
            parameter("SetVariable", "Also store the decoded text in this variable", expressions: false),
            parameter("CopyToClipboard", .boolean, default: .bool(false), "Copy the decoded text to the clipboard")
        ],
        outputVariables: [
            output("Barcode.Text", "Decoded text of the detected barcode(s), one per line", conditional: true),
            output("Barcode.Format", "Format of the detected barcode(s), e.g. QR_CODE, one per line", conditional: true),
            output("Zxing.DecodedText", "Same as Barcode.Text", conditional: true),
            output("{Parameter:SetVariable}", "The decoded text, when SetVariable is set", conditional: true)
        ],
        payload: PayloadContract(rawCapture: .required, surface: .required, extractedText: .created))
}

/// The slots extensions go into (upstream `RecipeSlots`).
enum RecipeSlots {
    static let afterCapture = "AfterCapture"
    static let beforeExport = "BeforeExport"
    static let afterExport = "AfterExport"
    static let beforeDestination = "BeforeDestination"
    static let all = [afterCapture, beforeExport, afterExport, beforeDestination]
    static let acceptAll = "all"
    static let acceptNone = "none"

    /// The slot name as declared, nil for an unknown name.
    static func normalize(_ name: String?) -> String? {
        guard let name else { return nil }
        let trimmed = name.trimmingCharacters(in: .whitespaces)
        return all.first { recipeEquals($0, trimmed) }
    }
}
