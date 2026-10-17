// Greenshot for Mac (Community) - an unofficial macOS port of Greenshot
// Copyright (C) 2026 Greenshot for Mac (Community) contributors
// Based on Greenshot, Copyright (C) 2007-2026 Thomas Braun, Jens Klingen, Robin Krom
// SPDX-License-Identifier: GPL-3.0-or-later

import Foundation

/// The recipe settings: upstream greenshot.ini sections `[Recipe]` (`IRecipeConfiguration`) and `[RecipeOptions]`
/// (`IRecipeOptionsConfiguration`).
public struct RecipeSettings: Codable, Equatable, Sendable {
    /// Recipes on: the recipe menu, recipe triggers and recipe files (upstream `EnableRecipeFeature`, default true).
    public var enabled = true
    /// The recipe files to load, absolute paths; no folder is scanned (upstream `RecipeFiles`, semicolon list).
    public var files: [String] = []
    /// The ids of switched-off recipes (upstream `DisabledRecipeIds`).
    public var disabledRecipeIds: [String] = []
    /// The user's recipe option values as "<recipe id>.<option key>", only those that differ from the default
    /// (upstream `[RecipeOptions] Values`).
    public var optionValues: [String: String] = [:]

    public init() {}

    enum CodingKeys: String, CodingKey { case enabled, files, disabledRecipeIds, optionValues }

    // Every value falls back to its default, so settings written by another version still load.
    public init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        let d = RecipeSettings()
        func value<T: Decodable>(_ key: CodingKeys, _ fallback: T) -> T {
            (try? c.decodeIfPresent(T.self, forKey: key)) ?? fallback
        }
        enabled = value(.enabled, d.enabled)
        files = value(.files, d.files)
        disabledRecipeIds = value(.disabledRecipeIds, d.disabledRecipeIds)
        optionValues = value(.optionValues, d.optionValues)
    }
}
