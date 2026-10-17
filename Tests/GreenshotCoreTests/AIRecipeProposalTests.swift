// Greenshot for Mac (Community) - an unofficial macOS port of Greenshot
// Copyright (C) 2026 Greenshot for Mac (Community) contributors
// Based on Greenshot, Copyright (C) 2007-2026 Thomas Braun, Jens Klingen, Robin Krom
// SPDX-License-Identifier: GPL-3.0-or-later

import Foundation
import Testing
@testable import GreenshotCore

/// Holds the approval sheet open until the test answers.
@MainActor
final class WaitingApprover: RecipeApprover {
    private(set) var requests: [RecipeApprovalRequest] = []
    private var pending: CheckedContinuation<RecipeApprovalDecision?, Never>?

    func requestApproval(_ request: RecipeApprovalRequest) async -> RecipeApprovalDecision? {
        requests.append(request)
        return await withCheckedContinuation { pending = $0 }
    }

    func showValidationError(_ request: RecipeApprovalRequest) async {}

    var isWaiting: Bool { pending != nil }

    func answer(_ decision: RecipeApprovalDecision?) {
        pending?.resume(returning: decision)
        pending = nil
    }
}

/// Upstream AiRecipeIpcHandlerTests: RECIPE_CATALOG, VALIDATE_RECIPE, PROPOSE_RECIPE.
@MainActor
@Suite struct AIRecipeProposalTests {
    private let claude = AIToolClient(path: "/Applications/Claude.app/Contents/MacOS/Claude", displayName: "Claude",
                                      signer: "Developer ID Application: Anthropic PBC (Q6L2SF6YDW)")

    private func json(_ recipe: CaptureRecipe) -> String { RecipeSerializer.encode(recipe) }

    private func proposal(_ recipe: CaptureRecipe, replaces: String? = nil, request: String? = "Copy my region") -> AIRecipeProposals.Proposal {
        AIRecipeProposals.Proposal(json: json(recipe), request: request, explanation: "A hotkey that captures and copies.",
                                   replaces: replaces, client: claude)
    }

    private func proposals(_ fixture: LibraryFixture) -> AIRecipeProposals {
        AIRecipeProposals(library: fixture.library, folder: fixture.folder.appendingPathComponent("AI", isDirectory: true))
    }

    @Test func readsExactlyOneRecipe() {
        let fixture = LibraryFixture()
        defer { fixture.cleanUp() }
        func error(_ text: String?) -> String? {
            if case .failure(let failure) = AIRecipeCatalog.parse(text, library: fixture.library) { return failure.message }
            return nil
        }
        #expect(error(nil) == "The recipe JSON is missing.")
        #expect(error("  ") == "The recipe JSON is missing.")
        #expect(error("{ not json")?.hasPrefix("The recipe is not valid JSON for a recipe:") == true)
        let two = "[" + json(libraryRecipe(id: "a")) + "," + json(libraryRecipe(id: "b")) + "]"
        #expect(error(two) == "Send exactly one recipe (a JSON object, not a list).")
        let huge = "{\"id\":\"x\",\"name\":\"" + String(repeating: "a", count: RecipeFileReader.maxBytes) + "\"}"
        #expect(error(huge)?.hasPrefix("The recipe is too large") == true)
        // What only Greenshot decides is dropped
        var leaked = libraryRecipe(id: "a")
        leaked.extra["isBuiltIn"] = .bool(true)
        leaked.extra["filePath"] = .string("/etc/x")
        let draft = try? AIRecipeCatalog.parse(json(leaked), library: fixture.library).get()
        #expect(draft?.recipe.extra["isBuiltIn"] == nil)
        #expect(draft?.content.contains("filePath") == false)
    }

