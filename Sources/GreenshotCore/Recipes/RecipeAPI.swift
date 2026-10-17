// Greenshot for Mac (Community) - an unofficial macOS port of Greenshot
// Copyright (C) 2026 Greenshot for Mac (Community) contributors
// Based on Greenshot, Copyright (C) 2007-2026 Thomas Braun, Jens Klingen, Robin Krom
// SPDX-License-Identifier: GPL-3.0-or-later

// The frozen public API of the recipe engine (package RCORE, wave 3). The prep commit adds this file; RCORE fills in
// the bodies marked `rcoreStub()` without changing a signature. RAPP (wave 4) and AUT plug into these types.
// Upstream: src/Greenshot.Base/Recipes/** and src/Greenshot/Recipes/** at 0aedcf04; docs/capture-recipes.md.

import CoreGraphics
import Foundation

@inline(never)
func rcoreStub(_ function: StaticString = #function) -> Never {
    fatalError("RCORE: \(function) is implemented in wave 3, phase 2")
}

// MARK: - JSON (order-preserving, case-insensitive lookup)

/// A JSON value as a recipe file holds it (upstream reads recipe files with Newtonsoft `JToken`). Objects keep the
/// order of their members, so a recipe saved again keeps its layout, and look keys up case-insensitively like
/// upstream's parameter dictionaries (`StringComparer.OrdinalIgnoreCase`): files write `sourceType`, contracts say
/// `SourceType`. Also the value type of flow variables and expression results. Numbers are `Double` (JSON has one
/// number type); integral numbers are written without a fraction.
public enum JSONValue: Sendable, Hashable {
    case null
    case bool(Bool)
    case number(Double)
    case string(String)
    case array([JSONValue])
    case object(JSONObject)
}

/// One member of a JSON object, with the key spelled as in the file.
public struct JSONMember: Sendable, Hashable {
    public var key: String
    public var value: JSONValue

    public init(_ key: String, _ value: JSONValue) {
        self.key = key
        self.value = value
    }
}

/// A JSON object: members in file order, keys looked up case-insensitively. Two objects are equal when they have the
/// same keys (exact spelling) with equal values, in any order (Newtonsoft `JToken.DeepEquals`).
public struct JSONObject: Sendable, Hashable, Sequence, ExpressibleByDictionaryLiteral {
    public private(set) var members: [JSONMember]

    public init(_ members: [JSONMember] = []) {
        self.members = members
    }

    public init(dictionaryLiteral elements: (String, JSONValue)...) {
        self.members = elements.map { JSONMember($0.0, $0.1) }
    }

    public var count: Int { members.count }
    public var isEmpty: Bool { members.isEmpty }
    public var keys: [String] { members.map(\.key) }
    public func makeIterator() -> IndexingIterator<[JSONMember]> { members.makeIterator() }

    /// The position of the member with this key (case-insensitive), nil when there is none.
    public func index(forKey key: String) -> Int? {
        members.firstIndex { $0.key.caseInsensitiveCompare(key) == .orderedSame }
    }

    /// Case-insensitive. Setting keeps the spelling and position of an existing key and appends a new one; nil removes.
    public subscript(key: String) -> JSONValue? {
        get { index(forKey: key).map { members[$0].value } }
        set {
            if let index = index(forKey: key) {
                if let newValue { members[index].value = newValue } else { members.remove(at: index) }
            } else if let newValue {
                members.append(JSONMember(key, newValue))
            }
        }
    }

    public func contains(key: String) -> Bool { index(forKey: key) != nil }

    @discardableResult
    public mutating func removeValue(forKey key: String) -> JSONValue? {
        guard let index = index(forKey: key) else { return nil }
        return members.remove(at: index).value
    }

    public static func == (lhs: JSONObject, rhs: JSONObject) -> Bool {
        guard lhs.members.count == rhs.members.count else { return false }
        return lhs.members.allSatisfy { member in rhs.members.contains { $0.key == member.key && $0.value == member.value } }
    }

    public func hash(into hasher: inout Hasher) {
        for member in members.sorted(by: { $0.key < $1.key }) {
            hasher.combine(member.key)
            hasher.combine(member.value)
        }
    }
}

/// Why a text is not JSON: the message and the character offset.
public struct JSONParseError: Error, LocalizedError, Equatable, Sendable {
    public var message: String
    public var offset: Int

    public init(message: String, offset: Int) {
        self.message = message
        self.offset = offset
    }

    public var errorDescription: String? { "\(message) (at character \(offset))" }
}

extension JSONValue {
    /// Parses UTF-8 (a byte order mark is skipped, like upstream's `StreamReader`), keeping the member order.
    public static func parse(_ data: Data) throws -> JSONValue { rcoreStub() }
    public static func parse(_ text: String) throws -> JSONValue { rcoreStub() }
    /// JSON text; indented like upstream's `Formatting.Indented` (two spaces, `"key": value`).
    public func serialized(indented: Bool = true) -> String { rcoreStub() }

    public var stringValue: String? { if case .string(let value) = self { return value } else { return nil } }
    public var boolValue: Bool? { if case .bool(let value) = self { return value } else { return nil } }
    public var doubleValue: Double? { if case .number(let value) = self { return value } else { return nil } }
    public var arrayValue: [JSONValue]? { if case .array(let value) = self { return value } else { return nil } }
    public var objectValue: JSONObject? { if case .object(let value) = self { return value } else { return nil } }
    public var isNull: Bool { self == .null }

    /// The value converted like upstream's `GetParameter<T>` (`Convert.ChangeType`): "2" is 2, 2 is "2", "true" is
    /// true. Nil when it doesn't convert.
    public var asString: String? { rcoreStub() }
    public var asInt: Int? { rcoreStub() }
    public var asDouble: Double? { rcoreStub() }
    public var asBool: Bool? { rcoreStub() }
    /// An array of strings, or a string split at `,` and `;` (upstream `GetParameter<List<string>>`, describer `GetStrings`).
    public var asStrings: [String]? { rcoreStub() }

    /// The text of the value in an interpolated template, as upstream's `ToString()` gives it: "True", "42", "0.5", "".
    public var interpolationText: String { rcoreStub() }
}

/// Codable for embedding in other Codable types (settings, the trust store). Objects go through Foundation's keyed
/// containers, which don't keep the member order: recipe files use `JSONValue.parse` and `serialized()` instead.
extension JSONValue: Codable {
    public init(from decoder: Decoder) throws { rcoreStub() }
    public func encode(to encoder: Encoder) throws { rcoreStub() }
}

extension JSONObject {
    /// Typed reads of a member, converted like `JSONValue.asString` etc.
    public func string(_ key: String) -> String? { self[key]?.asString }
    public func int(_ key: String) -> Int? { self[key]?.asInt }
    public func double(_ key: String) -> Double? { self[key]?.asDouble }
    public func bool(_ key: String) -> Bool? { self[key]?.asBool }
    public func strings(_ key: String) -> [String]? { self[key]?.asStrings }
}

// MARK: - Recipe file model (upstream CaptureRecipe, FlowDefinition, RecipeNodeConfig, RecipeFlowConfig, TriggerConfig)

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
    public static func isDestination(_ stepType: String) -> Bool { rcoreStub() }
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
    public init?(caseInsensitive text: String) { rcoreStub() }
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

    public var isTemplate: Bool { rcoreStub() }
    /// The value converted to the option type (bool, integer or decimal number clamped to min/max, color, choice,
    /// string), nil when it doesn't fit (upstream `TryConvert`).
    public func convert(_ raw: JSONValue) -> JSONValue? { rcoreStub() }
    /// The default as a value of the type, or the neutral value of the type (upstream `GetDefaultValue`).
    public var resolvedDefault: JSONValue { rcoreStub() }
    /// The value as stored in the settings ("True", "2", "#FF0000"; upstream `ToStorageString`).
    public func storageString(_ value: JSONValue) -> String { rcoreStub() }
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
    public func targets(from nodeId: String) -> [String] { rcoreStub() }
    /// Transitions and conditional transitions together, keyed by the lowercased node id (upstream `GetUnifiedTransitions`).
    public var unifiedTransitions: [String: [String]] { rcoreStub() }
    /// The best error transition for a failed node: exact node and type, exact node and `*`, `*` and type, `*` and `*`
    /// (upstream `GetErrorTransition`); a type matches the error's type or its inner error's type.
    public func errorTransition(from nodeId: String, errorType: String, innerErrorType: String? = nil) -> ErrorTransition? { rcoreStub() }
    public mutating func addTransition(from: String, to: String) { rcoreStub() }
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
    public var arguments: [CommandlineArgument] { rcoreStub() }
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
    public func node(_ id: String) -> RecipeNode? { rcoreStub() }
    public func firstNode(ofType stepType: String) -> RecipeNode? { rcoreStub() }
    public func option(_ key: String) -> RecipeOption? { rcoreStub() }
    /// A Source or RecordVideo node (upstream `HasSourceStep`).
    public var hasSourceStep: Bool { rcoreStub() }
    public var hasDestinationStep: Bool { rcoreStub() }
    /// It has an AiTool trigger.
    public var isAIToolRecipe: Bool { rcoreStub() }
}

/// A file that isn't a recipe: not JSON, a list holding an extension, a member of the wrong type. The messages are
/// upstream's (`RecipeSerializer`).
public struct RecipeFormatError: Error, LocalizedError, Equatable, Sendable {
    public var message: String

    public init(_ message: String) {
        self.message = message
    }

    public var errorDescription: String? { message }
}

/// Reads and writes `.gsrecipe.json` (upstream `RecipeSerializer`). Reading is tolerant: names are case-insensitive,
/// a missing kind is "recipe", a missing member gets its default, an unknown member is kept in `extra`. A file holds
/// one recipe or a JSON array of recipes.
public enum RecipeSerializer {
    public static let fileExtension = ".gsrecipe.json"

