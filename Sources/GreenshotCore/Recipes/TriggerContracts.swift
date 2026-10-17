// Greenshot for Mac (Community) - an unofficial macOS port of Greenshot
// Copyright (C) 2026 Greenshot for Mac (Community) contributors
// Based on Greenshot, Copyright (C) 2007-2026 Thomas Braun, Jens Klingen, Robin Krom
// SPDX-License-Identifier: GPL-3.0-or-later

import CoreGraphics
import Foundation

/// The contract of a trigger type: its parameters (for the recipe editor's forms), what it hands to the flow, and
/// whether it starts the recipe on its own or from outside (upstream `RecipeDescriber` risk, `RecipeContract.GetTriggerInputs`,
/// `TriggerRecipePreparer`).
public struct TriggerContract: Sendable {
    public var triggerType: String
    public var displayName: String
    public var description: String
    public var parameters: [ParameterContract]
    /// Variables the trigger sets (OpenFile: Filename, Editor: EditorForm, Extension: Capture and Browser; Commandline
    /// and AiTool: their declared arguments, see `RecipeContractAnalyzer.triggerInputs`).
    public var providedVariables: [VariableContract]
    /// The trigger hands the image to the flow (Extension).
    public var providesPayload: Bool
    /// Clipboard, Schedule, Commandline, OpenFile, Extension, AiTool: the approval asks for it separately and an edit
    /// that adds it needs a decision (upstream `RecipeEditApproval`).
    public var startsOnItsOwn: Bool
    /// The Source a recipe without one gets for this trigger (upstream `TriggerRecipePreparer`): Clipboard, CurrentEditor,
    /// File, Extension, else FullScreen.
    public var defaultSourceType: String

    public init(triggerType: String, displayName: String, description: String = "", parameters: [ParameterContract] = [],
                providedVariables: [VariableContract] = [], providesPayload: Bool = false, startsOnItsOwn: Bool = false,
                defaultSourceType: String = "FullScreen") {
        self.triggerType = triggerType
        self.displayName = displayName
        self.description = description
        self.parameters = parameters
        self.providedVariables = providedVariables
        self.providesPayload = providesPayload
        self.startsOnItsOwn = startsOnItsOwn
        self.defaultSourceType = defaultSourceType
    }
}

public struct TriggerContractCatalog: Sendable {
    public static var builtIn: TriggerContractCatalog { builtInCatalog }
    private static let builtInCatalog = TriggerContractCatalog(BuiltInTriggerContracts.all)

    private let contracts: [TriggerContract]

    public init(_ contracts: [TriggerContract]) {
        self.contracts = contracts
    }

    public var all: [TriggerContract] { contracts }
    public func contract(for triggerType: String) -> TriggerContract? {
        contracts.first { recipeEquals($0.triggerType, triggerType) }
    }
}

/// The trigger types of upstream (`TriggerConfig.Type*`) with the parameters their trigger classes read
/// (Greenshot/Recipes/Triggers/*.cs, `TriggerManager.SyncRecipeTriggers`), what they hand to the flow
/// (`RecipeContract.GetTriggerInputs`), whether they start the recipe on their own (`RecipeDescriber.DescribeTrigger`)
/// and the Source a recipe without one gets (`TriggerRecipePreparer.GetTriggerSpecificSourceNode`).
enum BuiltInTriggerContracts {
    private static func parameter(_ name: String, _ type: ContractDataType = .string, required: Bool = false,
                                  default value: JSONValue? = nil, _ description: String) -> ParameterContract {
        ParameterContract(name, type, required: required, defaultValue: value, description: description)
    }

    private static func parameter(_ name: String, required: Bool = false, default value: JSONValue? = nil,
                                  _ description: String) -> ParameterContract {
        parameter(name, .string, required: required, default: value, description)
    }

    private static let menuParameters: [ParameterContract] = [
        parameter("MenuItemText", "Text of the menu entry (default: the recipe name)"),
        parameter("Group", default: .string("Recipes"), "Submenu of the entry"),
        parameter("Order", .integer, default: .number(0), "Position of the entry in its group")
    ]

    private static let commandArguments = parameter("Arguments", .object, "Declared arguments: name, variable, description, required, defaultValue, type, allowedValues")

