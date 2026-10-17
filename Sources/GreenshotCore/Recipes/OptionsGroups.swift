// Greenshot for Mac (Community) - an unofficial macOS port of Greenshot
// Copyright (C) 2026 Greenshot for Mac (Community) contributors
// Based on Greenshot, Copyright (C) 2007-2026 Thomas Braun, Jens Klingen, Robin Krom
// SPDX-License-Identifier: GPL-3.0-or-later

import Foundation

/// One option row of Settings › Recipes (upstream `RecipeOptionViewModel`).
public struct RecipeOptionItem: Identifiable, Equatable, Sendable {
    public var option: RecipeOption
    /// The stored value, or the default.
    public var value: JSONValue
    /// False while the Boolean option its `enabledWhen` names is off (upstream: greyed).
    public var isEditable: Bool

    public init(option: RecipeOption, value: JSONValue, isEditable: Bool = true) {
        self.option = option
        self.value = value
        self.isEditable = isEditable
    }

    public var id: String { option.key }
    /// The label, else the key (upstream `DisplayLabel`).
    public var label: String {
        let label = option.label?.trimmingCharacters(in: .whitespaces) ?? ""
        return label.isEmpty ? option.key : label
    }
    /// "1 – 50" next to a number box (upstream `RangeText`), nil without a range.
    public var rangeText: String? {
        guard option.type == .integer || option.type == .decimal, option.min != nil || option.max != nil else { return nil }
        return "\(option.min.map(JSONValue.format) ?? "…") – \(option.max.map(JSONValue.format) ?? "…")"
    }
    /// The value as the text field shows it ("2", "0.6", "#FF0000").
    public var text: String { value.asString ?? "" }
}

/// The options of one automatic step or recipe in Settings › Recipes (upstream `RecipeOptionGroupViewModel`): an
/// automatic step with an on/off option has it in front of its name, its other options only show while it is on.
public struct RecipeOptionGroup: Identifiable, Equatable, Sendable {
    /// The automatic step's or recipe's id.
    public var id: String
    public var name: String
    public var description: String?
    public var isExtension: Bool
    /// The on/off option of an automatic step; nil for a recipe and an automatic step which is always on.
    public var switchOption: RecipeOption?
    /// Switched on (always for a group without switch): the options are shown.
    public var isOn: Bool
    /// All options but the switch.
    public var items: [RecipeOptionItem]
    /// Automatic steps: where it is used; nil when no recipe has a slot for it.
    public var scope: RecipeExtensionScope?

    public init(id: String, name: String, description: String? = nil, isExtension: Bool, switchOption: RecipeOption? = nil,
                isOn: Bool = true, items: [RecipeOptionItem] = [], scope: RecipeExtensionScope? = nil) {
        self.id = id
        self.name = name
        self.description = description
        self.isExtension = isExtension
        self.switchOption = switchOption
        self.isOn = isOn
        self.items = items
        self.scope = scope
    }
}

/// An option in Quick Settings › "Automatic steps" (upstream `TrayMenu.AddRecipeQuickSettings`).
public struct RecipeQuickSetting: Equatable, Sendable {
    public var ownerId: String
    public var option: RecipeOption
    /// The option label, with the owner's name in front when two options have the same label.
    public var label: String
    public var value: JSONValue

    public init(ownerId: String, option: RecipeOption, label: String, value: JSONValue) {
        self.ownerId = ownerId
        self.option = option
        self.label = label
        self.value = value
    }

    /// Upstream `MaxRecipeQuickSettings`.
    public static let maximum = 6
}

