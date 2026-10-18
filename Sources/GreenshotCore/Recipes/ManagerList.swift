// Greenshot for Mac (Community) - an unofficial macOS port of Greenshot
// Copyright (C) 2026 Greenshot for Mac (Community) contributors
// Based on Greenshot, Copyright (C) 2007-2026 Thomas Braun, Jens Klingen, Robin Krom
// SPDX-License-Identifier: GPL-3.0-or-later

import Foundation

/// A row of the recipe manager (upstream `RecipeManagerItemViewModel`, Greenshot.Plugin.RecipeEditor/ViewModels/
/// RecipeManagerViewModel.cs): a recipe, or an automatic step in the group of its own.
public struct RecipeManagerItem: Identifiable, Equatable, Sendable {
    public var id: String
    public var name: String
    public var description: String
    public var version: String
    public var isExtension: Bool
    public var isBuiltIn: Bool
    /// A file replaces the built-in recipe or automatic step with the same id.
    public var isOverridden: Bool
    /// The AI tool that wrote the file (and the user approved).
    public var proposedBy: String?
    /// A recipe switched on, an automatic step's `enabled` option on (always for one without switch).
    public var isEnabled: Bool
    /// Automatic steps without an on/off option can't be switched.
    public var canToggle: Bool
    public var triggersSummary: String
    public var stepCount: Int
    public var filePath: String?
    /// Triggers in the recipe which its approval doesn't switch on.
    public var hasUnapprovedTriggers: Bool

    public init(id: String, name: String, description: String = "", version: String = "1.0", isExtension: Bool = false,
                isBuiltIn: Bool = false, isOverridden: Bool = false, proposedBy: String? = nil, isEnabled: Bool = true,
                canToggle: Bool = true, triggersSummary: String = "", stepCount: Int = 0, filePath: String? = nil,
                hasUnapprovedTriggers: Bool = false) {
        self.id = id
        self.name = name
        self.description = description
        self.version = version
        self.isExtension = isExtension
        self.isBuiltIn = isBuiltIn
        self.isOverridden = isOverridden
        self.proposedBy = proposedBy
        self.isEnabled = isEnabled
        self.canToggle = canToggle
        self.triggersSummary = triggersSummary
        self.stepCount = stepCount
        self.filePath = filePath
        self.hasUnapprovedTriggers = hasUnapprovedTriggers
    }

    /// "OVERRIDDEN", "BUILT-IN" or "CUSTOM" (upstream `RecipeTypeBadge`), in the app's language.
    public var typeBadge: String {
        if isOverridden { return String(localized: "OVERRIDDEN", comment: "Badge of a recipe whose file replaces a built-in recipe") }
        return isBuiltIn ? String(localized: "BUILT-IN", comment: "Badge of a built-in recipe")
            : String(localized: "CUSTOM", comment: "Badge of a recipe from a file")
    }
    public var statusBadge: String { Self.statusBadge(isEnabled: isEnabled) }
    public static func statusBadge(isEnabled: Bool) -> String {
        isEnabled ? String(localized: "ACTIVE", comment: "Badge of a recipe that is switched on")
            : String(localized: "DEACTIVATED", comment: "Badge of a recipe that is switched off")
    }
    public var isAICreated: Bool { !(proposedBy ?? "").isEmpty }
    /// Unload (a file recipe or automatic step) or Reset Default (a file which replaces a built-in recipe).
    public var canUnload: Bool { isExtension ? filePath != nil : (!isBuiltIn || isOverridden) }
    public var unloadTitle: String {
        isOverridden && !isExtension ? String(localized: "Reset Default", comment: "Button: bring back the built-in version of a recipe")
            : String(localized: "Unload")
    }
    /// Permissions: only what came from a file has an approval.
    public var hasFile: Bool { filePath != nil }
}

/// The category chips of the recipe manager (upstream `SelectedFilterCategory`).
public enum RecipeManagerFilter: String, CaseIterable, Sendable {
    case all = "All"
    case active = "Active"
    case deactivated = "Deactivated"
    case builtIn = "Built-in"
    case custom = "Custom"
    case ai = "AI"