    /// Every definition of the file, in order; extensions included (their kind says so).
    public static func decode(_ data: Data) throws -> [CaptureRecipe] { rcoreStub() }
    public static func decode(text: String) throws -> [CaptureRecipe] { rcoreStub() }
    public static func recipe(from json: JSONValue) throws -> CaptureRecipe { rcoreStub() }
    public static func json(of recipe: CaptureRecipe) -> JSONValue { rcoreStub() }
    /// Upstream's layout: "kind" first, camelCase names, null members left out, two-space indent.
    public static func encode(_ recipe: CaptureRecipe, indented: Bool = true) -> String { rcoreStub() }
    public static func encode(_ recipes: [CaptureRecipe], indented: Bool = true) -> String { rcoreStub() }
    /// The text of file bytes, UTF-8 with or without byte order mark (upstream `RecipeManager.DecodeRecipeFile`).
    public static func text(of data: Data) -> String? { rcoreStub() }
}

// MARK: - Step and trigger contracts (upstream Contracts/*, StepContractAttributes, the [Step*] attributes of each step)

/// What a step needs from and does to the image (upstream `PayloadRequirement`).
public enum PayloadRequirement: String, Sendable, Codable, CaseIterable {
    case none, required, optional, created
}

/// How a step changes the image (upstream `PayloadEffect`).
public enum PayloadEffect: String, Sendable, Codable, CaseIterable {
    case none, mutatesPixels, addsAnnotations, replacesImage
}

/// The kinds of actions that need the user's permission (upstream `RecipeGateType`).
public enum RecipeGateType: String, Sendable, Codable, CaseIterable, Comparable {
    case externalCommand = "ExternalCommand"
    case networkAccess = "NetworkAccess"
    case fileSystemAccess = "FileSystemAccess"
    case custom = "Custom"

    public static func < (lhs: RecipeGateType, rhs: RecipeGateType) -> Bool {
        allCases.firstIndex(of: lhs)! < allCases.firstIndex(of: rhs)!
    }

    /// For messages: "external commands", "network access (uploads)", "file system access", "custom actions"
    /// (upstream `RecipeApprovalPolicy.GetGateName`).
    public var displayName: String { rcoreStub() }
}

/// A gated action of a step (upstream `RecipeGatedAction`): equal when the type and the target (case-insensitive) are.
public struct RecipeGatedAction: Sendable, Hashable {
    public var gateType: RecipeGateType
    /// What it acts on: "Jira", "Writes files to ~/Shots", the command line.
    public var target: String

    public init(_ gateType: RecipeGateType, target: String) {
        self.gateType = gateType
        self.target = target
    }

    public static func == (lhs: RecipeGatedAction, rhs: RecipeGatedAction) -> Bool {
        lhs.gateType == rhs.gateType && lhs.target.caseInsensitiveCompare(rhs.target) == .orderedSame
    }

    public func hash(into hasher: inout Hasher) {
        hasher.combine(gateType)
        hasher.combine(target.lowercased())
    }
}

/// A parameter of a step or trigger (upstream `ParameterContract`). Names are case-insensitive.
public struct ParameterContract: Sendable {
    public var name: String
    public var dataType: ContractDataType
    public var required: Bool
    public var defaultValue: JSONValue?
    public var description: String
    /// Allowed values (case-insensitive), empty for any. `allowedValuesProvider` wins when set (upstream
    /// `IAllowedValuesProvider`, e.g. the file formats).
    public var allowedValues: [String]
    public var allowedValuesProvider: (@Sendable () -> [String])?
    /// False: the value is used as written, `${...}` is not evaluated (e.g. Source `SourceType`, Conditional `Branches`).
    public var supportsExpressions: Bool

    public init(_ name: String, _ dataType: ContractDataType = .string, required: Bool = false, defaultValue: JSONValue? = nil,
                description: String = "", allowedValues: [String] = [], supportsExpressions: Bool = true) {
        self.name = name
        self.dataType = dataType
        self.required = required
        self.defaultValue = defaultValue
        self.description = description
        self.allowedValues = allowedValues
        self.supportsExpressions = supportsExpressions
    }

    public var effectiveAllowedValues: [String] { allowedValuesProvider?() ?? allowedValues }
    public func matches(_ parameterName: String) -> Bool { name.caseInsensitiveCompare(parameterName) == .orderedSame }
}

/// An input or output variable of a step (upstream `VariableContract`). A name can depend on the node: `{NodeId}`,
/// `{Parameter:X}` (the value of parameter X), or a whole name `{ParameterKeys:X}` (every key of the object X).
public struct VariableContract: Sendable, Equatable {
    public var name: String
    public var dataType: ContractDataType
    public var required: Bool
    public var description: String
    public var exampleValue: String?
    /// Outputs: not always set (e.g. only when a barcode was found).
    public var conditional: Bool
    /// Outputs: a conditional output that is always set when the node has this parameter.
    public var whenParameter: String?

    public init(_ name: String, _ dataType: ContractDataType = .string, required: Bool = false, description: String = "",
                exampleValue: String? = nil, conditional: Bool = false, whenParameter: String? = nil) {
        self.name = name
        self.dataType = dataType
        self.required = required
        self.description = description
        self.exampleValue = exampleValue
        self.conditional = conditional
        self.whenParameter = whenParameter
    }

    public var isNodeSpecific: Bool { name.contains("{") }
    /// The variable name(s) for the node, placeholders replaced; empty when a parameter placeholder isn't set.
    public func resolveNames(for node: RecipeNode) -> [String] { rcoreStub() }
    /// Always set by this node: not conditional, or its `whenParameter` is set.
    public func isGuaranteed(for node: RecipeNode) -> Bool { rcoreStub() }
}

/// What a step needs and does to the image (upstream `PayloadContract`).
public struct PayloadContract: Sendable, Equatable {
    public var rawCapture: PayloadRequirement
    public var surface: PayloadRequirement
    public var extractedText: PayloadRequirement
    public var visualMutation: PayloadEffect

    public init(rawCapture: PayloadRequirement = .none, surface: PayloadRequirement = .none,
                extractedText: PayloadRequirement = .none, visualMutation: PayloadEffect = .none) {
        self.rawCapture = rawCapture
        self.surface = surface
        self.extractedText = extractedText
        self.visualMutation = visualMutation
    }
}

/// What the gate check of a step may look up besides the node: the external commands of the settings (the command line
/// of a named command) and the destinations of the settings (a Destinations node without designations exports to
/// them, upstream `ResolveDestinationDesignations` priority 4).
public struct GateEnvironment: Sendable {
    public var commandLine: @Sendable (String) -> String?
    public var defaultDestinations: [String]

    public init(commandLine: @escaping @Sendable (String) -> String? = { _ in nil }, defaultDestinations: [String] = []) {
        self.commandLine = commandLine
        self.defaultDestinations = defaultDestinations
    }

    public static let empty = GateEnvironment()
    /// From the settings: `externalCommands` and `destinations`.
    public init(settings: AppSettings) { rcoreStub() }
}

/// The contract of a step type (upstream `StepContract`, built from the `[Step*]` attributes): its parameters, the
/// variables it reads and sets, what it does to the image, and which gated actions a node of it does (upstream
/// `IRequiresRecipeAuthorization.GetGatedActions`, here a pure function of the node so validation, the describer and
/// `--info` work without the app).
public struct StepContract: Sendable {
    public var stepType: String
    public var displayName: String
    public var description: String
    public var category: String
    public var parameters: [ParameterContract]
    public var inputVariables: [VariableContract]
    public var outputVariables: [VariableContract]
    public var payload: PayloadContract
    /// The step reads more parameters than declared (Annotation): undeclared ones aren't reported.
    public var acceptsUndeclaredParameters: Bool
    /// The step evaluates the `${...}` in its parameters itself and gets them raw (upstream `IEvaluatesOwnParameters`).
    public var evaluatesOwnParameters: Bool
    public var gates: @Sendable (RecipeNode, GateEnvironment) -> [RecipeGatedAction]

    public init(stepType: String, displayName: String, description: String = "", category: String = "General",
                parameters: [ParameterContract] = [], inputVariables: [VariableContract] = [],
                outputVariables: [VariableContract] = [], payload: PayloadContract = PayloadContract(),
                acceptsUndeclaredParameters: Bool = false, evaluatesOwnParameters: Bool = false,
                gates: @escaping @Sendable (RecipeNode, GateEnvironment) -> [RecipeGatedAction] = { _, _ in [] }) {
        self.stepType = stepType
        self.displayName = displayName
        self.description = description
        self.category = category
        self.parameters = parameters
        self.inputVariables = inputVariables
        self.outputVariables = outputVariables
        self.payload = payload
        self.acceptsUndeclaredParameters = acceptsUndeclaredParameters
        self.evaluatesOwnParameters = evaluatesOwnParameters
        self.gates = gates
    }

    public func parameter(_ name: String) -> ParameterContract? { parameters.first { $0.matches(name) } }
}

/// The contracts of the step types by step type (case-insensitive; upstream `StepRegistry` contracts). `builtIn` has
/// every step type of upstream, the plug-in steps included (ExternalCommand, Jira, Confluence, Box, Dropbox, Office,
/// Pdf, BarcodeScan), whether or not the app has an executor for it yet.
public struct StepContractCatalog: Sendable {
    public static var builtIn: StepContractCatalog { rcoreStub() }

    public init(_ contracts: [StepContract]) { rcoreStub() }
    public var all: [StepContract] { rcoreStub() }
    public func contract(for stepType: String) -> StepContract? { rcoreStub() }
    public func contains(_ stepType: String) -> Bool { contract(for: stepType) != nil }
    /// A copy with the contract added or replaced.
    public func adding(_ contract: StepContract) -> StepContractCatalog { rcoreStub() }
}

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
    public static var builtIn: TriggerContractCatalog { rcoreStub() }

    public init(_ contracts: [TriggerContract]) { rcoreStub() }
    public var all: [TriggerContract] { rcoreStub() }
    public func contract(for triggerType: String) -> TriggerContract? { rcoreStub() }
}

/// The `requires` ids the Mac satisfies (upstream `RecipeValidator.ExtensionAvailabilityCheck`): the upstream plug-ins
/// whose features are built in. Unknown ids fail with upstream's message naming the plug-in and its URL.
public struct RecipeRequirementCatalog: Sendable {
    public static var builtIn: RecipeRequirementCatalog { rcoreStub() }

