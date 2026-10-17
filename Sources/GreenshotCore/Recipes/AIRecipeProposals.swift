// Greenshot for Mac (Community) - an unofficial macOS port of Greenshot
// Copyright (C) 2026 Greenshot for Mac (Community) contributors
// Based on Greenshot, Copyright (C) 2007-2026 Thomas Braun, Jens Klingen, Robin Krom
// SPDX-License-Identifier: GPL-3.0-or-later

import Foundation

/// PROPOSE_RECIPE (propose_recipe, update_recipe; upstream `AiRecipeIpcHandler.HandleProposeRecipeAsync`): a recipe an
/// AI tool wrote is shown in the approval sheet, marked as written by the AI tool, with all switches off; it is saved only
/// when the user approves it, with only what the user switched on. Greenshot saves only what it showed: it writes the
/// recipe JSON itself, and those bytes are hashed, approved and saved. One proposal at a time; a rejected one isn't shown
/// again until the app restarts.
@MainActor
public final class AIRecipeProposals {
    /// What the AI tool sent.
    public struct Proposal: Sendable {
        public var json: String?
        /// The user's request and the AI tool's explanation, shown as the AI tool's (untrusted) words.
        public var request: String?
        public var explanation: String?
        /// update_recipe: the id of the recipe it changes.
        public var replaces: String?
        public var client: AIToolClient

        public init(json: String?, request: String?, explanation: String?, replaces: String?, client: AIToolClient) {
            self.json = json
            self.request = request
            self.explanation = explanation
            self.replaces = replaces
            self.client = client
        }
    }

    /// The reply, and the saved file when the user ticked "Open in the recipe editor after saving" (the caller opens it).
    public struct Outcome: Sendable {
        public var reply: IPCReply
        public var openInEditor: URL?
    }

    private let library: RecipeLibrary
    /// `<recipes folder>/AI`: where new recipes of AI tools go (upstream `Recipes\AI` next to greenshot.ini).
    public let folder: URL
    private var rejected: Set<String> = []
    private var busy = false

    public init(library: RecipeLibrary, folder: URL) {
        self.library = library
        self.folder = folder
    }

    public func propose(_ proposal: Proposal) async -> Outcome {
        guard library.isFeatureEnabled else {
            return Outcome(reply: .error("Recipes are switched off in Greenshot for Mac (Settings › Recipes), so it can't take recipes."),
                           openInEditor: nil)
        }
        let draft: AIRecipeDraft
        switch AIRecipeCatalog.parse(proposal.json, library: library) {
        case .success(let parsed): draft = parsed
        case .failure(let error): return Outcome(reply: .error(error.message), openInEditor: nil)
        }
        guard draft.validation.isValid else {
            let errors = draft.validation.errors.joined(separator: "\n")
            return Outcome(reply: .error("The recipe is not valid, fix it first (validate_recipe):\n" + errors), openInEditor: nil)
        }
        if draft.isExtension { return await proposeExtension(draft, proposal) }

        var recipe = draft.recipe
        let target: Target
        switch resolveTarget(&recipe, replaces: proposal.replaces) {
        case .success(let resolved): target = resolved
        case .failure(let error): return Outcome(reply: .error(error.message), openInEditor: nil)
        }
        // The id may now be the replaced recipe's
        let content = RecipeSerializer.encode(recipe)
        let data = Data(content.utf8)
        let hash = RecipeHash.sha256Hex(data)
        let rejectionKey = proposal.client.key.lowercased() + "|" + hash
        guard !rejected.contains(rejectionKey) else {
            return Outcome(reply: .error("The user already rejected this recipe. Ask the user what to change before proposing a recipe again."),
                           openInEditor: nil)
        }
        guard !busy else {
            return Outcome(reply: .error("Another recipe proposal is waiting for the user, try again after it was answered."), openInEditor: nil)
        }
        busy = true
        defer { busy = false }

        let request = approvalRequest(recipe, target: target, content: content, hash: hash, validation: draft.validation, proposal: proposal)
        guard let decision = await library.approver?.requestApproval(request), var approval = decision.approval else {
            rejected.insert(rejectionKey)
            log.info("The user rejected the recipe '\(recipe.id)' proposed by \(proposal.client.logText).")
            return Outcome(reply: .ok("The user rejected the recipe, nothing was saved.",
                                      extra: ["decision": .string("rejected"), "recipe": .string(recipe.id)]), openInEditor: nil)
        }
        approval.recipeId = recipe.id
        approval.replacesBuiltIn = library.builtInRecipe(id: recipe.id) != nil
        if let error = save(data, content: content, hash: hash, approval: approval, to: target.fileURL, recipe: recipe, client: proposal.client) {
            return Outcome(reply: .error(error), openInEditor: nil)
        }
        log.info("Saved the recipe '\(recipe.id)' proposed by \(proposal.client.logText) to '\(target.fileURL.path)'.")
        // Loads what is on disk now: changed since it was written, the hash doesn't match and nothing is loaded
        let loaded = await library.loadFile(target.fileURL, interactive: false)
        guard loaded.isValid else {
            return Outcome(reply: .error("The recipe was saved, but could not be loaded: \(loaded.errors.joined(separator: "; "))"),
                           openInEditor: nil)
        }
        let describer = RecipeDescriber(contracts: library.contracts, gates: library.gates())
        let triggers = describer.describeTriggers(recipe)
        let on = triggers.filter { approval.isTriggerApproved($0.key) }.map { JSONValue.string($0.label) }
        let off = triggers.filter { !approval.isTriggerApproved($0.key) }.map { JSONValue.string($0.label) }
        let reply = IPCReply.ok("The user approved the recipe, it is saved.",
                                extra: ["decision": .string("approved"), "recipe": .string(recipe.id), "file": .string(target.fileURL.path),
                                        "triggers_on": .array(on), "triggers_off": .array(off)])
        return Outcome(reply: reply, openInEditor: decision.openInEditor ? target.fileURL : nil)
    }

