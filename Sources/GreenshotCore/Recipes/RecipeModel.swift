// Greenshot for Mac (Community) - an unofficial macOS port of Greenshot
// Copyright (C) 2026 Greenshot for Mac (Community) contributors
// Based on Greenshot, Copyright (C) 2007-2026 Thomas Braun, Jens Klingen, Robin Krom
// SPDX-License-Identifier: GPL-3.0-or-later

import CoreGraphics
import Foundation

/// What a `.gsrecipe.json` file holds (upstream `FlowDefinition.Kind`): a recipe (the default) or an extension.
public enum RecipeKind: String, Sendable, Codable, CaseIterable {
    case recipe
    case `extension`
}

/// The flow-definition types of the recipe engine: well-known step types (upstream `WellKnownStepTypes` plus the
/// plugin steps the Mac has built in).
public enum WellKnownStepType {
    public static let source = "Source"
    public static let interactiveSelection = "InteractiveSelection"
    public static let immediateFeedback = "ImmediateFeedback"
    public static let processors = "Processors"
    public static let destinations = "Destinations"
    public static let notification = "Notification"
    public static let dynamicDestination = "DynamicDestination"
    public static let effect = "Effect"
    public static let conditional = "Conditional"
    public static let textEffect = "TextEffect"
    public static let annotation = "Annotation"
    public static let setVariable = "SetVariable"
    public static let saveFile = "SaveFile"
    public static let clipboard = "Clipboard"
    public static let editor = "Editor"
    public static let printer = "Printer"
    public static let email = "Email"
    public static let customDestination = "CustomDestination"
    public static let userPrompt = "UserPrompt"
    public static let recordVideo = "RecordVideo"
    public static let stdout = "Stdout"
    public static let stderr = "Stderr"
    public static let slot = "Slot"
    // Upstream plugin steps, built in on the Mac.
    public static let externalCommand = "ExternalCommand"
    public static let jira = "Jira"
    public static let confluence = "Confluence"
    public static let box = "Box"
    public static let dropbox = "Dropbox"
    public static let office = "Office"
    public static let pdf = "Pdf"
    public static let barcodeScan = "BarcodeScan"

    /// Destinations, SaveFile, Clipboard, Editor, Printer, Email, DynamicDestination, CustomDestination
    /// (upstream `WellKnownStepTypes.IsDestination`).
    public static func isDestination(_ stepType: String) -> Bool {
        [destinations, saveFile, clipboard, editor, printer, email, dynamicDestination, customDestination]
            .contains { recipeEquals($0, stepType) }
    }
}

/// The trigger types (upstream `TriggerConfig.Type*`).
public enum WellKnownTriggerType {
    public static let hotkey = "Hotkey"
    public static let contextMenu = "ContextMenu"
    public static let systray = "Systray"
    public static let clipboard = "Clipboard"
    public static let editor = "Editor"
    public static let manual = "Manual"
    public static let schedule = "Schedule"
    public static let commandline = "Commandline"
    public static let openFile = "OpenFile"
    public static let `extension` = "Extension"
    public static let aiTool = "AiTool"
}

/// A plug-in or extension a recipe needs (upstream `RecipeRequirement`).
public struct RecipeRequirement: Sendable, Equatable {
    public var id: String
    public var name: String?
    public var minVersion: String?
    public var url: String?
    /// Members this version doesn't know, written back unchanged.
    public var extra: JSONObject = [:]

    public init(id: String, name: String? = nil, minVersion: String? = nil, url: String? = nil) {
        self.id = id
        self.name = name
        self.minVersion = minVersion
        self.url = url
    }
}

/// The type system of parameters, variables and options (upstream `ContractDataType`); raw values as in the files.
public enum ContractDataType: String, Sendable, Codable, CaseIterable {
    case string = "String"
    case integer = "Integer"
    case decimal = "Decimal"
    case boolean = "Boolean"
    case filePath = "FilePath"
    case directoryPath = "DirectoryPath"
    case enumeration = "Enum"
    case object = "Object"
    /// A window: AI tools pass a window reference, resolved to the window (CGWindowID on the Mac).
    case window = "Window"
    /// A screen region "x,y,width,height".
    case region = "Region"
    /// "#RRGGBB" or "#AARRGGBB".
    case color = "Color"