    public init(available: Set<String>) { rcoreStub() }
    /// The error for the requirement, nil when it is satisfied.
    public func problem(with requirement: RecipeRequirement) -> String? { rcoreStub() }
}

/// An upstream destination designation in a recipe ("Editor", "FileNoDialog", "External MS Paint", "Jira") and the
/// Mac destination it means. Designations are case-insensitive; the Mac-only ones are named after `CaptureDestination`.
public struct RecipeDestinationDesignation: Sendable, Equatable {
    public var designation: String
    public var destination: CaptureDestination?
    /// For "External <name>": the external command of the settings.
    public var externalCommandName: String?

    public init(_ designation: String) { rcoreStub() }
    /// The designation upstream uses for a Mac destination ("FileNoDialog" for `.file`).
    public static func designation(for destination: CaptureDestination) -> String { rcoreStub() }
    /// Uploads (Jira, Confluence, Box, Dropbox) and external commands; nil for the others (upstream's destinations'
    /// `GetGatedActions`).
    public func gatedAction(_ environment: GateEnvironment) -> RecipeGatedAction? { rcoreStub() }
    /// For the describer: "Open in image editor (Editor)".
    public var displayName: String { rcoreStub() }
}

/// Upstream hotkey text ("Ctrl + Shift + B", "Ctrl + K, C", "PrintScreen") to a Mac hotkey and back
/// (upstream `HotkeySequence.Parse`, `KeyChord.Parse`). Mapping: Ctrl/Control -> ⌘, Alt -> ⌥, Shift -> ⇧, Win -> ⌃;
/// the Mac names Cmd/Command/⌘, Option/Opt/⌥ and ⌃ are read too, so the same file works on both systems.
public enum RecipeHotkeyText {
    public static func parse(_ text: String) -> KeyCombo? { rcoreStub() }
    /// Why the text is not a usable hotkey (syntax, or `KeyCombo.validationProblem`), nil when it is.
    public static func problem(with text: String) -> String? { rcoreStub() }
    public static func format(_ combo: KeyCombo) -> String { rcoreStub() }
}

// MARK: - Expressions (upstream Greenshot.Base/Recipes/Expressions/ExpressionEvaluator.cs)

/// Where `user.*`, `machine.*`, `config.*` and the clock come from. Tests pass fixed values; the app passes
/// `SystemRecipeEnvironment` with a snapshot of the settings.
public protocol RecipeEnvironment: Sendable {
    /// `user.username`, `user.desktop`, ... (upstream `ResolveUserEnvironment`, macOS folders), then the environment.
    func userValue(_ key: String) -> JSONValue?
    /// `machine.computername`, `machine.os`, ... (upstream `ResolveMachineEnvironment`; Windows-only names are empty).
    func machineValue(_ key: String) -> JSONValue?
    /// `config.<name>`: a setting by its upstream `greenshot.ini` name or its Mac name, case-insensitive; read-only.
    func configValue(_ key: String) -> JSONValue?
    func now() -> Date
    var timeZone: TimeZone { get }
}

/// The real environment: NSUserName, the user's folders, ProcessInfo, and `config.*` from the settings snapshot through
/// a table of upstream names (`language`, `capturemousepointer`, `outputfilepath`, ...).
public struct SystemRecipeEnvironment: RecipeEnvironment {
    public init(settings: AppSettings) { rcoreStub() }
    public func userValue(_ key: String) -> JSONValue? { rcoreStub() }
    public func machineValue(_ key: String) -> JSONValue? { rcoreStub() }
    public func configValue(_ key: String) -> JSONValue? { rcoreStub() }
    public func now() -> Date { Date() }
    public var timeZone: TimeZone { .current }
}

/// Flow variables (upstream `CaptureFlowContext.Properties`): case-insensitive names, the spelling of the first set kept.
public struct RecipeVariables: Sendable, Equatable, Sequence {
    public init(_ values: [String: JSONValue] = [:]) { rcoreStub() }
    public subscript(name: String) -> JSONValue? {
        get { rcoreStub() }
        set { rcoreStub() }
    }
    public var names: [String] { rcoreStub() }
    public var count: Int { rcoreStub() }
    public func makeIterator() -> IndexingIterator<[JSONMember]> { rcoreStub() }
}

/// What `payload.*` reads (upstream `ResolvePayloadProperty`). Sizes are points (image pixels / pixels per point), the
/// unit of every geometry in a recipe on the Mac, see `RecipePayload`.
public struct PayloadMetrics: Sendable, Equatable {
    public var width: Double
    public var height: Double
    public var extractedText: String
    public var title: String
    public var filename: String
    public var metadata: [String: JSONValue]

    public init(width: Double, height: Double, extractedText: String = "", title: String = "", filename: String = "",
                metadata: [String: JSONValue] = [:]) {
        self.width = width
        self.height = height
        self.extractedText = extractedText
        self.title = title
        self.filename = filename
        self.metadata = metadata
    }
}

/// Everything an expression can read besides the environment. The runner makes it from the flow context
/// (`RecipeFlowContext.scope(extraVariables:)`); tests make it directly.
public struct ExpressionScope: Sendable {
    public var variables: RecipeVariables
    /// Nil before an image was acquired: `payload.*` is then 0, like upstream.
    public var payload: PayloadMetrics?
    /// `option.<key>`: the user's value of an option of the recipe (and its template flag), nil when not declared.
    /// Read before the variables, so a run can't override an option (upstream `ResolveSingleToken`).
    public var option: @Sendable (String) -> (value: JSONValue, isTemplate: Bool)?
    /// Node-local variables, read first (e.g. the Annotation step's surface size).
    public var extraVariables: [String: JSONValue]
    /// `context.RecipeId`, `context.RecipeName`, `context.ExecutionId`, `context.State`, `context.AbortReason`.
    public var recipeId: String
    public var recipeName: String
    public var executionId: String
    public var state: String
    public var abortReason: String?

    public init(variables: RecipeVariables = RecipeVariables(), payload: PayloadMetrics? = nil,
                option: @escaping @Sendable (String) -> (value: JSONValue, isTemplate: Bool)? = { _ in nil },
                extraVariables: [String: JSONValue] = [:], recipeId: String = "", recipeName: String = "",
                executionId: String = "", state: String = "NotStarted", abortReason: String? = nil) {
        self.variables = variables
        self.payload = payload
        self.option = option
        self.extraVariables = extraVariables
        self.recipeId = recipeId
        self.recipeName = recipeName
        self.executionId = executionId
        self.state = state
        self.abortReason = abortReason
    }
}

/// `${...}` in recipe values (upstream `ExpressionEvaluator`), same semantics: a value that is one `${...}` gives the typed
/// result, text around or several `${...}` interpolate into a string. Inside: `now:<.NET format>`, `utcnow:<format>`,
/// ternary `a ? b : c`, `||`, `&&`, `== != < <= > >=` (numbers with an epsilon, else case-insensitive text), `+ -`
/// (`+` joins when a side is text), `* / %` (by zero: 0), parentheses, literals ('text', "text", numbers, true, false,
/// null), scopes `user.` `machine.` `config.` `option.` `context.` `payload.`, bare `now`/`utcnow`, and bare names of
/// flow variables (`${Barcode.Text}`). Unknown names are null, syntax errors give null (logged): a recipe never fails
/// on an expression. No functions and no `??`: upstream has none, and recipes must stay portable.
public struct ExpressionEvaluator: Sendable {
    public init(environment: any RecipeEnvironment) { rcoreStub() }

    /// A value from a recipe: `${...}` evaluated, other text unchanged (upstream `Evaluate`).
    public func evaluate(_ text: String, in scope: ExpressionScope) -> JSONValue { rcoreStub() }
    /// The inside of `${...}` (upstream `EvaluateExpression`).
    public func evaluateExpression(_ expression: String, in scope: ExpressionScope) -> JSONValue { rcoreStub() }
    /// True when the value is true (upstream `ConvertToBoolean`: null false, numbers not 0, "true"/"false", other text
    /// when not empty); `defaultValue` when the text is nil or empty.
    public func evaluateBool(_ text: String?, in scope: ExpressionScope, default defaultValue: Bool) -> Bool { rcoreStub() }
    /// Every string with `${` in the value, recursively (upstream `ResolveParameters`/`ResolveObject`). Evaluated once:
    /// a result is never evaluated again, so `${...}` text from data (OCR, QR codes, window titles) stays text.
    public func resolve(_ value: JSONValue, in scope: ExpressionScope) -> JSONValue { rcoreStub() }
    public func resolveParameters(_ parameters: JSONObject, in scope: ExpressionScope) -> JSONObject { rcoreStub() }

    /// The syntax problem of the first `${...}` that has one, nil when all parse (validator and editor diagnostics).
    public static func syntaxProblem(in text: String) -> String? { rcoreStub() }
    /// The option keys `${...}` in the text read ("key", or "extension.key"; upstream `FindOptionReferences`).
    public static func optionReferences(in text: String) -> Set<String> { rcoreStub() }
    /// The variable names `${...}` in the text start with (upstream `RecipeContract.VariableReference`).
    public static func variableReferences(in text: String) -> [String] { rcoreStub() }
}

/// The user's values of recipe options (upstream `RecipeOptionStore`, greenshot.ini `[RecipeOptions]`): stored as
/// "<recipe id>.<option key>" in `RecipeSettings.optionValues`, only when they differ from the default.
public struct RecipeOptionValues: Sendable, Equatable {
    public var stored: [String: String]

    public init(_ stored: [String: String] = [:]) {
        self.stored = stored
    }

    public static func storageKey(recipeId: String, optionKey: String) -> String { "\(recipeId).\(optionKey)" }
    /// The stored value converted to the option, or its default.
    public func value(of option: RecipeOption, recipeId: String) -> JSONValue { rcoreStub() }
    /// Stores the value, removes it when it is the default; false when nothing changed or the value doesn't fit.
    @discardableResult
    public mutating func setValue(_ value: JSONValue, of option: RecipeOption, recipeId: String) -> Bool { rcoreStub() }
    /// Back to the defaults ("Reset to defaults").
    @discardableResult
    public mutating func reset(recipeId: String) -> Bool { rcoreStub() }
}