    /// The text shown as who proposed it: name, path and signer (the approval sheet's banner).
    public static func proposerText(_ client: AIToolClient) -> String {
        let script = client.identity.script.map { " running \($0)" } ?? ""
        let text = "\(client.displayName) — \(client.path)\(script) · \(client.signer.map { "signed by \($0)" } ?? "not signed by a developer")"
        return AIToolText.displayed(text, limit: 400)
    }

    // MARK: Target

    struct Target {
        var fileURL: URL
        var replaced: LoadedRecipe?
        var replacesBuiltIn: Bool
    }

    /// Upstream `ResolveTarget`: a new recipe gets its own file in the AI folder and needs an unused id; a change keeps
    /// the recipe's file when that file holds only this recipe; a built-in recipe gets a file in the AI folder.
    func resolveTarget(_ recipe: inout CaptureRecipe, replaces: String?) -> Result<Target, AIToolError> {
        let replacedId = replaces?.trimmingCharacters(in: .whitespaces) ?? ""
        guard !replacedId.isEmpty else {
            if library.recipe(id: recipe.id) != nil || library.extensions.contains(where: { recipeEquals($0.recipe.id, recipe.id) }) {
                return .failure(AIToolError("A recipe with the id '\(recipe.id)' exists. Use another id, or update_recipe to change that recipe."))
            }
            return .success(Target(fileURL: newFileURL(for: recipe.id), replaced: nil, replacesBuiltIn: false))
        }
        guard let existing = library.recipe(id: replacedId) else {
            return .failure(AIToolError("There is no recipe with the id '\(replacedId)'."))
        }
        // The changed recipe keeps the id of the recipe it replaces
        recipe.id = existing.recipe.id
        let replacesBuiltIn = library.builtInRecipe(id: existing.recipe.id) != nil
        guard let file = existing.fileURL else {
            return .success(Target(fileURL: newFileURL(for: existing.recipe.id), replaced: existing, replacesBuiltIn: replacesBuiltIn))
        }
        let inFile = library.recipes.filter { $0.fileURL.map { recipeEquals($0.path, file.path) } ?? false }.count
        guard inFile <= 1 else {
            return .failure(AIToolError("The recipe '\(existing.recipe.id)' is in a file with other recipes (\(file.path)), change it in the recipe editor."))
        }
        return .success(Target(fileURL: file, replaced: existing, replacesBuiltIn: replacesBuiltIn))
    }

