// Greenshot for Mac (Community) - an unofficial macOS port of Greenshot
// Copyright (C) 2026 Greenshot for Mac (Community) contributors
// Based on Greenshot, Copyright (C) 2007-2026 Thomas Braun, Jens Klingen, Robin Krom
// SPDX-License-Identifier: GPL-3.0-or-later

import CoreGraphics
import Foundation

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
    public static func decode(_ data: Data) throws -> [CaptureRecipe] {
        guard let text = text(of: data) else { throw RecipeFormatError("The file is not UTF-8 or UTF-16 text.") }
        return try decode(text: text)
    }

    public static func decode(text: String) throws -> [CaptureRecipe] {
        guard !text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
            throw RecipeFormatError("The recipe file is empty.")
        }
        let json: JSONValue
        do {
            json = try JSONValue.parse(text)
        } catch let error as JSONParseError {
            throw RecipeFormatError("The recipe file is not valid JSON: \(error.errorDescription ?? error.message)")
        }
        switch json {
        case .object:
            return [try recipe(from: json)]
        case .array(let items):
            return try items.enumerated().map { index, item in
                do {
                    return try recipe(from: item)
                } catch let error as RecipeFormatError {
                    throw RecipeFormatError("Recipe at index \(index): \(error.message)")
                }
            }
        default:
            throw RecipeFormatError("A recipe file holds one recipe (a JSON object) or a list of recipes.")
        }
    }

    public static func recipe(from json: JSONValue) throws -> CaptureRecipe {
        guard let object = json.objectValue else { throw RecipeFormatError("A recipe must be a JSON object.") }
        var reader = MemberReader(object)
        let kindText = reader.take("kind")?.asString?.trimmingCharacters(in: .whitespaces).lowercased() ?? ""
        let kind: RecipeKind
        if kindText.isEmpty {
            kind = .recipe
        } else if let known = RecipeKind(rawValue: kindText) {
            kind = known
        } else {
            throw RecipeFormatError("Unknown kind '\(kindText)', use \"recipe\" or \"extension\".")
        }
        var recipe = CaptureRecipe(id: reader.take("id")?.asString ?? "", name: reader.take("name")?.asString ?? "")
        recipe.kind = kind
        recipe.schema = reader.take("$schema")?.asString
        if let version = reader.take("version"), !version.isNull { recipe.version = version.asString ?? "" }
        recipe.description = reader.take("description")?.asString
        recipe.requires = try reader.takeArray("requires").enumerated().map { try requirement(from: $1, index: $0) }
        recipe.triggers = try reader.takeArray("triggers").enumerated().map { try trigger(from: $1, index: $0) }
        recipe.nodes = try reader.takeArray("nodes").enumerated().map { try node(from: $1, index: $0) }
        if let flowValue = reader.take("flow"), !flowValue.isNull { recipe.flow = try flow(from: flowValue) }
        if let optionsValue = reader.take("options"), !optionsValue.isNull {
            guard let items = optionsValue.arrayValue else { throw RecipeFormatError("'options' must be a list.") }
            recipe.options = try items.enumerated().map { try option(from: $1, index: $0) }
        }
        if let concurrency = reader.take("concurrency"), !concurrency.isNull {
            let text = concurrency.asString ?? ""
            guard let value = FlowConcurrency.allCases.first(where: { recipeEquals($0.rawValue, text) }) else {
                throw RecipeFormatError("Unknown concurrency '\(text)', use Parallel, Exclusive or ReplacePrevious.")
            }
            recipe.concurrency = value
        }
        recipe.showInContextMenu = reader.take("showInContextMenu")?.asBool ?? true
        if let extends = reader.take("extends")?.objectValue {
            var target = MemberReader(extends)
            var value = ExtensionTarget()
            value.recipes = target.take("recipes")?.asStrings ?? []
            value.slot = target.take("slot")?.asString
            value.order = target.take("order")?.asInt ?? 0
            recipe.extends = value
        }
        recipe.when = reader.take("when")?.asString
        recipe.extra = reader.rest
        return recipe
    }

    public static func json(of recipe: CaptureRecipe) -> JSONValue {
        var object = JSONObject()
        object["kind"] = .string(recipe.kind.rawValue)
        if let schema = recipe.schema { object["$schema"] = .string(schema) }
        object["version"] = .string(recipe.version)
        object["id"] = .string(recipe.id)
        object["name"] = .string(recipe.name)
        if let description = recipe.description { object["description"] = .string(description) }
        if !recipe.requires.isEmpty { object["requires"] = .array(recipe.requires.map(json(of:))) }
        if recipe.kind == .recipe || !recipe.triggers.isEmpty { object["triggers"] = .array(recipe.triggers.map(json(of:))) }
        object["nodes"] = .array(recipe.nodes.map(json(of:)))
        object["flow"] = json(of: recipe.flow)
        if let options = recipe.options { object["options"] = .array(options.map(json(of:))) }
        if let concurrency = recipe.concurrency { object["concurrency"] = .string(concurrency.rawValue) }
        if !recipe.showInContextMenu { object["showInContextMenu"] = .bool(false) }
        if let extends = recipe.extends {
            var target: JSONObject = ["recipes": .array(extends.recipes.map(JSONValue.string))]
            if let slot = extends.slot { target["slot"] = .string(slot) }
            target["order"] = .number(Double(extends.order))
            object["extends"] = .object(target)
        }
        if let when = recipe.when { object["when"] = .string(when) }
        appendExtra(recipe.extra, to: &object)
        return .object(object)
    }

    /// Upstream's layout: "kind" first, camelCase names, null members left out, two-space indent.
    public static func encode(_ recipe: CaptureRecipe, indented: Bool = true) -> String {
        json(of: recipe).serialized(indented: indented)
    }

    public static func encode(_ recipes: [CaptureRecipe], indented: Bool = true) -> String {
        JSONValue.array(recipes.map(json(of:))).serialized(indented: indented)
    }

    /// The text of file bytes, UTF-8 with or without byte order mark (upstream `RecipeManager.DecodeRecipeFile`).
    public static func text(of data: Data) -> String? {
        let bytes = [UInt8](data)
        if bytes.starts(with: [0xEF, 0xBB, 0xBF]) { return String(decoding: bytes.dropFirst(3), as: UTF8.self) }
        if bytes.starts(with: [0xFF, 0xFE]) { return String(data: Data(bytes.dropFirst(2)), encoding: .utf16LittleEndian) }
        if bytes.starts(with: [0xFE, 0xFF]) { return String(data: Data(bytes.dropFirst(2)), encoding: .utf16BigEndian) }
        return String(decoding: bytes, as: UTF8.self)
    }

    // MARK: - Parts

    private static func requirement(from value: JSONValue, index: Int) throws -> RecipeRequirement {
        guard let object = value.objectValue else { throw RecipeFormatError("Requirement at index \(index) must be an object.") }
        var reader = MemberReader(object)
        var requirement = RecipeRequirement(id: reader.take("id")?.asString ?? "")
        requirement.name = reader.take("name")?.asString
        requirement.minVersion = reader.take("minVersion")?.asString
        requirement.url = reader.take("url")?.asString
        requirement.extra = reader.rest
        return requirement
    }

    private static func json(of requirement: RecipeRequirement) -> JSONValue {
        var object: JSONObject = ["id": .string(requirement.id)]
        if let name = requirement.name { object["name"] = .string(name) }
        if let minVersion = requirement.minVersion { object["minVersion"] = .string(minVersion) }
        if let url = requirement.url { object["url"] = .string(url) }
        appendExtra(requirement.extra, to: &object)
        return .object(object)
    }

    private static func trigger(from value: JSONValue, index: Int) throws -> TriggerConfig {
        guard let object = value.objectValue else { throw RecipeFormatError("Trigger at index \(index) must be an object.") }
        var reader = MemberReader(object)
        var trigger = TriggerConfig(triggerType: reader.take("triggerType")?.asString ?? "", name: reader.take("name")?.asString)
        trigger.enabled = reader.take("enabled")?.asBool ?? true
        trigger.parameters = try parameters(reader.take("parameters"), what: "Trigger at index \(index)")
        trigger.extra = reader.rest
        return trigger
    }

    private static func json(of trigger: TriggerConfig) -> JSONValue {
        var object: JSONObject = ["triggerType": .string(trigger.triggerType)]
        if let name = trigger.name { object["name"] = .string(name) }
        object["enabled"] = .bool(trigger.enabled)
        object["parameters"] = .object(trigger.parameters)
        appendExtra(trigger.extra, to: &object)
        return .object(object)
    }

    private static func node(from value: JSONValue, index: Int) throws -> RecipeNode {
        guard let object = value.objectValue else { throw RecipeFormatError("Node at index \(index) must be an object.") }
        var reader = MemberReader(object)
        var node = RecipeNode(id: reader.take("id")?.asString ?? "", stepType: reader.take("stepType")?.asString ?? "",
                              name: reader.take("name")?.asString)
        node.enabled = enabled(from: reader.take("enabled"))
        node.onErrorNodeId = reader.take("onErrorNodeId")?.asString
        node.onErrorRecipeId = reader.take("onErrorRecipeId")?.asString
        node.parameters = try parameters(reader.take("parameters"), what: "Node '\(node.id)'")
        node.extra = reader.rest
        return node
    }

    /// Upstream `RecipeNodeConfig.EnabledJson`: a bool, "true"/"false", an expression, anything else true.
    private static func enabled(from value: JSONValue?) -> NodeEnabled {
        switch value {
        case .bool(let flag)?:
            return .value(flag)
        case .string(let text)?:
            let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
            switch trimmed.lowercased() {
            case "true": return .value(true)
            case "false": return .value(false)
            case "": return .value(true)
            default: return .expression(trimmed)
            }
        default:
            return .value(true)
        }
    }

    private static func json(of node: RecipeNode) -> JSONValue {
        var object: JSONObject = ["id": .string(node.id), "stepType": .string(node.stepType)]
        if let name = node.name { object["name"] = .string(name) }
        switch node.enabled {
        case .value(let flag): object["enabled"] = .bool(flag)
        case .expression(let expression): object["enabled"] = .string(expression)
        }
        if let target = node.onErrorNodeId { object["onErrorNodeId"] = .string(target) }
        if let target = node.onErrorRecipeId { object["onErrorRecipeId"] = .string(target) }
        object["parameters"] = .object(node.parameters)
        appendExtra(node.extra, to: &object)
        return .object(object)
    }

    private static func parameters(_ value: JSONValue?, what: String) throws -> JSONObject {
        guard let value, !value.isNull else { return [:] }
        guard let object = value.objectValue else { throw RecipeFormatError("\(what): 'parameters' must be an object.") }
        return object
    }

    private static func flow(from value: JSONValue) throws -> RecipeFlow {
        guard let object = value.objectValue else { throw RecipeFormatError("'flow' must be an object.") }
        var reader = MemberReader(object)
        var flow = RecipeFlow()
        flow.startNodes = reader.take("startNodes")?.asStrings ?? []
        if let transitions = reader.take("transitions"), !transitions.isNull {
            guard let map = transitions.objectValue else { throw RecipeFormatError("'flow.transitions' must be an object.") }
            flow.transitions = map.members.map { member in
                RecipeTransition(from: member.key, to: (member.value.arrayValue?.compactMap(\.asString) ?? member.value.asString.map { [$0] } ?? [])
                    .filter { !$0.trimmingCharacters(in: .whitespaces).isEmpty })
            }
        }
        flow.conditionalTransitions = try reader.takeArray("conditionalTransitions").enumerated().map { index, item in
            guard let object = item.objectValue else { throw RecipeFormatError("Conditional transition at index \(index) must be an object.") }
            return ConditionalTransition(from: object.string("from") ?? "", branch: object.string("branch") ?? "", to: object.string("to") ?? "")
        }
        flow.errorTransitions = try reader.takeArray("errorTransitions").enumerated().map { index, item in
            guard let object = item.objectValue else { throw RecipeFormatError("Error transition at index \(index) must be an object.") }
            return ErrorTransition(from: object.string("from"), to: object.string("to"), targetRecipeId: object.string("targetRecipeId"),
                                   errorType: object.string("errorType") ?? "*")
        }
        flow.extra = reader.rest
        return flow
    }

    private static func json(of flow: RecipeFlow) -> JSONValue {
        var object: JSONObject = ["startNodes": .array(flow.startNodes.map(JSONValue.string))]
        object["transitions"] = .object(JSONObject(flow.transitions.map { JSONMember($0.from, .array($0.to.map(JSONValue.string))) }))
        if !flow.conditionalTransitions.isEmpty {
            object["conditionalTransitions"] = .array(flow.conditionalTransitions.map {
                .object(["from": .string($0.from), "branch": .string($0.branch), "to": .string($0.to)])
            })
        }
        if !flow.errorTransitions.isEmpty {
            object["errorTransitions"] = .array(flow.errorTransitions.map { transition in
                var item = JSONObject()
                if let from = transition.from { item["from"] = .string(from) }
                if let to = transition.to { item["to"] = .string(to) }
                if let recipe = transition.targetRecipeId { item["targetRecipeId"] = .string(recipe) }
                item["errorType"] = .string(transition.errorType)
                return .object(item)
            })
        }
        appendExtra(flow.extra, to: &object)
        return .object(object)
    }

    private static func option(from value: JSONValue, index: Int) throws -> RecipeOption {
        guard let object = value.objectValue else { throw RecipeFormatError("Option at index \(index) must be an object.") }
        var reader = MemberReader(object)
        let key = reader.take("key")?.asString ?? ""
        var type = ContractDataType.boolean
        if let typeValue = reader.take("type"), !typeValue.isNull {
            let text = typeValue.asString ?? ""
            guard let known = ContractDataType(caseInsensitive: text) else {
                throw RecipeFormatError("Option '\(key)' has the unknown type '\(text)'.")
            }
            type = known
        }
        var option = RecipeOption(key: key, type: type)
        if let defaultValue = reader.take("default"), !defaultValue.isNull { option.defaultValue = defaultValue }
        option.label = reader.take("label")?.asString
        option.description = reader.take("description")?.asString
        option.min = reader.take("min")?.asDouble
        option.max = reader.take("max")?.asDouble
        if let choices = reader.take("choices")?.arrayValue {
            option.choices = choices.compactMap { item in
                guard let choice = item.objectValue else { return item.asString.map { RecipeOptionChoice(value: $0) } }
                return RecipeOptionChoice(value: choice.string("value") ?? "", label: choice.string("label"))
            }
        }
        option.enabledWhen = reader.take("enabledWhen")?.asString
        option.quickSettings = reader.take("quickSettings")?.asBool ?? false
        option.format = reader.take("format")?.asString
        option.extra = reader.rest
        return option
    }

    private static func json(of option: RecipeOption) -> JSONValue {
        var object: JSONObject = ["key": .string(option.key), "type": .string(option.type.rawValue)]
        if let defaultValue = option.defaultValue { object["default"] = defaultValue }
        if let label = option.label { object["label"] = .string(label) }
        if let description = option.description { object["description"] = .string(description) }
        if let min = option.min { object["min"] = .number(min) }
        if let max = option.max { object["max"] = .number(max) }
        if let choices = option.choices {
            object["choices"] = .array(choices.map { choice in
                var item: JSONObject = ["value": .string(choice.value)]
                if let label = choice.label { item["label"] = .string(label) }
                return .object(item)
            })
        }
        if let enabledWhen = option.enabledWhen { object["enabledWhen"] = .string(enabledWhen) }
        if option.quickSettings { object["quickSettings"] = .bool(true) }
        if let format = option.format { object["format"] = .string(format) }
        appendExtra(option.extra, to: &object)
        return .object(object)
    }

    private static func appendExtra(_ extra: JSONObject, to object: inout JSONObject) {
        for member in extra where !object.contains(key: member.key) {
            object[member.key] = member.value
        }
    }
}

/// Takes the known members of an object (case-insensitive); what is left are the unknown ones.
private struct MemberReader {
    private var object: JSONObject

    init(_ object: JSONObject) {
        self.object = object
    }

    mutating func take(_ key: String) -> JSONValue? {
        object.removeValue(forKey: key)
    }

    mutating func takeArray(_ key: String) throws -> [JSONValue] {
        guard let value = take(key), !value.isNull else { return [] }
        guard let items = value.arrayValue else { throw RecipeFormatError("'\(key)' must be a list.") }
        return items
    }

    var rest: JSONObject { object }
}
