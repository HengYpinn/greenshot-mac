// Greenshot for Mac (Community) - an unofficial macOS port of Greenshot
// Copyright (C) 2026 Greenshot for Mac (Community) contributors
// Based on Greenshot, Copyright (C) 2007-2026 Thomas Braun, Jens Klingen, Robin Krom
// SPDX-License-Identifier: GPL-3.0-or-later

import Foundation
import Testing
@testable import GreenshotCore

/// Answers the approval sheet's questions in the tests.
@MainActor
final class StubApprover: RecipeApprover {
    var answer: (RecipeApprovalRequest) -> RecipeApprovalDecision?
    private(set) var requests: [RecipeApprovalRequest] = []
    private(set) var validationErrors: [RecipeApprovalRequest] = []

    init(_ answer: @escaping (RecipeApprovalRequest) -> RecipeApprovalDecision? = StubApprover.approveAll) {
        self.answer = answer
    }

    /// Every trigger and every permission the recipe needs.
    nonisolated static func approveAll(_ request: RecipeApprovalRequest) -> RecipeApprovalDecision? {
        RecipeApprovalDecision(approval: RecipeApproval(recipeId: request.recipe?.id ?? "", approvedTriggers: request.triggers.map(\.key),
                                                        allowedGates: request.gates))
    }

    func requestApproval(_ request: RecipeApprovalRequest) async -> RecipeApprovalDecision? {
        requests.append(request)
        return answer(request)
    }

    func showValidationError(_ request: RecipeApprovalRequest) async {
        validationErrors.append(request)
    }
}

@MainActor
final class SettingsBox {
    var settings = RecipeSettings()
}

@MainActor
struct LibraryFixture {
    let folder = recipeTemporaryFolder()
    let box = SettingsBox()
    let approver: StubApprover
    let store: RecipeTrustStore
    let library: RecipeLibrary

    init(approver: StubApprover? = nil, builtIns: [CaptureRecipe] = []) {
        let approver = approver ?? StubApprover()
        self.approver = approver
        store = RecipeTrustStore(fileURL: folder.appendingPathComponent("trust.json"), secrets: InMemorySecretStore())
        let box = self.box
        library = RecipeLibrary(loadSettings: { box.settings }, saveSettings: { box.settings = $0 }, trustStore: store, approver: approver,
                                builtInRecipes: builtIns, watchFiles: false)
    }

    func write(_ recipe: CaptureRecipe, name: String = "test.gsrecipe.json") throws -> URL {
        let url = folder.appendingPathComponent(name)
        try Data(RecipeSerializer.encode(recipe).utf8).write(to: url)
        return url
    }

    func cleanUp() {
        try? FileManager.default.removeItem(at: folder)
    }
}

/// A recipe with a hotkey and a clipboard trigger, a Source and a Clipboard step.
func libraryRecipe(id: String = "lib_recipe", extraNode: RecipeNode? = nil) -> CaptureRecipe {
    var recipe = testRecipe()
    recipe.id = id
    recipe.name = "Library Recipe"
    recipe.triggers = [TriggerConfig(triggerType: "Hotkey", parameters: ["Hotkey": .string("Ctrl + Alt + F1")]),
                       TriggerConfig(triggerType: "Clipboard")]
    if let extraNode {
        recipe.nodes.append(extraNode)
        recipe.flow.addTransition(from: "b", to: extraNode.id)
    }
    return recipe
}

/// Upstream RecipeManager: loading with default-deny approval, override, enable, save, revoke, review, commands.
@MainActor
@Suite struct RecipeLibraryTests {
    @Test func unapprovedFilesDontLoadWithoutAsking() async throws {
        let fixture = LibraryFixture()
        defer { fixture.cleanUp() }
        let url = try fixture.write(libraryRecipe())
        let result = await fixture.library.loadFile(url, interactive: false)
        #expect(result.errors.count == 1)
        #expect(fixture.library.recipes.isEmpty)
    }

