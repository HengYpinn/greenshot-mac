// Greenshot for Mac (Community) - an unofficial macOS port of Greenshot
// Copyright (C) 2026 Greenshot for Mac (Community) contributors
// Based on Greenshot, Copyright (C) 2007-2026 Thomas Braun, Jens Klingen, Robin Krom
// SPDX-License-Identifier: GPL-3.0-or-later

import Foundation
import Testing
@testable import GreenshotCore

/// A folder for one test, removed by the test.
func recipeTemporaryFolder() -> URL {
    let folder = FileManager.default.temporaryDirectory.appendingPathComponent("recipe-tests-\(UUID().uuidString)", isDirectory: true)
    try? FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
    return folder
}

/// The trust store: approvals pinned to the content, per recipe, signed with a key in the secret store.
@Suite struct RecipeTrustStoreTests {
    @Test func pinsTheApprovalPerRecipeAndContent() throws {
        let folder = recipeTemporaryFolder()
        defer { try? FileManager.default.removeItem(at: folder) }
        let secrets = InMemorySecretStore()
        let store = RecipeTrustStore(fileURL: folder.appendingPathComponent("trust.json"), secrets: secrets)
        let path = folder.appendingPathComponent("a.gsrecipe.json").path
        let approval = RecipeApproval(recipeId: "one", approvedTriggers: ["0:Hotkey"], allowedGates: [.networkAccess])
        try store.recordApproval(approval, forFile: path, sha256: "ABC", content: "{}", origin: nil, recipeName: "One", recipeVersion: "1.0")
        try store.recordApproval(RecipeApproval(recipeId: "two"), forFile: path, sha256: "abc", content: nil, origin: nil, recipeName: nil, recipeVersion: nil)
        #expect(store.approval(forFile: path, sha256: "abc", recipeId: "ONE") == approval)
        #expect(store.approval(forFile: path, sha256: "abc", recipeId: "two") != nil)
        #expect(store.approval(forFile: path, sha256: "def", recipeId: "one") == nil)
        #expect(store.approval(forFile: path.uppercased(), sha256: "abc", recipeId: "one") != nil)
        // New content starts a new record.
        try store.recordApproval(RecipeApproval(recipeId: "one"), forFile: path, sha256: "def", content: nil, origin: nil, recipeName: nil, recipeVersion: nil)
        #expect(store.approval(forFile: path, sha256: "def", recipeId: "two") == nil)
        let record = try #require(store.record(forFile: path))
        #expect(record.recipes.count == 1)
        #expect(record.recipeName == nil)
        #expect(secrets.secretValue(RecipeTrustStore.keyName) != nil)
    }

    @Test func persistsAndDetectsTampering() throws {
        let folder = recipeTemporaryFolder()
        defer { try? FileManager.default.removeItem(at: folder) }
        let file = folder.appendingPathComponent("trust.json")
        let secrets = InMemorySecretStore()
        let path = "/tmp/recipes/b.gsrecipe.json"
        try RecipeTrustStore(fileURL: file, secrets: secrets)
            .recordApproval(RecipeApproval(recipeId: "b"), forFile: path, sha256: "11", content: nil, origin: "ai:Claude", recipeName: "B", recipeVersion: nil)
        let reopened = RecipeTrustStore(fileURL: file, secrets: secrets)
        let record = try #require(reopened.record(forFile: path))
        #expect(record.isAICreated)
        #expect(record.proposedBy == "Claude")
        #expect(!reopened.wasTampered)

        // Someone edits the file: the signature doesn't match any more, nothing is approved.
        let text = try String(contentsOf: file, encoding: .utf8)
        try text.replacingOccurrences(of: "\"signature\":\"", with: "\"signature\":\"AAAA").write(to: file, atomically: true, encoding: .utf8)
        let tampered = RecipeTrustStore(fileURL: file, secrets: secrets)
        #expect(tampered.record(forFile: path) == nil)
        #expect(tampered.wasTampered)

        // Without the key nothing is approved either.
        try RecipeTrustStore(fileURL: file, secrets: secrets)
            .recordApproval(RecipeApproval(recipeId: "b"), forFile: path, sha256: "11", content: nil, origin: nil, recipeName: nil, recipeVersion: nil)
        let keyless = RecipeTrustStore(fileURL: file, secrets: InMemorySecretStore())
        #expect(keyless.allRecords.isEmpty)
        #expect(keyless.wasTampered)
    }