    @Test func approvedProposalIsSavedInTheAIFolder() async throws {
        let fixture = LibraryFixture()
        defer { fixture.cleanUp() }
        let outcome = await proposals(fixture).propose(proposal(libraryRecipe(id: "ai_region")))
        #expect(outcome.reply.status == "ok")
        #expect(outcome.reply.extra["decision"]?.stringValue == "approved")
        let file = try #require(outcome.reply.extra["file"]?.stringValue)
        #expect(file.hasSuffix("/AI/ai_region.gsrecipe.json"))
        #expect(FileManager.default.fileExists(atPath: file))
        #expect(outcome.openInEditor == nil)
        let request = try #require(fixture.approver.requests.first)
        #expect(request.mode == .newRecipe)
        #expect(request.startSwitchedOff)
        #expect(request.proposedBy?.contains("Claude — /Applications/Claude.app/Contents/MacOS/Claude") == true)
        #expect(request.proposedBy?.contains("signed by Developer ID Application") == true)
        #expect(request.aiRequest == "Copy my region")
        // Greenshot saves what it showed
        let saved = try String(contentsOfFile: file, encoding: .utf8)
        #expect(saved == request.content)
        let record = try #require(fixture.store.record(forFile: RecipeTrustStore.standardized(file)))
        #expect(record.proposedBy == "Claude")
        let loaded = try #require(fixture.library.recipe(id: "ai_region"))
        #expect(loaded.proposedBy == "Claude")
        #expect(outcome.reply.extra["triggers_on"]?.arrayValue?.count == 2)
    }

    @Test func aNewRecipeNeedsAnUnusedId() async {
        let fixture = LibraryFixture(builtIns: [libraryRecipe(id: "taken")])
        defer { fixture.cleanUp() }
        let outcome = await proposals(fixture).propose(proposal(libraryRecipe(id: "taken")))
        #expect(outcome.reply.stderr == "A recipe with the id 'taken' exists. Use another id, or update_recipe to change that recipe.")
        #expect(fixture.approver.requests.isEmpty)
    }

    @Test func aRejectedProposalIsNotShownAgain() async {
        let fixture = LibraryFixture(approver: StubApprover { _ in nil })
        defer { fixture.cleanUp() }
        let service = proposals(fixture)
        let first = await service.propose(proposal(libraryRecipe(id: "ai_x")))
        #expect(first.reply.status == "ok")
        #expect(first.reply.extra["decision"]?.stringValue == "rejected")
        let again = await service.propose(proposal(libraryRecipe(id: "ai_x")))
        #expect(again.reply.stderr?.hasPrefix("The user already rejected this recipe.") == true)
        #expect(fixture.approver.requests.count == 1)
        #expect(fixture.library.recipe(id: "ai_x") == nil)
    }

    @Test func oneProposalAtATime() async {
        let approver = WaitingApprover()
        let fixture = LibraryFixture()
        defer { fixture.cleanUp() }
        let service = AIRecipeProposals(library: RecipeLibrary(loadSettings: { RecipeSettings() }, saveSettings: { _ in },
                                                               trustStore: fixture.store, approver: approver, watchFiles: false),
                                        folder: fixture.folder)
        let first = Task { await service.propose(proposal(libraryRecipe(id: "one"))) }
        while !approver.isWaiting { await Task.yield() }
        let second = await service.propose(proposal(libraryRecipe(id: "two")))
        #expect(second.reply.stderr == "Another recipe proposal is waiting for the user, try again after it was answered.")
        approver.answer(nil)
        let outcome = await first.value
        #expect(outcome.reply.extra["decision"]?.stringValue == "rejected")
    }

    @Test func updateKeepsTheFileAndShowsTheChange() async throws {
        let fixture = LibraryFixture()
        defer { fixture.cleanUp() }
        let service = proposals(fixture)
        let created = await service.propose(proposal(libraryRecipe(id: "ai_edit")))
        let file = try #require(created.reply.extra["file"]?.stringValue)
        var changed = libraryRecipe(id: "whatever")
        changed.name = "Changed name"
        let updated = await service.propose(proposal(changed, replaces: "ai_edit"))
        #expect(updated.reply.extra["decision"]?.stringValue == "approved")
        #expect(updated.reply.extra["file"]?.stringValue == file)
        let request = try #require(fixture.approver.requests.last)
        #expect(request.mode == .modified)
        #expect(request.recipe?.id == "ai_edit")
        #expect(request.previousContent != nil)
        #expect(request.diff?.isEmpty == false)
        #expect(fixture.library.recipe(id: "ai_edit")?.recipe.name == "Changed name")
    }

    @Test func updateOfABuiltInGetsItsOwnFile() async throws {
        let fixture = LibraryFixture(builtIns: [libraryRecipe(id: "recipe_region")])
        defer { fixture.cleanUp() }
        var changed = libraryRecipe(id: "recipe_region")
        changed.name = "My region"
        let outcome = await proposals(fixture).propose(proposal(changed, replaces: "recipe_region"))
        let file = try #require(outcome.reply.extra["file"]?.stringValue)
        #expect(file.hasSuffix("/AI/recipe_region.gsrecipe.json"))
        let request = try #require(fixture.approver.requests.first)
        #expect(request.replacesBuiltIn)
        #expect(fixture.library.recipe(id: "recipe_region")?.replacesBuiltIn == true)
    }

