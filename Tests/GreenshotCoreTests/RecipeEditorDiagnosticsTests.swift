// Greenshot for Mac (Community) - an unofficial macOS port of Greenshot
// Copyright (C) 2026 Greenshot for Mac (Community) contributors
// Based on Greenshot, Copyright (C) 2007-2026 Thomas Braun, Jens Klingen, Robin Krom
// SPDX-License-Identifier: GPL-3.0-or-later

import Foundation
import Testing
@testable import GreenshotCore

@Suite struct RecipeEditorDiagnosticsTests {
    private let recipe = EditorFixtures.conditional()

    private func target(_ message: String) -> RecipeDiagnosticTarget {
        RecipeEditorDiagnostics.target(of: message, in: recipe)
    }

    @Test func messagesAboutSteps() {
        #expect(target("Node 'large' (Editor) is never executed: no path from a start node leads to it.") == .node("large"))
        #expect(target("Node 'SMALL' [Source]: Unknown SourceType 'x'.") == .node("small"))
        #expect(target("Duplicate node id 'decide' found in recipe.") == .node("decide"))
        #expect(target("Conditional transition target node 'ghost' (from 'decide', branch 'A') does not exist in 'nodes'.") == .node("decide"))
        #expect(target("Flow transition target node 'ghost' (from 'source') does not exist in 'nodes'.") == .node("source"))
        #expect(target("Conditional transition source node 'notify' has stepType 'Notification' rather than 'Conditional'.") == .node("notify"))
        #expect(target("Cycle/loop detected in recipe flow: large -> notify -> large. Loops are strictly disallowed in DAG flows.") == .node("large"))
        #expect(target("Node '1' is missing required 'stepType'.") == .node("decide"))
    }

    @Test func messagesAboutTriggersOptionsAndRoutes() {
        #expect(target("Trigger at index 2 has unrecognized triggerType 'X'.") == .trigger(2))
        #expect(target("Hotkey trigger 'Go' at index 0 is missing required 'Hotkey' parameter.") == .trigger(0))
        #expect(target("Option 'size': 'min' (5) is larger than 'max' (1).") == .option("size"))
        #expect(target("Option key '1x' is invalid: use letters, digits and underscores, starting with a letter.") == .option("1x"))
        #expect(target("Duplicate option key 'size'.") == .option("size"))
        #expect(target("Error transition to 'x' doesn't lead to a node of the extension.") == .errorRoutes)
        #expect(target("Recipe 'name' is required and cannot be empty.") == .recipe)
        #expect(target("Flow start node 'ghost' does not match any defined node id.") == .recipe)
    }

    @Test func validatorResultsAreAttributed() {
        var broken = recipe
        broken.nodes[0].parameters["SourceType"] = .string("Nowhere")
        let diagnostics = RecipeEditorDiagnostics.diagnostics(of: RecipeValidator().validate(broken), in: broken)
        #expect(diagnostics.contains { $0.isError && $0.target == .node("source") })
    }