// MARK: - Payload and flow context (upstream CapturePayload, CaptureFlowContext)

/// The capture a flow works on (upstream `ICapturePayload`: raw capture + surface + extracted text). A value: a parallel
/// branch gets its own copy. `annotations` are the surface's elements, still editable when the Editor destination opens
/// it (RAPP builds an `EditorDocument` from image, scale, title and annotations).
///
/// Units: recipe geometry (annotation left/top/width/height/offsets/margins, effect sizes, `payload.width`) is in points,
/// i.e. upstream's pixels at 96 DPI, multiplied by `scale` to get image pixels; the same rule as `ImageEffects`.
public struct RecipePayload: @unchecked Sendable {
    public var image: CGImage
    /// Pixels per point of the capture (2 on a Retina display).
    public var scale: CGFloat
    public var annotations: [Annotation] = []
    /// OCR or barcode text (upstream `ExtractedText`).
    public var extractedText: String?
    /// The window title (upstream `CaptureDetails.Title`).
    public var title: String
    public var captureDate: Date
    /// The file it was loaded from or saved to (upstream `CaptureDetails.Filename`).
    public var fileURL: URL?
    /// The source type that acquired it ("Region", "Window", "File", ...).
    public var sourceType: String?
    /// Upstream `ICapturePayload.Metadata` (`payload.<key>` falls back to it).
    public var metadata: [String: JSONValue] = [:]
    /// What the app keeps with the capture for its own steps (the mouse pointer, the frozen screens the selection needs);
    /// copied by reference with the payload.
    public var attachments: [String: any Sendable] = [:]

    public init(image: CGImage, scale: CGFloat, title: String, captureDate: Date = Date()) {
        self.image = image
        self.scale = scale
        self.title = title
        self.captureDate = captureDate
    }

    public var metrics: PayloadMetrics { rcoreStub() }
    /// The image with the annotations drawn on it (`AnnotationRenderer.flatten`).
    public func flattened() -> CGImage? { rcoreStub() }
}

/// The lifecycle of a flow (upstream `CaptureFlowState`).
public enum RecipeFlowState: String, Sendable, Codable, CaseIterable {
    case notStarted = "NotStarted"
    case acquiring = "Acquiring"
    case selecting = "Selecting"
    case processing = "Processing"
    case exporting = "Exporting"
    case completed = "Completed"
    case cancelled = "Cancelled"
    case failed = "Failed"
}

/// Who started a flow and what the world looked like then (upstream `FlowTriggerContext`, snapshotted synchronously
/// where the trigger fired).
public struct RecipeTriggerInfo: Sendable, Equatable {
    public var triggerType: String
    public var triggerName: String?
    /// The index of the trigger in the recipe, nil for a start without one (menu, test run, forwarding).
    public var triggerIndex: Int?
    public var triggeredAt: Date
    /// The frontmost application then (nil: Greenshot itself or unknown).
    public var frontmostProcessID: Int32?
    public var cursorLocation: CGPoint?

    public init(triggerType: String, triggerName: String? = nil, triggerIndex: Int? = nil, triggeredAt: Date = Date(),
                frontmostProcessID: Int32? = nil, cursorLocation: CGPoint? = nil) {
        self.triggerType = triggerType
        self.triggerName = triggerName
        self.triggerIndex = triggerIndex
        self.triggeredAt = triggeredAt
        self.frontmostProcessID = frontmostProcessID
        self.cursorLocation = cursorLocation
    }
}

/// Where Stdout and Stderr steps write (upstream `StdoutWriter`/`StderrWriter`): the CLI or AI-tool caller (AUT).
public protocol RecipeOutputSink: Sendable {
    func writeStdout(_ text: String) async
    func writeStderr(_ text: String) async
}

/// One export of a flow (upstream `ExportOutcome`), for the Notification step and the failure notification.
public struct RecipeExportOutcome: Sendable, Equatable {
    /// The designation of the destination that exported ("Clipboard", "FileNoDialog", "Jira").
    public var designation: String
    public var succeeded: Bool
    /// The file, URL or name it went to.
    public var target: String?
    public var uri: URL?
    public var errorMessage: String?

    public init(designation: String, succeeded: Bool, target: String? = nil, uri: URL? = nil, errorMessage: String? = nil) {
        self.designation = designation
        self.succeeded = succeeded
        self.target = target
        self.uri = uri
        self.errorMessage = errorMessage
    }
}

/// The exports of one flow, shared by its branch contexts (upstream `ExportLog`). Thread safe.
public final class RecipeExportLog: @unchecked Sendable {
    public init() {}
    public func add(_ outcome: RecipeExportOutcome) { rcoreStub() }
    public var all: [RecipeExportOutcome] { rcoreStub() }
    /// The exports since the last call (a recipe with two Notification steps doesn't show an export twice).
    public func takeUnnotified() -> [RecipeExportOutcome] { rcoreStub() }
}

/// The state of one running flow (upstream `CaptureFlowContext`), handed to every step. Thread safe; a parallel branch
/// works on its own copy (`makeBranch()`), which shares the export log and the output sink.
public final class RecipeFlowContext: @unchecked Sendable {
    public let executionId: UUID
    /// The recipe as it runs (prepared for its trigger).
    public let recipe: CaptureRecipe
    public let trigger: RecipeTriggerInfo?
    public let environment: any RecipeEnvironment
    public let evaluator: ExpressionEvaluator
    /// The user's option values when the flow started.
    public let optionValues: RecipeOptionValues
    public let output: (any RecipeOutputSink)?
    public let exports: RecipeExportLog

    public init(recipe: CaptureRecipe, trigger: RecipeTriggerInfo? = nil, environment: any RecipeEnvironment,
                optionValues: RecipeOptionValues = RecipeOptionValues(), output: (any RecipeOutputSink)? = nil,
                executionId: UUID = UUID()) {
        self.executionId = executionId
        self.recipe = recipe
        self.trigger = trigger
        self.environment = environment
        self.evaluator = ExpressionEvaluator(environment: environment)
        self.optionValues = optionValues
        self.output = output
        self.exports = RecipeExportLog()
        rcoreStub()
    }

    public var payload: RecipePayload? {
        get { rcoreStub() }
        set { rcoreStub() }
    }
    /// The payload was handed to the flow (forwarded, from the browser extension or the editor): Source keeps it,
    /// InteractiveSelection and ImmediateFeedback skip (upstream `IsPayloadPreSupplied`).
    public var isPayloadPreSupplied: Bool {
        get { rcoreStub() }
        set { rcoreStub() }
    }
    public var state: RecipeFlowState {
        get { rcoreStub() }
        set { rcoreStub() }
    }
    public var exitCode: Int {
        get { rcoreStub() }
        set { rcoreStub() }
    }
    public var abortReason: String? { rcoreStub() }
    public var errorDescription: String? { rcoreStub() }
    /// Cancelled or failed.
    public var isAborted: Bool { rcoreStub() }
    public func abort(_ reason: String) { rcoreStub() }
    public func fail(_ reason: String, error: Error? = nil) { rcoreStub() }

    /// A flow variable, case-insensitive (upstream `Properties`).
    public subscript(variable name: String) -> JSONValue? {
        get { rcoreStub() }
        set { rcoreStub() }
    }
    public var variables: RecipeVariables { rcoreStub() }
    /// Host objects that aren't values (the editor of an Editor trigger as "EditorForm", a chosen window as
    /// "SelectedWindow"); not readable by expressions. Case-insensitive keys.
    public func object(forKey key: String) -> (any Sendable)? { rcoreStub() }
    public func setObject(_ object: (any Sendable)?, forKey key: String) { rcoreStub() }

    public func log(_ message: String) { rcoreStub() }
    public var executionLog: [String] { rcoreStub() }

    /// The scope for expressions now: the variables, `payload.*` and the recipe's options.
    public func scope(extraVariables: [String: JSONValue] = [:]) -> ExpressionScope { rcoreStub() }
    /// A copy for a parallel branch: variables, payload and objects copied; export log, output and id shared.
    public func makeBranch() -> RecipeFlowContext { rcoreStub() }
}

// MARK: - Steps

/// Runs the nodes of one step type. RCORE registers the executors that need no app (SetVariable, Conditional, Slot,
/// Stdout, Stderr, Effect, Annotation, TextEffect, Processors, BarcodeScan); RAPP registers the others at launch.
///
/// Conventions the engine relies on: an executor reads its parameters from `step` (already evaluated once, unless the
/// contract says `evaluatesOwnParameters`) and never evaluates `${...}` in a value it got; a UserPrompt executor sets
/// the variable `UserChoice.<node id>` to the chosen key; an export records each export with `context.exports.add`;
/// Source sets `context.payload` (keeping a pre-supplied one); an executor that throws fails the node (error
/// transitions apply), one that is cancelled throws `CancellationError`. Executors run off the main thread and hop to
/// the main actor themselves for UI.
public protocol RecipeStepExecutor: Sendable {
    func execute(_ step: RecipeStepInvocation, in context: RecipeFlowContext) async throws
}

/// A node about to run: its raw node, its parameters evaluated once, and its contract.
public struct RecipeStepInvocation: Sendable {
    public let node: RecipeNode
    /// The parameters with `${...}` evaluated (raw when `contract.evaluatesOwnParameters`).
    public let parameters: JSONObject
    public let contract: StepContract?

    public init(node: RecipeNode, parameters: JSONObject, contract: StepContract?) {
        self.node = node
        self.parameters = parameters
        self.contract = contract
    }

    /// The parameter, or the contract's default when it isn't set.
    public func value(_ name: String) -> JSONValue? { rcoreStub() }
    public func string(_ name: String) -> String? { value(name)?.asString }
    public func int(_ name: String) -> Int? { value(name)?.asInt }
    public func double(_ name: String) -> Double? { value(name)?.asDouble }
    public func bool(_ name: String) -> Bool? { value(name)?.asBool }
    public func strings(_ name: String) -> [String]? { value(name)?.asStrings }
    /// "#RRGGBB", "#AARRGGBB", "rgba(r,g,b,a)" with a = 0-255, or a .NET color name (upstream `ColorTranslator`).
    public func color(_ name: String) -> RGBAColor? { rcoreStub() }
    /// Set on the node (not the default).
    public func isSet(_ name: String) -> Bool { rcoreStub() }
    /// The three-tier precedence of docs/capture-recipes.md section 5: the run-time override in the flow variable
    /// `overrideVariable` (trigger, command line), then the node parameter; nil means "use the live setting".
    public func resolved(_ name: String, overrideVariable: String?, in context: RecipeFlowContext) -> JSONValue? { rcoreStub() }
}