    /// Case-insensitive, like Newtonsoft's `StringEnumConverter`.
    public init?(caseInsensitive text: String) {
        let trimmed = text.trimmingCharacters(in: .whitespaces)
        guard let match = ContractDataType.allCases.first(where: { recipeEquals($0.rawValue, trimmed) }) else { return nil }
        self = match
    }
}

/// One value of an Enum option (upstream `RecipeOptionChoice`).
public struct RecipeOptionChoice: Sendable, Equatable {
    public var value: String
    public var label: String?

    public init(value: String, label: String? = nil) {
        self.value = value
        self.label = label
    }
}

/// A value the user sets once in Settings > Recipes, read with `${option.key}` (upstream `RecipeOption`).
public struct RecipeOption: Sendable, Equatable {
    /// `format` of a String option whose value is a template (upstream `RecipeOption.FormatTemplate`).
    public static let formatTemplate = "template"

    public var key: String
    public var type: ContractDataType = .boolean
    /// The value until the user changes it ("default" in the file).
    public var defaultValue: JSONValue?
    public var label: String?
    public var description: String?
    public var min: Double?
    public var max: Double?
    public var choices: [RecipeOptionChoice]?
    /// The key of a Boolean option of the same recipe; this one can only be changed while that one is on.
    public var enabledWhen: String?
    public var quickSettings: Bool = false
    public var format: String?
    public var extra: JSONObject = [:]

    public init(key: String, type: ContractDataType = .boolean, defaultValue: JSONValue? = nil) {
        self.key = key
        self.type = type
        self.defaultValue = defaultValue
    }

    public var isTemplate: Bool { type == .string && recipeEquals(format ?? "", Self.formatTemplate) }
    /// The value converted to the option type (bool, integer or decimal number clamped to min/max, color, choice,
    /// string), nil when it doesn't fit (upstream `TryConvert`).
    public func convert(_ raw: JSONValue) -> JSONValue? {
        if raw.isNull { return nil }
        let text = raw.asString?.trimmingCharacters(in: .whitespaces)
        switch type {
        case .boolean:
            if case .bool = raw { return raw }
            switch text?.lowercased() {
            case "true": return .bool(true)
            case "false": return .bool(false)
            default: return nil
            }
        case .integer:
            guard let number = raw.doubleValue ?? text.flatMap(Self.parseNumber), number == number.rounded() else { return nil }
            return .number(clamp(number).rounded())
        case .decimal:
            guard let number = raw.doubleValue ?? text.flatMap(Self.parseNumber) else { return nil }
            return .number(clamp(number))
        case .color:
            guard let text, Self.isColor(text) else { return nil }
            return .string(text.uppercased())
        case .enumeration:
            guard let text, let choice = choices?.first(where: { recipeEquals($0.value, text) }) else { return nil }
            return .string(choice.value)
        case .string:
            return .string(text ?? "")
        default:
            return nil
        }
    }

    /// `#RRGGBB` or `#AARRGGBB`.
    static func isColor(_ text: String) -> Bool {
        guard text.hasPrefix("#") else { return false }
        let digits = text.dropFirst()
        return (digits.count == 6 || digits.count == 8) && digits.allSatisfy(\.isHexDigit)
    }

    /// .NET `NumberStyles.Number`, invariant culture: sign, digits with "," as thousands separator, a "." fraction.
    static func parseNumber(_ text: String) -> Double? {
        Double(text.replacingOccurrences(of: ",", with: ""))
    }

    private func clamp(_ value: Double) -> Double {
        var result = value
        if let min, result < min { result = min }
        if let max, result > max { result = max }
        return result
    }
    /// The default as a value of the type, or the neutral value of the type (upstream `GetDefaultValue`).
    public var resolvedDefault: JSONValue {
        if let defaultValue, let value = convert(defaultValue) { return value }
        switch type {
        case .boolean: return .bool(false)
        case .integer: return .number(clamp(0).rounded())
        case .decimal: return .number(clamp(0))
        case .color: return .string("#000000")
        case .enumeration: return .string(choices?.first?.value ?? "")
        default: return .string("")
        }
    }
    /// The value as stored in the settings ("True", "2", "#FF0000"; upstream `ToStorageString`).
    public func storageString(_ value: JSONValue) -> String {
        (convert(value) ?? resolvedDefault).asString ?? ""
    }
}

/// A node's "enabled": true, false or an expression like `${option.border}` (upstream `RecipeNodeConfig.EnabledJson`).
public enum NodeEnabled: Sendable, Equatable {
    case value(Bool)
    case expression(String)
}

