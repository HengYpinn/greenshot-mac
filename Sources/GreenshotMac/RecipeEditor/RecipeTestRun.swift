// Greenshot for Mac (Community) - an unofficial macOS port of Greenshot
// Copyright (C) 2026 Greenshot for Mac (Community) contributors
// Based on Greenshot, Copyright (C) 2007-2026 Thomas Braun, Jens Klingen, Robin Krom
// SPDX-License-Identifier: GPL-3.0-or-later

import AppKit
import GreenshotCore

private let log = Log("RecipeEditor")

/// "Test Run" (upstream RecipeEditorViewModel.cs:1975 `ExecuteTestRunAsync`, ViewModels/TestRun.cs): the editor's copy runs
/// through the app's runner like every other flow, prepared like upstream's `PrepareForTestRun` (a menu-entry trigger).
extension RecipeEditorModel {
    func testRun() async {
        guard let recipe else { return }
        guard let runtime = environment.runtime() else {
            await tell("Test Run", detail: "Recipes aren't running in Greenshot right now.")
            return
        }
        let loaded = runtime.library.recipe(id: recipe.id)
        var allowed = loaded?.approval?.allowedGates ?? []
        if loaded?.isBuiltIn == true || (loaded == nil && runtime.library.builtInRecipe(id: recipe.id) != nil) {
            // A built-in recipe's own permissions need no approval.
            let builtIn = runtime.library.builtInRecipe(id: recipe.id) ?? recipe
            allowed = RecipeValidator(contracts: contracts, gates: environment.gates()).validate(builtIn).gateTypes
        }
        let isLoaded = loaded.map { RecipeSerializer.encode($0.recipe) == content } ?? false
        switch RecipeEditorDiagnostics.testRunDecision(recipe, validation: validation, isDirty: isDirty || !isLoaded,
                                                       isLoaded: loaded != nil, allowedGates: allowed) {
        case .automaticStep:
            await tell("Test Run", detail: "An automatic step runs inside the recipes it changes: save it, switch it on in Settings › Recipes and test run one of those recipes.",
                       style: .informational)
            return
        case .invalid(let errors):
            await tell("Validation Error", detail: "Cannot test run recipe. Fix validation errors first:\n\n" + errors.joined(separator: "\n"))
            return
        case .saveFirst(let gates):
            let names = gates.map(\.displayName).joined(separator: ", ")
            let answer = await ask("Save Before the Test Run",
                                   detail: "The changed recipe needs \(names), which its approval doesn't allow yet. Save it first; saving asks for your approval.",
                                   buttons: ["Save and Run", "Cancel"])
            guard answer == 0, await save() else { return }
            await testRun()
            return
        case .run:
            break
        }
        status = "Executing test run for '\(recipe.name)'..."
        var request = RecipeRunRequest(recipe: recipe, trigger: RecipeRuntime.triggerInfo(type: WellKnownTriggerType.contextMenu,
                                                                                           name: "Test Run Trigger"))
        request.optionValues = runtime.library.optionValues
        let result = await runtime.start(request).result
        log.info("Test run of recipe '\(recipe.id)' ended: \(result.state.rawValue).")
        if result.state == .failed {
            let error = result.errorDescription ?? result.reason ?? "unknown error"
            status = "Test run error: \(error)"
            await tell("Execution Error", detail: "Recipe execution encountered an error:\n\(error)", style: .critical)
        } else {
            status = "Test run of '\(recipe.name)' ended: \(result.state.rawValue)."
        }
    }
}
