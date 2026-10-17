// Greenshot for Mac (Community) - an unofficial macOS port of Greenshot
// Copyright (C) 2026 Greenshot for Mac (Community) contributors
// Based on Greenshot, Copyright (C) 2007-2026 Thomas Braun, Jens Klingen, Robin Krom
// SPDX-License-Identifier: GPL-3.0-or-later

import Foundation
import Testing
@testable import GreenshotCore

/// Which way the app's own captures go (CAP-012), and which recipe takes a capture of the browser extension (upstream
/// `CaptureHelper.ImportExtensionCapture`).
@Suite struct RecipeBuiltInRouteTests {
    let stock = LoadedRecipe(recipe: BuiltInRecipes.region, source: .builtIn)

    @Test func recipesOffIsTheAppsOwnCapture() {
        #expect(BuiltInCaptureRoute.decision(featureEnabled: false, loaded: stock, composed: nil) == .direct)
        var switchedOff = stock
        switchedOff.isEnabled = false
        #expect(BuiltInCaptureRoute.decision(featureEnabled: false, loaded: switchedOff, composed: nil) == .direct)
        #expect(BuiltInCaptureRoute.decision(featureEnabled: true, loaded: nil, composed: nil) == .direct)
    }

    @Test func stockBuiltInIsTheAppsOwnCapture() {
        #expect(BuiltInCaptureRoute.decision(featureEnabled: true, loaded: stock, composed: nil) == .direct)
        #expect(BuiltInCaptureRoute.decision(featureEnabled: true, loaded: stock, composed: stock.recipe) == .direct)
    }

    @Test func aFileReplacingTheBuiltInRunsTheRecipe() {
        var replaced = BuiltInRecipes.region
        replaced.name = "My region"
        let loaded = LoadedRecipe(recipe: replaced, source: .file(URL(fileURLWithPath: "/tmp/region.gsrecipe.json")), replacesBuiltIn: true)
        #expect(BuiltInCaptureRoute.decision(featureEnabled: true, loaded: loaded, composed: replaced) == .recipe)
    }

    @Test func anAutomaticStepRunsTheRecipe() {
        var composed = stock.recipe
        composed.nodes.append(RecipeNode(id: "ext_border/border", stepType: WellKnownStepType.effect))
        #expect(BuiltInCaptureRoute.decision(featureEnabled: true, loaded: stock, composed: composed) == .recipe)
    }

    @Test func aSwitchedOffBuiltInCapturesNothing() {
        var switchedOff = stock
        switchedOff.isEnabled = false
        #expect(BuiltInCaptureRoute.decision(featureEnabled: true, loaded: switchedOff, composed: nil) == .off)
    }

    // MARK: The browser extension's capture

    func recipe(_ id: String, browser: String?, enabled: Bool = true, triggerOn: Bool = true) -> LoadedRecipe {
        var recipe = CaptureRecipe(id: id, name: id)
        var parameters: JSONObject = [:]
        if let browser { parameters["Browser"] = .string(browser) }
        var trigger = TriggerConfig(triggerType: WellKnownTriggerType.extension, parameters: parameters)
        trigger.enabled = triggerOn
        recipe.triggers = [trigger]
        // A file recipe's trigger counts once its approval says so.
        var approval = RecipeApproval(recipeId: id)
        approval.allTriggers = true
        return LoadedRecipe(recipe: recipe, source: .file(URL(fileURLWithPath: "/tmp/\(id).json")), isEnabled: enabled, approval: approval)
    }

    var builtIns: [LoadedRecipe] {
        [LoadedRecipe(recipe: BuiltInRecipes.browserExtension, source: .builtIn)]
    }

    @Test func theBuiltInTakesItWithoutARecipeOfOnesOwn() {
        let pick = RecipeExtensionCapturePick.pick(builtIns, browser: "Chrome")
        #expect(pick.recipeId == BuiltInRecipes.browserExtensionId)
    }

    @Test func aRecipeForThatBrowserComesFirst() {
        let recipes = builtIns + [recipe("firefox_only", browser: "Firefox"), recipe("chrome_only", browser: "chrome")]
        let pick = RecipeExtensionCapturePick.pick(recipes, browser: "Chrome")
        #expect(pick.recipeId == "chrome_only")
        #expect(pick.triggerIndex == 0)
    }

    @Test func aRecipeWithoutBrowserTakesEveryBrowser() {
        let pick = RecipeExtensionCapturePick.pick(builtIns + [recipe("any_browser", browser: nil)], browser: "Edge")
        #expect(pick.recipeId == "any_browser")
    }

    @Test func switchedOffRecipesAndTriggersDontCount() {
        let recipes = builtIns + [recipe("off", browser: nil, enabled: false), recipe("trigger_off", browser: nil, triggerOn: false)]
        let pick = RecipeExtensionCapturePick.pick(recipes, browser: "Safari")
        #expect(pick.recipeId == BuiltInRecipes.browserExtensionId)
    }

    @Test func withoutTheBuiltInTheFallbackIsStillItsId() {
        let pick = RecipeExtensionCapturePick.pick([], browser: nil)
        #expect(pick.recipeId == BuiltInRecipes.browserExtensionId)
        #expect(pick.triggerIndex == nil)
    }
}