/// An error with a type name that error transitions can match (`errorType`; upstream matches the .NET exception type,
/// e.g. "InvalidOperationException"). Other errors match by their Swift type name.
public struct RecipeStepError: Error, LocalizedError, Sendable {
    public var errorType: String
    public var message: String
    /// The type of the error that caused it; error transitions match it too (upstream matches `InnerException`).
    public var innerErrorType: String?

    public init(_ message: String, errorType: String = "RecipeStepError", innerErrorType: String? = nil) {
        self.message = message
        self.errorType = errorType
        self.innerErrorType = innerErrorType
    }

    public var errorDescription: String? { message }
}

/// The executors by step type (case-insensitive). The contracts come from the catalog; registering an executor for a
/// step type without a contract needs `register(contract:executor:)`.
public final class RecipeStepRegistry: @unchecked Sendable {
    public init(contracts: StepContractCatalog = .builtIn) { rcoreStub() }
    public var contracts: StepContractCatalog { rcoreStub() }
    public func register(_ stepType: String, executor: any RecipeStepExecutor) { rcoreStub() }
    public func register(contract: StepContract, executor: any RecipeStepExecutor) { rcoreStub() }
    public func executor(for stepType: String) -> (any RecipeStepExecutor)? { rcoreStub() }
    /// Registers RCORE's executors: SetVariable, Conditional, Slot, Stdout, Stderr, Effect, Annotation, TextEffect,
    /// Processors (OCR), BarcodeScan. `clipboard` is for BarcodeScan's `CopyToClipboard` (nil: not copied, logged);
    /// `cursorImages` draws the Annotation step's `CursorName` presets (nil: presets are skipped, logged).
    public func registerCoreExecutors(clipboard: (any RecipeClipboardWriting)? = nil,
                                      cursorImages: (any RecipeCursorImageProviding)? = nil) { rcoreStub() }
}

/// The pictures of the cursor presets of the Annotation step ("Arrow", "Hand", "IBeam", "Cross", "Wait", ...;
/// upstream's Windows cursor names): RAPP maps them to `NSCursor` images; Core itself doesn't use AppKit.
public protocol RecipeCursorImageProviding: Sendable {
    /// The picture and its hot spot (pixels from the top left), nil for an unknown preset.
    func cursorImage(named preset: String) async -> (image: CGImage, hotSpot: CGPoint)?
}

/// Copies text to the clipboard for Core's executors (RAPP: `NSPasteboard`); Core itself doesn't use AppKit.
public protocol RecipeClipboardWriting: Sendable {
    func copy(text: String) async
}

// MARK: - Running flows (upstream DagExecutionEngine, CapturePipeline, CaptureFlowRunner, CaptureFlowHandle)

/// Everything a start needs. The trigger hub, the CLI and the menu fill it.
public struct RecipeRunRequest: Sendable {
    public var recipe: CaptureRecipe
    public var trigger: RecipeTriggerInfo?
    /// Initial flow variables: bound arguments, "Filename" of an opened file, "PreSuppliedRegion", ...
    public var variables: [String: JSONValue] = [:]
    /// Initial host objects ("EditorForm", "TargetWindow").
    public var objects: [String: any Sendable] = [:]
    /// A capture handed to the flow (forwarded, browser extension, editor): `isPayloadPreSupplied` is set.
    public var payload: RecipePayload?
    public var output: (any RecipeOutputSink)?
    public var optionValues = RecipeOptionValues()
    /// Nil: the runner's environment.
    public var environment: (any RecipeEnvironment)?
    /// Runs once at the end, before the flow is gone (upstream `FlowFinishedAsync`): the CLI evaluates the trigger's
    /// `Stdout` and `--query` here with `context.evaluator.evaluate(_:in: context.scope())`.
    public var onFinish: (@Sendable (RecipeFlowContext) async -> Void)?

    public init(recipe: CaptureRecipe, trigger: RecipeTriggerInfo? = nil) {
        self.recipe = recipe
        self.trigger = trigger
    }
}

/// How a flow ended (upstream `CaptureFlowResult`). A flow never throws: errors end it as failed.
public struct RecipeFlowResult: Sendable {
    public var flowId: UUID
    public var recipeId: String
    public var recipeName: String
    /// Completed, cancelled or failed.
    public var state: RecipeFlowState
    public var reason: String?
    public var errorDescription: String?
    public var exitCode: Int
    public var variables: RecipeVariables
    public var executionLog: [String]
    public var exports: [RecipeExportOutcome]
    /// The final capture (nil when none was acquired or the flow didn't start).
    public var payload: RecipePayload?

    public init(flowId: UUID, recipeId: String, recipeName: String, state: RecipeFlowState, reason: String? = nil,
                errorDescription: String? = nil, exitCode: Int = 0, variables: RecipeVariables = RecipeVariables(),
                executionLog: [String] = [], exports: [RecipeExportOutcome] = [], payload: RecipePayload? = nil) {
        self.flowId = flowId
        self.recipeId = recipeId
        self.recipeName = recipeName
        self.state = state
        self.reason = reason
        self.errorDescription = errorDescription
        self.exitCode = exitCode
        self.variables = variables
        self.executionLog = executionLog
        self.exports = exports
        self.payload = payload
    }

    public var isSuccess: Bool { state == .completed }
}

/// What the runner reports while flows run: RAPP's failure notification (RCP-018) and running-flows list, AUT's
/// streaming. Delivered on an arbitrary thread.
public enum RecipeFlowEvent: Sendable {
    case flowStarted(flowId: UUID, recipeId: String, recipeName: String)
    /// A start that didn't run: exclusive recipe already running, a selection already open, shutting down.
    case flowRejected(recipeId: String, reason: String)
    case nodeStarted(flowId: UUID, nodeId: String, stepType: String)
    case nodeSkipped(flowId: UUID, nodeId: String, reason: String)
    case nodeFinished(flowId: UUID, nodeId: String)
    /// `handledBy`: the error node or recipe it went on with, nil when the flow failed.
    case nodeFailed(flowId: UUID, nodeId: String, message: String, handledBy: String?)
    case branchChosen(flowId: UUID, nodeId: String, branch: String?)
    /// Debug builds: a step did something its contract doesn't say (upstream `ContractViolation`).
    case contractViolation(flowId: UUID, message: String)
    case flowFinished(RecipeFlowResult)
}

/// A started flow (upstream `CaptureFlowHandle`).
public final class RecipeFlowHandle: Sendable {
    public let id: UUID
    public let recipeId: String
    public let recipeName: String

    public init(id: UUID, recipeId: String, recipeName: String, task: Task<RecipeFlowResult, Never>) { rcoreStub() }
    /// A start that was rejected; `result` is cancelled with the reason.
    public static func rejected(recipe: CaptureRecipe, reason: String) -> RecipeFlowHandle { rcoreStub() }
    /// Waits for the end; never throws.
    public var result: RecipeFlowResult { get async { rcoreStub() } }
    public func cancel() { rcoreStub() }
}

/// Executes a recipe on a context to the end (upstream `DagExecutionEngine`): start nodes; fork into merge clusters
/// (siblings that meet again run one after the other on the same context, independent ones in parallel on branch
/// copies, merged back after); join when all parents finished or were bypassed; Conditional's first true branch and
/// UserPrompt's choice with dead-path elimination; disabled nodes pass the flow on; error transitions and
/// `onErrorNodeId`/`onErrorRecipeId` with `LastError`, `LastErrorType`, `FailedNodeId`; cancellation aborts.
public struct RecipeFlowEngine: Sendable {
    public init(steps: RecipeStepRegistry,
                recipeLookup: @escaping @Sendable (String) async -> CaptureRecipe? = { _ in nil },
                checkContracts: Bool = false,
                events: (@Sendable (RecipeFlowEvent) -> Void)? = nil) { rcoreStub() }
    public func execute(_ context: RecipeFlowContext) async { rcoreStub() }
}

/// An observer registration; dropping it doesn't remove the observer, `cancel()` does.
public final class RecipeObservation: Sendable {
    public init(cancel: @escaping @Sendable () -> Void) { rcoreStub() }
    public func cancel() { rcoreStub() }
}

/// The one place that starts flows (upstream `CaptureFlowRunner`): runs each off the main thread, tracks the running
/// ones, applies the recipe's `concurrency`, refuses a second interactive selection, cancels everything on shutdown.
/// `start` returns at once. A flow runs `preflight`, then `RecipeTriggerPreparer.prepare` for the request's trigger type
/// (when it has a trigger), then the engine.
public final class RecipeRunner: @unchecked Sendable {
    /// - Parameters:
    ///   - preflight: before a flow starts: the recipe as it may run, nil to refuse (the library re-checks the approval
    ///     of a file recipe whose file changed, upstream `EnsureRecipeApprovedAndUpToDateAsync`).
    ///   - recipeLookup: for `onErrorRecipeId` / error transitions to another recipe.
    ///   - selectionInProgress: whether the capture screen is open (main actor); a recipe with an InteractiveSelection
    ///     node then brings it to the front via `bringSelectionToFront` and is rejected.
    public init(steps: RecipeStepRegistry,
                environment: @escaping @Sendable () -> any RecipeEnvironment,
                preflight: (@Sendable (CaptureRecipe) async -> CaptureRecipe?)? = nil,
                recipeLookup: @escaping @Sendable (String) async -> CaptureRecipe? = { _ in nil },
                selectionInProgress: (@MainActor @Sendable () -> Bool)? = nil,
                bringSelectionToFront: (@MainActor @Sendable () -> Void)? = nil) { rcoreStub() }