    /// The chip's name, in the app's language (the raw value is the English name).
    public var displayName: String {
        switch self {
        case .all: return String(localized: "recipeManager.filter.all", defaultValue: "All", comment: "Recipe manager filter: every recipe")
        case .active: return String(localized: "Active", comment: "Recipe manager filter: the recipes that are switched on")
        case .deactivated: return String(localized: "Deactivated", comment: "Recipe manager filter: the recipes that are switched off")
        case .builtIn: return String(localized: "Built-in", comment: "Recipe manager filter: the built-in recipes")
        case .custom: return String(localized: "recipeManager.filter.custom", defaultValue: "Custom", comment: "Recipe manager filter: the recipes from files")
        case .ai: return String(localized: "AI", comment: "Recipe manager filter: the recipes written by AI tools")
        }
    }

    public func matches(_ item: RecipeManagerItem) -> Bool {
        switch self {
        case .all: return true
        case .active: return item.isEnabled
        case .deactivated: return !item.isEnabled
        case .builtIn: return item.isBuiltIn && !item.isOverridden
        case .custom: return !item.isBuiltIn || item.isOverridden
        case .ai: return item.isAICreated
        }
    }
}

/// Filtering and counting the manager's rows (upstream `ApplyFilter`, `UpdateStats`).
public enum RecipeManagerList {
    /// The rows of the category whose name, id, description, triggers or file contain the query (case-insensitive). A
    /// built-in row's name and description also match as the manager shows them, in the language of the app
    /// (`display`, `L10nText.display`).
    public static func filter(_ items: [RecipeManagerItem], by filter: RecipeManagerFilter, query: String,
                              display: (String) -> String = { L10nText.display($0) }) -> [RecipeManagerItem] {
        let text = query.trimmingCharacters(in: .whitespacesAndNewlines)
        return items.filter { item in
            guard filter.matches(item) else { return false }
            guard !text.isEmpty else { return true }
            var fields = [item.name, item.id, item.description, item.triggersSummary, item.filePath ?? ""]
            if item.isBuiltIn && !item.isOverridden {
                fields += [display(item.name), display(item.description)]
            }
            return fields.contains { $0.range(of: text, options: [.caseInsensitive, .diacriticInsensitive]) != nil }
        }
    }

    /// "Total", "Active", "Deactivated" of the recipes (automatic steps aren't counted, like upstream).
    public static func counts(_ recipes: [RecipeManagerItem]) -> (total: Int, active: Int, deactivated: Int) {
        let active = recipes.filter(\.isEnabled).count
        return (recipes.count, active, recipes.count - active)
    }

    /// What the triggers of a recipe do, in one line (upstream `TriggersSummary`).
    public static func triggersSummary(_ loaded: LoadedRecipe) -> String {
        let recipe = loaded.recipe
        guard !recipe.triggers.isEmpty else {
            return recipe.showInContextMenu ? String(localized: "Recipes menu (default)") : String(localized: "No triggers (recipe editor only)")
        }
        var parts: [String] = []
        for (index, trigger) in recipe.triggers.enumerated() {
            var label = describe(trigger, of: recipe)
            if trigger.isType(WellKnownTriggerType.commandline), trigger.allowsBrowserInvocation {
                let key = RecipeApprovalPolicy.browserInvocationKey(index: index, trigger: trigger)
                let approved = loaded.isBuiltIn || loaded.approval?.isTriggerApproved(key) == true
                label = approved ? String(localized: "\(label) (+ web pages)", comment: "%@ is a trigger of a recipe")
                    : String(localized: "\(label) (web pages: not approved)", comment: "%@ is a trigger of a recipe")
            }
            if !trigger.enabled {
                label = String(localized: "\(label) (disabled)", comment: "%@ is a trigger of a recipe")
            } else if !isApproved(loaded, index: index) {
                label = String(localized: "\(label) (off, not approved)", comment: "%@ is a trigger of a recipe")
            }
            parts.append(label)
        }
        return parts.joined(separator: "  •  ")
    }

    /// An enabled trigger the approval doesn't switch on (upstream `HasUnapprovedTriggers`).
    public static func hasUnapprovedTriggers(_ loaded: LoadedRecipe) -> Bool {
        loaded.recipe.triggers.indices.contains { loaded.recipe.triggers[$0].enabled && !isApproved(loaded, index: $0) }
    }

    private static func isApproved(_ loaded: LoadedRecipe, index: Int) -> Bool {
        guard !loaded.isBuiltIn else { return true }
        let key = RecipeApprovalPolicy.triggerKey(index: index, trigger: loaded.recipe.triggers[index])
        return loaded.approval?.isTriggerApproved(key) ?? false
    }