    @Test func updateErrors() async throws {
        let fixture = LibraryFixture()
        defer { fixture.cleanUp() }
        let service = proposals(fixture)
        let unknown = await service.propose(proposal(libraryRecipe(id: "x"), replaces: "nope"))
        #expect(unknown.reply.stderr == "There is no recipe with the id 'nope'.")
        // A file with two recipes is changed in the recipe editor
        var second = libraryRecipe(id: "pair_b")
        second.triggers = []
        let url = fixture.folder.appendingPathComponent("pair.gsrecipe.json")
        try Data(RecipeSerializer.encode([libraryRecipe(id: "pair_a"), second]).utf8).write(to: url)
        _ = await fixture.library.loadFile(url)
        let shared = await service.propose(proposal(libraryRecipe(id: "x"), replaces: "pair_a"))
        #expect(shared.reply.stderr?.contains("is in a file with other recipes") == true)
    }

    @Test func openInEditorAfterSaving() async throws {
        let fixture = LibraryFixture(approver: StubApprover { request in
            var decision = StubApprover.approveAll(request)
            decision?.openInEditor = true
            return decision
        })
        defer { fixture.cleanUp() }
        let outcome = await proposals(fixture).propose(proposal(libraryRecipe(id: "ai_open")))
        let file = try #require(outcome.reply.extra["file"]?.stringValue)
        #expect(outcome.openInEditor?.path == file)
    }

    @Test func invalidRecipesAndSwitchedOffRecipesAreRefused() async {
        let fixture = LibraryFixture()
        defer { fixture.cleanUp() }
        var invalid = libraryRecipe(id: "bad")
        invalid.flow.startNodes = ["missing"]
        let outcome = await proposals(fixture).propose(proposal(invalid))
        #expect(outcome.reply.stderr?.hasPrefix("The recipe is not valid, fix it first (validate_recipe):") == true)
        fixture.box.settings.enabled = false
        let off = await proposals(fixture).propose(proposal(libraryRecipe(id: "fine")))
        #expect(off.reply.stderr?.contains("Recipes are switched off") == true)
    }

    @Test func automaticStepsGoToTheLibrary() async throws {
        let fixture = LibraryFixture()
        defer { fixture.cleanUp() }
        var step = CaptureRecipe(id: "border_everywhere", name: "Border")
        step.kind = .extension
        step.extends = ExtensionTarget(recipes: ["*"], slot: "BeforeExport", order: 0)
        step.nodes = [RecipeNode(id: "border", stepType: "Effect", parameters: ["EffectType": .string("Border")])]
        step.flow.startNodes = ["border"]
        step.options = [RecipeOption(key: "enabled", type: .boolean, defaultValue: .bool(false))]
        let outcome = await proposals(fixture).propose(proposal(step))
        // RMANAGER's library asks for the automatic step like for a recipe, everything switched off
        #expect(outcome.reply.status == "ok")
        #expect(outcome.reply.extra["decision"]?.stringValue == "approved")
        let request = try #require(fixture.approver.requests.first)
        #expect(request.recipe?.kind == .extension)
        #expect(request.startSwitchedOff)
        let file = try #require(outcome.reply.extra["file"]?.stringValue)
        #expect(file.hasSuffix("/AI/border_everywhere.gsrecipe.json"))
        #expect(FileManager.default.fileExists(atPath: file))
    }

    /// An automatic step with its switch, as an AI tool should write it.
    private func switchableStep(id: String, width: Double = 2) -> CaptureRecipe {
        var step = CaptureRecipe(id: id, name: "Border")
        step.kind = .extension
        step.extends = ExtensionTarget(recipes: ["*"], slot: "BeforeExport", order: 0)
        var option = RecipeOption(key: "enabled", type: .boolean, defaultValue: .bool(false))
        option.label = "Border"
        step.options = [option]
        step.nodes = [RecipeNode(id: "border", stepType: "Effect", parameters: ["EffectType": .string("Border"), "Width": .number(width)])]
        step.flow.startNodes = ["border"]
        return step
    }