/// One node of the flow (upstream `RecipeNodeConfig`).
public struct RecipeNode: Sendable, Equatable {
    public var id: String
    public var stepType: String
    public var name: String?
    public var enabled: NodeEnabled = .value(true)
    public var onErrorNodeId: String?
    public var onErrorRecipeId: String?
    /// The step parameters as in the file (expressions not evaluated); keys case-insensitive.
    public var parameters: JSONObject = [:]
    public var extra: JSONObject = [:]

    public init(id: String, stepType: String, name: String? = nil, parameters: JSONObject = [:]) {
        self.id = id
        self.stepType = stepType
        self.name = name
        self.parameters = parameters
    }

    /// Upstream `ToString()`: the name, or the step type.
    public var displayName: String { name ?? stepType }
}

/// `flow.transitions`: a node to its next nodes, in file order. A single string target is read as a list of one
/// (upstream `TransitionsDictionaryConverter`).
public struct RecipeTransition: Sendable, Equatable {
    public var from: String
    public var to: [String]

    public init(from: String, to: [String]) {
        self.from = from
        self.to = to
    }
}

/// `flow.conditionalTransitions` (upstream `RecipeConditionalTransitionConfig`).
public struct ConditionalTransition: Sendable, Equatable {
    public var from: String
    public var branch: String
    public var to: String

    public init(from: String, branch: String, to: String) {
        self.from = from
        self.branch = branch
        self.to = to
    }
}

/// `flow.errorTransitions` (upstream `RecipeErrorTransitionConfig`): from a node or `*`, to a node or another recipe.
public struct ErrorTransition: Sendable, Equatable {
    public var from: String?
    public var to: String?
    public var targetRecipeId: String?
    /// `*` (any) or the type of the error, see `RecipeStepError.errorType`.
    public var errorType: String = "*"

    public init(from: String?, to: String? = nil, targetRecipeId: String? = nil, errorType: String = "*") {
        self.from = from
        self.to = to
        self.targetRecipeId = targetRecipeId
        self.errorType = errorType
    }
}

/// The DAG of a recipe (upstream `RecipeFlowConfig`).
public struct RecipeFlow: Sendable, Equatable {
    public var startNodes: [String] = []
    public var transitions: [RecipeTransition] = []
    public var conditionalTransitions: [ConditionalTransition] = []
    public var errorTransitions: [ErrorTransition] = []
    public var extra: JSONObject = [:]

    public init(startNodes: [String] = []) {
        self.startNodes = startNodes
    }

    /// The `transitions` targets of a node (case-insensitive), without the conditional ones.
    public func targets(from nodeId: String) -> [String] {
        var result: [String] = []
        for transition in transitions where recipeEquals(transition.from, nodeId) {
            for target in transition.to where !target.trimmingCharacters(in: .whitespaces).isEmpty {
                if !result.contains(where: { recipeEquals($0, target) }) { result.append(target) }
            }
        }
        return result
    }
    /// Transitions and conditional transitions together, keyed by the lowercased node id (upstream `GetUnifiedTransitions`).
    public var unifiedTransitions: [String: [String]] {
        var map: [String: [String]] = [:]
        func add(_ from: String, _ to: String) {
            guard !from.trimmingCharacters(in: .whitespaces).isEmpty, !to.trimmingCharacters(in: .whitespaces).isEmpty else { return }
            var list = map[from.lowercased()] ?? []
            if !list.contains(where: { recipeEquals($0, to) }) { list.append(to) }
            map[from.lowercased()] = list
        }
        for transition in transitions {
            if map[transition.from.lowercased()] == nil, !transition.from.isEmpty { map[transition.from.lowercased()] = [] }
            for target in transition.to { add(transition.from, target) }
        }
        for conditional in conditionalTransitions { add(conditional.from, conditional.to) }
        return map
    }
    /// The best error transition for a failed node: exact node and type, exact node and `*`, `*` and type, `*` and `*`
    /// (upstream `GetErrorTransition`); a type matches the error's type or its inner error's type.
    public func errorTransition(from nodeId: String, errorType: String, innerErrorType: String? = nil) -> ErrorTransition? {
        guard !errorTransitions.isEmpty, !nodeId.trimmingCharacters(in: .whitespaces).isEmpty else { return nil }
        func matchesType(_ transition: ErrorTransition) -> Bool {
            recipeEquals(transition.errorType, errorType) || (innerErrorType.map { !$0.isEmpty && recipeEquals(transition.errorType, $0) } ?? false)
        }
        func isWildcardType(_ transition: ErrorTransition) -> Bool { transition.errorType.isEmpty || transition.errorType == "*" }
        func matchesFrom(_ transition: ErrorTransition) -> Bool { transition.from.map { recipeEquals($0, nodeId) } ?? false }
        func isWildcardFrom(_ transition: ErrorTransition) -> Bool { (transition.from ?? "").isEmpty || transition.from == "*" }
        return errorTransitions.first { matchesFrom($0) && matchesType($0) }
            ?? errorTransitions.first { matchesFrom($0) && isWildcardType($0) }
            ?? errorTransitions.first { isWildcardFrom($0) && matchesType($0) }
            ?? errorTransitions.first { isWildcardFrom($0) && isWildcardType($0) }
    }