    private static func describe(_ trigger: TriggerConfig, of recipe: CaptureRecipe) -> String {
        let menuText = trigger.menuItemText ?? recipe.name
        switch trigger.triggerType.lowercased() {
        case WellKnownTriggerType.hotkey.lowercased():
            guard let text = trigger.hotkey?.trimmingCharacters(in: .whitespaces), !text.isEmpty else { return String(localized: "Hotkey") }
            let hotkey = RecipeHotkeyText.parse(text)?.displayString ?? text
            return String(localized: "Hotkey \(hotkey)", comment: "A recipe's hotkey trigger; %@ is the hotkey, e.g. ⇧⌘R")
        case WellKnownTriggerType.contextMenu.lowercased(), WellKnownTriggerType.systray.lowercased():
            return String(localized: "Recipes menu (“\(menuText)”)", comment: "A recipe's menu trigger; %@ is the menu item")
        case WellKnownTriggerType.editor.lowercased():
            return String(localized: "Editor (“\(menuText)”)", comment: "A recipe's trigger in the editor; %@ is the menu item")
        case WellKnownTriggerType.clipboard.lowercased(): return String(localized: "Clipboard monitor")
        case WellKnownTriggerType.commandline.lowercased():
            let command = trigger.command ?? recipe.id
            return String(localized: "Command line: \(command)")
        case WellKnownTriggerType.aiTool.lowercased():
            let tool = trigger.toolName ?? trigger.name ?? recipe.id
            return String(localized: "AI tool “\(tool)”")
        case WellKnownTriggerType.openFile.lowercased(): return String(localized: "Open file", comment: "A recipe's trigger: a file opened with Greenshot")
        case WellKnownTriggerType.extension.lowercased(): return String(localized: "Browser extension")
        case WellKnownTriggerType.schedule.lowercased(): return String(localized: "Schedule", comment: "A recipe's trigger: at set times")
        case WellKnownTriggerType.manual.lowercased(): return String(localized: "Manual", comment: "A recipe's trigger: started by hand")
        default: return trigger.name ?? trigger.triggerType
        }
    }
}

extension RecipeLibrary {
    /// The manager's rows: the recipes as the library lists them, then the automatic steps (by order, then id).
    public func managerItems() -> (recipes: [RecipeManagerItem], extensions: [RecipeManagerItem]) {
        let recipeRows = recipes.map { loaded -> RecipeManagerItem in
            let recipe = loaded.recipe
            return RecipeManagerItem(id: recipe.id, name: Self.displayName(recipe), description: recipe.description ?? "",
                                     version: Self.version(recipe), isBuiltIn: loaded.isBuiltIn, isOverridden: loaded.replacesBuiltIn,
                                     proposedBy: loaded.proposedBy, isEnabled: loaded.isEnabled,
                                     triggersSummary: RecipeManagerList.triggersSummary(loaded), stepCount: recipe.nodes.count,
                                     filePath: loaded.fileURL?.path, hasUnapprovedTriggers: RecipeManagerList.hasUnapprovedTriggers(loaded))
        }
        let all = recipes.map(\.recipe)
        let extensionRows = extensions.map { loaded -> RecipeManagerItem in
            let ext = loaded.recipe
            let fits = all.filter { RecipeComposer.canExtend(ext, $0) }.count
            return RecipeManagerItem(id: ext.id, name: Self.displayName(ext), description: ext.description ?? "",
                                     version: Self.version(ext), isExtension: true, isBuiltIn: loaded.isBuiltIn,
                                     isOverridden: loaded.replacesBuiltIn, proposedBy: loaded.proposedBy, isEnabled: loaded.isEnabled,
                                     canToggle: ext.extensionEnabledOption != nil,
                                     triggersSummary: Self.extensionSummary(slot: ext.extensionSlotName ?? ext.extends?.slot ?? "?", fits: fits),
                                     stepCount: ext.nodes.count, filePath: loaded.fileURL?.path)
        }
        return (recipeRows, extensionRows)
    }

    /// "Automatic step at BeforeExport, fits 3 recipe(s)" in the automatic step's row.
    private static func extensionSummary(slot: String, fits: Int) -> String {
        String(localized: "Automatic step at \(slot), fits \(fits) recipe(s)", comment: "%@ is a slot name (BeforeExport), %lld a number")
    }

    private static func version(_ recipe: CaptureRecipe) -> String {
        let version = recipe.version.trimmingCharacters(in: .whitespaces)
        return version.isEmpty ? "1.0" : version
    }
}