    /// SM-M4 / MC-M2: a change of an automatic step keeps the id of the step it replaces (and its file).
    @Test func changedAutomaticStepKeepsItsId() async throws {
        let fixture = LibraryFixture()
        defer { fixture.cleanUp() }
        let service = proposals(fixture)
        let created = await service.propose(proposal(switchableStep(id: "redact_all")))
        let file = try #require(created.reply.extra["file"]?.stringValue)
        let changed = await service.propose(proposal(switchableStep(id: "something_else", width: 5), replaces: "redact_all"))
        #expect(changed.reply.extra["decision"]?.stringValue == "approved")
        #expect(changed.reply.extra["recipe"]?.stringValue == "redact_all")
        #expect(changed.reply.extra["file"]?.stringValue == file)
        let request = try #require(fixture.approver.requests.last)
        #expect(request.recipe?.id == "redact_all")
        #expect(request.content.contains("something_else") == false)
        #expect(fixture.library.extensions.contains { $0.recipe.id == "something_else" } == false)
    }

    /// MC-M3: a rejected automatic step is the user's answer, and isn't shown again.
    @Test func rejectedAutomaticStepIsRemembered() async {
        let fixture = LibraryFixture(approver: StubApprover { _ in nil })
        defer { fixture.cleanUp() }
        let service = proposals(fixture)
        let first = await service.propose(proposal(switchableStep(id: "step_x")))
        #expect(first.reply.status == "ok")
        #expect(first.reply.extra["decision"]?.stringValue == "rejected")
        let again = await service.propose(proposal(switchableStep(id: "step_x")))
        #expect(again.reply.stderr?.hasPrefix("The user already rejected this automatic step.") == true)
        #expect(fixture.approver.requests.count == 1)
    }

    /// SM-M3: the reply says whether the step is switched on; an AI tool's step starts off.
    @Test func approvedAutomaticStepSaysItIsOff() async {
        let fixture = LibraryFixture()
        defer { fixture.cleanUp() }
        let outcome = await proposals(fixture).propose(proposal(switchableStep(id: "step_y")))
        #expect(outcome.reply.extra["switched_on"]?.boolValue == false)
        #expect(fixture.library.extensions.first { $0.recipe.id == "step_y" }?.isEnabled == false)
    }

    @Test func updateOfAMissingAutomaticStep() async {
        let fixture = LibraryFixture()
        defer { fixture.cleanUp() }
        let outcome = await proposals(fixture).propose(proposal(switchableStep(id: "z"), replaces: "nope"))
        #expect(outcome.reply.stderr == "There is no automatic step with the id 'nope'.")
    }

    /// SM-L4: the banner's text about the program is cleaned.
    @Test func proposerTextIsCleaned() {
        let client = AIToolClient(path: "/opt/homebrew/bin/node\u{202E}", displayName: "node\nSigned by Apple",
                                  identity: AIToolIdentity(executable: "/opt/homebrew/bin/node", script: "/x/cli.js"))
        let text = AIRecipeProposals.proposerText(client)
        #expect(!text.contains("\n"))
        #expect(!text.contains("\u{202E}"))
        #expect(text.contains("running /x/cli.js"))
    }

    @Test func proposerTextNamesTheProgram() {
        #expect(AIRecipeProposals.proposerText(AIToolClient(path: "/usr/local/bin/node", displayName: "node"))
                == "node — /usr/local/bin/node · not signed by a developer")
        #expect(AIRecipeProposals.truncated(String(repeating: "a", count: 2005), 2000)?.count == 2001)
    }
}

