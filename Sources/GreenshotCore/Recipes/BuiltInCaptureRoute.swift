// Greenshot for Mac (Community) - an unofficial macOS port of Greenshot
// Copyright (C) 2026 Greenshot for Mac (Community) contributors
// Based on Greenshot, Copyright (C) 2007-2026 Thomas Braun, Jens Klingen, Robin Krom
// SPDX-License-Identifier: GPL-3.0-or-later

import Foundation

/// Which way a capture the app starts itself goes (the hotkeys, the menus, Open Image from File/Clipboard, a notification
/// click). Upstream runs every capture as its built-in recipe (`CaptureHelper`); the Mac keeps its own capture code for a
/// built-in nobody changed, and runs the recipe when a file replaces it, an automatic step changes it, or it is switched off.
public enum BuiltInCaptureRoute: Equatable, Sendable {
    /// The app's own code, as without recipes.
    case direct
    /// The recipe flow.
    case recipe
    /// The built-in recipe is switched off (upstream `CapturePipeline` aborts "deactivated"): nothing is captured.
    case off

    /// - Parameters:
    ///   - featureEnabled: recipes switched on.
    ///   - loaded: the recipe with the built-in's id as the library has it (a file may replace the built-in).
    ///   - composed: `loaded`'s recipe with its automatic steps; nil when nothing composes recipes.
    public static func decision(featureEnabled: Bool, loaded: LoadedRecipe?, composed: CaptureRecipe?) -> BuiltInCaptureRoute {
        guard featureEnabled, let loaded else { return .direct }
        guard loaded.isEnabled else { return .off }
        guard loaded.isBuiltIn else { return .recipe }
        if let composed, composed != loaded.recipe { return .recipe }
        return .direct
    }
}

/// The recipe that takes a capture of the browser extension (upstream `CaptureHelper.ImportExtensionCapture`,
/// CaptureHelper.cs:112-131): the first switched-on recipe with an active Extension trigger whose `Browser` is empty or
/// the capture's browser (case-insensitive), else the built-in `recipe_browser_extension`. The user's recipes come before
/// the built-in ones (whose own Extension trigger takes every browser), so a recipe of one's own wins.
public enum RecipeExtensionCapturePick {
    /// The recipe id and the index of its trigger (nil for the built-in fallback).
    public static func pick(_ recipes: [LoadedRecipe], browser: String?) -> (recipeId: String, triggerIndex: Int?) {
        let wanted = browser?.trimmingCharacters(in: .whitespaces) ?? ""
        let ordered = recipes.filter { !$0.isBuiltIn } + recipes.filter(\.isBuiltIn)
        for loaded in ordered where loaded.isEnabled {
            for (index, trigger) in loaded.recipe.triggers.enumerated() where trigger.isType(WellKnownTriggerType.extension) {
                guard loaded.isTriggerActive(at: index) else { continue }
                let filter = trigger.browser?.trimmingCharacters(in: .whitespaces) ?? ""
                if filter.isEmpty || filter.caseInsensitiveCompare(wanted) == .orderedSame {
                    return (loaded.recipe.id, index)
                }
            }
        }
        return (BuiltInRecipes.browserExtensionId, nil)
    }
}