    @Test func approvedTriggersOnly() async throws {
        let approver = StubApprover { request in
            RecipeApprovalDecision(approval: RecipeApproval(recipeId: "x", approvedTriggers: ["0:Hotkey"]))
        }
        let fixture = LibraryFixture(approver: approver)
        defer { fixture.cleanUp() }
        let url = try fixture.write(libraryRecipe())
        // Import is an interactive load.
        let result = await fixture.library.importFile(url)
        #expect(result.isValid)
        let request = try #require(approver.requests.first)
        #expect(request.mode == .newRecipe)
        #expect(request.triggers.map(\.key) == ["0:Hotkey", "1:Clipboard"])
        let active = fixture.library.activeTriggers()
        #expect(active.map(\.key) == ["0:Hotkey"])
        #expect(active.first?.hotkey != nil)
        #expect(fixture.box.settings.files == [RecipeTrustStore.standardized(url.path)])
        // Approved for this content: no question the next time.
        _ = await fixture.library.reload()
        #expect(approver.requests.count == 1)
        #expect(fixture.library.recipes.count == 1)
    }

    @Test func rejectedAndMissingPermissions() async throws {
        let rejecting = LibraryFixture(approver: StubApprover { _ in nil })
        defer { rejecting.cleanUp() }
        let url = try rejecting.write(libraryRecipe())
        let rejected = await rejecting.library.loadFile(url)
        #expect(rejected.errors.first?.hasPrefix("User rejected recipe 'Library Recipe'") == true)

        let noPermissions = LibraryFixture(approver: StubApprover { request in
            RecipeApprovalDecision(approval: RecipeApproval(recipeId: "x", approvedTriggers: request.triggers.map(\.key)))
        })
        defer { noPermissions.cleanUp() }
        let uploading = try noPermissions.write(libraryRecipe(extraNode: RecipeNode(id: "upload", stepType: "Jira")))
        let result = await noPermissions.library.loadFile(uploading)
        #expect(result.errors == ["Recipe 'Library Recipe' needs network access (uploads), but that was not allowed."])
        #expect(noPermissions.approver.requests.first?.gates == [.networkAccess])
        #expect(noPermissions.library.recipes.isEmpty)
    }

    @Test func changedFileAsksAgainWithTheChanges() async throws {
        let fixture = LibraryFixture()
        defer { fixture.cleanUp() }
        let url = try fixture.write(libraryRecipe())
        _ = await fixture.library.loadFile(url)
        let loaded = try #require(fixture.library.recipe(id: "lib_recipe"))
        let unchanged = await fixture.library.ensureApprovedAndCurrent(loaded.recipe)
        #expect(unchanged == loaded.recipe)
        var changed = libraryRecipe()
        changed.nodes.append(RecipeNode(id: "print", stepType: "Printer"))
        changed.flow.addTransition(from: "b", to: "print")
        _ = try fixture.write(changed)
        let current = await fixture.library.ensureApprovedAndCurrent(loaded.recipe)
        #expect(current == changed)
        let request = try #require(fixture.approver.requests.last)
        #expect(request.mode == .modified)
        #expect(request.changes == ["Adds: Prints the result"])
        #expect(request.diff?.contains { $0.kind == .added } == true)
        // Rejected the next time: the recipe doesn't run.
        fixture.approver.answer = { _ in nil }
        _ = try fixture.write(libraryRecipe())
        let refused = await fixture.library.ensureApprovedAndCurrent(changed)
        #expect(refused == nil)
    }

    /// Security review: permissions are kept per kind (command, upload, files), but the approval is pinned to the file's
    /// SHA-256, so another command or upload target in the file asks again before the recipe runs.
    @Test func anotherTargetOfTheSameKindAsksAgain() async throws {
        let fixture = LibraryFixture()
        defer { fixture.cleanUp() }
        let harmless = RecipeNode(id: "run", stepType: "ExternalCommand", parameters: ["CommandLine": .string("/usr/bin/true")])
        let url = try fixture.write(libraryRecipe(extraNode: harmless))
        _ = await fixture.library.loadFile(url)
        let loaded = try #require(fixture.library.recipe(id: "lib_recipe"))
        let approved = await fixture.library.ensureApprovedAndCurrent(loaded.recipe)
        #expect(approved == loaded.recipe)
        #expect(fixture.approver.requests.count == 1)

        let other = RecipeNode(id: "run", stepType: "ExternalCommand", parameters: ["CommandLine": .string("/bin/rm")])
        _ = try fixture.write(libraryRecipe(extraNode: other))
        fixture.approver.answer = { _ in nil }
        let refused = await fixture.library.ensureApprovedAndCurrent(loaded.recipe)
        #expect(refused == nil)
        let request = try #require(fixture.approver.requests.last)
        #expect(request.mode == .modified)
        #expect(request.changes.contains("Adds: Runs the program /bin/rm"))
        #expect(request.changes.contains("Removes: Runs the program /usr/bin/true"))
        let quiet = await fixture.library.loadFile(url, interactive: false)
        #expect(!quiet.isValid)

        // The same for an upload that goes elsewhere.
        let uploads = LibraryFixture()
        defer { uploads.cleanUp() }
        let jira = try uploads.write(libraryRecipe(extraNode: RecipeNode(id: "up", stepType: "Jira")))
        _ = await uploads.library.loadFile(jira)
        let uploading = try #require(uploads.library.recipe(id: "lib_recipe"))
        _ = try uploads.write(libraryRecipe(extraNode: RecipeNode(id: "up", stepType: "Confluence")))
        uploads.approver.answer = { _ in nil }
        let elsewhere = await uploads.library.ensureApprovedAndCurrent(uploading.recipe)
        #expect(elsewhere == nil)
        #expect(uploads.approver.requests.last?.changes.contains("Adds: Uploads to Confluence") == true)
    }

