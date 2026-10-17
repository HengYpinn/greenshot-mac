// Greenshot for Mac (Community) - an unofficial macOS port of Greenshot
// Copyright (C) 2026 Greenshot for Mac (Community) contributors
// Based on Greenshot, Copyright (C) 2007-2026 Thomas Braun, Jens Klingen, Robin Krom
// SPDX-License-Identifier: GPL-3.0-or-later

import Foundation

/// A question before an action on a recipe that can't be undone with one click (W-L4).
public struct RecipeConfirmation: Sendable, Equatable {
    public var title: String
    public var message: String
    /// The button that does it; the other one is Cancel.
    public var button: String

    public init(title: String, message: String, button: String) {
        self.title = title
        self.message = message
        self.button = button
    }

    /// Settings › Recipes "Unload", with the recipe manager's words (upstream `RecipeManagerViewModel.cs:255-259`).
    public static func unload(name: String, appName: String) -> RecipeConfirmation {
        RecipeConfirmation(title: String(localized: "Unload Recipe"),
                           message: String(localized: "Are you sure you want to unload '\(name)'? It will be unregistered from \(appName)."),
                           button: String(localized: "Unload"))
    }

    /// Settings › Recipes "Reset Default", with the recipe manager's words (upstream `RecipeManagerViewModel.cs:255-259`).
    public static func resetToDefault(name: String) -> RecipeConfirmation {
        RecipeConfirmation(title: String(localized: "Reset Recipe to Default"),
                           message: String(localized: "Are you sure you want to revert '\(name)' back to its default built-in definition?"),
                           button: String(localized: "Reset", comment: "Button: bring back the built-in version of a recipe"))
    }
}
