// Greenshot for Mac (Community) - an unofficial macOS port of Greenshot
// Copyright (C) 2026 Greenshot for Mac (Community) contributors
// Based on Greenshot, Copyright (C) 2007-2026 Thomas Braun, Jens Klingen, Robin Krom
// SPDX-License-Identifier: GPL-3.0-or-later

import Foundation
import Testing
@testable import GreenshotCore

@Suite struct RecipeEditorHistoryTests {
    @Test func aChangeIsRecordedOnceItStoppedChanging() {
        var history = RecipeEditHistory()
        history.reset(recipeId: "r", content: "v0")
        let r1 = history.record("v1", force: false)
        #expect(!r1)
        #expect(history.canUndo)
        let r2 = history.record("v12", force: false)
        #expect(!r2)
        let r3 = history.record("v12", force: false)
        #expect(r3)
        #expect(history.undoCount == 1)
        #expect(history.current == "v12")
    }

    @Test func undoAndRedo() {
        var history = RecipeEditHistory()
        history.reset(recipeId: "r", content: "a")
        history.record("b", force: true)
        history.record("c", force: true)
        let r4 = history.undo(from: "c")
        #expect(r4 == "b")
        let r5 = history.undo(from: "b")
        #expect(r5 == "a")
        let r6 = history.undo(from: "a")
        #expect(r6 == nil)
        let r7 = history.redo(from: "a")
        #expect(r7 == "b")
        #expect(history.canRedo)
        // A new change clears redo.
        history.record("x", force: true)
        #expect(!history.canRedo)
    }

    @Test func undoRecordsAPendingChangeFirst() {
        var history = RecipeEditHistory()
        history.reset(recipeId: "r", content: "a")
        history.record("typing", force: false)
        let r8 = history.undo(from: "typing")
        #expect(r8 == "a")
        let r9 = history.redo(from: "a")
        #expect(r9 == "typing")
    }

    @Test func historyIsLimited() {
        var history = RecipeEditHistory()
        history.reset(recipeId: "r", content: "0")
        for step in 1...150 { history.record("\(step)", force: true) }
        #expect(history.undoCount == RecipeEditHistory.maxSteps)
    }

    @Test func keptPerRecipeAndPastASave() {
        var history = RecipeEditHistory()
        history.reset(recipeId: "one", content: "a")
        history.record("b", force: true)
        history.keep(recipeId: "one")
        history.reset(recipeId: "two", content: "x")
        #expect(!history.canUndo)
        history.keep(recipeId: "two")
        // Back to "one" as it was left: its undo is there.
        history.reset(recipeId: "One", content: "b")
        let r10 = history.undo(from: "b")
        #expect(r10 == "a")
    }

    @Test func aRecipeThatChangedMeanwhileUndoesToHowItWasLeft() {
        var history = RecipeEditHistory()
        history.reset(recipeId: "one", content: "a")
        history.record("b", force: true)
        history.keep(recipeId: "one")
        history.reset(recipeId: "one", content: "saved elsewhere")
        let r11 = history.undo(from: "saved elsewhere")
        #expect(r11 == "b")
        let r12 = history.undo(from: "b")
        #expect(r12 == "a")
    }
}
