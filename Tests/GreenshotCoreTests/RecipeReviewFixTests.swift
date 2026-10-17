// Greenshot for Mac (Community) - an unofficial macOS port of Greenshot
// Copyright (C) 2026 Greenshot for Mac (Community) contributors
// Based on Greenshot, Copyright (C) 2007-2026 Thomas Braun, Jens Klingen, Robin Krom
// SPDX-License-Identifier: GPL-3.0-or-later

import Foundation
import Testing
@testable import GreenshotCore

/// Wave 4 review fixes of the recipe library: the preflight runs only what was approved (S-M2, R-F12), unloading one
/// recipe of a file sticks (W-M4), and a matched command runs exactly that recipe and trigger (MC-M1).
@MainActor
@Suite struct RecipeReviewFixTests {
    func command(_ commandLine: String, arguments: String = "-o2") -> RecipeNode {
        RecipeNode(id: "run", stepType: "ExternalCommand", parameters: ["CommandLine": .string(commandLine), "Arguments": .string(arguments)])
    }

    /// Source, Clipboard, an approved external command and a text annotation.
    func approvedRecipe() -> CaptureRecipe {
        var recipe = libraryRecipe(extraNode: command("/usr/bin/optipng"))
        recipe.nodes.append(RecipeNode(id: "stamp", stepType: "Annotation", parameters: ["Type": .string("Text"), "Text": .string("Draft")]))
        recipe.flow.addTransition(from: "run", to: "stamp")
        return recipe
    }

    func node(_ id: String, in recipe: CaptureRecipe) -> Int {
        recipe.nodes.firstIndex { $0.id == id } ?? 0
    }

    // MARK: S-M2, R-F12: the preflight

    @Test func preflightRunsOnlyWhatWasApproved() async throws {
        let fixture = LibraryFixture()
        defer { fixture.cleanUp() }
        _ = await fixture.library.loadFile(try fixture.write(approvedRecipe()))
        let loaded = try #require(fixture.library.recipe(id: "lib_recipe")).recipe
        let same = await fixture.library.ensureApprovedAndCurrent(loaded)
        #expect(same == loaded)

        // An edit of the annotation's text only: nothing gated changed, it runs.
        var textOnly = loaded
        textOnly.nodes[node("stamp", in: loaded)].parameters["Text"] = .string("Final")
        let edited = await fixture.library.ensureApprovedAndCurrent(textOnly)
        #expect(edited == textOnly)

        // Another program, other arguments of the same program: refused.
        var otherProgram = loaded
        otherProgram.nodes[node("run", in: loaded)] = command("/bin/rm")
        let program = await fixture.library.ensureApprovedAndCurrent(otherProgram)
        #expect(program == nil)
        var otherArguments = loaded
        otherArguments.nodes[node("run", in: loaded)] = command("/usr/bin/optipng", arguments: "-o7 /etc/hosts")
        let arguments = await fixture.library.ensureApprovedAndCurrent(otherArguments)
        #expect(arguments == nil)

        // A foreign file opened in the editor that reuses the approved id and adds its own command: refused.
        var foreign = libraryRecipe()
        foreign.nodes.append(RecipeNode(id: "evil", stepType: "ExternalCommand", parameters: ["CommandLine": .string("/tmp/payload")]))
        foreign.flow.addTransition(from: "b", to: "evil")
        let refused = await fixture.library.ensureApprovedAndCurrent(foreign)
        #expect(refused == nil)
        // The file on disk wasn't touched: no approval was asked for.
        #expect(fixture.approver.requests.count == 1)
    }

    @Test func anotherFolderOrUploadIsAnotherAction() async throws {
        let fixture = LibraryFixture()
        defer { fixture.cleanUp() }
        let save = RecipeNode(id: "save", stepType: "SaveFile", parameters: ["SaveDirectory": .string("/tmp/shots")])
        _ = await fixture.library.loadFile(try fixture.write(libraryRecipe(extraNode: save)))
        let loaded = try #require(fixture.library.recipe(id: "lib_recipe")).recipe
        var elsewhere = loaded
        elsewhere.nodes[node("save", in: loaded)].parameters["SaveDirectory"] = .string("/tmp/Shots")
        let folder = await fixture.library.ensureApprovedAndCurrent(elsewhere)
        #expect(folder == nil)
        var upload = loaded
        upload.nodes[node("save", in: loaded)] = RecipeNode(id: "save", stepType: "Jira")
        let jira = await fixture.library.ensureApprovedAndCurrent(upload)
        #expect(jira == nil)
    }

    @Test func builtInIdsAndNewRecipes() async throws {
        var builtIn = testRecipe()
        builtIn.id = "recipe_builtin"
        builtIn.name = "Built-in"
        let fixture = LibraryFixture(builtIns: [builtIn])
        defer { fixture.cleanUp() }
        let original = await fixture.library.ensureApprovedAndCurrent(builtIn)
        #expect(original == builtIn)
        // A copy with the built-in's id that adds an upload: refused.
        var uploading = builtIn
        uploading.nodes.append(RecipeNode(id: "up", stepType: "Jira"))
        uploading.flow.addTransition(from: "b", to: "up")
        let refused = await fixture.library.ensureApprovedAndCurrent(uploading)
        #expect(refused == nil)
        // An unsaved edit of the built-in without anything gated runs.
        var renamed = builtIn
        renamed.name = "My region"
        let edit = await fixture.library.ensureApprovedAndCurrent(renamed)
        #expect(edit == renamed)
        // A recipe that is neither loaded nor built in runs only without gated actions.
        var fresh = testRecipe()
        fresh.id = "fresh"
        let harmless = await fixture.library.ensureApprovedAndCurrent(fresh)
        #expect(harmless == fresh)
        fresh.nodes.append(command("/usr/bin/true"))
        fresh.flow.addTransition(from: "b", to: "run")
        let gated = await fixture.library.ensureApprovedAndCurrent(fresh)
        #expect(gated == nil)
    }
}
