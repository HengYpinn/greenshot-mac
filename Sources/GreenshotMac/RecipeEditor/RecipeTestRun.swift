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
            await tell(String(localized: "Test Run"), detail: String(localized: "Recipes aren't running in Greenshot right now."))
            return
        }
        let coverage = testRunCoverage(recipe, library: runtime.library)
        switch RecipeEditorDiagnostics.testRunDecision(recipe, validation: validation, isDirty: isDirty || !coverage.isLoaded,
                                                       isLoaded: coverage.isLoaded, approvedActions: coverage.actions) {
        case .automaticStep:
            await tell(String(localized: "Test Run"),
                       detail: String(localized: "An automatic step runs inside the recipes it changes: save it, switch it on in Settings › Recipes and test run one of those recipes."),
                       style: .informational)
            return
        case .invalid(let errors):
            let list = errors.joined(separator: "\n")
            await tell(String(localized: "Validation Error"), detail: String(localized: "Cannot test run recipe. Fix validation errors first:") + "\n\n" + list)
            return
        case .saveFirst(let gates):
            let names = gates.map(\.displayName).joined(separator: ", ")
            let answer = await ask(String(localized: "Save Before the Test Run"),
                                   detail: String(localized: "The changed recipe needs \(names), which its approval doesn't allow yet. Save it first; saving asks for your approval."),
                                   buttons: [String(localized: "Save and Run"), String(localized: "Cancel")])
            guard answer == 0, await save() else { return }
            await testRun()
            return
        case .run:
            break
        }
        let name = recipe.name
        status = String(localized: "Executing test run for '\(name)'...")
        var request = RecipeRunRequest(recipe: recipe, trigger: RecipeRuntime.triggerInfo(type: WellKnownTriggerType.contextMenu,
                                                                                           name: "Test Run Trigger"))
        request.optionValues = runtime.library.optionValues
        let result = await runtime.start(request).result
        log.info("Test run of recipe '\(recipe.id)' ended: \(result.state.rawValue).")
        if result.state == .cancelled, let reason = result.reason {
            // The runner's preflight refused the copy (its approval doesn't cover it) or another flow was running.
            status = String(localized: "Test run not started: \(reason)")
            await tell(String(localized: "Test Run"), detail: reason, style: .informational)
        } else if result.state == .failed {
            let error = result.errorDescription ?? result.reason ?? String(localized: "unknown error")
            status = String(localized: "Test run error: \(error)")
            await tell(String(localized: "Execution Error"), detail: String(localized: "Recipe execution encountered an error:") + "\n" + error, style: .critical)
        } else {
            let state = result.state.rawValue
            status = String(localized: "Test run of '\(name)' ended: \(state).")
        }
    }

    /// The approval a test run may use (S-M2): the approved version loaded from this file, or the built-in recipe for an
    /// unsaved edit of a built-in; a copy from another file with the same id gets nothing. `isLoaded`: the copy is that
    /// version unchanged.
    private func testRunCoverage(_ recipe: CaptureRecipe, library: RecipeLibrary) -> (isLoaded: Bool, actions: [RecipeGatedAction]) {
        let loaded = library.recipe(id: recipe.id)
        let sameFile: Bool
        if let source = loaded?.sourceFile, let fileURL {
            sameFile = RecipeEditorFiles.standardized(source).path == RecipeEditorFiles.standardized(fileURL).path
        } else {
            sameFile = false
        }
        if let loaded, sameFile {
            let unchanged = RecipeSerializer.encode(loaded.recipe) == content
            return (unchanged, RecipeEditorDiagnostics.approvedActions(of: loaded.validation, approval: loaded.approval))
        }
        if fileURL == nil, let builtIn = library.builtInRecipe(id: recipe.id), loaded?.isBuiltIn ?? true {
            // A built-in recipe's own permissions need no approval.
            let actions = RecipeValidator(contracts: contracts, gates: environment.gates()).validate(builtIn).gatedActions
            return (RecipeSerializer.encode(builtIn) == content, actions)
        }
        return (false, [])
    }
}