    /// `<folder>/<id>.gsrecipe.json` with characters a file name can't have replaced, `-2`, `-3`, … when taken.
    func newFileURL(for recipeId: String) -> URL {
        let cleaned = String(recipeId.map { "/:\\.".contains($0) || $0.isNewline ? "_" : $0 })
        let base = cleaned.trimmingCharacters(in: .whitespaces).isEmpty ? "recipe" : cleaned
        var url = folder.appendingPathComponent(base + RecipeSerializer.fileExtension)
        var number = 2
        while FileManager.default.fileExists(atPath: url.path) {
            url = folder.appendingPathComponent("\(base)-\(number)" + RecipeSerializer.fileExtension)
            number += 1
        }
        return URL(fileURLWithPath: RecipeTrustStore.standardized(url.path))
    }

    // MARK: The sheet

    func approvalRequest(_ recipe: CaptureRecipe, target: Target, content: String, hash: String, validation: RecipeValidationResult,
                         proposal: Proposal) -> RecipeApprovalRequest {
        var request = library.approvalRequest(recipe, target.fileURL, content, hash, validation,
                                              mode: target.replaced == nil ? .newRecipe : .modified)
        if let replaced = target.replaced, request.previousContent == nil {
            let previous = RecipeSerializer.encode(replaced.recipe)
            request.previousContent = previous
            request.diff = RecipeTextDiff.compare(previous, content)
            request.changes = RecipeDescriber(contracts: library.contracts, gates: library.gates())
                .describeChanges(from: replaced.recipe, to: recipe)
            request.replacedRecipe = replaced.recipe
        }
        request.replacesBuiltIn = request.replacesBuiltIn || target.replacesBuiltIn
        request.proposedBy = Self.proposerText(proposal.client)
        request.aiRequest = Self.truncated(proposal.request, 2000)
        request.aiExplanation = Self.truncated(proposal.explanation, 4000)
        request.startSwitchedOff = true
        request.suggestedApproval = nil
        return request
    }

    static func truncated(_ text: String?, _ limit: Int) -> String? {
        guard let text, !text.isEmpty else { return nil }
        return text.count <= limit ? text : String(text.prefix(limit)) + "…"
    }

    // MARK: Saving

    /// Upstream `SaveAsync`: the approval is recorded before the file is written, so the change on disk is known as
    /// Greenshot's own and doesn't ask again.
    private func save(_ data: Data, content: String, hash: String, approval: RecipeApproval, to url: URL, recipe: CaptureRecipe,
                      client: AIToolClient) -> String? {
        do {
            try library.trustStore.recordApproval(approval, forFile: url.path, sha256: hash, content: content,
                                                  origin: RecipeTrustRecord.aiOriginPrefix + client.displayName,
                                                  recipeName: recipe.name, recipeVersion: recipe.version)
        } catch {
            log.error("The approval of the recipe '\(recipe.id)' proposed by an AI tool could not be saved.", error: error)
            return "The user approved the recipe, but Greenshot could not save its approval: \(error.localizedDescription)"
        }
        do {
            try FileManager.default.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
            try data.write(to: url, options: .atomic)
        } catch {
            log.error("Could not save the recipe '\(recipe.id)' to '\(url.path)'.", error: error)
            return "The user approved the recipe, but Greenshot could not save it: \(error.localizedDescription)"
        }
        library.askedForChangedFile[url.path.lowercased()] = hash
        return nil
    }

    // MARK: Automatic steps