    @discardableResult
    public func start(_ request: RecipeRunRequest) -> RecipeFlowHandle { rcoreStub() }
    public var running: [RecipeFlowHandle] { rcoreStub() }
    public func addObserver(_ observer: @escaping @Sendable (RecipeFlowEvent) -> Void) -> RecipeObservation { rcoreStub() }
    /// Stops accepting flows, cancels the running ones and waits for them.
    public func shutdown() async { rcoreStub() }
}

/// What a trigger adds before the recipe runs (upstream `TriggerRecipePreparer`): a Source for its trigger when the
/// recipe has none, an editor destination when it has no destination (not for AI tools). Only `RecipeRunner` calls it
/// (once per flow, after the preflight); callers hand it the recipe as loaded.
public enum RecipeTriggerPreparer {
    public static func prepare(_ recipe: CaptureRecipe, triggerType: String) -> CaptureRecipe { rcoreStub() }
}

/// Binds the arguments a caller passes (CLI, `greenshot://`, browser extension, AI tool) to the arguments a trigger
/// declares (upstream `CommandlineArgumentBinder`): only declared names, required/default, type conversion. Paths go
/// through `resolvePath` (AUT's security rules and working directory); a thrown error's description is the message.
public enum RecipeArgumentBinder {
    public static func bind(declared: [CommandlineArgument], supplied: [String: String], recipeName: String,
                            resolvePath: (String, ContractDataType) throws -> String) -> Result<[String: JSONValue], RecipeStepError> {
        rcoreStub()
    }
}

// MARK: - Validation and contract analysis (upstream RecipeValidator, RecipeContract)

/// Errors stop a recipe from loading, warnings are shown (upstream `RecipeValidationResult`).
public struct RecipeValidationResult: Sendable, Equatable {
    public var errors: [String] = []
    public var warnings: [String] = []
    /// Every gated action of the recipe, once.
    public var gatedActions: [RecipeGatedAction] = []

    public init() {}

    public var isValid: Bool { errors.isEmpty }
    /// The kinds of gated actions, sorted (upstream `RecipeApprovalPolicy.GetGateTypes`).
    public var gateTypes: [RecipeGateType] { Array(Set(gatedActions.map(\.gateType))).sorted() }
}

/// Structural rules (header, triggers, nodes, options, flow, cycles) then, when valid, the contract warnings
/// (upstream `RecipeValidator.Validate`). The messages are upstream's; they are the editor's diagnostics too.
public struct RecipeValidator: Sendable {
    public init(contracts: StepContractCatalog = .builtIn, triggers: TriggerContractCatalog = .builtIn,
                requirements: RecipeRequirementCatalog = .builtIn, gates: GateEnvironment = .empty) { rcoreStub() }
    public func validate(_ recipe: CaptureRecipe) -> RecipeValidationResult { rcoreStub() }
}

/// One node in the contract report (upstream `StepSummaryContract`).
public struct RecipeStepSummary: Sendable, Equatable {
    public var nodeId: String
    public var stepType: String
    public var displayName: String
    public var requiredInputs: [String]
    public var producedOutputs: [String]
    public var reachable: Bool
    /// Variables set on every path to the node (by earlier nodes or the trigger).
    public var guaranteedVariables: [String]

    public init(nodeId: String, stepType: String, displayName: String, requiredInputs: [String] = [],
                producedOutputs: [String] = [], reachable: Bool = true, guaranteedVariables: [String] = []) {
        self.nodeId = nodeId
        self.stepType = stepType
        self.displayName = displayName
        self.requiredInputs = requiredInputs
        self.producedOutputs = producedOutputs
        self.reachable = reachable
        self.guaranteedVariables = guaranteedVariables
    }
}

/// The contract of a recipe along its graph (upstream `RecipeContract`): what it needs from the caller, what it
/// produces, and the warnings of docs section 8. `--info` (AUT) prints it.
public struct RecipeContractReport: Sendable, Equatable {
    public var recipeId: String
    public var recipeName: String
    public var description: String
    public var inputs: [VariableContract]
    public var outputs: [VariableContract]
    public var steps: [RecipeStepSummary]
    public var warnings: [String]
    public var acquiresImage: Bool
    public var mutatesPixels: Bool
    public var extractsText: Bool

    public init(recipeId: String, recipeName: String, description: String = "", inputs: [VariableContract] = [],
                outputs: [VariableContract] = [], steps: [RecipeStepSummary] = [], warnings: [String] = [],
                acquiresImage: Bool = false, mutatesPixels: Bool = false, extractsText: Bool = false) {
        self.recipeId = recipeId
        self.recipeName = recipeName
        self.description = description
        self.inputs = inputs
        self.outputs = outputs
        self.steps = steps
        self.warnings = warnings
        self.acquiresImage = acquiresImage
        self.mutatesPixels = mutatesPixels
        self.extractsText = extractsText
    }
}

public enum RecipeContractAnalyzer {
    /// The variables the triggers hand to the flow, and whether one hands the image (upstream `GetTriggerInputs`).
    public static func triggerInputs(of recipe: CaptureRecipe) -> (inputs: [VariableContract], providesPayload: Bool) { rcoreStub() }
    public static func analyze(_ recipe: CaptureRecipe, contracts: StepContractCatalog = .builtIn) -> RecipeContractReport { rcoreStub() }
}

// MARK: - Approval and trust (upstream Greenshot/Recipes/Approval/*)

/// What the user approved for one recipe of a file (upstream `RecipeApproval`).
public struct RecipeApproval: Sendable, Codable, Equatable {
    public var recipeId: String
    /// Keys from `RecipeApprovalPolicy.triggerKey`.
    public var approvedTriggers: [String] = []
    public var allTriggers: Bool = false
    public var allowedGates: [RecipeGateType] = []
    public var replacesBuiltIn: Bool = false

    public init(recipeId: String, approvedTriggers: [String] = [], allowedGates: [RecipeGateType] = []) {
        self.recipeId = recipeId
        self.approvedTriggers = approvedTriggers
        self.allowedGates = allowedGates
    }

    public func isTriggerApproved(_ key: String) -> Bool { rcoreStub() }
    public func isGateAllowed(_ gate: RecipeGateType) -> Bool { allowedGates.contains(gate) }
}

/// The approval of a file's exact content (upstream `RecipeTrustRecord`).
public struct RecipeTrustRecord: Sendable, Codable, Equatable {
    /// Origin of a recipe an AI tool wrote: "ai:" and the tool's name.
    public static let aiOriginPrefix = "ai:"

    /// The standardized path, compared case-insensitively.
    public var filePath: String
    /// SHA-256 of the file bytes, lowercase hex.
    public var sha256: String
    public var approvedAt: Date
    public var recipeName: String?
    public var recipeVersion: String?
    public var origin: String?
    /// The approved text (up to 256 KB), to show the changes when the file changes.
    public var approvedContent: String?
    public var recipes: [RecipeApproval] = []

    public init(filePath: String, sha256: String, approvedAt: Date = Date()) {
        self.filePath = filePath
        self.sha256 = sha256
        self.approvedAt = approvedAt
    }

    public var isAICreated: Bool { origin?.lowercased().hasPrefix(Self.aiOriginPrefix) ?? false }
    /// The AI tool's name, nil when no AI tool wrote it.
    public var proposedBy: String? { rcoreStub() }
    public func approval(for recipeId: String) -> RecipeApproval? { rcoreStub() }
}

/// SHA-256 of file bytes (upstream `RecipeTrustStore.ComputeSha256`).
public enum RecipeHash {
    public static func sha256Hex(_ data: Data) -> String { rcoreStub() }
}

/// The approvals (upstream `RecipeTrustStore`).
public protocol RecipeTrustStoring: Sendable {
    func record(forFile path: String) -> RecipeTrustRecord?
    /// The approval of the recipe when the record is for exactly this content, else nil.
    func approval(forFile path: String, sha256: String, recipeId: String) -> RecipeApproval?
    /// Keeps the approvals of the file's other recipes for the same content; new content starts a new record.
    func recordApproval(_ approval: RecipeApproval, forFile path: String, sha256: String, content: String?,
                        origin: String?, recipeName: String?, recipeVersion: String?) throws
    /// The record goes when no recipe of it is left.
    func revokeApproval(recipeId: String, forFile path: String) throws
    func revokeAll(forFile path: String) throws
    var allRecords: [RecipeTrustRecord] { get }
}

/// The trust store of the Mac (upstream: DPAPI-encrypted `recipe_trust.dat`): a JSON file (Application Support, RAPP
/// picks the URL) signed with HMAC-SHA256. The key is 32 random bytes in the `SecretStore` (the Keychain in the app)
/// under `keyName`, made on first use. A file whose signature doesn't match, or without a key, counts as empty
/// (default-deny: every recipe asks again) and `wasTampered` says so.
public final class RecipeTrustStore: RecipeTrustStoring, @unchecked Sendable {
    public static let keyName = "recipes.trustStoreKey"

    public init(fileURL: URL, secrets: any SecretStore) { rcoreStub() }
    public var wasTampered: Bool { rcoreStub() }
    public func record(forFile path: String) -> RecipeTrustRecord? { rcoreStub() }
    public func approval(forFile path: String, sha256: String, recipeId: String) -> RecipeApproval? { rcoreStub() }
    public func recordApproval(_ approval: RecipeApproval, forFile path: String, sha256: String, content: String?,
                               origin: String?, recipeName: String?, recipeVersion: String?) throws { rcoreStub() }
    public func revokeApproval(recipeId: String, forFile path: String) throws { rcoreStub() }
    public func revokeAll(forFile path: String) throws { rcoreStub() }
    public var allRecords: [RecipeTrustRecord] { rcoreStub() }
}

/// What an approval means at run time (upstream `RecipeApprovalPolicy`).
public enum RecipeApprovalPolicy {
    public static let browserInvocationSuffix = ":browser"
    /// "<index>:<TriggerType>": the approval belongs to one content, so the position identifies the trigger.
    public static func triggerKey(index: Int, trigger: TriggerConfig) -> String { "\(index):\(trigger.triggerType)" }
    public static func browserInvocationKey(index: Int, trigger: TriggerConfig) -> String {
        triggerKey(index: index, trigger: trigger) + browserInvocationSuffix
    }
    /// The gate types the approval doesn't allow; the recipe isn't loaded while there are any.
    public static func missingGates(_ validation: RecipeValidationResult, approval: RecipeApproval?) -> [RecipeGateType] { rcoreStub() }
}