    /// The Keychain fails to read the key for a while (not "no key"): nothing is approved meanwhile, nothing is saved over
    /// the approvals, and once it reads again they are all back.
    @Test func aKeyThatCantBeReadForAWhileDoesntLoseTheApprovals() throws {
        let folder = recipeTemporaryFolder()
        defer { try? FileManager.default.removeItem(at: folder) }
        let file = folder.appendingPathComponent("trust.json")
        let secrets = FlakySecretStore()
        let first = "/tmp/recipes/first.gsrecipe.json"
        let second = "/tmp/recipes/second.gsrecipe.json"
        try RecipeTrustStore(fileURL: file, secrets: secrets)
            .recordApproval(RecipeApproval(recipeId: "one"), forFile: first, sha256: "11", content: nil, origin: nil, recipeName: nil, recipeVersion: nil)

        let store = RecipeTrustStore(fileURL: file, secrets: secrets)
        secrets.failsReading = true
        #expect(store.record(forFile: first) == nil)
        #expect(throws: FlakySecretStore.ReadError.self) {
            try store.recordApproval(RecipeApproval(recipeId: "two"), forFile: second, sha256: "22", content: nil, origin: nil,
                                     recipeName: nil, recipeVersion: nil)
        }
        // A revocation isn't lost either: it says it failed.
        #expect(throws: FlakySecretStore.ReadError.self) { try store.revokeApproval(recipeId: "one", forFile: first) }
        #expect(throws: FlakySecretStore.ReadError.self) { try store.revokeAll(forFile: first) }
        secrets.failsReading = false
        #expect(store.approval(forFile: first, sha256: "11", recipeId: "one") != nil)
        try store.recordApproval(RecipeApproval(recipeId: "two"), forFile: second, sha256: "22", content: nil, origin: nil,
                                 recipeName: nil, recipeVersion: nil)
        let reopened = RecipeTrustStore(fileURL: file, secrets: secrets)
        #expect(reopened.allRecords.map(\.filePath) == [first, second].map(RecipeTrustStore.standardized))
        #expect(!reopened.wasTampered)
    }

    /// The key is gone for a while (deleted, then put back): the store counts as empty (default-deny), but the first
    /// approval saved after the key is back keeps the approvals of the other files.
    @Test func aKeyThatWasHiddenForAWhileDoesntLoseTheApprovals() throws {
        let folder = recipeTemporaryFolder()
        defer { try? FileManager.default.removeItem(at: folder) }
        let file = folder.appendingPathComponent("trust.json")
        let secrets = FlakySecretStore()
        let first = "/tmp/recipes/first.gsrecipe.json"
        let second = "/tmp/recipes/second.gsrecipe.json"
        try RecipeTrustStore(fileURL: file, secrets: secrets)
            .recordApproval(RecipeApproval(recipeId: "one"), forFile: first, sha256: "11", content: nil, origin: nil, recipeName: nil, recipeVersion: nil)

        let store = RecipeTrustStore(fileURL: file, secrets: secrets)
        secrets.hidesItems = true
        #expect(store.record(forFile: first) == nil)
        #expect(store.wasTampered)
        secrets.hidesItems = false
        try store.recordApproval(RecipeApproval(recipeId: "two"), forFile: second, sha256: "22", content: nil, origin: nil,
                                 recipeName: nil, recipeVersion: nil)
        let reopened = RecipeTrustStore(fileURL: file, secrets: secrets)
        #expect(reopened.allRecords.map(\.filePath) == [first, second].map(RecipeTrustStore.standardized))
    }

    /// The Keychain can unlock between the two reads of one change: the prompt of the read before the change cancelled,
    /// the password typed at the prompt of the save's read. The change is still refused: it was made on records the
    /// locked Keychain didn't give (empty), and saved it would be the only approval left.
    @Test func aChangeIsRefusedWhenTheKeychainUnlocksOnlyAtTheSave() throws {
        let folder = recipeTemporaryFolder()
        defer { try? FileManager.default.removeItem(at: folder) }
        let file = folder.appendingPathComponent("trust.json")
        let secrets = FlakySecretStore()
        let first = "/tmp/recipes/first.gsrecipe.json"
        let second = "/tmp/recipes/second.gsrecipe.json"
        try RecipeTrustStore(fileURL: file, secrets: secrets)
            .recordApproval(RecipeApproval(recipeId: "one"), forFile: first, sha256: "11", content: nil, origin: nil, recipeName: nil, recipeVersion: nil)
        let saved = try Data(contentsOf: file)

        let store = RecipeTrustStore(fileURL: file, secrets: secrets)
        secrets.unavailableReads = 1
        #expect(store.allRecords.isEmpty)
        secrets.unavailableReads = 1
        #expect(throws: SecretStoreUnavailableError.self) {
            try store.recordApproval(RecipeApproval(recipeId: "two"), forFile: second, sha256: "22", content: nil, origin: nil,
                                     recipeName: nil, recipeVersion: nil)
        }
        let after = try Data(contentsOf: file)
        #expect(after == saved)
        let reopened = RecipeTrustStore(fileURL: file, secrets: secrets)
        #expect(reopened.allRecords.map(\.filePath) == [RecipeTrustStore.standardized(first)])
    }

    /// After a locked Keychain the empty records stay (no password prompt per look-up) until a change, a new store (the
    /// next start) or `readAgainIfUnavailable` (Reload Recipes) reads the key again; a store that was read isn't.
    @Test func aLockedKeychainIsReadAgainWhenAskedTo() throws {
        let folder = recipeTemporaryFolder()
        defer { try? FileManager.default.removeItem(at: folder) }
        let file = folder.appendingPathComponent("trust.json")
        let secrets = LockableSecretStore()
        let path = "/tmp/recipes/a.gsrecipe.json"
        try RecipeTrustStore(fileURL: file, secrets: secrets)
            .recordApproval(RecipeApproval(recipeId: "one"), forFile: path, sha256: "11", content: nil, origin: nil, recipeName: nil, recipeVersion: nil)

        secrets.isLocked = true
        let store = RecipeTrustStore(fileURL: file, secrets: secrets)
        #expect(store.allRecords.isEmpty)
        // Asked again while still locked: one read, still empty, still no change saved.
        store.readAgainIfUnavailable()
        let lockedReads = secrets.reads
        #expect(store.allRecords.isEmpty)
        #expect(store.allRecords.isEmpty)
        #expect(secrets.reads == lockedReads + 1)
        #expect(throws: SecretStoreUnavailableError.self) { try store.revokeAll(forFile: path) }

        // Unlocked (in Keychain Access): a look-up alone doesn't read again, Reload Recipes does.
        secrets.isLocked = false
        #expect(store.approval(forFile: path, sha256: "11", recipeId: "one") == nil)
        store.readAgainIfUnavailable()
        #expect(store.approval(forFile: path, sha256: "11", recipeId: "one") != nil)
        #expect(!store.wasTampered)
        let reads = secrets.reads
        store.readAgainIfUnavailable()
        #expect(store.allRecords.count == 1)
        #expect(secrets.reads == reads)
    }

    @Test func revokes() throws {
        let folder = recipeTemporaryFolder()
        defer { try? FileManager.default.removeItem(at: folder) }
        let store = RecipeTrustStore(fileURL: folder.appendingPathComponent("trust.json"), secrets: InMemorySecretStore())
        let path = "/tmp/c.gsrecipe.json"
        for id in ["x", "y"] {
            try store.recordApproval(RecipeApproval(recipeId: id), forFile: path, sha256: "1", content: nil, origin: nil, recipeName: nil, recipeVersion: nil)
        }
        try store.revokeApproval(recipeId: "X", forFile: path)
        #expect(store.record(forFile: path)?.recipes.map(\.recipeId) == ["y"])
        try store.revokeApproval(recipeId: "y", forFile: path)
        #expect(store.record(forFile: path) == nil)
        try store.recordApproval(RecipeApproval(recipeId: "z"), forFile: path, sha256: "1", content: nil, origin: nil, recipeName: nil, recipeVersion: nil)
        try store.revokeAll(forFile: path)
        #expect(store.allRecords.isEmpty)
    }

    @Test func keepsOnlySmallContent() throws {
        let folder = recipeTemporaryFolder()
        defer { try? FileManager.default.removeItem(at: folder) }
        let store = RecipeTrustStore(fileURL: folder.appendingPathComponent("trust.json"), secrets: InMemorySecretStore())
        let big = String(repeating: "x", count: RecipeTrustStore.maxApprovedContentLength + 1)
        try store.recordApproval(RecipeApproval(recipeId: "big"), forFile: "/tmp/big.json", sha256: "1", content: big, origin: nil, recipeName: nil, recipeVersion: nil)
        #expect(store.record(forFile: "/tmp/big.json")?.approvedContent == nil)
    }

    @Test func hashes() {
        #expect(RecipeHash.sha256Hex(Data("abc".utf8)) == "ba7816bf8f01cfea414140de5dae2223b00361a396177a9cb410ff61f20015ad")
    }
}

