// Greenshot for Mac (Community) - an unofficial macOS port of Greenshot
// Copyright (C) 2026 Greenshot for Mac (Community) contributors
// Based on Greenshot, Copyright (C) 2007-2026 Thomas Braun, Jens Klingen, Robin Krom
// SPDX-License-Identifier: GPL-3.0-or-later

import Foundation
import Testing
@testable import GreenshotCore

/// Calls the editor hook of an approved proposal.
@MainActor
final class OpenedInEditor {
    var ids: [String] = []
}

/// Upstream RecipeManager.ExtensionFiles: automatic step files loaded, approved, dropped, revoked, saved and proposed.
@MainActor
@Suite struct RecipeExtensionLibraryTests {
    func fileExtension(_ id: String = "lib_ext", slot: String = "BeforeExport", recipes: [String] = ["*capture"]) -> CaptureRecipe {
        var ext = ComposerFixture.ext(id, recipes: recipes, slot: slot)
        ext.options = [RecipeOption(key: "enabled", type: .boolean, defaultValue: .bool(true))]
        return ext
    }

    func fileExtensions(_ library: RecipeLibrary) -> [LoadedRecipe] {
        library.extensions.filter { !$0.isBuiltIn }
    }

    @Test func anApprovedFileChangesTheRecipes() async throws {
        let fixture = LibraryFixture(builtIns: [ComposerFixture.recipe()])
        defer { fixture.cleanUp() }
        let url = try fixture.write(fileExtension(), name: "ext.gsrecipe.json")
        let result = await fixture.library.loadFile(url)
        #expect(result.errors.isEmpty)
        #expect(result.loadedRecipeIds == ["lib_ext"])
        let request = try #require(fixture.approver.requests.first)
        #expect(request.recipe?.kind == .extension)
        #expect(request.triggers.isEmpty)
        let reach = try #require(request.extensionReach)
        #expect(reach.first == "• Changes these recipes now: Capture cap.")
        #expect(reach.contains("• Also every capture recipe added later (\"*capture\")."))
        #expect(reach.contains("• Where: once before the destinations, when the image is final."))
        let loaded = try #require(fileExtensions(fixture.library).first)
        #expect(loaded.fileURL?.lastPathComponent == "ext.gsrecipe.json")
        #expect(fixture.box.settings.files.count == 1)
        let recipe = ComposerFixture.recipe()
        let effective = fixture.library.effectiveRecipe(recipe)
        #expect(effective != recipe)
        #expect(ComposerFixture.ids(effective).contains("lib_ext/a"))
        #expect(fixture.library.extensionsChanging(recipeId: "cap").map(\.recipe.id) == ["lib_ext"])
        // Switched off: the recipe runs as loaded.
        fixture.library.setExtensionEnabled(false, id: "lib_ext")
        #expect(fixture.library.effectiveRecipe(recipe) == recipe)
    }

    /// CAP-012's routing: a stock capture recipe stays `==` itself while no automatic step is switched on.
    @Test func stockRecipesStayUnchangedUntilAnAutomaticStepIsOn() throws {
        let fixture = LibraryFixture()
        defer { fixture.cleanUp() }
        var region = ComposerFixture.recipe("recipe_region", slots: [])
        RecipeSlotNodes.addStandardSlots(to: &region, afterCaptureBefore: "export", exportNode: "export")
        let stock = fixture.library.effectiveRecipe(region)
        #expect(stock == region)
        fixture.library.setExtensionEnabled(true, id: RecipeBuiltInExtensions.borderId)
        let composed = fixture.library.effectiveRecipe(region)
        #expect(composed != region)
        let chains = try #require(composed.composition?.destinationChains)
        #expect(chains.map(\.extensionId) == ["ext_border"])
        #expect(fixture.library.effectiveRecipe(composed) == composed)
    }

    @Test func aRejectedFileIsNotUsed() async throws {
        let fixture = LibraryFixture(approver: StubApprover { _ in nil }, builtIns: [ComposerFixture.recipe()])
        defer { fixture.cleanUp() }
        let result = await fixture.library.loadFile(try fixture.write(fileExtension(), name: "ext.gsrecipe.json"))
        #expect(result.errors.first?.contains("User rejected automatic step") == true)
        #expect(fileExtensions(fixture.library).isEmpty)
        #expect(fixture.box.settings.files.isEmpty)
    }