    @Test func reviewKeepsOrRevokes() async throws {
        let fixture = LibraryFixture()
        defer { fixture.cleanUp() }
        let url = try fixture.write(libraryRecipe())
        _ = await fixture.library.loadFile(url)
        fixture.approver.answer = { _ in nil }
        let kept = await fixture.library.reviewApproval(recipeId: "lib_recipe")
        #expect(kept.isValid)
        let review = try #require(fixture.approver.requests.last)
        #expect(review.mode == .reVerify)
        #expect(review.suggestedApproval != nil)
        #expect(fixture.library.recipe(id: "lib_recipe") != nil)
        fixture.approver.answer = { _ in .revoked }
        _ = await fixture.library.reviewApproval(recipeId: "lib_recipe")
        #expect(fixture.library.recipe(id: "lib_recipe") == nil)
        #expect(fixture.store.record(forFile: url.path) == nil)
    }

    @Test func overrideAndResetBuiltIns() async throws {
        var builtIn = libraryRecipe(id: "recipe_region")
        builtIn.name = "Region"
        let fixture = LibraryFixture(builtIns: [builtIn])
        defer { fixture.cleanUp() }
        #expect(fixture.library.recipe(id: "recipe_region")?.isBuiltIn == true)
        var replacement = libraryRecipe(id: "recipe_region")
        replacement.name = "My Region"
        let url = try fixture.write(replacement)
        _ = await fixture.library.loadFile(url)
        let request = try #require(fixture.approver.requests.first)
        #expect(request.replacesBuiltIn)
        #expect(request.previousContent != nil)
        let replaced = try #require(fixture.library.recipe(id: "RECIPE_REGION"))
        #expect(replaced.replacesBuiltIn)
        #expect(replaced.recipe.name == "My Region")
        #expect(fixture.library.details(recipeId: "recipe_region")?.builtInDiff?.contains("+     \"name\": \"My Region\"") == false)
        #expect(fixture.library.details(recipeId: "recipe_region")?.builtInDiff?.contains("My Region") == true)
        #expect(fixture.library.resetToDefault(recipeId: "recipe_region"))
        #expect(fixture.library.recipe(id: "recipe_region")?.recipe.name == "Region")
        #expect(fixture.box.settings.files.isEmpty)
    }

    @Test func switchingRecipesAndTheFeature() async throws {
        let fixture = LibraryFixture()
        defer { fixture.cleanUp() }
        let url = try fixture.write(libraryRecipe())
        _ = await fixture.library.loadFile(url)
        var changes = 0
        fixture.library.onChange = { changes += 1 }
        fixture.library.setEnabled(false, recipeId: "LIB_RECIPE")
        #expect(fixture.box.settings.disabledRecipeIds == ["LIB_RECIPE"])
        #expect(fixture.library.recipe(id: "lib_recipe")?.isEnabled == false)
        #expect(fixture.library.activeTriggers().isEmpty)
        fixture.library.setEnabled(true, recipeId: "lib_recipe")
        #expect(fixture.library.activeTriggers().count == 2)
        #expect(changes == 2)
        fixture.box.settings.enabled = false
        #expect(fixture.library.activeTriggers().isEmpty)
        _ = await fixture.library.reload()
        #expect(fixture.library.recipes.isEmpty)
        let refused = await fixture.library.loadFile(url)
        #expect(refused.errors == ["Recipes are switched off."])
    }