extension InMemorySecretStore {
    func secretValue(_ key: String) -> String? {
        (try? secret(for: key)) ?? nil
    }
}

/// A secret store whose reads throw while `failsReading` is set (an error of the Keychain), or find nothing while
/// `hidesItems` is set (the key was deleted). A locked Keychain throws `SecretStoreUnavailableError`: `LockableSecretStore`,
/// or here `unavailableReads` for a Keychain that unlocks between two reads.
final class FlakySecretStore: SecretStore, @unchecked Sendable {
    struct ReadError: Error {}

    private let base = InMemorySecretStore()
    private let lock = NSLock()
    private var failing = false
    private var hiding = false
    private var unavailable = 0

    var failsReading: Bool {
        get { lock.withLock { failing } }
        set { lock.withLock { failing = newValue } }
    }

    var hidesItems: Bool {
        get { lock.withLock { hiding } }
        set { lock.withLock { hiding = newValue } }
    }

    /// The next reads that throw `SecretStoreUnavailableError`: the Keychain's password prompt cancelled that many
    /// times, then answered with the password.
    var unavailableReads: Int {
        get { lock.withLock { unavailable } }
        set { lock.withLock { unavailable = newValue } }
    }

    func secret(for key: String) throws -> String? {
        let isUnavailable: Bool = lock.withLock {
            guard unavailable > 0 else { return false }
            unavailable -= 1
            return true
        }
        if isUnavailable { throw SecretStoreUnavailableError("The Keychain is locked.") }
        if failsReading { throw ReadError() }
        if hidesItems { return nil }
        return try base.secret(for: key)
    }