    @Test func saveNotice() {
        #expect(RecipeEditorDiagnostics.saveNotice(reasons: []) == nil)
        #expect(RecipeEditorDiagnostics.saveNotice(reasons: ["It needs network access (uploads).", "Clipboard trigger"])
                == "Saving asks for your approval: It needs network access (uploads). Clipboard trigger.")
    }

    @Test func approvalNotices() {
        var details = RecipeDetails()
        details.isApprovalCurrent = false
        #expect(RecipeEditorDiagnostics.approvalNotice(details: details, fileExists: true)?.contains("isn't approved yet") == true)
        details.approvedHash = "abc"
        #expect(RecipeEditorDiagnostics.approvalNotice(details: details, fileExists: true)?.contains("changed outside Greenshot") == true)
        details.isApprovalCurrent = true
        #expect(RecipeEditorDiagnostics.approvalNotice(details: details, fileExists: true) == nil)
        details.triggers = [RecipeTriggerDescription(key: "0:Clipboard", label: "Runs when an image is copied (off, not approved)"),
                            RecipeTriggerDescription(key: "1:Hotkey", label: "Hotkey ⌘⇧B (on)")]
        #expect(RecipeEditorDiagnostics.approvalNotice(details: details, fileExists: true)
                == "1 trigger was left off when this recipe was approved: \"Runs when an image is copied\". Review the approval to switch it on.")
        details.triggers.append(RecipeTriggerDescription(key: "2:AiTool", label: "AI tool (off, not approved)"))
        #expect(RecipeEditorDiagnostics.approvalNotice(details: details, fileExists: true)?.hasPrefix("2 triggers were left off") == true)
        #expect(RecipeEditorDiagnostics.approvalNotice(details: nil, fileExists: true) == nil)
    }

    @Test func testRunRule() {
        var withUpload = EditorFixtures.recipe(["a:Source", "up:Jira"], ["a>up"])
        withUpload.nodes[1].parameters["IssueKey"] = .string("X-1")
        let validation = RecipeValidator().validate(withUpload)
        #expect(validation.gateTypes == [.networkAccess])
        let approved = validation.gatedActions
        // No approval that belongs to this copy: save first.
        let none = RecipeEditorDiagnostics.testRunDecision(withUpload, validation: validation, isDirty: true, isLoaded: true, approvedActions: [])
        #expect(none == .saveFirst([.networkAccess]))
        // The approved version has exactly these actions.
        let covered = RecipeEditorDiagnostics.testRunDecision(withUpload, validation: validation, isDirty: true, isLoaded: true,
                                                              approvedActions: approved)
        #expect(covered == .run)
        let unchanged = RecipeEditorDiagnostics.testRunDecision(withUpload, validation: validation, isDirty: false, isLoaded: true,
                                                                approvedActions: [])
        #expect(unchanged == .run)
        let notLoaded = RecipeEditorDiagnostics.testRunDecision(withUpload, validation: validation, isDirty: false, isLoaded: false,
                                                                approvedActions: [])
        #expect(notLoaded == .saveFirst([.networkAccess]))
        var invalid = RecipeValidationResult()
        invalid.errors = ["broken"]
        let broken = RecipeEditorDiagnostics.testRunDecision(withUpload, validation: invalid, isDirty: true, isLoaded: true, approvedActions: [])
        #expect(broken == .invalid(["broken"]))
        let ext = RecipeEditorDiagnostics.testRunDecision(RecipeEditorCatalog.newExtension(), validation: validation, isDirty: false,
                                                          isLoaded: true, approvedActions: [])
        #expect(ext == .automaticStep)
    }

    /// R-F12: a changed target of an allowed gate type (another program) is not covered by the approval.
    @Test func testRunComparesTargetsNotOnlyTypes() {
        var recipe = EditorFixtures.recipe(["a:Source", "run:ExternalCommand"], ["a>run"])
        recipe.nodes[1].parameters["CommandLine"] = .string("/usr/local/bin/optipng")
        let approvedVersion = RecipeValidator().validate(recipe)
        var approval = RecipeApproval(recipeId: recipe.id)
        approval.allowedGates = [.externalCommand]
        let actions = RecipeEditorDiagnostics.approvedActions(of: approvedVersion, approval: approval)
        #expect(actions.count == 1)
        recipe.nodes[1].parameters["CommandLine"] = .string("/bin/rm")
        let changed = RecipeValidator().validate(recipe)
        let decision = RecipeEditorDiagnostics.testRunDecision(recipe, validation: changed, isDirty: true, isLoaded: true, approvedActions: actions)
        #expect(decision == .saveFirst([.externalCommand]))
        // A gate type the approval doesn't allow gives no actions.
        let nothing = RecipeEditorDiagnostics.approvedActions(of: approvedVersion, approval: RecipeApproval(recipeId: recipe.id))
        #expect(nothing.isEmpty)
        #expect(RecipeEditorDiagnostics.approvedActions(of: approvedVersion, approval: nil).isEmpty)
    }

    // MARK: Files (W-H1, W-H2)

    @Test func overwriteNamesWhatSavingRemoves() {
        var mine = EditorFixtures.recipe(["a:Source"])
        mine.id = "mine"
        var other = EditorFixtures.recipe(["b:Source"])
        other.id = "other"
        other.name = "Other Recipe"
        let both = Data(RecipeSerializer.encode([mine, other]).utf8)
        #expect(RecipeEditorFiles.overwrite(saving: mine, existing: nil) == .none)
        #expect(RecipeEditorFiles.overwrite(saving: mine, existing: Data(RecipeSerializer.encode(mine).utf8)) == .none)
        #expect(RecipeEditorFiles.overwrite(saving: mine, existing: both) == .removes(["Other Recipe"]))
        // One other recipe alone is removed too.
        #expect(RecipeEditorFiles.overwrite(saving: mine, existing: Data(RecipeSerializer.encode(other).utf8)) == .removes(["Other Recipe"]))
        // ...unless it is this recipe under its old id (renamed in the editor, saved to its own file).
        #expect(RecipeEditorFiles.overwrite(saving: mine, existing: Data(RecipeSerializer.encode(other).utf8), ownIds: ["other"]) == .none)
        #expect(RecipeEditorFiles.overwrite(saving: mine, existing: both, ownIds: ["other"]) == .removes(["Other Recipe"]))
        #expect(RecipeEditorFiles.overwrite(saving: mine, existing: Data("{\"hello\": 1}".utf8)) == .notARecipe)
        #expect(RecipeEditorFiles.overwrite(saving: mine, existing: Data()) == .none)
        // An automatic step with the same id is another thing.
        var ext = RecipeEditorCatalog.newExtension()
        ext.id = "mine"
        #expect(RecipeEditorFiles.overwrite(saving: mine, existing: Data(RecipeSerializer.encode(ext).utf8)) == .removes([ext.name]))
    }

    @Test func recipeFileNames() {
        let folder = URL(fileURLWithPath: "/tmp/recipes")
        #expect(RecipeEditorFiles.recipeFileURL(for: folder.appendingPathComponent("Capture.json")).lastPathComponent == "Capture.gsrecipe.json")
        #expect(RecipeEditorFiles.recipeFileURL(for: folder.appendingPathComponent("Capture")).lastPathComponent == "Capture.gsrecipe.json")
        #expect(RecipeEditorFiles.recipeFileURL(for: folder.appendingPathComponent("a.GSRECIPE.json")).lastPathComponent == "a.GSRECIPE.json")
        let taken: Set<String> = ["/tmp/recipes/r1.gsrecipe.json", "/tmp/recipes/r1 2.gsrecipe.json"]
        let free = RecipeEditorFiles.freeFileURL(for: "r1", in: folder) { taken.contains($0.path) }
        #expect(free.lastPathComponent == "r1 3.gsrecipe.json")
        #expect(RecipeEditorFiles.freeFileURL(for: "", in: folder) { _ in false }.lastPathComponent == "recipe.gsrecipe.json")
    }
}
