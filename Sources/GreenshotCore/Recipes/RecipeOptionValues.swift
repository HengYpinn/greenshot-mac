// Greenshot for Mac (Community) - an unofficial macOS port of Greenshot
// Copyright (C) 2026 Greenshot for Mac (Community) contributors
// Based on Greenshot, Copyright (C) 2007-2026 Thomas Braun, Jens Klingen, Robin Krom
// SPDX-License-Identifier: GPL-3.0-or-later

import CoreGraphics
import Foundation

/// The user's values of recipe options (upstream `RecipeOptionStore`, greenshot.ini `[RecipeOptions]`): stored as
/// "<recipe id>.<option key>" in `RecipeSettings.optionValues`, only when they differ from the default.
public struct RecipeOptionValues: Sendable, Equatable {
    public var stored: [String: String]

    public init(_ stored: [String: String] = [:]) {
        self.stored = stored
    }

    public static func storageKey(recipeId: String, optionKey: String) -> String { "\(recipeId).\(optionKey)" }
    /// The stored value converted to the option, or its default.
    public func value(of option: RecipeOption, recipeId: String) -> JSONValue { rcoreStub() }
    /// Stores the value, removes it when it is the default; false when nothing changed or the value doesn't fit.
    @discardableResult
    public mutating func setValue(_ value: JSONValue, of option: RecipeOption, recipeId: String) -> Bool { rcoreStub() }
    /// Back to the defaults ("Reset to defaults").
    @discardableResult
    public mutating func reset(recipeId: String) -> Bool { rcoreStub() }
}