    func setSecret(_ value: String?, for key: String) throws {
        try base.setSecret(value, for: key)
    }
}

/// Upstream RecipeApprovalTests: policy, diff, describer, the editor's decision table.
@Suite struct RecipeApprovalTests {
    func recipe(_ id: String, triggers: [TriggerConfig] = []) -> CaptureRecipe {
        var recipe = testRecipe()
        recipe.id = id
        recipe.triggers = triggers
        return recipe
    }

    func hotkey(_ text: String) -> TriggerConfig { TriggerConfig(triggerType: "Hotkey", parameters: ["Hotkey": .string(text)]) }
    var clipboard: TriggerConfig { TriggerConfig(triggerType: "Clipboard", parameters: ["OnImageCopied": .bool(true)]) }

    @Test func diffs() throws {
        #expect(RecipeTextDiff.unifiedText("a\nb\n", "a\r\nb") == "// No changes.")
        let oldLines = (1...20).map { "line \($0)" }
        var newLines = oldLines
        newLines[1] = "line two"
        newLines.insert("inserted", at: 15)
        let diff = RecipeTextDiff.unifiedText(oldLines.joined(separator: "\n"), newLines.joined(separator: "\n"), context: 1)
        let lines = diff.split(separator: "\n").map(String.init)
        #expect(lines.contains("- line 2"))
        #expect(lines.contains("+ line two"))
        #expect(lines.contains("+ inserted"))
        #expect(!lines.contains("  line 8"))
        #expect(lines.contains("@@"))
        let huge = (0...RecipeTextDiff.maxLines).map(String.init).joined(separator: "\n")
        #expect(RecipeTextDiff.compare(huge, "x") == nil)
        #expect(RecipeTextDiff.unifiedText(huge, "x").contains("too large"))
        let lineDiff = try #require(RecipeTextDiff.compare("a\nb", "a\nc"))
        #expect(lineDiff == [RecipeDiffLine(.unchanged, "a"), RecipeDiffLine(.removed, "b"), RecipeDiffLine(.added, "c")])
    }