    @Test func savingRenewsTheApproval() async throws {
        let fixture = LibraryFixture()
        defer { fixture.cleanUp() }
        let url = fixture.folder.appendingPathComponent("saved.gsrecipe.json")
        var recipe = libraryRecipe()
        recipe.triggers = [recipe.triggers[0]]
        #expect(fixture.library.saveDecisionReasons(for: recipe, at: url).isEmpty)
        let saved = await fixture.library.save(recipe, to: url)
        #expect(saved.isValid)
        #expect(fixture.approver.requests.isEmpty)
        #expect(fixture.library.activeTriggers().map(\.key) == ["0:Hotkey"])
        // Adding a trigger that starts the recipe on its own asks.
        recipe.triggers.append(TriggerConfig(triggerType: "Clipboard"))
        #expect(fixture.library.saveDecisionReasons(for: recipe, at: url) == ["When an image is copied to the clipboard"])
        _ = await fixture.library.save(recipe, to: url)
        let request = try #require(fixture.approver.requests.first)
        #expect(request.ownEditReasons == ["When an image is copied to the clipboard"])
        #expect(request.suggestedApproval?.approvedTriggers == ["0:Hotkey", "1:Clipboard"])
        #expect(fixture.library.activeTriggers().count == 2)
        let onDisk = try RecipeSerializer.decode(Data(contentsOf: url))
        #expect(onDisk == [recipe])
        // Not approved: not saved.
        fixture.approver.answer = { _ in nil }
        recipe.triggers.append(TriggerConfig(triggerType: "OpenFile"))
        let refused = await fixture.library.save(recipe, to: url)
        #expect(refused.errors == ["The recipe was not saved, its changes were not approved."])
    }

    /// Security review: a file is read before it is approved, so its size is limited (1 MB) and only regular files count.
    @Test func oversizedFilesAreNotRead() async throws {
        let fixture = LibraryFixture()
        defer { fixture.cleanUp() }
        // A valid recipe padded with spaces: it would load without the limit.
        let text = RecipeSerializer.encode(libraryRecipe()) + String(repeating: " ", count: RecipeFileReader.maxBytes)
        let url = fixture.folder.appendingPathComponent("huge.gsrecipe.json")
        try Data(text.utf8).write(to: url)
        let path = RecipeTrustStore.standardized(url.path)
        let quiet = await fixture.library.loadFile(url, interactive: false)
        #expect(quiet.errors == ["The recipe file is larger than 1 MB: \(path)"])
        #expect(fixture.library.recipes.isEmpty)
        let imported = await fixture.library.importFile(url)
        #expect(imported.errors.count == 1)
        #expect(fixture.approver.requests.isEmpty)
        let shown = try #require(fixture.approver.validationErrors.first)
        #expect(shown.errorMessage == "The recipe file is larger than 1 MB: \(path)")
        #expect(fixture.box.settings.files.isEmpty)
        // At most 50 recipes in one file.
        let many = (0..<51).map { libraryRecipe(id: "r\($0)") }
        let crowded = fixture.folder.appendingPathComponent("many.gsrecipe.json")
        try Data(JSONValue.array(many.map { RecipeSerializer.json(of: $0) }).serialized(indented: true).utf8).write(to: crowded)
        let refused = await fixture.library.loadFile(crowded, interactive: false)
        #expect(refused.errors == ["The recipe file holds 51 recipes; at most 50 are allowed."])
        // Not a file: a folder, or a device that never ends.
        #expect(RecipeFileReader.read(fixture.folder) == .failure(.notAFile))
        #expect(RecipeFileReader.read(URL(fileURLWithPath: "/dev/zero")) == .failure(.notAFile))
        let small = try fixture.write(libraryRecipe())
        let read = RecipeFileReader.read(small)
        #expect((try? read.get())?.isEmpty == false)
    }

    @Test func extensionAndInvalidFiles() async throws {
        let fixture = LibraryFixture()
        defer { fixture.cleanUp() }
        var extensionFile = libraryRecipe()
        extensionFile.kind = .extension
        _ = await fixture.library.loadFile(try fixture.write(extensionFile, name: "ext.gsrecipe.json"))
        #expect(fixture.approver.validationErrors.first?.errorMessage?.contains("automatic step") == true)
        var cyclic = libraryRecipe()
        cyclic.flow.addTransition(from: "b", to: "a")
        let result = await fixture.library.loadFile(try fixture.write(cyclic, name: "cycle.gsrecipe.json"))
        #expect(result.errors.first?.contains("Cycle/loop detected") == true)
        let request = try #require(fixture.approver.validationErrors.last)
        #expect(request.mode == .validationError)
        #expect(request.hint == "Remove a transition that leads back to an earlier step: recipes run from start to end.")
        let broken = fixture.folder.appendingPathComponent("broken.gsrecipe.json")
        try Data("{ \"id\": ".utf8).write(to: broken)
        let unreadable = await fixture.library.loadFile(broken)
        #expect(unreadable.errors.first?.contains("not valid JSON") == true)
        #expect(fixture.approver.requests.isEmpty)
    }