/// Why the approval sheet is shown (upstream `RecipeApprovalMode`).
public enum RecipeApprovalMode: String, Sendable, CaseIterable {
    /// A file not approved before.
    case newRecipe
    /// An approved file changed outside Greenshot.
    case modified
    /// "Permissions" / Review: change the switches of an approved recipe.
    case reVerify
    /// The file can't load: the problem, a hint and "Edit Recipe File".
    case validationError
}

/// A line of what a recipe does (upstream `RecipeDescriptionLine`).
public struct RecipeDescriptionLine: Sendable, Equatable {
    public var text: String
    /// The kind of gated action the line is about, nil when harmless.
    public var risk: RecipeGateType?
    /// A detail of the line before (what a step uploads, which program it runs).
    public var isDetail: Bool

    public init(_ text: String, risk: RecipeGateType? = nil, isDetail: Bool = false) {
        self.text = text
        self.risk = risk
        self.isDetail = isDetail
    }
}

/// A trigger in words and why it matters (upstream `RecipeTriggerDescription`).
public struct RecipeTriggerDescription: Sendable, Equatable {
    /// The approval key (`RecipeApprovalPolicy.triggerKey`, or the browser-invocation key).
    public var key: String
    public var label: String
    /// Why it needs attention, nil when it only adds something the user starts (a hotkey, a menu entry).
    public var risk: String?
    /// Switched off in the recipe itself.
    public var isDisabled: Bool

    public init(key: String, label: String, risk: String? = nil, isDisabled: Bool = false) {
        self.key = key
        self.label = label
        self.risk = risk
        self.isDisabled = isDisabled
    }
}

/// One line of a line diff (upstream `RecipeTextDiff.DiffLine`).
public struct RecipeDiffLine: Sendable, Equatable {
    public enum Kind: String, Sendable { case unchanged, removed, added }
    public var kind: Kind
    public var text: String

    public init(_ kind: Kind, _ text: String) {
        self.kind = kind
        self.text = text
    }
}

/// Line diff of two versions of a file (upstream `RecipeTextDiff`, LCS; nil above 3000 lines).
public enum RecipeTextDiff {
    public static let maxLines = 3000
    public static func compare(_ old: String?, _ new: String?) -> [RecipeDiffLine]? { rcoreStub() }
    /// The changed lines with "-"/"+" and `context` unchanged lines around them, "@@" between the parts.
    public static func unifiedText(_ old: String?, _ new: String?, context: Int = 3) -> String { rcoreStub() }
}

/// What the approval sheet shows (upstream `RecipeApprovalRequest`), all computed by Core.
public struct RecipeApprovalRequest: Sendable {
    public var mode: RecipeApprovalMode
    /// Nil when the file couldn't be read as a recipe (validation-error mode with `errorMessage`).
    public var recipe: CaptureRecipe?
    public var fileURL: URL?
    /// The text that was read once: shown, parsed and hashed, so the approval is for exactly this.
    public var content: String
    public var contentHash: String
    public var validation: RecipeValidationResult?
    public var previousRecord: RecipeTrustRecord?
    /// "What it does", from the recipe (never from its description or an AI's words).
    public var steps: [RecipeDescriptionLine] = []
    public var triggers: [RecipeTriggerDescription] = []
    /// The gate types it needs, one permission switch each.
    public var gates: [RecipeGateType] = []
    /// Modified / replaces a built-in: "Adds: ..." / "Removes: ..." lines and the line diff against `previousContent`.
    public var changes: [String] = []
    public var previousContent: String?
    public var diff: [RecipeDiffLine]?
    public var replacesBuiltIn: Bool = false
    public var replacedRecipe: CaptureRecipe?
    /// The AI tool that proposed it and its own words (untrusted, shown as such).
    public var proposedBy: String?
    public var aiRequest: String?
    public var aiExplanation: String?
    /// Every trigger and permission starts switched off (AI proposals and files an AI tool wrote).
    public var startSwitchedOff: Bool = false
    /// Saved in Greenshot's recipe editor: why the change needs a decision.
    public var ownEditReasons: [String]?
    /// The switches as they start (own edit: unchanged triggers keep theirs, new harmless ones on).
    public var suggestedApproval: RecipeApproval?
    /// Details: nothing can be switched, only Close.
    public var isReadOnly: Bool = false
    /// Validation-error mode: the problem and a hint what to change.
    public var errorMessage: String?
    public var hint: String?

    public init(mode: RecipeApprovalMode, recipe: CaptureRecipe?, fileURL: URL?, content: String, contentHash: String) {
        self.mode = mode
        self.recipe = recipe
        self.fileURL = fileURL
        self.content = content
        self.contentHash = contentHash
    }
}

/// The user's answer (upstream `ApprovalResult`).
public struct RecipeApprovalDecision: Sendable, Equatable {
    public var approval: RecipeApproval?
    /// "Open in the recipe editor after saving".
    public var openInEditor: Bool
    /// "Revoke Approval" in a review.
    public var isRevoked: Bool

    public init(approval: RecipeApproval?, openInEditor: Bool = false, isRevoked: Bool = false) {
        self.approval = approval
        self.openInEditor = openInEditor
        self.isRevoked = isRevoked
    }

    public static let revoked = RecipeApprovalDecision(approval: nil, isRevoked: true)
}

/// Shows the approval sheet (RAPP). Nil: rejected, or closed without a change in a review.
@MainActor
public protocol RecipeApprover: AnyObject {
    func requestApproval(_ request: RecipeApprovalRequest) async -> RecipeApprovalDecision?
    /// Validation-error mode: shows the problem; nothing to decide.
    func showValidationError(_ request: RecipeApprovalRequest) async
}

/// What the user must decide about a change saved in the recipe editor (upstream `RecipeEditDecision`).
public struct RecipeEditDecision: Sendable, Equatable {
    public var reasons: [String] = []
    /// The keys of the new triggers it is about.
    public var triggerKeys: [String] = []

    public init() {}

    public var isNeeded: Bool { !reasons.isEmpty }
}

/// The approval of a recipe saved in the recipe editor (upstream `RecipeEditApproval`): renewed without asking, unless
/// the change adds a trigger that starts it on its own or from outside, a new kind of permission, or first replaces a
/// built-in recipe.
public enum RecipeEditApproval {
    public static func create(edited: CaptureRecipe, validation: RecipeValidationResult, approvedVersion: CaptureRecipe?,
                              previousApproval: RecipeApproval?, replacesBuiltIn: Bool) -> (approval: RecipeApproval, decision: RecipeEditDecision) {
        rcoreStub()
    }
    /// The recipe with the id in an approved content.
    public static func findRecipe(in content: String?, id: String) -> CaptureRecipe? { rcoreStub() }
}

/// What a recipe does in plain words, from the recipe itself (upstream `RecipeDescriber`).
public struct RecipeDescriber: Sendable {
    public init(contracts: StepContractCatalog = .builtIn, gates: GateEnvironment = .empty) { rcoreStub() }
    public func describeTriggers(_ recipe: CaptureRecipe) -> [RecipeTriggerDescription] { rcoreStub() }
    public func describeSteps(_ recipe: CaptureRecipe) -> [RecipeDescriptionLine] { rcoreStub() }
    /// "Adds: ..." / "Removes: ..." between two versions.
    public func describeChanges(from old: CaptureRecipe?, to new: CaptureRecipe?) -> [String] { rcoreStub() }
    /// "Uploads to Jira", "Runs the program /usr/local/bin/pngquant", or the file-access text.
    public func describe(_ action: RecipeGatedAction) -> String { rcoreStub() }
}

/// What the recipe manager's Details shows (upstream `RecipeDetails`).
public struct RecipeDetails: Sendable, Equatable {
    public var whatItDoes: [RecipeDescriptionLine] = []
    public var triggers: [RecipeTriggerDescription] = []
    public var approvedAt: Date?
    public var approvedHash: String?
    /// The file on disk is the approved content.
    public var isApprovalCurrent: Bool = false
    public var permissions: [RecipeGateType] = []
    public var proposedBy: String?
    /// The changed lines against the built-in recipe it replaces.
    public var builtInDiff: String?

    public init() {}
}

// MARK: - The recipe library (upstream RecipeManager) and triggers (upstream TriggerManager)

/// Where a loaded recipe comes from.
public enum RecipeSource: Sendable, Equatable {
    case builtIn
    case file(URL)
}

/// A recipe Greenshot knows (upstream `CaptureRecipe` with its runtime state): file content plus where it came from,
/// whether it is switched on, its approval.
public struct LoadedRecipe: Sendable {
    public var recipe: CaptureRecipe
    public var source: RecipeSource
    /// Not in `RecipeSettings.disabledRecipeIds`.
    public var isEnabled: Bool
    /// A file replaces the built-in recipe with the same id.
    public var replacesBuiltIn: Bool
    /// Nil for built-in recipes (always approved).
    public var approval: RecipeApproval?
    /// The AI tool that wrote the file.
    public var proposedBy: String?
    public var validation: RecipeValidationResult

    public init(recipe: CaptureRecipe, source: RecipeSource, isEnabled: Bool = true, replacesBuiltIn: Bool = false,
                approval: RecipeApproval? = nil, proposedBy: String? = nil, validation: RecipeValidationResult = RecipeValidationResult()) {
        self.recipe = recipe
        self.source = source
        self.isEnabled = isEnabled
        self.replacesBuiltIn = replacesBuiltIn
        self.approval = approval
        self.proposedBy = proposedBy
        self.validation = validation
    }

    public var isBuiltIn: Bool { source == .builtIn }
    /// Enabled in the recipe and approved (built-in: enabled), when the recipe is switched on (upstream `IsActive`).
    public func isTriggerActive(at index: Int) -> Bool { rcoreStub() }
    /// A Commandline trigger's browser invocation is approved too.
    public func isBrowserInvocationApproved(at index: Int) -> Bool { rcoreStub() }
}

