// Greenshot for Mac (Community) - an unofficial macOS port of Greenshot
// Copyright (C) 2026 Greenshot for Mac (Community) contributors
// Based on Greenshot, Copyright (C) 2007-2026 Thomas Braun, Jens Klingen, Robin Krom
// SPDX-License-Identifier: GPL-3.0-or-later

import CoreGraphics
import Foundation

/// A file that isn't a recipe: not JSON, a list holding an extension, a member of the wrong type. The messages are
/// upstream's (`RecipeSerializer`).
public struct RecipeFormatError: Error, LocalizedError, Equatable, Sendable {
    public var message: String

    public init(_ message: String) {
        self.message = message
    }

    public var errorDescription: String? { message }
}

/// Reads and writes `.gsrecipe.json` (upstream `RecipeSerializer`). Reading is tolerant: names are case-insensitive,
/// a missing kind is "recipe", a missing member gets its default, an unknown member is kept in `extra`. A file holds
/// one recipe or a JSON array of recipes.
public enum RecipeSerializer {
    public static let fileExtension = ".gsrecipe.json"

    /// Every definition of the file, in order; extensions included (their kind says so).
    public static func decode(_ data: Data) throws -> [CaptureRecipe] { rcoreStub() }
    public static func decode(text: String) throws -> [CaptureRecipe] { rcoreStub() }
    public static func recipe(from json: JSONValue) throws -> CaptureRecipe { rcoreStub() }
    public static func json(of recipe: CaptureRecipe) -> JSONValue { rcoreStub() }
    /// Upstream's layout: "kind" first, camelCase names, null members left out, two-space indent.
    public static func encode(_ recipe: CaptureRecipe, indented: Bool = true) -> String { rcoreStub() }
    public static func encode(_ recipes: [CaptureRecipe], indented: Bool = true) -> String { rcoreStub() }
    /// The text of file bytes, UTF-8 with or without byte order mark (upstream `RecipeManager.DecodeRecipeFile`).
    public static func text(of data: Data) -> String? { rcoreStub() }
}
