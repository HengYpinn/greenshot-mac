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
    public func value(of option: RecipeOption, recipeId: String) -> JSONValue {
        guard let raw = storedValue(Self.storageKey(recipeId: recipeId, optionKey: option.key)) else { return option.resolvedDefault }
        if let value = option.convert(.string(raw)) { return value }
        log.warn("The value '\(raw)' of option '\(option.key)' of '\(recipeId)' doesn't fit the option, using the default.")
        return option.resolvedDefault
    }

    private func storedKey(_ key: String) -> String? {
        stored.keys.first { recipeEquals($0, key) }
    }

    private func storedValue(_ key: String) -> String? {
        storedKey(key).flatMap { stored[$0] }
    }
    /// Stores the value, removes it when it is the default; false when nothing changed or the value doesn't fit.
    @discardableResult
    public mutating func setValue(_ value: JSONValue, of option: RecipeOption, recipeId: String) -> Bool {
        guard !recipeId.isEmpty, let converted = option.convert(value) else {
            log.warn("Ignoring a value for option '\(option.key)' of '\(recipeId)': it doesn't fit the option.")
            return false
        }
        let key = Self.storageKey(recipeId: recipeId, optionKey: option.key)
        let text = option.storageString(converted)
        let isDefault = text == option.storageString(option.resolvedDefault)
        let existing = storedKey(key)
        if isDefault {
            guard let existing else { return false }
            stored[existing] = nil
            return true
        }
        if let existing, stored[existing] == text { return false }
        if let existing { stored[existing] = nil }
        stored[key] = text
        return true
    }
    /// Back to the defaults ("Reset to defaults"). Only this recipe's keys: an option key has no dot, so
    /// "capture.annotate.border" belongs to recipe "capture.annotate", not to "capture" (upstream `Reset` removes every key
    /// that starts with "<id>.").
    @discardableResult
    public mutating func reset(recipeId: String) -> Bool {
        let prefix = (recipeId + ".").lowercased()
        let keys = stored.keys.filter { key in
            let lowered = key.lowercased()
            return lowered.hasPrefix(prefix) && !lowered.dropFirst(prefix.count).contains(".")
        }
        for key in keys { stored[key] = nil }
        return !keys.isEmpty
    }
}

private let log = Log("Recipes")