    @Test func invalidFilesAreRefusedWithoutAsking() async throws {
        let fixture = LibraryFixture()
        defer { fixture.cleanUp() }
        // An automatic step can't extend another one.
        let onBorder = await fixture.library.loadFile(try fixture.write(fileExtension(recipes: ["ext_border"]), name: "a.gsrecipe.json"))
        #expect(onBorder.errors.first?.contains("can't extend another one") == true)
        let shown = try #require(fixture.approver.validationErrors.last)
        #expect(shown.errorMessage?.hasPrefix("The automatic step 'Ext lib_ext' can't be used:") == true)
        // One automatic step per file.
        let two = fixture.folder.appendingPathComponent("two.gsrecipe.json")
        try Data(RecipeSerializer.encode([fileExtension("one"), fileExtension("two")]).utf8).write(to: two)
        let twoResult = await fixture.library.loadFile(two)
        #expect(twoResult.errors.first?.contains("holds 2 automatic steps") == true)
        #expect(fixture.approver.requests.isEmpty)
    }

    @Test func aChangedFileIsDroppedUntilApprovedAgain() async throws {
        var approve = true
        let fixture = LibraryFixture(approver: StubApprover { approve ? StubApprover.approveAll($0) : nil }, builtIns: [ComposerFixture.recipe()])
        defer { fixture.cleanUp() }
        var ext = fileExtension()
        let url = try fixture.write(ext, name: "ext.gsrecipe.json")
        _ = await fixture.library.loadFile(url)
        #expect(fileExtensions(fixture.library).count == 1)
        // Changed behind the monitor's back: left out of the next run.
        ext.name = "Changed"
        try Data(RecipeSerializer.encode(ext).utf8).write(to: url)
        let recipe = ComposerFixture.recipe()
        #expect(fixture.library.effectiveRecipe(recipe) == recipe)
        // The monitor's call: dropped, asked again, and rejected.
        approve = false
        await fixture.library.fileDidChange(url)
        #expect(fileExtensions(fixture.library).isEmpty)
        #expect(fixture.library.effectiveRecipe(recipe) == recipe)
    }

    @Test func aFileReplacesABuiltInUntilUnloaded() async throws {
        let fixture = LibraryFixture()
        defer { fixture.cleanUp() }
        var border = RecipeBuiltInExtensions.border()
        border.name = "My border"
        let result = await fixture.library.loadFile(try fixture.write(border, name: "border.gsrecipe.json"))
        #expect(result.errors.isEmpty)
        let request = try #require(fixture.approver.requests.first)
        #expect(request.replacesBuiltIn)
        #expect(request.previousContent != nil)
        let loaded = try #require(fixture.library.loadedExtension(id: "ext_border"))
        #expect(loaded.replacesBuiltIn)
        #expect(loaded.recipe.name == "My border")
        #expect(fixture.library.extensions.count == 3)
        #expect(fixture.library.unloadExtension(id: "ext_border"))
        #expect(fixture.library.loadedExtension(id: "ext_border")?.isBuiltIn == true)
        #expect(fixture.box.settings.files.isEmpty)
        #expect(!fixture.library.unloadExtension(id: "ext_border"))
    }

    @Test func revokeAndReloadForgetTheFile() async throws {
        let fixture = LibraryFixture()
        defer { fixture.cleanUp() }
        let url = try fixture.write(fileExtension(), name: "ext.gsrecipe.json")
        _ = await fixture.library.loadFile(url)
        // Reload loads it again from the settings (already approved, nothing asked).
        _ = await fixture.library.reload()
        #expect(fileExtensions(fixture.library).count == 1)
        #expect(fixture.approver.requests.count == 1)
        #expect(fixture.library.revokeExtensionApproval(id: "lib_ext"))
        #expect(fileExtensions(fixture.library).isEmpty)
        #expect(fixture.box.settings.files.isEmpty)
        let hash = RecipeHash.sha256Hex(try Data(contentsOf: url))
        #expect(fixture.store.approval(forFile: url.path, sha256: hash, recipeId: "lib_ext") == nil)
        _ = await fixture.library.reload()
        #expect(fileExtensions(fixture.library).isEmpty)
    }

