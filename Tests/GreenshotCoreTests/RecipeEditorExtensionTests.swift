// Greenshot for Mac (Community) - an unofficial macOS port of Greenshot
// Copyright (C) 2026 Greenshot for Mac (Community) contributors
// Based on Greenshot, Copyright (C) 2007-2026 Thomas Braun, Jens Klingen, Robin Krom
// SPDX-License-Identifier: GPL-3.0-or-later

import Foundation
import Testing
@testable import GreenshotCore

/// RCP-300 end to end on the Core side: the editor's new automatic step is saved through the library, listed, opened
/// again by id, and plugs into the standard slot of the editor's new recipe.
@MainActor
@Suite struct RecipeEditorExtensionTests {
    @Test func newAutomaticStepSavesListsAndPlugsIn() async throws {
        let fixture = LibraryFixture()
        defer { fixture.cleanUp() }
        var ext = RecipeEditorCatalog.newExtension()
        let url = fixture.folder.appendingPathComponent("\(ext.id).gsrecipe.json")
        #expect(!fixture.library.extensionSaveDecisionReasons(for: ext, at: url).isEmpty)
        let saved = await fixture.library.saveExtension(ext, to: url)
        #expect(saved.errors.isEmpty, "\(saved.errors)")
        #expect(fixture.approver.requests.count == 1)
        let listed = try #require(fixture.library.extensions.first { $0.recipe.id == ext.id })
        #expect(listed.sourceFile.map { RecipeEditorFiles.standardized($0).path } == RecipeEditorFiles.standardized(url).path)
        // A plain change saves without asking again.
        ext.name = "Renamed Step"
        let again = await fixture.library.saveExtension(ext, to: url)
        #expect(again.errors.isEmpty)
        #expect(fixture.approver.requests.count == 1)
        // It plugs into the editor's new recipe (BeforeDestination, every capture).
        let recipe = RecipeEditorCatalog.newRecipe()
        let slot = try #require(recipe.node("before_destination"))
        let plugged = fixture.library.extensionsPlugging(into: slot, of: recipe)
        #expect(plugged.contains { $0.loaded.recipe.id == ext.id })
        // A recipe can't be saved as an automatic step.
        let refused = await fixture.library.saveExtension(recipe, to: url)
        #expect(!refused.errors.isEmpty)
    }
}