    @Test func missingGates() {
        var validation = RecipeValidationResult()
        validation.gatedActions = [RecipeGatedAction(.networkAccess, target: "Jira"), RecipeGatedAction(.externalCommand, target: "x")]
        #expect(RecipeApprovalPolicy.missingGates(validation, approval: nil) == [.externalCommand, .networkAccess])
        let approval = RecipeApproval(recipeId: "r", allowedGates: [.networkAccess])
        #expect(RecipeApprovalPolicy.missingGates(validation, approval: approval) == [.externalCommand])
        #expect(RecipeApprovalPolicy.triggerKey(index: 2, trigger: clipboard) == "2:Clipboard")
    }

    @Test func describerExplainsTriggers() {
        var command = TriggerConfig(triggerType: "Commandline", parameters: ["Command": .string("qr"), "AllowBrowserInvocation": .bool(true)])
        command.enabled = false
        let described = RecipeDescriber().describeTriggers(recipe("t", triggers: [hotkey("Ctrl + Shift + B"), clipboard, command]))
        #expect(described.map(\.key) == ["0:Hotkey", "1:Clipboard", "2:Commandline", "2:Commandline:browser"])
        #expect(described[0].label == "Hotkey ⇧⌘B")
        #expect(described[0].risk == nil)
        #expect(described[1].risk == "Runs on its own every time you copy an image, without you starting it.")
        #expect(described[2].label == "Command line command \"qr\"")
        #expect(described[3].isDisabled)
    }