    static let all: [TriggerContract] = [
        TriggerContract(triggerType: WellKnownTriggerType.hotkey, displayName: "Hotkey", description: "A global hotkey starts the recipe.",
                        parameters: [parameter("Hotkey", required: true, "The hotkey, e.g. \"Ctrl + Shift + B\" (Ctrl is ⌘, Win is ⌃ on the Mac)")]),
        TriggerContract(triggerType: WellKnownTriggerType.contextMenu, displayName: "Menu Entry",
                        description: "An entry in the Recipes menu of the menu bar icon starts the recipe.", parameters: menuParameters),
        TriggerContract(triggerType: WellKnownTriggerType.systray, displayName: "Menu Entry",
                        description: "Like ContextMenu: an entry in the menu of the menu bar icon.", parameters: menuParameters),
        TriggerContract(triggerType: WellKnownTriggerType.clipboard, displayName: "Clipboard",
                        description: "Runs when another app copies an image to the clipboard.",
                        parameters: [
                            parameter("OnImageCopied", .boolean, default: .bool(true), "Run when an image is copied"),
                            parameter("FormatFilter", "Only for these clipboard formats, comma separated (e.g. PNG)")
                        ],
                        startsOnItsOwn: true, defaultSourceType: "Clipboard"),
        TriggerContract(triggerType: WellKnownTriggerType.editor, displayName: "Editor Menu Entry",
                        description: "An entry in the image editor's menu runs the recipe on the open image.", parameters: menuParameters,
                        providedVariables: [VariableContract("EditorForm", .object, required: true, description: "The editor that triggered the recipe")],
                        defaultSourceType: "CurrentEditor"),
        TriggerContract(triggerType: WellKnownTriggerType.manual, displayName: "Manual",
                        description: "Only started from the recipe list, a test run or another recipe."),
        TriggerContract(triggerType: WellKnownTriggerType.schedule, displayName: "Schedule",
                        description: "Reserved: runs at scheduled times (not available yet, like upstream).", startsOnItsOwn: true),
        TriggerContract(triggerType: WellKnownTriggerType.commandline, displayName: "Command Line",
                        description: "The recipe is a command of the greenshot command line tool.",
                        parameters: [
                            parameter("Command", "The command name (default: the recipe id)"),
                            parameter("Description", "What the command does, shown in the command list"),
                            parameter("FireAndForget", .boolean, default: .bool(false), "Return at once instead of waiting for the result"),
                            parameter("Stdout", "What to write to standard output at the end, e.g. ${Barcode.Text}"),
                            commandArguments,
                            parameter("AllowBrowserInvocation", .boolean, default: .bool(false), "Web pages and the browser extension may start it too")
                        ],
                        startsOnItsOwn: true),
        TriggerContract(triggerType: WellKnownTriggerType.openFile, displayName: "Open With",
                        description: "Runs for image files opened with Greenshot.",
                        parameters: [
                            parameter("Filter", "File extensions separated by ';', e.g. .png;.jpg (default: every image)"),
                            parameter("FireAndForget", .boolean, default: .bool(false), "Don't wait for the result")
                        ],
                        providedVariables: [VariableContract("Filename", .filePath, required: true, description: "The file that was opened")],
                        startsOnItsOwn: true, defaultSourceType: "File"),
        TriggerContract(triggerType: WellKnownTriggerType.extension, displayName: "Browser Extension",
                        description: "Handles the captures the Greenshot browser extension sends.",
                        parameters: [
                            parameter("Browser", "Only captures from this browser"),
                            parameter("FireAndForget", .boolean, default: .bool(false), "Don't wait for the result")
                        ],
                        providedVariables: [
                            VariableContract("Capture", .object, required: true, description: "The capture imported from the browser (also the payload)"),
                            VariableContract("Browser", .string, description: "The browser that sent the capture", conditional: true)
                        ],
                        providesPayload: true, startsOnItsOwn: true, defaultSourceType: "Extension"),
        TriggerContract(triggerType: WellKnownTriggerType.aiTool, displayName: "AI Tool",
                        description: "Offers the recipe as a tool to AI clients.",
                        parameters: [
                            parameter("ToolName", required: true, "The tool name: 1 to 64 letters, digits, '_' or '-'"),
                            parameter("Title", "Name of the tool for people"),
                            parameter("Description", "What the tool does, for the AI"),
                            parameter("ReadOnly", .boolean, default: .bool(true), "The tool doesn't change anything"),
                            parameter("Destructive", .boolean, default: .bool(false), "The tool can overwrite or delete something"),
                            commandArguments
                        ],
                        startsOnItsOwn: true)
    ]

    /// Upstream `AiToolTrigger.IsValidToolName`: 1 to 64 letters, digits, '_' or '-'.
    static func isValidToolName(_ name: String?) -> Bool {
        guard let name, (1...64).contains(name.count) else { return false }
        return name.unicodeScalars.allSatisfy { scalar in
            scalar.isASCII && (CharacterSet.alphanumerics.contains(scalar) || scalar == "_" || scalar == "-")
        }
    }
}
