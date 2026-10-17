// Greenshot for Mac (Community) - an unofficial macOS port of Greenshot
// Copyright (C) 2026 Greenshot for Mac (Community) contributors
// Based on Greenshot, Copyright (C) 2007-2026 Thomas Braun, Jens Klingen, Robin Krom
// SPDX-License-Identifier: GPL-3.0-or-later

import Foundation

/// The console text of greenshot-cli for LIST_RECIPES and DESCRIBE_RECIPE, from the same JSON that JSON clients get
/// (upstream `Ipc/Cli/CliTextRenderer.cs`).
public enum IPCRecipeText {
    /// `--list-recipes`: the recipes with an active Commandline trigger.
    public static func recipeList(_ recipes: [JSONValue]) -> String {
        var text = "Available recipes with CommandlineTrigger:\n\n"
        for recipe in recipes {
            let id = string(recipe, "id") ?? ""
            let command = string(recipe, "command") ?? ""
            let name = string(recipe, "name") ?? ""
            let description = string(recipe, "description") ?? ""
            text += "  " + pad(command.isEmpty ? id : command, 20) + " " + (description.isEmpty ? name : description) + " (ID: \(id))\n"
            if let stdout = string(recipe, "stdout"), !stdout.isEmpty {
                text += "      Stdout  : \(stdout)\n"
            }
            appendArguments(&text, value(recipe, "arguments"), indent: "      ")
            text += "\n"
        }
        if recipes.isEmpty {
            text += "  (No recipes currently configured with active CommandlineTrigger)\n\n"
        }
        return text
    }

    /// `--info`: the recipe, its command line triggers and its contract.
    public static func recipeDescription(_ recipe: JSONValue) -> String {
        let id = string(recipe, "id") ?? ""
        let name = string(recipe, "name") ?? ""
        let description = string(recipe, "description") ?? ""
        let category = string(recipe, "category") ?? ""
        var text = "Recipe: \(name.isEmpty ? id : name) (ID: \(id), Category: \(category.isEmpty ? "General" : category))\n"
        text += "Description: \(description.isEmpty ? "(None)" : description)\n\n"
        for trigger in value(recipe, "triggers")?.arrayValue ?? [] {
            guard (string(trigger, "type") ?? "").caseInsensitiveCompare(WellKnownTriggerType.commandline) == .orderedSame else { continue }
            let command = string(trigger, "command") ?? ""
            text += "Command: \(command.isEmpty ? id : command)\n"
            appendArguments(&text, value(trigger, "arguments"), indent: "  ")
            text += "\n"
        }
        guard let contract = value(recipe, "contract"), contract.objectValue != nil else { return text }
        if let lifecycle = value(contract, "lifecycle"), lifecycle.objectValue != nil {
            text += "Payload Lifecycle:\n"
            text += "  Acquires Image: \(yesNo(bool(lifecycle, "acquires_image")))\n"
            text += "  Mutates Pixels: \(yesNo(bool(lifecycle, "mutates_pixels")))\n"
            text += "  Extracts Text : \(yesNo(bool(lifecycle, "extracts_text")))\n\n"
        }
        appendVariables(&text, value(contract, "inputs"), title: "Inputs (Parameters & Variables)", inputs: true)
        appendVariables(&text, value(contract, "outputs"), title: "Outputs", inputs: false)
        if let steps = value(contract, "steps")?.arrayValue {
            text += "Pipeline Steps:\n"
            for (offset, step) in steps.enumerated() {
                let stepType = string(step, "step_type") ?? ""
                let displayName = string(step, "display_name") ?? ""
                var marks = bool(step, "requires_image") ? " (requires image)" : ""
                if value(step, "reachable") != nil, !bool(step, "reachable") { marks += " (never executed)" }
                let number = String(offset + 1)
                let numberColumn = String(repeating: " ", count: max(0, 2 - number.count)) + number
                text += "  \(numberColumn). " + pad(stepType, 20) + " [\(displayName.isEmpty ? stepType : displayName)]\(marks)\n"
            }
            if steps.isEmpty { text += "  (None)\n" }
            text += "\n"
        }
        let warnings = (value(contract, "warnings")?.arrayValue ?? []).compactMap(\.stringValue)
        if !warnings.isEmpty {
            text += "Validation Warnings:\n"
            for warning in warnings { text += "  [!] \(warning)\n" }
            text += "\n"
        }
        return text
    }