    /// An automatic step: the library's `proposeExtension` shows it with which recipes it changes and saves it switched off
    /// (RMANAGER's). Upstream `ProposeExtensionAsync`: a change keeps the id of the step it replaces (SM-M4, MC-M2); a
    /// rejected one isn't shown again until the app restarts, and the rejection is the user's answer, not an error
    /// (MC-M3); the reply says whether it is switched on (SM-M3).
    private func proposeExtension(_ draft: AIRecipeDraft, _ proposal: Proposal) async -> Outcome {
        // TODO(merge): before the sheet, refuse a step without a Boolean "enabled" option with RMANAGER's
        // `RecipeExtensionNames.aiProposalProblem(draft.recipe)` (SM-M3): the AI tool gets the reason without a sheet. Its
        // `proposeExtension` refuses such a step itself; VALIDATE_RECIPE reports it already (`AIRecipeCatalog`).
        var step = draft.recipe
        var content = draft.content
        let replacedId = proposal.replaces?.trimmingCharacters(in: .whitespaces) ?? ""
        var url: URL
        if replacedId.isEmpty {
            if library.extensions.contains(where: { recipeEquals($0.recipe.id, step.id) }) || library.recipe(id: step.id) != nil {
                return Outcome(reply: .error("The id '\(step.id)' is used. Use another id, or update_recipe to change that automatic step."),
                               openInEditor: nil)
            }
            url = newFileURL(for: step.id)
        } else {
            guard let replaced = library.extensions.first(where: { recipeEquals($0.recipe.id, replacedId) }) else {
                return Outcome(reply: .error("There is no automatic step with the id '\(replacedId)'."), openInEditor: nil)
            }
            // The changed step keeps the id of the one it replaces, and its file when it has one
            if step.id != replaced.recipe.id {
                step.id = replaced.recipe.id
                content = RecipeSerializer.encode(step)
            }
            url = replaced.fileURL ?? newFileURL(for: replaced.recipe.id)
        }
        let rejectionKey = proposal.client.key.lowercased() + "|" + RecipeHash.sha256Hex(Data(content.utf8))
        guard !rejected.contains(rejectionKey) else {
            return Outcome(reply: .error("The user already rejected this automatic step. Ask the user what to change before proposing it again."),
                           openInEditor: nil)
        }
        guard !busy else {
            return Outcome(reply: .error("Another proposal is waiting for the user, try again after it was answered."), openInEditor: nil)
        }
        busy = true
        defer { busy = false }
        let result = await library.proposeExtension(content: content, proposedBy: Self.proposerText(proposal.client),
                                                    aiRequest: Self.truncated(proposal.request, 2000),
                                                    aiExplanation: Self.truncated(proposal.explanation, 4000), saveTo: url)
        guard result.isValid, !result.loadedRecipeIds.isEmpty else {
            if Self.isRejection(result) {
                rejected.insert(rejectionKey)
                log.info("The user rejected the automatic step '\(step.id)' proposed by \(proposal.client.logText).")
                return Outcome(reply: .ok("The user rejected the automatic step, nothing was saved.",
                                          extra: ["decision": .string("rejected"), "recipe": .string(step.id),
                                                  "kind": .string(RecipeKind.extension.rawValue)]), openInEditor: nil)
            }
            return Outcome(reply: .error(result.errors.isEmpty ? "The automatic step was not saved." : result.errors.joined(separator: "\n")),
                           openInEditor: nil)
        }
        url = URL(fileURLWithPath: RecipeTrustStore.standardized(url.path))
        let isOn = library.extensions.first { recipeEquals($0.recipe.id, step.id) }?.isEnabled ?? false
        let text = isOn ? "The user approved the automatic step, it is saved and switched on."
                        : "The user approved the automatic step, it is saved. It is switched off: the user switches it on in Settings › Recipes."
        return Outcome(reply: .ok(text, extra: ["decision": .string("approved"), "recipe": .string(step.id),
                                                "kind": .string(RecipeKind.extension.rawValue), "file": .string(url.path),
                                                "switched_on": .bool(isOn)]),
                       openInEditor: nil)
    }

    /// The library's answer to a rejected automatic step (`proposeExtension`'s "The user rejected the automatic step …").
    static func isRejection(_ result: RecipeLoadResult) -> Bool {
        result.loadedRecipeIds.isEmpty && result.errors.count == 1 && result.errors[0].hasPrefix("The user rejected the automatic step")
    }
}

private let log = Log("AITools")
