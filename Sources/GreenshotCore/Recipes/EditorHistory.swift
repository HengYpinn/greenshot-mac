// Greenshot for Mac (Community) - an unofficial macOS port of Greenshot
// Copyright (C) 2026 Greenshot for Mac (Community) contributors
// Based on Greenshot, Copyright (C) 2007-2026 Thomas Braun, Jens Klingen, Robin Krom
// SPDX-License-Identifier: GPL-3.0-or-later

import Foundation

/// Undo and redo of the recipe editor (upstream RecipeEditorViewModel.cs:399-620, `RecipeMemento`): states are the recipe
/// as it would be saved; a change is recorded once it stopped changing (typing becomes one step) or when forced (before
/// undo and redo); the history of each recipe is kept while the editor is open, also past a save.
public struct RecipeEditHistory: Sendable {
    /// Upstream `MaxHistory`.
    public static let maxSteps = 100

    private var undoStack: [String] = []
    private var redoStack: [String] = []
    /// The state the history is at.
    public private(set) var current: String?
    /// A change seen at the last check, recorded once it stopped changing.
    private var pending: String?
    /// The histories of the other recipes opened while the editor is open, by id (lowercased).
    private var kept: [String: (undo: [String], redo: [String], current: String)] = [:]

    public init() {}

    public var canUndo: Bool { !undoStack.isEmpty || (current != nil && pending != nil) }
    public var canRedo: Bool { !redoStack.isEmpty }
    public var undoCount: Int { undoStack.count }

    /// Upstream `KeepHistory`: the closed recipe's history, for when it is opened again.
    public mutating func keep(recipeId: String?) {
        guard let recipeId, !recipeId.isEmpty, let current else { return }
        kept[recipeId.lowercased()] = (undoStack, redoStack, current)
    }

    /// Upstream `ResetHistory`: starts the history of the opened recipe with what was kept of it. A recipe that changed
    /// since (discarded changes, saved elsewhere) gets back to how it was left with one undo.
    public mutating func reset(recipeId: String?, content: String?) {
        undoStack.removeAll()
        redoStack.removeAll()
        pending = nil
        current = content
        guard let content, let recipeId, let saved = kept.removeValue(forKey: recipeId.lowercased()) else { return }
        undoStack = saved.undo
        if saved.current == content {
            redoStack = saved.redo
        } else {
            undoStack.append(saved.current)
        }
        if undoStack.count > Self.maxSteps { undoStack.removeFirst(undoStack.count - Self.maxSteps) }
    }

    /// Upstream `RecordHistory`. Returns true when a step was recorded.
    @discardableResult
    public mutating func record(_ content: String, force: Bool) -> Bool {
        guard let current, content != current else {
            pending = nil
            return false
        }
        if !force && content != pending {
            // Still changing: wait for the next check.
            pending = content
            return false
        }
        undoStack.append(current)
        if undoStack.count > Self.maxSteps { undoStack.removeFirst() }
        redoStack.removeAll()
        self.current = content
        pending = nil
        return true
    }

    /// Upstream `Undo`: the state to restore; `content` is the recipe now (recorded first).
    public mutating func undo(from content: String) -> String? {
        record(content, force: true)
        guard let target = undoStack.popLast(), let current else { return nil }
        redoStack.append(current)
        self.current = target
        return target
    }

    /// Upstream `Redo`.
    public mutating func redo(from content: String) -> String? {
        record(content, force: true)
        guard let target = redoStack.popLast(), let current else { return nil }
        undoStack.append(current)
        self.current = target
        return target
    }

    /// After a restore: the restored content as the editor writes it, so it isn't recorded as a new change.
    public mutating func didRestore(_ content: String) {
        current = content
        pending = nil
    }
}
