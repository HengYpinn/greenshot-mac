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
    public static func compare(_ old: String?, _ new: String?) -> [RecipeDiffLine]? {
        let a = lines(old)
        let b = lines(new)
        guard a.count <= maxLines, b.count <= maxLines else { return nil }
        // Longest common subsequence, from the end so the walk below can go forward.
        let width = b.count + 1
        var lcs = [Int32](repeating: 0, count: (a.count + 1) * width)
        if !a.isEmpty, !b.isEmpty {
            for i in stride(from: a.count - 1, through: 0, by: -1) {
                for j in stride(from: b.count - 1, through: 0, by: -1) {
                    if a[i] == b[j] {
                        lcs[i * width + j] = lcs[(i + 1) * width + j + 1] + 1
                    } else {
                        lcs[i * width + j] = max(lcs[(i + 1) * width + j], lcs[i * width + j + 1])
                    }
                }
            }
        }
        var result: [RecipeDiffLine] = []
        var x = 0
        var y = 0
        while x < a.count, y < b.count {
            if a[x] == b[y] {
                result.append(RecipeDiffLine(.unchanged, a[x]))
                x += 1
                y += 1
            } else if lcs[(x + 1) * width + y] >= lcs[x * width + y + 1] {
                result.append(RecipeDiffLine(.removed, a[x]))
                x += 1
            } else {
                result.append(RecipeDiffLine(.added, b[y]))
                y += 1
            }
        }
        while x < a.count {
            result.append(RecipeDiffLine(.removed, a[x]))
            x += 1
        }
        while y < b.count {
            result.append(RecipeDiffLine(.added, b[y]))
            y += 1
        }
        return result
    }
    /// The changed lines with "-"/"+" and `context` unchanged lines around them, "@@" between the parts.
    public static func unifiedText(_ old: String?, _ new: String?, context: Int = 3) -> String {
        guard let diff = compare(old, new) else { return "// The recipes are too large to compare (more than \(maxLines) lines)." }
        guard diff.contains(where: { $0.kind != .unchanged }) else { return "// No changes." }
        var show = [Bool](repeating: false, count: diff.count)
        for index in diff.indices where diff[index].kind != .unchanged {
            for near in max(0, index - context)...min(diff.count - 1, index + context) { show[near] = true }
        }
        var text = ""
        var skipped = false
        for index in diff.indices {
            guard show[index] else {
                skipped = true
                continue
            }
            if skipped { text += "@@\n" }
            skipped = false
            let mark: String
            switch diff[index].kind {
            case .unchanged: mark = " "
            case .removed: mark = "-"
            case .added: mark = "+"
            }
            text += "\(mark) \(diff[index].text)\n"
        }
        return text
    }

    private static func lines(_ text: String?) -> [String] {
        guard let text, !text.isEmpty else { return [] }
        var normalized = text.replacingOccurrences(of: "\r\n", with: "\n").replacingOccurrences(of: "\r", with: "\n")
        while normalized.hasSuffix("\n") { normalized.removeLast() }
        return normalized.components(separatedBy: "\n")
    }
}
