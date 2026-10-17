// Greenshot for Mac (Community) - an unofficial macOS port of Greenshot
// Copyright (C) 2026 Greenshot for Mac (Community) contributors
// Based on Greenshot, Copyright (C) 2007-2026 Thomas Braun, Jens Klingen, Robin Krom
// SPDX-License-Identifier: GPL-3.0-or-later
// Owned by RMANAGER after the wave 4 prep.

import Foundation

/// The automatic steps a running recipe was composed with (upstream `AppliedExtensions`, `DestinationChains`): set by
/// `RecipeComposer` on the recipe as it runs, never read from or written to a file. Filled in by the RMANAGER package.
public struct RecipeComposition: Sendable, Equatable {
    public init() {}
}

/// Puts the switched-on automatic steps into a recipe (upstream `Greenshot.Base/Recipes/RecipeComposer.cs`). Filled in by
/// the RMANAGER package.
public enum RecipeComposer {
    /// `${option.<key>}` of the running recipe; RMANAGER adds `option.<extension id>.<key>` of the automatic steps it was
    /// composed with (upstream `RecipeOptionStore.TryResolve`).
    public static func resolveOption(_ key: String, in recipe: CaptureRecipe) -> (ownerId: String, option: RecipeOption)? {
        guard let option = recipe.option(key) else { return nil }
        return (ownerId: recipe.id, option: option)
    }
}
