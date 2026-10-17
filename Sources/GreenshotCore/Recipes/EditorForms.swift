// Greenshot for Mac (Community) - an unofficial macOS port of Greenshot
// Copyright (C) 2026 Greenshot for Mac (Community) contributors
// Based on Greenshot, Copyright (C) 2007-2026 Thomas Braun, Jens Klingen, Robin Krom
// SPDX-License-Identifier: GPL-3.0-or-later

import Foundation

/// The control a parameter gets in the recipe editor (upstream RecipeEditorWindow.xaml:1086-3090 has one hand-written
/// panel per step; the Mac generates them from the step contracts).
public enum RecipeEditorFieldKind: Sendable, Equatable {
    case text
    case multilineText
    case integer
    case decimal
    case boolean
    /// One of these values (an Enum parameter).
    case choice([String])
    /// "#RRGGBB", "#AARRGGBB", a colour name or `rgba(…)`.
    case color
    case filePath
    case directoryPath
    /// A sound file with a play button (ImmediateFeedback `SoundFilePath`).
    case soundFile
    /// A list of texts, one per line (TextEffect `Patterns`, Processors `ProcessorIds`).
    case stringList
    /// Name → value (SetVariable `Variables`).
    case keyValueTable
    /// Key + expression (Conditional `Branches`).
    case branchTable
    /// Key, label, style, default, cancel (UserPrompt `Choices`).
    case choiceTable
    /// Destination designations (Destinations `DestinationDesignations`, DynamicDestination `Destinations`).
    case destinationList
    /// Torn edges: top, right, bottom, left.
    case edges
    /// Slot `Accept`: "all", "none" or extension ids.
    case accept
    /// Commandline / AiTool `Arguments`.
    case arguments
    /// Annotation `Annotations`.
    case annotations
    /// Hotkey trigger `Hotkey` ("Ctrl + Shift + B").
    case hotkey
    /// Any other object, as JSON text.
    case json
}

/// A field is only shown while another parameter has one of some values (upstream shows one panel per effect, source type…).
public struct RecipeEditorFieldCondition: Sendable, Equatable {
    public var parameter: String
    public var values: [String]

    public init(parameter: String, values: [String]) {
        self.parameter = parameter
        self.values = values
    }
}

/// One field of a generated form.
public struct RecipeEditorField: Sendable, Equatable, Identifiable {
    public var name: String
    public var label: String
    public var help: String
    public var kind: RecipeEditorFieldKind
    public var required: Bool
    public var defaultValue: JSONValue?
    /// False: the value is used as written (`${…}` not evaluated), so the field offers no expression.
    public var supportsExpressions: Bool
    public var condition: RecipeEditorFieldCondition?
    /// A destination parameter that only matters for these designations ("Editor", "Printer", "Clipboard",
    /// "CustomDestination"; "File" for the file parameters).
    public var destinationGroup: String?

    public var id: String { name }

    public init(name: String, label: String, help: String = "", kind: RecipeEditorFieldKind, required: Bool = false,
                defaultValue: JSONValue? = nil, supportsExpressions: Bool = true, condition: RecipeEditorFieldCondition? = nil,
                destinationGroup: String? = nil) {
        self.name = name
        self.label = label
        self.help = help
        self.kind = kind
        self.required = required
        self.defaultValue = defaultValue
        self.supportsExpressions = supportsExpressions
        self.condition = condition
        self.destinationGroup = destinationGroup
    }
}

/// Forms generated from `StepContract` and `TriggerContract` (the reason the contracts were built first: upstream's
/// StepNodeViewModel.cs is 4000 hand-written lines).
public enum RecipeEditorForm {
    /// The object parameters with their own editor.
    static let objectKinds: [String: RecipeEditorFieldKind] = [
        "branches": .branchTable, "choices": .choiceTable, "patterns": .stringList, "variables": .keyValueTable,
        "annotations": .annotations, "destinationdesignations": .destinationList, "destinations": .destinationList,
        "edges": .edges, "accept": .accept, "processorids": .stringList, "arguments": .arguments
    ]

    /// The destination parameters and the designation they belong to.
    static let destinationGroups: [String: String] = [
        "savedirectory": "File", "filenamepattern": "File", "format": "File", "jpegquality": "File", "reducecolors": "File",
        "promptquality": "File", "allowoverwrite": "File", "copypathtoclipboard": "File"
    ]