extension RecipeLibrary {
    /// Settings › Recipes: the automatic steps (by order, then id), then the recipes with options (by name).
    /// `destinations`: the choices of the scope dialog (`RecipeExtensionScope.destinationChoices`).
    public func optionGroups(destinations: [(designation: String, name: String)]) -> [RecipeOptionGroup] {
        let values = optionValues
        var groups: [RecipeOptionGroup] = []
        for loaded in extensions {
            let ext = loaded.recipe
            let switchOption = ext.extensionEnabledOption
            var group = RecipeOptionGroup(id: ext.id, name: Self.displayName(ext), description: ext.description, isExtension: true,
                                          switchOption: switchOption, items: Self.items(of: ext, values: values, without: switchOption),
                                          scope: extensionScope(id: ext.id, destinations: destinations))
            group.isOn = switchOption.map { values.value(of: $0, recipeId: ext.id) == .bool(true) } ?? true
            groups.append(group)
        }
        let withOptions = recipes.map(\.recipe).filter { !($0.options ?? []).isEmpty }
            .sorted { Self.displayName($0).localizedCaseInsensitiveCompare(Self.displayName($1)) == .orderedAscending }
        for recipe in withOptions {
            groups.append(RecipeOptionGroup(id: recipe.id, name: Self.displayName(recipe), description: recipe.description,
                                            isExtension: false, items: Self.items(of: recipe, values: values, without: nil)))
        }
        return groups
    }

    /// Quick Settings › "Automatic steps": Boolean and Enum options marked `quickSettings`, automatic steps first (by order,
    /// then id), then recipes (by name), at most `RecipeQuickSetting.maximum` (upstream `AddRecipeQuickSettings`).
    public func quickSettings() -> [RecipeQuickSetting] {
        let values = optionValues
        let owners = extensions.map(\.recipe) + recipes.map(\.recipe).filter { !($0.options ?? []).isEmpty }
            .sorted { Self.displayName($0).localizedCaseInsensitiveCompare(Self.displayName($1)) == .orderedAscending }
        var found: [(owner: CaptureRecipe, option: RecipeOption)] = []
        for owner in owners {
            for option in owner.options ?? [] where option.quickSettings {
                if option.type == .boolean || (option.type == .enumeration && !(option.choices ?? []).isEmpty) {
                    found.append((owner, option))
                }
            }
        }
        func label(_ option: RecipeOption) -> String { RecipeOptionItem(option: option, value: .null).label }
        var counts: [String: Int] = [:]
        for entry in found { counts[label(entry.option).lowercased(), default: 0] += 1 }
        if found.count > RecipeQuickSetting.maximum {
            log.debug("\(found.count) recipe options are marked for the quick settings, showing \(RecipeQuickSetting.maximum).")
        }
        return found.prefix(RecipeQuickSetting.maximum).map { entry in
            let text = label(entry.option)
            let shown = (counts[text.lowercased()] ?? 0) > 1 ? "\(Self.displayName(entry.owner)): \(text)" : text
            return RecipeQuickSetting(ownerId: entry.owner.id, option: entry.option, label: shown,
                                      value: values.value(of: entry.option, recipeId: entry.owner.id))
        }
    }

    private static func items(of owner: CaptureRecipe, values: RecipeOptionValues, without switchOption: RecipeOption?) -> [RecipeOptionItem] {
        let options = owner.options ?? []
        func value(_ option: RecipeOption) -> JSONValue { values.value(of: option, recipeId: owner.id) }
        return options.filter { $0.key != switchOption?.key }.map { option in
            var editable = true
            if let key = option.enabledWhen?.trimmingCharacters(in: .whitespaces), !key.isEmpty,
               let gate = options.first(where: { recipeEquals($0.key, key) && $0.type == .boolean }) {
                editable = value(gate) == .bool(true)
            }
            return RecipeOptionItem(option: option, value: value(option), isEditable: editable)
        }
    }
}

/// Colour options as text (`#RRGGBB`, `#AARRGGBB`) and back (upstream `Settings/RecipeOptionColors.cs`).
public enum RecipeOptionColor {
    /// Nil when the text is no colour.
    public static func parse(_ text: String) -> RGBAColor? {
        RecipeColor.parse(text)
    }

    /// `#RRGGBB` when opaque, else `#AARRGGBB`, upper case.
    public static func format(_ color: RGBAColor) -> String {
        func byte(_ value: Double) -> Int { Int((min(max(value, 0), 1) * 255).rounded()) }
        let rgb = String(format: "%02X%02X%02X", byte(color.red), byte(color.green), byte(color.blue))
        let alpha = byte(color.alpha)
        return alpha == 255 ? "#" + rgb : String(format: "#%02X", alpha) + rgb
    }
}

private let log = Log("Recipes")
