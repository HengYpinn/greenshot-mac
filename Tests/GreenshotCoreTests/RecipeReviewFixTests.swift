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

    // MARK: W-M4: unloading one recipe of a file sticks

    @Test func settingsWithoutTheKeyStillLoad() throws {
        let old = try JSONDecoder().decode(RecipeSettings.self, from: Data(#"{"enabled": true, "files": ["/a.gsrecipe.json"]}"#.utf8))
        #expect(old.unloadedRecipes.isEmpty)
        #expect(old.files == ["/a.gsrecipe.json"])
        var settings = RecipeSettings()
        settings.unloadedRecipes = ["/a.gsrecipe.json": ["recipe_a"]]
        let decoded = try JSONDecoder().decode(RecipeSettings.self, from: JSONEncoder().encode(settings))
        #expect(decoded == settings)
    }

    func twoRecipeFile(_ fixture: LibraryFixture) throws -> URL {
        let first = libraryRecipe(id: "recipe_a")
        let second = libraryRecipe(id: "recipe_b")
        let url = fixture.folder.appendingPathComponent("two.gsrecipe.json")
        let text = JSONValue.array([RecipeSerializer.json(of: first), RecipeSerializer.json(of: second)]).serialized(indented: true)
        try Data(text.utf8).write(to: url)
        return url
    }

    func ids(_ library: RecipeLibrary) -> [String] {
        library.recipes.map(\.recipe.id)
    }

    @Test func unloadingOneRecipeOfAFileSticks() async throws {
        let fixture = LibraryFixture()
        defer { fixture.cleanUp() }
        let url = try twoRecipeFile(fixture)
        _ = await fixture.library.importFile(url)
        #expect(ids(fixture.library) == ["recipe_a", "recipe_b"])
        let asked = fixture.approver.requests.count

        fixture.library.unload(recipeId: "recipe_a")
        #expect(ids(fixture.library) == ["recipe_b"])
        #expect(fixture.box.settings.files.count == 1)
        _ = await fixture.library.reload()
        #expect(ids(fixture.library) == ["recipe_b"])
        #expect(fixture.approver.requests.count == asked)

        // Importing the file again brings it back.
        _ = await fixture.library.importFile(url)
        #expect(ids(fixture.library) == ["recipe_b", "recipe_a"])
        #expect(fixture.box.settings.unloadedRecipes.isEmpty)

        // Revoked: not loaded again and not asked again at the next reload.
        #expect(fixture.library.revokeApproval(recipeId: "recipe_a"))
        _ = await fixture.library.reload()
        #expect(ids(fixture.library) == ["recipe_b"])
        #expect(fixture.approver.requests.count == asked)

        // Saving the recipe from the editor brings it back too.
        var edited = libraryRecipe(id: "recipe_a")
        edited.name = "Edited"
        let saved = await fixture.library.save(edited, to: url)
        #expect(saved.loadedRecipeIds == ["recipe_a"])
        #expect(fixture.box.settings.unloadedRecipes.isEmpty)

        // The last recipe of a file takes the file out of the settings, and the list with it.
        fixture.library.unload(recipeId: "recipe_a")
        fixture.library.unload(recipeId: "recipe_b")
        #expect(fixture.box.settings.files.isEmpty)
        #expect(fixture.box.settings.unloadedRecipes.isEmpty)
    }

    /// Save As of a loaded recipe to another file moves it: after a reload only the new file carries its id.
    @Test func savingToAnotherFileMovesTheRecipe() async throws {
        let fixture = LibraryFixture()
        defer { fixture.cleanUp() }
        let two = try twoRecipeFile(fixture)
        _ = await fixture.library.importFile(two)
        let moved = fixture.folder.appendingPathComponent("moved.gsrecipe.json")
        var recipeA = try #require(fixture.library.recipe(id: "recipe_a")).recipe
        recipeA.name = "Moved A"
        _ = await fixture.library.save(recipeA, to: moved)
        #expect(fixture.box.settings.files.count == 2)
        #expect(fixture.box.settings.unloadedRecipes.values.map { $0 } == [["recipe_a"]])
        // The old file loads last: it must not bring its copy of the recipe back.
        fixture.box.settings.files.reverse()
        _ = await fixture.library.reload()
        let loadedA = try #require(fixture.library.recipe(id: "recipe_a"))
        #expect(loadedA.recipe.name == "Moved A")
        #expect(loadedA.fileURL?.lastPathComponent == "moved.gsrecipe.json")
        #expect(fixture.library.recipe(id: "recipe_b")?.fileURL?.lastPathComponent == "two.gsrecipe.json")
        #expect(fixture.library.recipes.filter { $0.recipe.id == "recipe_a" }.count == 1)

        // A file that held only that recipe leaves the settings.
        let again = fixture.folder.appendingPathComponent("again.gsrecipe.json")
        _ = await fixture.library.save(loadedA.recipe, to: again)
        let files = fixture.box.settings.files.map { URL(fileURLWithPath: $0).lastPathComponent }.sorted()
        #expect(files == ["again.gsrecipe.json", "two.gsrecipe.json"])
    }

    @Test func resetToTheBuiltInSticks() async throws {
        var builtIn = libraryRecipe(id: "recipe_a")
        builtIn.name = "Built-in A"
        let fixture = LibraryFixture(builtIns: [builtIn])
        defer { fixture.cleanUp() }
        _ = await fixture.library.importFile(try twoRecipeFile(fixture))
        #expect(fixture.library.recipe(id: "recipe_a")?.isBuiltIn == false)
        #expect(fixture.library.resetToDefault(recipeId: "recipe_a"))
        _ = await fixture.library.reload()
        #expect(fixture.library.recipe(id: "recipe_a")?.recipe.name == "Built-in A")
        #expect(fixture.library.recipe(id: "recipe_b") != nil)
    }

    // MARK: MC-M1: the matched recipe and trigger run

    @Test func theMatchedCommandRuns() async throws {
        let harness = RecipeCommandHarness()
        defer { harness.cleanUp() }
        try await harness.load(commandLineRecipe(id: "recipe_a", command: "shot", sourceType: "FullScreen"))
        try await harness.load(commandLineRecipe(id: "recipe_b", command: "shot", sourceType: "Clipboard"))
        let library = harness.fixture.library
        let listed = library.commands(for: .commandLine)
        #expect(listed.map(\.recipeId) == ["recipe_a", "recipe_b"])
        let second = try #require(listed.last)
        let request = try library.runRequest(match: second, arguments: ["name": "Ann"], source: .commandLine) { raw, _ in raw }
        #expect(request.recipe.id == "recipe_b")
        #expect(request.trigger?.triggerIndex == 0)
        let byId = try library.runRequest(command: "recipe_b", arguments: ["name": "Ann"], source: .commandLine) { raw, _ in raw }
        #expect(byId.recipe.id == "recipe_b")

        // greenshot-cli -r recipe_b runs recipe_b, not the first recipe with the command "shot".
        let envelope = try #require(IPCCommandLine.parse(["-r", "recipe_b", "name=Ann"], source: .cli, cwd: "/Users/me").envelope)
        let (reply, _, asked) = await harness.run(envelope)
        #expect(!reply.isError)
        #expect(harness.recorder.all.contains("Source:Clipboard"))
        #expect(!harness.recorder.all.contains("Source:FullScreen"))
        #expect(asked.allSatisfy { $0.hasPrefix("Greeter recipe_b") })
    }

    /// A file with a padded ToolName doesn't validate; a built-in recipe isn't validated, so the library trims too.
    @Test func aiToolNamesAreTrimmedAndNeverIds() async throws {
        var tool = libraryRecipe(id: "recipe_tool")
        tool.triggers = [TriggerConfig(triggerType: "AiTool", parameters: ["ToolName": .string(" snap_screen "), "Description": .string("Snap")])]
        let fixture = LibraryFixture(builtIns: [tool])
        defer { fixture.cleanUp() }
        let source = RecipeInvocationSource.aiTool(client: "Test")
        let offered = fixture.library.commands(for: source)
        #expect(offered.map(\.command) == ["snap_screen"])
        let request = try fixture.library.runRequest(command: "snap_screen", arguments: [:], source: source) { raw, _ in raw }
        #expect(request.recipe.id == "recipe_tool")
        // An AI tool is its tool name only: the recipe id doesn't run it.
        #expect(throws: RecipeStepError.self) {
            try fixture.library.runRequest(command: "recipe_tool", arguments: [:], source: source) { raw, _ in raw }
        }
    }
}