    public mutating func addTransition(from: String, to: String) {
        guard !from.isEmpty, !to.isEmpty else { return }
        if let index = transitions.firstIndex(where: { recipeEquals($0.from, from) }) {
            if !transitions[index].to.contains(where: { recipeEquals($0, to) }) { transitions[index].to.append(to) }
        } else {
            transitions.append(RecipeTransition(from: from, to: [to]))
        }
    }
}

/// An argument a Commandline or AiTool trigger declares (upstream `CommandlineArgument`).
public struct CommandlineArgument: Sendable, Equatable {
    public var name: String
    /// The flow variable the value goes into; the name when empty.
    public var variable: String?
    public var description: String?
    public var required: Bool = false
    public var defaultValue: String?
    public var type: ContractDataType = .string
    public var allowedValues: [String]?

    public init(name: String, type: ContractDataType = .string) {
        self.name = name
        self.type = type
    }

    public var effectiveVariable: String { (variable?.isEmpty == false ? variable : nil) ?? name }
}

/// A trigger of a recipe (upstream `TriggerConfig`). The approval state is not part of the file: see `LoadedRecipe`.
public struct TriggerConfig: Sendable, Equatable {
    public var triggerType: String
    public var name: String?
    public var enabled: Bool = true
    public var parameters: JSONObject = [:]
    public var extra: JSONObject = [:]

    public init(triggerType: String, name: String? = nil, parameters: JSONObject = [:]) {
        self.triggerType = triggerType
        self.name = name
        self.parameters = parameters
    }

    public func isType(_ type: String) -> Bool { triggerType.caseInsensitiveCompare(type) == .orderedSame }
    // Typed reads with upstream's defaults (TriggerManager.SyncRecipeTriggers).
    /// Hotkey: "Ctrl + Shift + B", see `RecipeHotkeyText`.
    public var hotkey: String? { parameters.string("Hotkey") }
    /// ContextMenu, Systray, Editor: the menu entry; nil uses the recipe name.
    public var menuItemText: String? { parameters.string("MenuItemText") }
    /// ContextMenu, Editor: default "Recipes".
    public var group: String { parameters.string("Group") ?? "Recipes" }
    public var order: Int { parameters.int("Order") ?? 0 }
    /// Clipboard: default true.
    public var onImageCopied: Bool { parameters.bool("OnImageCopied") ?? true }
    /// Clipboard: comma separated formats, nil for any.
    public var formatFilter: String? { parameters.string("FormatFilter") }
    /// OpenFile: ".png;.jpg", nil for any image.
    public var fileFilter: String? { parameters.string("Filter") }
    /// OpenFile, Commandline, Extension.
    public var fireAndForget: Bool { parameters.bool("FireAndForget") ?? false }
    /// Commandline: the command name; nil uses the recipe id.
    public var command: String? { parameters.string("Command") }
    /// Commandline, AiTool: what the command or tool does.
    public var commandDescription: String? { parameters.string("Description") }
    /// Commandline: what to write to stdout at the end, an expression like `${Barcode.Text}`.
    public var stdout: String? { parameters.string("Stdout") }
    /// Commandline: web pages and the browser extension may start it too (approved separately).
    public var allowsBrowserInvocation: Bool { parameters.bool("AllowBrowserInvocation") ?? false }
    /// Commandline, AiTool: the declared arguments.
    public var arguments: [CommandlineArgument] {
        (parameters["Arguments"]?.arrayValue ?? []).compactMap { item -> CommandlineArgument? in
            guard let object = item.objectValue, let name = object.string("name"), !name.isEmpty else { return nil }
            var argument = CommandlineArgument(name: name, type: object.string("type").flatMap(ContractDataType.init(caseInsensitive:)) ?? .string)
            argument.variable = object.string("variable")
            argument.description = object.string("description")
            argument.required = object.bool("required") ?? false
            argument.defaultValue = object.string("defaultValue")
            argument.allowedValues = object.strings("allowedValues")
            return argument
        }
    }
    /// Extension: the browser filter.
    public var browser: String? { parameters.string("Browser") }
    /// AiTool.
    public var toolName: String? { parameters.string("ToolName") }
    public var toolTitle: String? { parameters.string("Title") }
    public var toolReadOnly: Bool { parameters.bool("ReadOnly") ?? true }
    public var toolDestructive: Bool { parameters.bool("Destructive") ?? false }
}