    @Test func commandsAndRunRequests() async throws {
        let fixture = LibraryFixture()
        defer { fixture.cleanUp() }
        var recipe = libraryRecipe(id: "qr_recipe")
        recipe.triggers = [TriggerConfig(triggerType: "Commandline", parameters: [
            "Command": .string("qr"), "Description": .string("Decode"),
            "Arguments": .array([.object(["name": .string("file"), "variable": .string("Filename"), "type": .string("FilePath"), "required": .bool(true)])])
        ])]
        _ = await fixture.library.loadFile(try fixture.write(recipe))
        let commands = fixture.library.commands(for: .commandLine)
        #expect(commands.map(\.command) == ["qr"])
        #expect(commands.first?.description == "Decode")
        #expect(fixture.library.commands(for: .browser).isEmpty)
        let request = try fixture.library.runRequest(command: "QR", arguments: ["file": "a.png"], source: .commandLine) { path, _ in "/work/" + path }
        #expect(request.variables["Filename"] == .string("/work/a.png"))
        #expect(request.trigger?.triggerType == "Commandline")
        #expect(throws: RecipeStepError.self) {
            try fixture.library.runRequest(command: "qr", arguments: [:], source: .commandLine) { path, _ in path }
        }
        do {
            _ = try fixture.library.runRequest(command: "qr", arguments: ["file": "a"], source: .browser) { path, _ in path }
            Issue.record("a browser may not start it")
        } catch let error as RecipeStepError {
            #expect(error.message.hasPrefix("[SECURITY]"))
        }
        #expect(fixture.library.runRequest(recipeId: "qr_recipe")?.trigger?.triggerType == "Manual")
        #expect(fixture.library.contractReport(recipeId: "qr_recipe")?.inputs.first?.name == "Filename")
    }

    @Test func aiProposals() async throws {
        let fixture = LibraryFixture()
        defer { fixture.cleanUp() }
        let url = fixture.folder.appendingPathComponent("ai.gsrecipe.json")
        let content = RecipeSerializer.encode(libraryRecipe(id: "ai_recipe"))
        let result = await fixture.library.propose(content: content, proposedBy: "Claude", aiRequest: "make a recipe", aiExplanation: "it does x",
                                                   saveTo: url)
        #expect(result.isValid)
        let request = try #require(fixture.approver.requests.first)
        #expect(request.startSwitchedOff)
        #expect(request.proposedBy == "Claude")
        #expect(request.aiExplanation == "it does x")
        #expect(fixture.library.recipe(id: "ai_recipe")?.proposedBy == "Claude")
        #expect(fixture.store.record(forFile: url.path)?.origin == "ai:Claude")
        let written = try String(contentsOf: url, encoding: .utf8)
        #expect(written == content)
        // Security review: a proposal has the size limit of a file.
        let padded = RecipeSerializer.encode(libraryRecipe(id: "huge_ai")) + String(repeating: " ", count: RecipeFileReader.maxBytes)
        let hugeURL = fixture.folder.appendingPathComponent("huge-ai.gsrecipe.json")
        let huge = await fixture.library.propose(content: padded, proposedBy: "Claude", aiRequest: nil, aiExplanation: nil, saveTo: hugeURL)
        #expect(huge.errors == ["The proposed recipe is larger than 1 MB."])
        #expect(fixture.approver.requests.count == 1)
        #expect(!FileManager.default.fileExists(atPath: hugeURL.path))
    }

    @Test func detailsAndRequests() async throws {
        let fixture = LibraryFixture()
        defer { fixture.cleanUp() }
        let url = try fixture.write(libraryRecipe(extraNode: RecipeNode(id: "upload", stepType: "Dropbox")))
        _ = await fixture.library.loadFile(url)
        let details = try #require(fixture.library.details(recipeId: "lib_recipe"))
        #expect(details.isApprovalCurrent)
        #expect(details.permissions == [.networkAccess])
        #expect(details.triggers.map(\.label) == ["Hotkey ⌥⌘F1 (on)", "When an image is copied to the clipboard (on)"])
        #expect(details.whatItDoes.contains { $0.text == "Uploads to Dropbox (dropbox.com)" })
        let request = try #require(fixture.library.detailsRequest(recipeId: "lib_recipe"))
        #expect(request.isReadOnly)
        #expect(request.content.contains("\"lib_recipe\""))
        #expect(fixture.library.revokeApproval(recipeId: "lib_recipe"))
        #expect(fixture.library.recipes.isEmpty)
        #expect(fixture.box.settings.files.isEmpty)
    }

    @Test func optionValues() async throws {
        let fixture = LibraryFixture()
        defer { fixture.cleanUp() }
        var recipe = libraryRecipe()
        recipe.options = [RecipeOption(key: "border", type: .boolean, defaultValue: .bool(false))]
        _ = await fixture.library.loadFile(try fixture.write(recipe))
        fixture.library.setOptionValue(.bool(true), key: "Border", recipeId: "lib_recipe")
        #expect(fixture.box.settings.optionValues == ["lib_recipe.border": "True"])
        #expect(fixture.library.runRequest(recipeId: "lib_recipe")?.optionValues.stored == ["lib_recipe.border": "True"])
        fixture.library.resetOptions(recipeId: "lib_recipe")
        #expect(fixture.box.settings.optionValues.isEmpty)
    }
}