    @Test func describerShowsWhatStepsDo() {
        var recipe = testRecipe([
            RecipeNode(id: "s", stepType: "Source", parameters: ["sourceType": .string("Window"), "windowTitle": .string("Notes"), "delayMs": .number(500)]),
            RecipeNode(id: "c", stepType: "ExternalCommand", parameters: ["commandLine": .string("/usr/local/bin/pngquant")]),
            RecipeNode(id: "d", stepType: "Destinations", parameters: ["destinationDesignations": .array([.string("Clipboard"), .string("Jira")])]),
            RecipeNode(id: "e", stepType: "Effect", parameters: ["effect": .string("DropShadow"), "shadowSize": .number(10)])
        ], transitions: [("s", ["c"]), ("c", ["d"]), ("d", ["e"])], start: ["s"])
        recipe.nodes[3].enabled = .expression("${option.shadow}")
        let lines = RecipeDescriber().describeSteps(recipe)
        #expect(lines.map(\.text) == [
            "Captures the window \"Notes\", after 500 ms",
            "External Command (commandLine: /usr/local/bin/pngquant)",
            "Runs the program /usr/local/bin/pngquant",
            "Sends the result to Copy to clipboard (Clipboard), Upload to Jira… (Jira)",
            "Uploads to Jira",
            "Image Effect (effect: DropShadow, shadowSize: 10) (only when ${option.shadow})"
        ])
        #expect(lines[1].risk == .externalCommand)
        #expect(lines[2].isDetail)
        #expect(lines[3].risk == .networkAccess)
    }

    @Test func describerNamesChanges() {
        let old = recipe("c", triggers: [hotkey("Ctrl + Shift + B")])
        var new = recipe("c", triggers: [clipboard])
        new.nodes.append(RecipeNode(id: "x", stepType: "Printer"))
        let changes = RecipeDescriber().describeChanges(from: old, to: new)
        #expect(changes == ["Adds: trigger When an image is copied to the clipboard", "Adds: Prints the result", "Removes: trigger Hotkey ⇧⌘B"])
    }

    @Test func editKeepsSwitchesAndApprovesHarmlessTriggers() {
        let approved = recipe("edit_recipe", triggers: [hotkey("Ctrl + Shift + F9"), clipboard])
        let previous = RecipeApproval(recipeId: "edit_recipe", approvedTriggers: ["0:Hotkey"])
        var edited = approved
        edited.triggers.insert(hotkey("Ctrl + Shift + F10"), at: 0)
        let (approval, decision) = RecipeEditApproval.create(edited: edited, validation: RecipeValidator().validate(edited),
                                                             approvedVersion: approved, previousApproval: previous, replacesBuiltIn: false)
        #expect(!decision.isNeeded)
        #expect(approval.isTriggerApproved("0:Hotkey"))
        #expect(approval.isTriggerApproved("1:Hotkey"))
        #expect(!approval.isTriggerApproved("2:Clipboard"))
    }

    @Test func editAddingAnAutonomousTriggerNeedsADecision() {
        let edited = recipe("edit_risky", triggers: [clipboard])
        let (_, decision) = RecipeEditApproval.create(edited: edited, validation: RecipeValidator().validate(edited),
                                                      approvedVersion: recipe("edit_risky"), previousApproval: RecipeApproval(recipeId: "edit_risky"),
                                                      replacesBuiltIn: false)
        #expect(decision.isNeeded)
        #expect(decision.triggerKeys == ["0:Clipboard"])
    }

    @Test func editWithoutTheApprovedVersionAsksForRiskyTriggers() {
        var previous = RecipeApproval(recipeId: "edit_legacy")
        previous.allTriggers = true
        let edited = recipe("edit_legacy", triggers: [TriggerConfig(triggerType: "Hotkey"), clipboard])
        let (approval, decision) = RecipeEditApproval.create(edited: edited, validation: RecipeValidator().validate(edited),
                                                             approvedVersion: nil, previousApproval: previous, replacesBuiltIn: false)
        #expect(decision.triggerKeys == ["1:Clipboard"])
        #expect(approval.approvedTriggers == ["0:Hotkey"])
    }

    @Test func editNeedingANewKindOfPermission() {
        var edited = recipe("edit_gates")
        edited.nodes.append(RecipeNode(id: "cmd", stepType: "ExternalCommand", parameters: ["commandLine": .string("/opt/optimize")]))
        edited.flow.addTransition(from: "b", to: "cmd")
        let validation = RecipeValidator().validate(edited)
        let (_, first) = RecipeEditApproval.create(edited: edited, validation: validation, approvedVersion: recipe("edit_gates"),
                                                   previousApproval: RecipeApproval(recipeId: "edit_gates"), replacesBuiltIn: false)
        #expect(first.reasons == ["It needs external commands."])
        let allowed = RecipeApproval(recipeId: "edit_gates", allowedGates: [.externalCommand])
        let (approval, second) = RecipeEditApproval.create(edited: edited, validation: validation, approvedVersion: recipe("edit_gates"),
                                                           previousApproval: allowed, replacesBuiltIn: false)
        #expect(!second.isNeeded)
        #expect(approval.isGateAllowed(.externalCommand))
    }

    @Test func editReplacingABuiltIn() {
        let edited = recipe("recipe_region")
        let (_, first) = RecipeEditApproval.create(edited: edited, validation: RecipeValidator().validate(edited), approvedVersion: nil,
                                                   previousApproval: nil, replacesBuiltIn: true)
        #expect(first.reasons == ["It replaces the built-in recipe \"recipe_region\"."])
        var replaced = RecipeApproval(recipeId: "recipe_region")
        replaced.replacesBuiltIn = true
        let (_, second) = RecipeEditApproval.create(edited: edited, validation: RecipeValidator().validate(edited), approvedVersion: edited,
                                                    previousApproval: replaced, replacesBuiltIn: true)
        #expect(!second.isNeeded)
    }

    @Test func findsTheApprovedVersion() {
        let content = RecipeSerializer.encode([recipe("a"), recipe("b")])
        #expect(RecipeEditApproval.findRecipe(in: content, id: "B")?.id == "b")
        #expect(RecipeEditApproval.findRecipe(in: "not json", id: "b") == nil)
    }
}
