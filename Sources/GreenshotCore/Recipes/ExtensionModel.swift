// Greenshot for Mac (Community) - an unofficial macOS port of Greenshot
// Copyright (C) 2026 Greenshot for Mac (Community) contributors
// Based on Greenshot, Copyright (C) 2007-2026 Thomas Braun, Jens Klingen, Robin Krom
// SPDX-License-Identifier: GPL-3.0-or-later

import Foundation

/// The names an automatic step (recipe extension, `"kind": "extension"`) works with (upstream `RecipeExtension`,
/// Greenshot.Base/Recipes/RecipeExtension.cs). On the Mac an automatic step is a `CaptureRecipe` of kind `.extension`.
public enum RecipeExtensionNames {
    /// A transition target in an extension flow: where the extension ends and the recipe goes on.
    public static let outNode = "Out"
    /// The key of the Boolean option which switches the extension on and off; an extension without one is always on.
    public static let enabledOptionKey = "enabled"
    /// For `extends.recipes`: every recipe with a slot (AI tool recipes only by id).
    public static let targetAll = "*"
    /// For `extends.recipes`: every recipe with a Source step and a destination (AI tool recipes only by id).
    public static let targetCaptures = "*capture"
    /// "Apply to" values.
    public static let applyToAll = "all"
    public static let applyToOnly = "only"

    /// "Apply to": all the recipes the extension targets, or only the ones the user picked.
    public static let applyToOption: RecipeOption = {
        var option = RecipeOption(key: "applyTo", type: .enumeration, defaultValue: .string(applyToAll))
        option.choices = [RecipeOptionChoice(value: applyToAll), RecipeOptionChoice(value: applyToOnly)]
        return option
    }()
    /// The recipe ids for "Apply to: only these recipes", a `storedList`.
    public static let onlyRecipesOption = RecipeOption(key: "onlyRecipes", type: .string, defaultValue: .string(""))
    /// The recipe ids the extension doesn't change, a `storedList`.
    public static let exceptRecipesOption = RecipeOption(key: "exceptRecipes", type: .string, defaultValue: .string(""))
    /// BeforeDestination only: the destination designations it runs for, empty for all; a `storedList`.
    public static let onlyDestinationsOption = RecipeOption(key: "onlyDestinations", type: .string, defaultValue: .string(""))
    /// The settings every extension has, stored like its options (they can't be declared as options).
    public static let scopeOptions = [applyToOption, onlyRecipesOption, exceptRecipesOption, onlyDestinationsOption]

    /// Why an AI tool may not propose this automatic step, nil when it may: it needs a Boolean `enabled` option, so it can
    /// start switched off until the user switches it on (an automatic step without one is always on once approved).
    /// The library's `proposeExtension` refuses it; MCP's validate_recipe can tell the AI tool before it proposes.
    public static func aiProposalProblem(_ ext: CaptureRecipe) -> String? {
        guard ext.kind == .extension, ext.extensionEnabledOption == nil else { return nil }
        return "An automatic step an AI tool proposes needs a Boolean option \"\(enabledOptionKey)\" (for example \"default\": false): "
            + "it starts switched off, and the user switches it on in Settings › Recipes."
    }

    /// Splits a comma or semicolon separated list of ids (upstream `RecipeSlots.SplitList`).
    public static func splitList(_ text: String?) -> [String] {
        (text ?? "").split(whereSeparator: { $0 == "," || $0 == ";" })
            .map { $0.trimmingCharacters(in: .whitespaces) }
            .filter { !$0.isEmpty }
    }

    /// A list of ids or designations as a scope option stores it: comma separated (upstream), or a JSON array of strings
    /// when the separated form wouldn't read back the same (an external command's name with "," or ";", or with a blank
    /// at the start or end).
    public static func storedList(_ items: [String]) -> String {
        let plain = items.joined(separator: ",")
        guard splitList(plain) != items else { return plain }
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.withoutEscapingSlashes]
        guard let data = try? encoder.encode(items), let text = String(data: data, encoding: .utf8) else { return plain }
        return text
    }

    /// Reads a `storedList`: a JSON array of strings, else a separated list (`splitList`; values stored before).
    public static func items(ofStoredList text: String?) -> [String] {
        let trimmed = (text ?? "").trimmingCharacters(in: .whitespaces)
        if trimmed.hasPrefix("["), let items = try? JSONDecoder().decode([String].self, from: Data(trimmed.utf8)) {
            return items.filter { !$0.trimmingCharacters(in: .whitespaces).isEmpty }
        }
        return splitList(text)
    }
}

extension CaptureRecipe {
    /// An automatic step's on/off option (a Boolean `enabled`), nil when it is always on (upstream `EnabledOption`).
    public var extensionEnabledOption: RecipeOption? {
        guard let option = option(RecipeExtensionNames.enabledOptionKey), option.type == .boolean else { return nil }
        return option
    }

    /// The slot of an automatic step, normalized; nil when unknown (upstream `SlotName`).
    public var extensionSlotName: String? { RecipeSlots.normalize(extends?.slot) }
}

/// What the user picked for an automatic step in Settings › Recipes: switched on, which recipes, which destinations
/// (upstream `RecipeExtensionSettings`). Ids are compared case-insensitively.
public struct RecipeExtensionSettings: Sendable, Equatable {
    public var enabled = true
    /// False for "only these recipes" (`onlyRecipes`).
    public var applyToAll = true
    public var onlyRecipes: [String] = []
    public var exceptRecipes: [String] = []
    /// BeforeDestination: the designations it runs for, empty for all.
    public var onlyDestinations: [String] = []

    public init(enabled: Bool = true, applyToAll: Bool = true, onlyRecipes: [String] = [], exceptRecipes: [String] = [],
                onlyDestinations: [String] = []) {
        self.enabled = enabled
        self.applyToAll = applyToAll
        self.onlyRecipes = onlyRecipes
        self.exceptRecipes = exceptRecipes
        self.onlyDestinations = onlyDestinations
    }

    /// Whether the user's choice lets the extension change the recipe.
    public func allowsRecipe(_ recipeId: String) -> Bool {
        guard enabled, !recipeId.isEmpty else { return false }
        if exceptRecipes.contains(where: { recipeEquals($0, recipeId) }) { return false }
        return applyToAll || onlyRecipes.contains { recipeEquals($0, recipeId) }
    }

    /// The settings as stored in `RecipeSettings.optionValues` as "<extension id>.<key>" (upstream `FromStore`).
    public static func stored(for ext: CaptureRecipe, in values: RecipeOptionValues) -> RecipeExtensionSettings {
        var settings = RecipeExtensionSettings()
        if let enabledOption = ext.extensionEnabledOption {
            settings.enabled = values.value(of: enabledOption, recipeId: ext.id) == .bool(true)
        }
        let applyTo = values.value(of: RecipeExtensionNames.applyToOption, recipeId: ext.id).asString ?? ""
        settings.applyToAll = !recipeEquals(applyTo, RecipeExtensionNames.applyToOnly)
        settings.onlyRecipes = list(RecipeExtensionNames.onlyRecipesOption, ext, values)
        settings.exceptRecipes = list(RecipeExtensionNames.exceptRecipesOption, ext, values)
        settings.onlyDestinations = list(RecipeExtensionNames.onlyDestinationsOption, ext, values)
        return settings
    }

    private static func list(_ option: RecipeOption, _ ext: CaptureRecipe, _ values: RecipeOptionValues) -> [String] {
        RecipeExtensionNames.items(ofStoredList: values.value(of: option, recipeId: ext.id).asString)
    }
}