    /// The step types that export through the destination step (upstream `DestinationExportStep` registrations).
    static let destinationStepTypes: Set<String> = [
        WellKnownStepType.destinations, WellKnownStepType.saveFile, WellKnownStepType.clipboard, WellKnownStepType.editor,
        WellKnownStepType.printer, WellKnownStepType.email, WellKnownStepType.customDestination
    ].reduce(into: Set<String>()) { $0.insert($1.lowercased()) }

    public static func fields(for contract: StepContract) -> [RecipeEditorField] {
        let isDestination = destinationStepTypes.contains(contract.stepType.lowercased())
        return contract.parameters.map { parameter in
            var field = self.field(for: parameter)
            let tags = tagGroups(of: parameter.description)
            if let condition = condition(for: tags, in: contract) {
                field.condition = condition
            } else if isDestination {
                let tag = tags.flatMap { $0 }.first { tag in destinationTags.contains { recipeEquals($0, tag) } }
                field.destinationGroup = tag ?? destinationGroups[parameter.name.lowercased()]
            }
            return field
        }
    }

    public static func fields(for contract: TriggerContract) -> [RecipeEditorField] {
        contract.parameters.map { parameter in
            var field = self.field(for: parameter)
            if recipeEquals(parameter.name, "Hotkey") { field.kind = .hotkey }
            return field
        }
    }

    /// The field of one parameter.
    public static func field(for parameter: ParameterContract) -> RecipeEditorField {
        RecipeEditorField(name: parameter.name, label: label(for: parameter.name), help: parameter.description,
                          kind: kind(for: parameter), required: parameter.required, defaultValue: parameter.defaultValue,
                          supportsExpressions: parameter.supportsExpressions)
    }

    static func kind(for parameter: ParameterContract) -> RecipeEditorFieldKind {
        let name = parameter.name.lowercased()
        if parameter.dataType == .object, let kind = objectKinds[name] { return kind }
        switch parameter.dataType {
        case .boolean: return .boolean
        case .integer: return .integer
        case .decimal: return .decimal
        case .color: return .color
        case .filePath: return name == "soundfilepath" ? .soundFile : .filePath
        case .directoryPath: return .directoryPath
        case .enumeration:
            let values = parameter.effectiveAllowedValues
            return values.isEmpty ? .text : .choice(values)
        case .object:
            return name == "windowhandle" ? .text : .json
        case .string, .window, .region:
            if name.hasSuffix("color") { return .color }
            if ["message", "text", "content", "clipboardcustomtext", "stdout"].contains(name) { return .multilineText }
            return .text
        }
    }

    /// The groups in parentheses at the end of the parts of a description: "Border width (Border), new width (Resize)"
    /// gives [["Border"], ["Resize"]]; "(DropShadow, TornEdge)" gives [["DropShadow", "TornEdge"]].
    static func tagGroups(of description: String) -> [[String]] {
        var groups: [[String]] = []
        var rest = Substring(description)
        while let open = rest.firstIndex(of: "("), let close = rest[open...].firstIndex(of: ")") {
            let inside = rest[rest.index(after: open)..<close]
            groups.append(inside.split(separator: ",").map { $0.trimmingCharacters(in: .whitespaces) }.filter { !$0.isEmpty })
            rest = rest[rest.index(after: close)...]
        }
        return groups
    }

    /// A condition from the tags that name values of an Enum parameter of the step ("Border" of Effect, "Monitor" of
    /// RecordVideo's SourceType) or are "<Parameter> <Value>" ("SourceType Window"); other tags ("default: settings",
    /// "1-100") are ignored. Nil when no tag matches, or tags name different parameters.
    static func condition(for groups: [[String]], in contract: StepContract) -> RecipeEditorFieldCondition? {
        var parameter: String?
        var values: [String] = []
        for tag in groups.flatMap({ $0 }) {
            let match = selectorValue(tag, in: contract)
            guard let match else { continue }
            if let parameter, !recipeEquals(parameter, match.parameter) { return nil }
            parameter = match.parameter
            values.append(match.value)
        }
        guard let parameter else { return nil }
        return RecipeEditorFieldCondition(parameter: parameter, values: values)
    }