    /// The declared arguments; snake_case (LIST_RECIPES) or camelCase (a trigger's own) names.
    private static func appendArguments(_ text: inout String, _ arguments: JSONValue?, indent: String) {
        guard let items = arguments?.arrayValue, !items.isEmpty else { return }
        text += indent + "Arguments:\n"
        for argument in items {
            let name = string(argument, "name") ?? ""
            let variable = string(argument, "variable") ?? ""
            var description = string(argument, "description") ?? ""
            let defaultValue = string(argument, "default_value") ?? string(argument, "defaultValue") ?? ""
            let type = string(argument, "type") ?? ""
            let allowed = (value(argument, "allowed_values") ?? value(argument, "allowedValues"))?.arrayValue?.compactMap(\.stringValue) ?? []
            if !allowed.isEmpty {
                description = "\(description) [\(allowed.joined(separator: "|"))]".trimmingCharacters(in: .whitespaces)
            }
            if !type.isEmpty, type.caseInsensitiveCompare("String") != .orderedSame {
                description = "\(description) <\(type)>".trimmingCharacters(in: .whitespaces)
            }
            if bool(argument, "required") {
                text += "\(indent)  * --" + pad(name, 14) + " (required)          : \(description)"
            } else if !defaultValue.isEmpty {
                text += "\(indent)    --" + pad(name, 14) + " (default: " + pad(defaultValue, 8) + ") : \(description)"
            } else {
                text += "\(indent)    --" + pad(name, 14) + " (optional)          : \(description)"
            }
            if !variable.isEmpty, variable.caseInsensitiveCompare(name) != .orderedSame {
                text += " -> ${\(variable)}"
            }
            text += "\n"
        }
    }

    private static func appendVariables(_ text: inout String, _ items: JSONValue?, title: String, inputs: Bool) {
        guard let list = items?.arrayValue else { return }
        text += title + ":\n"
        for item in list {
            let name = string(item, "name") ?? ""
            let typeName = string(item, "type") ?? ""
            let type = typeName.isEmpty ? "String" : typeName
            let description = string(item, "description") ?? ""
            if !inputs {
                let note = bool(item, "conditional") ? ", not always set" : ""
                text += "    " + pad(name, 20) + " (\(type)\(note)) : \(description)\n"
            } else if bool(item, "required") {
                text += "  * " + pad(name, 20) + " (\(type), required) : \(description)\n"
            } else if let defaultValue = string(item, "default_value"), !defaultValue.isEmpty {
                text += "    " + pad(name, 20) + " (\(type), default: \(defaultValue)) : \(description)\n"
            } else {
                text += "    " + pad(name, 20) + " (\(type), optional) : \(description)\n"
            }
        }
        if list.isEmpty { text += "  (None)\n" }
        text += "\n"
    }

    /// .NET's `{0,-width}`: left aligned, padded to `width`, never cut.
    static func pad(_ text: String, _ width: Int) -> String {
        text.count >= width ? text : text + String(repeating: " ", count: width - text.count)
    }

    private static func value(_ object: JSONValue, _ key: String) -> JSONValue? {
        guard let value = object.objectValue?[key], !value.isNull else { return nil }
        return value
    }

    private static func string(_ object: JSONValue, _ key: String) -> String? {
        value(object, key)?.asString
    }

    private static func bool(_ object: JSONValue, _ key: String) -> Bool {
        value(object, key)?.boolValue ?? false
    }

    private static func yesNo(_ value: Bool) -> String { value ? "Yes" : "No" }
}
