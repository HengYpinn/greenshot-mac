// Greenshot for Mac (Community) - an unofficial macOS port of Greenshot
// Copyright (C) 2026 Greenshot for Mac (Community) contributors
// Based on Greenshot, Copyright (C) 2007-2026 Thomas Braun, Jens Klingen, Robin Krom
// SPDX-License-Identifier: GPL-3.0-or-later

import Foundation

/// An entry of a Recipes menu: the menu bar icon's (upstream `ContextMenuTrigger` items, `TrayMenu.CreateRecipesItem`) or
/// the editor's (upstream `EditorTrigger` items, `ImageEditorForm.UpdateRecipesMenu`).
public struct RecipeMenuEntry: Sendable, Equatable {
    public var recipeId: String
    public var title: String
    /// The submenu the entry is in; nil: the Recipes menu itself (the trigger's `Group` "Recipes", the default).
    public var group: String?
    public var order: Int
    /// The trigger the entry fires; nil for the entry a recipe of a file gets when it has no menu trigger (upstream
    /// `trigger_recipe_<id>_menu_default`), which starts the recipe by its id.
    public var trigger: ActiveRecipeTrigger?
    /// The recipe's first active Hotkey trigger, shown next to the entry (upstream `FindHotkeyTriggerForRecipe`).
    public var hotkey: KeyCombo?

    public init(recipeId: String, title: String, group: String? = nil, order: Int = 0, trigger: ActiveRecipeTrigger? = nil,
                hotkey: KeyCombo? = nil) {
        self.recipeId = recipeId
        self.title = title
        self.group = group
        self.order = order
        self.trigger = trigger
        self.hotkey = hotkey
    }
}

/// An item of a built Recipes menu: an entry, or a submenu with the entries of one `Group`.
public enum RecipeMenuItemLayout: Sendable, Equatable {
    case entry(RecipeMenuEntry)
    case group(name: String, entries: [RecipeMenuEntry])
}

/// Which entries the Recipes menus show (upstream `TriggerManager.SyncRecipeTriggers` for the menu triggers and the
/// default entry, `TrayMenu.CreateRecipesItem` for the order and the hotkey).
public enum RecipeMenuEntries {
    /// The group of an entry that goes straight into the Recipes menu.
    public static let defaultGroup = "Recipes"

    /// The menu bar icon's Recipes menu: the active ContextMenu and Systray triggers of the switched-on recipes that show
    /// in the menu (`ShowInContextMenu`), and an entry for each such recipe of a file without an active menu trigger;
    /// sorted by `Order`, otherwise in the order of the recipes and their triggers.
    public static func statusMenu(recipes: [LoadedRecipe], active: [ActiveRecipeTrigger]) -> [RecipeMenuEntry] {
        var entries: [RecipeMenuEntry] = []
        for loaded in recipes where loaded.isEnabled && loaded.recipe.showInContextMenu {
            let id = loaded.recipe.id
            let menuTriggers = active.filter {
                recipeEquals($0.recipeId, id)
                    && ($0.trigger.isType(WellKnownTriggerType.contextMenu) || $0.trigger.isType(WellKnownTriggerType.systray))
            }
            let hotkey = firstHotkey(of: id, in: active)
            for trigger in menuTriggers {
                entries.append(entry(for: trigger, of: loaded.recipe, hotkey: hotkey))
            }
            if menuTriggers.isEmpty, !loaded.isBuiltIn {
                entries.append(RecipeMenuEntry(recipeId: id, title: displayName(of: loaded.recipe), hotkey: hotkey))
            }
        }
        return sortedByOrder(entries)
    }

    /// The editor's Recipes menu: the active Editor triggers of the switched-on recipes, in their order.
    public static func editorMenu(recipes: [LoadedRecipe], active: [ActiveRecipeTrigger]) -> [RecipeMenuEntry] {
        var entries: [RecipeMenuEntry] = []
        for loaded in recipes where loaded.isEnabled {
            let id = loaded.recipe.id
            let hotkey = firstHotkey(of: id, in: active)
            for trigger in active where recipeEquals(trigger.recipeId, id) && trigger.trigger.isType(WellKnownTriggerType.editor) {
                entries.append(entry(for: trigger, of: loaded.recipe, hotkey: hotkey))
            }
        }
        return sortedByOrder(entries)
    }

    /// The menu items: entries without a group in place, the others in one submenu per group, where its first entry is.
    public static func layout(_ entries: [RecipeMenuEntry]) -> [RecipeMenuItemLayout] {
        var items: [RecipeMenuItemLayout] = []
        var groupPositions: [String: Int] = [:]
        for entry in entries {
            guard let group = entry.group else {
                items.append(.entry(entry))
                continue
            }
            let key = group.lowercased()
            if let position = groupPositions[key], case .group(let name, let members) = items[position] {
                items[position] = .group(name: name, entries: members + [entry])
            } else {
                groupPositions[key] = items.count
                items.append(.group(name: group, entries: [entry]))
            }
        }
        return items
    }

    private static func entry(for trigger: ActiveRecipeTrigger, of recipe: CaptureRecipe, hotkey: KeyCombo?) -> RecipeMenuEntry {
        let text = trigger.trigger.menuItemText?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        let group = trigger.trigger.group.trimmingCharacters(in: .whitespacesAndNewlines)
        return RecipeMenuEntry(recipeId: recipe.id, title: text.isEmpty ? displayName(of: recipe) : text,
                               group: group.isEmpty || recipeEquals(group, defaultGroup) ? nil : group,
                               order: trigger.trigger.order, trigger: trigger, hotkey: hotkey)
    }

    private static func displayName(of recipe: CaptureRecipe) -> String {
        let name = recipe.name.trimmingCharacters(in: .whitespacesAndNewlines)
        return name.isEmpty ? recipe.id : name
    }

    private static func firstHotkey(of recipeId: String, in active: [ActiveRecipeTrigger]) -> KeyCombo? {
        active.first { recipeEquals($0.recipeId, recipeId) && $0.trigger.isType(WellKnownTriggerType.hotkey) && $0.hotkey != nil }?.hotkey
    }

    /// Upstream `OrderBy(t => t.Order)`: stable.
    private static func sortedByOrder(_ entries: [RecipeMenuEntry]) -> [RecipeMenuEntry] {
        entries.enumerated().sorted { lhs, rhs in
            lhs.element.order == rhs.element.order ? lhs.offset < rhs.offset : lhs.element.order < rhs.element.order
        }.map(\.element)
    }
}
