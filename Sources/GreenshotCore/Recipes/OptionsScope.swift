// Greenshot for Mac (Community) - an unofficial macOS port of Greenshot
// Copyright (C) 2026 Greenshot for Mac (Community) contributors
// Based on Greenshot, Copyright (C) 2007-2026 Thomas Braun, Jens Klingen, Robin Krom
// SPDX-License-Identifier: GPL-3.0-or-later

import Foundation

/// A recipe or a destination in "Where <automatic step> is used" (upstream `RecipeScopeViewModel`).
public struct RecipeScopeItem: Identifiable, Equatable, Sendable {
    /// The recipe id, or the destination designation ("FileNoDialog", "External Paint").
    public var id: String
    public var name: String
    public var isChecked: Bool

    public init(id: String, name: String, isChecked: Bool) {
        self.id = id
        self.name = name
        self.isChecked = isChecked
    }
}

/// Where an automatic step is used: the captures (recipes it can change) and, for one which runs per destination, the
/// destinations (upstream `RecipeOptionGroupViewModel.UseIn` / `OnlyDestinations`, `RecipeExtensionScopeWindow`).
public struct RecipeExtensionScope: Equatable, Sendable {
    public var captures: [RecipeScopeItem]
    /// Empty when the automatic step doesn't run per destination.
    public var destinations: [RecipeScopeItem]

    public init(captures: [RecipeScopeItem], destinations: [RecipeScopeItem]) {
        self.captures = captures
        self.destinations = destinations
    }

    /// "All captures → all destinations", "3 of 7 captures → EMail", "No captures" (upstream `ScopeSummary`).
    public var summary: String {
        let checked = captures.filter(\.isChecked).count
        let captureText: String
        if checked == captures.count {
            captureText = String(localized: "All captures")
        } else if checked == 0 {
            captureText = String(localized: "No captures")
        } else {
            captureText = String(localized: "\(checked) of \(captures.count) captures")
        }
        guard !destinations.isEmpty else { return captureText }
        let checkedDestinations = destinations.filter(\.isChecked)
        let destinationText = checkedDestinations.count == destinations.count
            ? String(localized: "all destinations") : checkedDestinations.map(\.name).joined(separator: ", ")
        return "\(captureText) → \(destinationText)"
    }

    /// At least one destination: without one the automatic step would never run (switch it off instead).
    public var isValid: Bool { destinations.isEmpty || destinations.contains(where: \.isChecked) }

    /// What is stored: the unchecked captures (new recipes get it too).
    public var exceptRecipes: [String] { captures.filter { !$0.isChecked }.map(\.id) }

    /// What is stored: the checked destinations, empty when all are (destinations added later get it too).
    public var onlyDestinations: [String] {
        destinations.allSatisfy(\.isChecked) ? [] : destinations.filter(\.isChecked).map(\.id)
    }

    /// The destinations an automatic step can be limited to, as designations: every destination but the picker and those
    /// the administrator turned off, the external commands one by one (upstream: `DestinationHelper.GetAllDestinations`
    /// without "Picker").
    public static func destinationChoices(settings: AppSettings) -> [(designation: String, name: String)] {
        var result: [(designation: String, name: String)] = []
        for destination in CaptureDestination.allCases where destination != .picker && !settings.isDestinationExcluded(destination) {
            if destination == .externalCommand {
                for command in settings.externalCommands where !command.name.isEmpty {
                    result.append((designation: "External \(command.name)", name: String(localized: "\(command.name) (external command)")))
                }
                continue
            }
            result.append((designation: RecipeDestinationDesignation.designation(for: destination), name: destination.displayName))
        }
        return result
    }
}

/// One line of Settings › Recipes › "Changed recipes": these automatic steps change these recipes (upstream
/// `RecipeChangeViewModel`).
public struct RecipeChangeLine: Equatable, Sendable {
    public var extensions: String
    public var recipes: String

    public init(extensions: String, recipes: String) {
        self.extensions = extensions
        self.recipes = recipes
    }
}

extension RecipeLibrary {
    /// The recipes and destinations of an automatic step's "Used for", with the stored choice checked; nil for an unknown
    /// id or one no recipe has a slot for (upstream `HasUseIn`).
    public func extensionScope(id: String, destinations: [(designation: String, name: String)]) -> RecipeExtensionScope? {
        guard let ext = loadedExtension(id: id)?.recipe else { return nil }
        let stored = RecipeExtensionSettings.stored(for: ext, in: optionValues)
        let captures = recipes.map(\.recipe).filter { RecipeComposer.canExtend(ext, $0) }
            .sorted { Self.displayName($0).localizedCaseInsensitiveCompare(Self.displayName($1)) == .orderedAscending }
            .map { recipe in
                let picked = stored.applyToAll || stored.onlyRecipes.contains { recipeEquals($0, recipe.id) }
                return RecipeScopeItem(id: recipe.id, name: Self.displayName(recipe),
                                       isChecked: picked && !stored.exceptRecipes.contains { recipeEquals($0, recipe.id) })
            }
        guard !captures.isEmpty else { return nil }
        var destinationItems: [RecipeScopeItem] = []
        if ext.extensionSlotName == RecipeSlots.beforeDestination {
            destinationItems = destinations.map { choice in
                RecipeScopeItem(id: choice.designation, name: choice.name,
                                isChecked: stored.onlyDestinations.isEmpty || stored.onlyDestinations.contains { recipeEquals($0, choice.designation) })
            }
        }
        return RecipeExtensionScope(captures: captures, destinations: destinationItems)
    }

    /// Settings › Recipes › "Changed recipes": one line per combination of automatic steps, with the recipes they change
    /// (upstream `UpdateRecipeChanges`); empty when none changes a recipe.
    /// The names as Settings shows them: a built-in recipe's or automatic step's in the language of the app
    /// (`L10nText.display`), a file's as written.
    public func recipeChanges() -> [RecipeChangeLine] {
        let values = optionValues
        let all = extensions.map(\.recipe)
        var extensionNames: [String: String] = [:]
        for loaded in extensions where extensionNames[loaded.recipe.id.lowercased()] == nil {
            extensionNames[loaded.recipe.id.lowercased()] = Self.shownName(loaded)
        }
        var lines: [RecipeChangeLine] = []
        let sorted = recipes.sorted {
            Self.shownName($0).localizedCaseInsensitiveCompare(Self.shownName($1)) == .orderedAscending
        }
        for loaded in sorted {
            let recipe = loaded.recipe
            let applied = RecipeComposer.applicable(to: recipe, among: all) { RecipeExtensionSettings.stored(for: $0, in: values) }
            guard !applied.isEmpty else { continue }
            let names = applied.map { extensionNames[$0.id.lowercased()] ?? Self.displayName($0) }.joined(separator: ", ")
            if let index = lines.firstIndex(where: { $0.extensions == names }) {
                lines[index].recipes += ", " + Self.shownName(loaded)
            } else {
                lines.append(RecipeChangeLine(extensions: names, recipes: Self.shownName(loaded)))
            }
        }
        return lines
    }

    /// A recipe's or automatic step's name as shown: a built-in's in the language of the app, a file's as written.
    static func shownName(_ loaded: LoadedRecipe) -> String {
        let name = displayName(loaded.recipe)
        return loaded.isBuiltIn ? L10nText.display(name) : name
    }

    static func displayName(_ recipe: CaptureRecipe) -> String {
        recipe.name.trimmingCharacters(in: .whitespaces).isEmpty ? recipe.id : recipe.name
    }
}