/// RECIPE_CATALOG and VALIDATE_RECIPE.
@MainActor
@Suite struct AIRecipeCatalogTests {
    @Test func catalogSections() throws {
        let fixture = LibraryFixture(builtIns: [libraryRecipe(id: "recipe_region")])
        defer { fixture.cleanUp() }
        let reply = AIRecipeCatalog.catalogReply(recipeId: nil, library: fixture.library)
        #expect(reply.status == "ok")
        for key in ["notes", "trigger_types", "steps", "destinations", "processors", "recipes", "slots", "option_types", "automatic_steps"] {
            #expect(reply.extra[key] != nil, "\(key)")
        }
        let steps = reply.extra["steps"]?.arrayValue ?? []
        #expect(steps.contains { $0.objectValue?.string("step_type") == "Source" })
        let destinations = reply.extra["destinations"]?.arrayValue ?? []
        let jira = destinations.first { $0.objectValue?.string("designation") == "Jira" }?.objectValue
        #expect(jira?["uploads"]?.boolValue == true)
        let clipboard = destinations.first { $0.objectValue?.string("designation") == "Clipboard" }?.objectValue
        #expect(clipboard?["uploads"]?.boolValue == false)
        let recipe = try #require(reply.extra["recipes"]?.arrayValue?.first?.objectValue)
        #expect(recipe.string("id") == "recipe_region")
        #expect(recipe["built_in"]?.boolValue == true)
        let aiTrigger = reply.extra["trigger_types"]?.arrayValue?.first { $0.objectValue?.string("type") == "AiTool" }?.objectValue
        #expect(aiTrigger?.string("parameters")?.contains("MaxImageSize") == true)
    }

    @Test func oneRecipesJSON() throws {
        let fixture = LibraryFixture(builtIns: [libraryRecipe(id: "recipe_region")])
        defer { fixture.cleanUp() }
        let reply = AIRecipeCatalog.catalogReply(recipeId: "RECIPE_REGION", library: fixture.library)
        let text = try #require(reply.extra["recipe_json"]?.stringValue)
        let parsed = try RecipeSerializer.decode(text: text)
        #expect(parsed.first?.id == "recipe_region")
        #expect(reply.extra["built_in"]?.boolValue == true)
        let missing = AIRecipeCatalog.catalogReply(recipeId: "nope", library: fixture.library)
        #expect(missing.stderr == "There is no recipe or automatic step with the id 'nope'.")
    }

    /// SM-M3: an AI tool's automatic step needs its "enabled" switch.
    @Test func automaticStepsWithoutASwitchAreInvalid() {
        let fixture = LibraryFixture()
        defer { fixture.cleanUp() }
        var step = CaptureRecipe(id: "no_switch", name: "Border")
        step.kind = .extension
        step.extends = ExtensionTarget(recipes: ["*"], slot: "BeforeExport", order: 0)
        step.nodes = [RecipeNode(id: "border", stepType: "Effect", parameters: ["EffectType": .string("Border")])]
        step.flow.startNodes = ["border"]
        let reply = AIRecipeCatalog.validateReply(json: RecipeSerializer.encode(step), library: fixture.library)
        #expect(reply.extra["valid"]?.boolValue == false)
        let errors = reply.extra["errors"]?.arrayValue?.compactMap(\.stringValue) ?? []
        #expect(errors.contains { $0.contains("Boolean option \"enabled\"") })
        #expect(AIRecipeCatalog.aiProposalProblem(libraryRecipe(id: "a_recipe")) == nil)
    }

    @Test func validation() throws {
        let fixture = LibraryFixture()
        defer { fixture.cleanUp() }
        var upload = libraryRecipe(id: "to_jira")
        upload.nodes.append(RecipeNode(id: "send", stepType: "Destinations", parameters: ["DestinationDesignations": .array([.string("Jira")])]))
        upload.flow.addTransition(from: "b", to: "send")
        let valid = AIRecipeCatalog.validateReply(json: RecipeSerializer.encode(upload), library: fixture.library)
        #expect(valid.extra["valid"]?.boolValue == true)
        #expect(valid.stdout == "The recipe is valid.")
        #expect(valid.extra["what_it_does"]?.arrayValue?.isEmpty == false)
        #expect(valid.extra["triggers"]?.arrayValue?.count == 2)
        let permissions = valid.extra["needs_permission"]?.arrayValue ?? []
        #expect(permissions.contains { $0.objectValue?.string("kind") == "NetworkAccess" })
        #expect(valid.extra["existing_recipe"]?.boolValue == false)
        var broken = libraryRecipe(id: "broken")
        broken.flow.startNodes = ["nowhere"]
        let invalid = AIRecipeCatalog.validateReply(json: RecipeSerializer.encode(broken), library: fixture.library)
        #expect(invalid.status == "ok")
        #expect(invalid.extra["valid"]?.boolValue == false)
        #expect(invalid.extra["errors"]?.arrayValue?.isEmpty == false)
        #expect(invalid.extra["what_it_does"]?.arrayValue?.isEmpty == true)
        #expect(AIRecipeCatalog.validateReply(json: "", library: fixture.library).isError)
    }
}