/// What happens when a recipe starts while a flow of it runs (upstream `FlowConcurrency`).
public enum FlowConcurrency: String, Sendable, Codable, CaseIterable {
    case parallel = "Parallel"
    case exclusive = "Exclusive"
    case replacePrevious = "ReplacePrevious"
}

/// Extensions only: where it goes (upstream `ExtensionTarget`). Kept so extension files load and save unchanged.
public struct ExtensionTarget: Sendable, Equatable {
    public var recipes: [String] = []
    public var slot: String?
    public var order: Int = 0

    public init(recipes: [String] = [], slot: String? = nil, order: Int = 0) {
        self.recipes = recipes
        self.slot = slot
        self.order = order
    }
}

/// A recipe or an extension as a `.gsrecipe.json` file holds it (upstream `CaptureRecipe` / `RecipeExtension` /
/// `FlowDefinition`). Only file content: where it was loaded from, its approval and whether it is switched on are in
/// `LoadedRecipe`. Keys the file has that this model doesn't (also upstream's leaked `isBuiltIn`, `filePath`,
/// `isOverridden`, `isEnabled`) are in `extra`: never trusted, written back unchanged.
public struct CaptureRecipe: Sendable, Equatable {
    public var kind: RecipeKind = .recipe
    /// "$schema"
    public var schema: String?
    public var version: String = "1.0"
    public var id: String
    public var name: String
    public var description: String?
    public var requires: [RecipeRequirement] = []
    public var triggers: [TriggerConfig] = []
    public var nodes: [RecipeNode] = []
    public var flow = RecipeFlow()
    public var options: [RecipeOption]?
    public var concurrency: FlowConcurrency?
    /// Upstream `ShowInContextMenu` (default true).
    public var showInContextMenu: Bool = true
    /// Extensions only.
    public var extends: ExtensionTarget?
    /// Extensions only: `${...}` evaluated at the slot.
    public var when: String?
    public var extra: JSONObject = [:]

    public init(id: String, name: String, description: String? = nil) {
        self.id = id
        self.name = name
        self.description = description
    }

    /// Case-insensitive, like upstream `FindNode`.
    public func node(_ id: String) -> RecipeNode? { nodes.first { recipeEquals($0.id, id) } }
    public func firstNode(ofType stepType: String) -> RecipeNode? { nodes.first { recipeEquals($0.stepType, stepType) } }
    public func option(_ key: String) -> RecipeOption? { options?.first { recipeEquals($0.key, key) } }
    /// A Source or RecordVideo node (upstream `HasSourceStep`).
    public var hasSourceStep: Bool {
        nodes.contains { recipeEquals($0.stepType, WellKnownStepType.source) || recipeEquals($0.stepType, WellKnownStepType.recordVideo) }
    }
    public var hasDestinationStep: Bool { nodes.contains { WellKnownStepType.isDestination($0.stepType) } }
    /// It has an AiTool trigger.
    public var isAIToolRecipe: Bool { triggers.contains { $0.isType(WellKnownTriggerType.aiTool) } }
}

/// Ids, step types, trigger types, keys and parameter names are compared case-insensitively everywhere, like upstream's
/// `StringComparison.OrdinalIgnoreCase`.
func recipeEquals(_ lhs: String, _ rhs: String) -> Bool {
    lhs.caseInsensitiveCompare(rhs) == .orderedSame
}