    @Test func anAIProposalStartsSwitchedOffAndOpensInTheEditor() async throws {
        let fixture = LibraryFixture(approver: StubApprover { request in
            RecipeApprovalDecision(approval: RecipeApproval(recipeId: request.recipe?.id ?? "", allowedGates: request.gates), openInEditor: true)
        })
        defer { fixture.cleanUp() }
        let opened = OpenedInEditor()
        fixture.library.openExtensionInEditor = { id in opened.ids.append(id) }
        let url = fixture.folder.appendingPathComponent("AI/proposed.gsrecipe.json")
        let result = await fixture.library.proposeExtension(content: RecipeSerializer.encode(fileExtension()), proposedBy: "Claude",
                                                            aiRequest: "a border", aiExplanation: "adds one", saveTo: url)
        #expect(result.errors.isEmpty)
        let request = try #require(fixture.approver.requests.first)
        #expect(request.startSwitchedOff)
        #expect(request.proposedBy == "Claude")
        #expect(request.extensionReach != nil)
        let loaded = try #require(fixture.library.loadedExtension(id: "lib_ext"))
        #expect(loaded.proposedBy == "Claude")
        #expect(!loaded.isEnabled)
        #expect(fixture.box.settings.optionValues["lib_ext.enabled"] == "False")
        #expect(FileManager.default.fileExists(atPath: url.path))
        #expect(opened.ids == ["lib_ext"])
        // A recipe is refused here.
        let recipe = await fixture.library.proposeExtension(content: RecipeSerializer.encode(libraryRecipe()), proposedBy: "Claude",
                                                            aiRequest: nil, aiExplanation: nil, saveTo: url)
        #expect(recipe.errors == ["An AI tool can propose one automatic step at a time."])
    }

    @Test func savingAsksOnlyWhenTheReachOrPermissionsChange() async throws {
        let fixture = LibraryFixture()
        defer { fixture.cleanUp() }
        let url = fixture.folder.appendingPathComponent("saved.gsrecipe.json")
        var ext = fileExtension()
        #expect(fixture.library.extensionSaveDecisionReasons(for: ext, at: url) == ["It is a new automatic step, which changes other recipes."])
        let first = await fixture.library.saveExtension(ext, to: url)
        #expect(first.errors.isEmpty)
        #expect(fixture.approver.requests.count == 1)
        ext.name = "Renamed"
        #expect(fixture.library.extensionSaveDecisionReasons(for: ext, at: url).isEmpty)
        let second = await fixture.library.saveExtension(ext, to: url)
        #expect(second.errors.isEmpty)
        #expect(fixture.approver.requests.count == 1)
        #expect(fixture.library.loadedExtension(id: "lib_ext")?.recipe.name == "Renamed")
        ext.extends?.slot = "AfterCapture"
        #expect(fixture.library.extensionSaveDecisionReasons(for: ext, at: url) == ["It changes other recipes than before (which recipes or where)."])
        #expect(fixture.library.extensionSaveDecisionReasons(for: RecipeBuiltInExtensions.border(), at: nil) == ["It replaces a built-in automatic step."])
        let refused = await fixture.library.saveExtension(libraryRecipe(), to: url)
        #expect(refused.errors.first?.contains("not an automatic step") == true)
    }

    @Test func extensionsPluggingIntoASlot() {
        let fixture = LibraryFixture()
        defer { fixture.cleanUp() }
        var recipe = ComposerFixture.recipe(slots: [])
        RecipeSlotNodes.addStandardSlots(to: &recipe, afterCaptureBefore: "export", exportNode: "export")
        fixture.library.setExtensionEnabled(true, id: "ext_caption")
        let slot = recipe.node("before_destination")!
        let plugged = fixture.library.extensionsPlugging(into: slot, of: recipe)
        #expect(plugged.map(\.loaded.recipe.id) == ["ext_caption", "ext_border", "ext_dropshadow"])
        #expect(plugged.map(\.isOn) == [true, false, false])
        #expect(fixture.library.extensionsPlugging(into: recipe.node("after_export")!, of: recipe).isEmpty)
    }

    @Test func detailsOfAnAutomaticStep() async throws {
        let fixture = LibraryFixture()
        defer { fixture.cleanUp() }
        let details = try #require(fixture.library.extensionDetails(id: "ext_border"))
        #expect(!details.whatItDoes.isEmpty)
        let request = try #require(fixture.library.extensionDetailsRequest(id: "ext_border"))
        #expect(request.isReadOnly)
        #expect(request.extensionReach?.isEmpty == false)
        await fixture.library.showDetails(id: "ext_border")
        #expect(fixture.approver.requests.last?.isReadOnly == true)
    }
}