/// A trigger source for the hub test.
@MainActor
final class TestTriggerSource: RecipeTriggerSource {
    var triggerTypes: Set<String> { ["Hotkey"] }
    private(set) var synced: [[ActiveRecipeTrigger]] = []
    private(set) var stopped = false

    func sync(_ triggers: [ActiveRecipeTrigger]) { synced.append(triggers) }
    func stop() { stopped = true }
}

@MainActor
@Suite struct RecipeTriggerHubTests {
    @Test func syncsSourcesAndFires() async throws {
        let fixture = LibraryFixture()
        defer { fixture.cleanUp() }
        let recorder = RecipeRecorder()
        let registry = RecipeEngineHarness.registry(recorder)
        for type in ["Source", "Clipboard"] {
            registry.register(type, executor: ClosureExecutor { step, _ in recorder.add(step.node.stepType) })
        }
        let runner = RecipeRunner(steps: registry, environment: { FixedRecipeEnvironment() })
        let hub = RecipeTriggerHub(library: fixture.library, runner: runner)
        let source = TestTriggerSource()
        hub.register(source)
        #expect(source.synced.last?.isEmpty == true)
        _ = await fixture.library.loadFile(try fixture.write(libraryRecipe()))
        hub.sync()
        let trigger = try #require(source.synced.last?.first)
        #expect(trigger.trigger.isType("Hotkey"))
        let handle = try #require(hub.fire(trigger, info: RecipeTriggerInfo(triggerType: "Hotkey", triggerIndex: trigger.index)))
        let result = await handle.result
        #expect(result.isSuccess)
        #expect(recorder.all == ["Source", "Clipboard"])
        fixture.library.setEnabled(false, recipeId: "lib_recipe")
        #expect(hub.fire(trigger, info: RecipeTriggerInfo(triggerType: "Hotkey")) == nil)
        hub.stopAll()
        #expect(source.stopped)
    }
}

/// The file monitor reports a changed file once.
@Suite struct RecipeFileMonitorTests {
    @Test func reportsAChange() async throws {
        let folder = recipeTemporaryFolder()
        defer { try? FileManager.default.removeItem(at: folder) }
        let url = folder.appendingPathComponent("watched.gsrecipe.json")
        try Data("{}".utf8).write(to: url)
        let changes = RecipeRecorder()
        let monitor = RecipeFileMonitor(debounce: 0.05) { changes.add($0.lastPathComponent) }
        monitor.watch(url)
        try await Task.sleep(for: .milliseconds(200))
        try Data("{\"id\": \"changed\"}".utf8).write(to: url, options: .atomic)
        var waited = 0
        while changes.all.isEmpty, waited < 100 {
            try await Task.sleep(for: .milliseconds(50))
            waited += 1
        }
        #expect(changes.all == ["watched.gsrecipe.json"])
        monitor.stopAll()
    }
}
