// Greenshot for Mac (Community) - an unofficial macOS port of Greenshot
// Copyright (C) 2026 Greenshot for Mac (Community) contributors
// Based on Greenshot, Copyright (C) 2007-2026 Thomas Braun, Jens Klingen, Robin Krom
// SPDX-License-Identifier: GPL-3.0-or-later

import CoreGraphics
import Foundation

/// One line of a line diff (upstream `RecipeTextDiff.DiffLine`).
public struct RecipeDiffLine: Sendable, Equatable {
    public enum Kind: String, Sendable { case unchanged, removed, added }
    public var kind: Kind
    public var text: String

    public init(_ kind: Kind, _ text: String) {
        self.kind = kind
        self.text = text
    }
}

/// Line diff of two versions of a file (upstream `RecipeTextDiff`, LCS; nil above 3000 lines).
public enum RecipeTextDiff {
    public static let maxLines = 3000
    public static func compare(_ old: String?, _ new: String?) -> [RecipeDiffLine]? { rcoreStub() }
    /// The changed lines with "-"/"+" and `context` unchanged lines around them, "@@" between the parts.
    public static func unifiedText(_ old: String?, _ new: String?, context: Int = 3) -> String { rcoreStub() }
}