/// A trigger that may start its recipe now, for a trigger source (upstream `SyncRecipeTriggers`).
public struct ActiveRecipeTrigger: Sendable, Equatable {
    public var recipeId: String
    public var recipeName: String
    public var index: Int
    public var trigger: TriggerConfig
    /// The parsed hotkey of a Hotkey trigger.
    public var hotkey: KeyCombo?
    public var browserInvocationApproved: Bool

    public init(recipeId: String, recipeName: String, index: Int, trigger: TriggerConfig, hotkey: KeyCombo? = nil,
                browserInvocationApproved: Bool = false) {
        self.recipeId = recipeId
        self.recipeName = recipeName
        self.index = index
        self.trigger = trigger
        self.hotkey = hotkey
        self.browserInvocationApproved = browserInvocationApproved
    }

    public var key: String { RecipeApprovalPolicy.triggerKey(index: index, trigger: trigger) }
}

/// A recipe that can run as a command (Commandline trigger; upstream `--list-recipes`).
public struct RecipeCommand: Sendable, Equatable {
    public var recipeId: String
    /// The command name (the trigger's `Command`, else the recipe id).
    public var command: String
    public var description: String?
    public var arguments: [CommandlineArgument]
    public var fireAndForget: Bool
    /// The trigger's `Stdout` expression.
    public var stdout: String?
    public var triggerIndex: Int
    public var allowsBrowserInvocation: Bool

    public init(recipeId: String, command: String, description: String? = nil, arguments: [CommandlineArgument] = [],
                fireAndForget: Bool = false, stdout: String? = nil, triggerIndex: Int, allowsBrowserInvocation: Bool = false) {
        self.recipeId = recipeId
        self.command = command
        self.description = description
        self.arguments = arguments
        self.fireAndForget = fireAndForget
        self.stdout = stdout
        self.triggerIndex = triggerIndex
        self.allowsBrowserInvocation = allowsBrowserInvocation
    }
}

/// Who asks to run a command; browser callers need the `:browser` approval.
public enum RecipeInvocationSource: Sendable, Equatable {
    case commandLine
    case urlScheme
    case browser
    case aiTool(client: String)
}

/// The outcome of loading files (upstream `RecipeValidationResult` of `LoadRecipeFromFile`).
public struct RecipeLoadResult: Sendable, Equatable {
    public var errors: [String] = []
    public var warnings: [String] = []
    public var loadedRecipeIds: [String] = []

    public init() {}

    public var isValid: Bool { errors.isEmpty }
}

/// The recipes Greenshot knows and their approvals (upstream `RecipeManager`): built-in recipes, files listed in
/// `RecipeSettings.files` (no folder scanning), default-deny approval of each recipe of a file pinned to the SHA-256 of
/// its bytes, override and reset of built-ins, switching recipes on and off, saving from the editor with the edit
/// decision table, revoke and review, details, commands for the CLI. Nothing here draws: questions go to the approver.
@MainActor
public final class RecipeLibrary {
    /// - Parameters:
    ///   - loadSettings / saveSettings: `AppSettings.recipes` (the app's settings store).
    ///   - gates: the settings' external commands and destinations, for the gate check.
    ///   - watchFiles: watch the loaded files (`RecipeFileMonitor`) and ask again right after one changes; off in tests.
    public init(loadSettings: @escaping @MainActor () -> RecipeSettings,
                saveSettings: @escaping @MainActor (RecipeSettings) -> Void,
                trustStore: any RecipeTrustStoring,
                approver: (any RecipeApprover)?,
                builtInRecipes: [CaptureRecipe] = [],
                contracts: StepContractCatalog = .builtIn,
                gates: @escaping @MainActor () -> GateEnvironment = { .empty },
                watchFiles: Bool = true) { rcoreStub() }

    /// Called after recipes, approvals or the switch changed (resync triggers and menus).
    public var onChange: (@MainActor () -> Void)?

    /// Off: no recipe files are loaded, no recipe triggers (upstream `EnableRecipeFeature`).
    public var isFeatureEnabled: Bool { rcoreStub() }
    public var recipes: [LoadedRecipe] { rcoreStub() }
    public func recipe(id: String) -> LoadedRecipe? { rcoreStub() }
    public func builtInRecipe(id: String) -> CaptureRecipe? { rcoreStub() }
    /// The triggers that may start their recipes now, of the given types (all when nil).
    public func activeTriggers(ofTypes types: Set<String>? = nil) -> [ActiveRecipeTrigger] { rcoreStub() }

    /// The user's option values (RCP-006), for Settings > Recipes and the runs.
    public var optionValues: RecipeOptionValues { rcoreStub() }
    public func setOptionValue(_ value: JSONValue, key: String, recipeId: String) { rcoreStub() }
    public func resetOptions(recipeId: String) { rcoreStub() }

    /// Loads the files of the settings again (tray "Reload Recipes").
    public func reload() async -> RecipeLoadResult { rcoreStub() }
    /// Reads the file once, hashes the bytes, validates each recipe and asks for the approval of those not approved for
    /// this content (`interactive`); approved and allowed ones replace what was loaded and the file joins the settings.
    public func loadFile(_ url: URL, interactive: Bool = true, forcePrompt: Bool = false) async -> RecipeLoadResult { rcoreStub() }
    /// Import: load interactively.
    public func importFile(_ url: URL) async -> RecipeLoadResult { await loadFile(url) }
    /// The file monitor saw a change: asks right away when a recipe in use lost its approval (upstream `CheckChangedFile`).
    public func fileDidChange(_ url: URL) async { rcoreStub() }
    /// Before a run: the recipe as it may run (its file still approved, or approved again), nil when not
    /// (upstream `EnsureRecipeApprovedAndUpToDateAsync`). The runner's `preflight`.
    public func ensureApprovedAndCurrent(_ recipe: CaptureRecipe) async -> CaptureRecipe? { rcoreStub() }

    /// Saves from the recipe editor: the approval is renewed without asking unless `saveDecisionReasons` is not empty.
    public func save(_ recipe: CaptureRecipe, to url: URL) async -> RecipeLoadResult { rcoreStub() }
    public func saveDecisionReasons(for recipe: CaptureRecipe, at url: URL?) -> [String] { rcoreStub() }
    /// An AI tool's proposal (RCP-204): written to `url` after the user approved it, triggers and permissions off.
    public func propose(content: String, proposedBy: String, aiRequest: String?, aiExplanation: String?, saveTo url: URL) async -> RecipeLoadResult { rcoreStub() }

    public func setEnabled(_ enabled: Bool, recipeId: String) { rcoreStub() }
    /// Drops the file recipe and brings the built-in back ("Reset Default").
    @discardableResult
    public func resetToDefault(recipeId: String) -> Bool { rcoreStub() }
    public func resetAllToDefault() { rcoreStub() }
    /// Forgets a file recipe (manager "Unload"): out of the settings, approval kept.
    public func unload(recipeId: String) { rcoreStub() }
    @discardableResult
    public func revokeApproval(recipeId: String) -> Bool { rcoreStub() }
    /// "Permissions": the approval sheet in review mode.
    public func reviewApproval(recipeId: String) async -> RecipeLoadResult { rcoreStub() }
    public func details(recipeId: String) -> RecipeDetails? { rcoreStub() }
    /// The approval sheet read-only (Details).
    public func detailsRequest(recipeId: String) -> RecipeApprovalRequest? { rcoreStub() }

    /// The recipes with an active Commandline (or, for `.aiTool`, AiTool) trigger the source may start.
    public func commands(for source: RecipeInvocationSource) -> [RecipeCommand] { rcoreStub() }
    /// A run request for a command with bound arguments (`RecipeArgumentBinder`) and a Commandline (or AiTool) trigger
    /// info; the runner prepares the recipe for it. Throws `RecipeStepError` with a message for stderr (unknown command,
    /// not approved, bad arguments).
    public func runRequest(command: String, arguments: [String: String], source: RecipeInvocationSource,
                           resolvePath: (String, ContractDataType) throws -> String) throws -> RecipeRunRequest { rcoreStub() }
    /// A run request for a recipe by id (menu entry, test run) with a trigger info of this type; the runner prepares
    /// the recipe for it.
    public func runRequest(recipeId: String, triggerType: String = WellKnownTriggerType.manual) -> RecipeRunRequest? { rcoreStub() }
    /// The contract report of a recipe (`--info`).
    public func contractReport(recipeId: String) -> RecipeContractReport? { rcoreStub() }
}

/// A kind of trigger the app provides (RAPP: hotkeys, the Recipes menu, the clipboard monitor, Open With, the editor
/// menu). The hub hands it the active triggers of its types whenever they change; it calls `RecipeTriggerHub.fire`.
@MainActor
public protocol RecipeTriggerSource: AnyObject {
    var triggerTypes: Set<String> { get }
    func sync(_ triggers: [ActiveRecipeTrigger])
    func stop()
}

/// Connects the trigger sources with the library and the runner (upstream `TriggerManager`).
@MainActor
public final class RecipeTriggerHub {
    public init(library: RecipeLibrary, runner: RecipeRunner) { rcoreStub() }
    public func register(_ source: any RecipeTriggerSource) { rcoreStub() }
    /// Recomputes the active triggers and syncs every source (after reload, approval, settings change).
    public func sync() { rcoreStub() }
    /// A trigger fired: starts its recipe with the trigger info (the runner prepares the recipe for the trigger). Nil
    /// when the trigger isn't active anymore.
    @discardableResult
    public func fire(_ trigger: ActiveRecipeTrigger, info: RecipeTriggerInfo, variables: [String: JSONValue] = [:],
                     objects: [String: any Sendable] = [:], payload: RecipePayload? = nil) -> RecipeFlowHandle? { rcoreStub() }
    public func stopAll() { rcoreStub() }
}

/// Watches the folders of recipe files for changes to `*.gsrecipe.json` (upstream `FileSystemWatcher`) and reports a
/// changed file once it has been quiet for `debounce` seconds (upstream 1.5 s).
public final class RecipeFileMonitor: @unchecked Sendable {
    public init(debounce: TimeInterval = 1.5, onChange: @escaping @Sendable (URL) -> Void) { rcoreStub() }
    public func watch(_ fileURL: URL) { rcoreStub() }
    public func stopAll() { rcoreStub() }
}
