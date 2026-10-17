// Greenshot for Mac (Community) - an unofficial macOS port of Greenshot
// Copyright (C) 2026 Greenshot for Mac (Community) contributors
// Based on Greenshot, Copyright (C) 2007-2026 Thomas Braun, Jens Klingen, Robin Krom
// SPDX-License-Identifier: GPL-3.0-or-later

import Foundation
@testable import GreenshotCore
import Testing

/// Files opened with Greenshot (RCP-069, upstream `IpcSecurityDispatcher.HandleOpenFileAsync`).
struct RecipeTriggersRoutingTests {
    static let png = URL(fileURLWithPath: "/tmp/Shot.PNG")
    static let jpeg = URL(fileURLWithPath: "/tmp/photo.jpg")

    static func openFile(_ recipeId: String, filter: String? = nil, fireAndForget: Bool = false, index: Int = 0) -> ActiveRecipeTrigger {
        var parameters: JSONObject = [:]
        if let filter { parameters["Filter"] = .string(filter) }
        if fireAndForget { parameters["FireAndForget"] = .bool(true) }
        return ActiveRecipeTrigger(recipeId: recipeId, recipeName: recipeId, index: index,
                                   trigger: TriggerConfig(triggerType: WellKnownTriggerType.openFile, parameters: parameters))
    }

    @Test func noOpenFileTriggerOpensTheEditor() {
        let plan = RecipeOpenFileRouting.plan(files: [Self.png], active: [], anyDefined: false)
        #expect(plan.kind == .editor)
        #expect(plan.runs.isEmpty)
    }

    @Test func onlyInactiveTriggersSkipTheFiles() {
        let plan = RecipeOpenFileRouting.plan(files: [Self.png], active: [], anyDefined: true)
        #expect(plan.kind == .skipped)
        #expect(RecipeOpenFileRouting.skippedReply == "File opening skipped: all OpenFileTrigger recipes are disabled.")
    }

    @Test func everyMatchingTriggerRunsForEveryFile() {
        let triggers = [Self.openFile("all"), Self.openFile("png_only", filter: ".png"), Self.openFile("jpeg_only", filter: ".jpg;.jpeg")]
        let plan = RecipeOpenFileRouting.plan(files: [Self.png, Self.jpeg], active: triggers, anyDefined: true)
        #expect(plan.kind == .run)
        let runs = plan.runs.map { "\($0.file.lastPathComponent)->\($0.trigger.recipeId)" }
        #expect(runs == ["Shot.PNG->all", "Shot.PNG->png_only", "photo.jpg->all", "photo.jpg->jpeg_only"])
    }

    @Test func aFileNoFilterMatchesGetsNoRun() {
        let plan = RecipeOpenFileRouting.plan(files: [Self.jpeg], active: [Self.openFile("png_only", filter: ".png")], anyDefined: true)
        #expect(plan.kind == .run)
        #expect(plan.runs.isEmpty)
    }

    @Test func filterIgnoresCaseAndBlanks() {
        #expect(RecipeOpenFileRouting.matches(filter: " .PNG ; .gif", file: Self.png))
        #expect(RecipeOpenFileRouting.matches(filter: nil, file: Self.jpeg))
        #expect(RecipeOpenFileRouting.matches(filter: ";", file: Self.jpeg))
        #expect(!RecipeOpenFileRouting.matches(filter: ".png", file: URL(fileURLWithPath: "/tmp/README")))
    }

    @Test func otherTriggerTypesDontCount() {
        let menu = ActiveRecipeTrigger(recipeId: "m", recipeName: "m", index: 0, trigger: TriggerConfig(triggerType: WellKnownTriggerType.contextMenu))
        let plan = RecipeOpenFileRouting.plan(files: [Self.png], active: [menu], anyDefined: false)
        #expect(plan.kind == .editor)
    }

    @Test func definedTriggersCountSwitchedOffOnes() {
        var recipe = CaptureRecipe(id: "r", name: "R")
        var trigger = TriggerConfig(triggerType: WellKnownTriggerType.openFile)
        trigger.enabled = false
        recipe.triggers = [trigger]
        #expect(RecipeOpenFileRouting.definesOpenFileTrigger([LoadedRecipe(recipe: recipe, source: .builtIn, isEnabled: false)]))
        #expect(!RecipeOpenFileRouting.definesOpenFileTrigger([LoadedRecipe(recipe: CaptureRecipe(id: "x", name: "X"), source: .builtIn)]))
    }

    /// R-F11: only the stock "Open file" recipe took the files: they open as before.
    @Test func onlyTheStockRecipeOpensAsBefore() {
        #expect(RecipeOpenFileRouting.opensAsBefore(files: [Self.png, Self.jpeg], direct: [Self.jpeg, Self.png], recipeRuns: 0))
        #expect(!RecipeOpenFileRouting.opensAsBefore(files: [Self.png, Self.jpeg], direct: [Self.png, Self.jpeg], recipeRuns: 1))
        #expect(!RecipeOpenFileRouting.opensAsBefore(files: [Self.png, Self.jpeg], direct: [Self.png], recipeRuns: 0))
        #expect(!RecipeOpenFileRouting.opensAsBefore(files: [], direct: [], recipeRuns: 0))
    }

    @Test func fireAndForgetIsTheTriggers() {
        let plan = RecipeOpenFileRouting.plan(files: [Self.png], active: [Self.openFile("quick", fireAndForget: true)], anyDefined: true)
        let run = plan.runs.first
        #expect(run?.trigger.trigger.fireAndForget == true)
        #expect(RecipeOpenFileRouting.summary(files: 2, runs: 3) == "Opened 2 file(s) with 3 recipe execution(s).")
    }
}