    private static func selectorValue(_ tag: String, in contract: StepContract) -> (parameter: String, value: String)? {
        let words = tag.split(separator: " ").map(String.init)
        if words.count == 2, let named = contract.parameter(words[0]), named.dataType == .enumeration,
           named.effectiveAllowedValues.contains(where: { recipeEquals($0, words[1]) }) {
            return (named.name, words[1])
        }
        for candidate in contract.parameters where candidate.dataType == .enumeration {
            if candidate.effectiveAllowedValues.contains(where: { recipeEquals($0, tag) }) { return (candidate.name, tag) }
        }
        return nil
    }

    /// The designation tags of the destination parameters.
    static let destinationTags = ["Editor", "Printer", "Clipboard", "CustomDestination"]

    /// Whether a field is shown for this node (the "Show all parameters" switch shows them all).
    public static func isVisible(_ field: RecipeEditorField, in node: RecipeNode, contract: StepContract) -> Bool {
        if let condition = field.condition {
            let current = node.parameters[condition.parameter]?.asString
                ?? contract.parameter(condition.parameter)?.defaultValue?.asString
            guard let current else { return true }
            if current.contains("${") { return true }
            return condition.values.contains { recipeEquals($0, current) }
        }
        let stepType = node.stepType.lowercased()
        guard destinationStepTypes.contains(stepType) else { return true }
        if recipeEquals(field.name, "DestinationDesignations") { return recipeEquals(node.stepType, WellKnownStepType.destinations) }
        let group = field.destinationGroup
        switch stepType {
        case WellKnownStepType.destinations.lowercased():
            guard let group, group != "File" else { return true }
            if recipeEquals(group, WellKnownStepType.customDestination) { return false }
            let listed = node.parameters.strings("DestinationDesignations") ?? []
            return listed.isEmpty || listed.contains { recipeEquals($0, group) }
        case WellKnownStepType.saveFile.lowercased(), WellKnownStepType.email.lowercased():
            return group == "File"
        case WellKnownStepType.customDestination.lowercased():
            return group == "File" || recipeEquals(group ?? "", WellKnownStepType.customDestination)
        default:
            return recipeEquals(group ?? "", node.stepType)
        }
    }

    /// The parameters of the node no contract parameter names (kept and shown as "Other parameters").
    public static func undeclaredKeys(of node: RecipeNode, contract: StepContract?) -> [String] {
        guard let contract else { return node.parameters.keys }
        return node.parameters.keys.filter { contract.parameter($0) == nil }
    }

    /// "DelayMs" → "Delay (ms)", "ShadowOffsetX" → "Shadow Offset X", "ClipboardFormatHTMLDataUrl" → "Clipboard Format
    /// HTML Data URL".
    public static func label(for name: String) -> String {
        var words: [String] = []
        var current = ""
        let characters = Array(name)
        for (index, character) in characters.enumerated() {
            let next = index + 1 < characters.count ? characters[index + 1] : nil
            let previous = index > 0 ? characters[index - 1] : nil
            let startsWord = character.isUppercase && !current.isEmpty
                && (previous?.isLowercase == true || previous?.isNumber == true || next?.isLowercase == true)
            if startsWord || (character.isNumber && previous?.isLetter == true && !current.isEmpty) {
                words.append(current)
                current = ""
            }
            current.append(character)
        }
        if !current.isEmpty { words.append(current) }
        let known: [String: String] = ["Ms": "(ms)", "Url": "URL", "Ocr": "OCR", "Jpeg": "JPEG", "Id": "ID", "Ids": "IDs",
                                       "Html": "HTML", "Dib": "DIB", "Png": "PNG", "Cli": "CLI", "Svg": "SVG", "Qr": "QR"]
        return words.map { known[$0] ?? $0 }.joined(separator: " ")
    }

    // MARK: Values

    /// Sets a parameter (case-insensitive key, keeps an existing spelling); nil removes it ("use the default").
    public static func set(_ value: JSONValue?, for name: String, in parameters: inout JSONObject) {
        parameters[name] = value
    }

    /// A `${…}` expression.
    public static func isExpression(_ value: JSONValue?) -> Bool {
        value?.stringValue?.contains("${") == true
    }

    /// The text a number field shows and the value it writes back: numbers stay numbers, an expression stays text.
    public static func numberValue(_ text: String, decimal: Bool) -> JSONValue? {
        let trimmed = text.trimmingCharacters(in: .whitespaces)
        if trimmed.isEmpty { return nil }
        if trimmed.contains("${") { return .string(trimmed) }
        if decimal, let number = Double(trimmed) { return .number(number) }
        if !decimal, let number = Int(trimmed) { return .number(Double(number)) }
        return .string(trimmed)
    }
}
