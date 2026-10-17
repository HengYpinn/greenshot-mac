// Greenshot for Mac (Community) - an unofficial macOS port of Greenshot
// Copyright (C) 2026 Greenshot for Mac (Community) contributors
// Based on Greenshot, Copyright (C) 2007-2026 Thomas Braun, Jens Klingen, Robin Krom
// SPDX-License-Identifier: GPL-3.0-or-later
// Owned by RMANAGER after the wave 4 prep.

import Foundation

/// The automatic steps (recipe extensions) the library knows, built in and from files (upstream `_extensions`,
/// `_builtInExtensions`). Keys are lowercased ids.
struct RecipeExtensionStore: Sendable {
    var builtIns: [String: CaptureRecipe] = [:]
    var builtInOrder: [String] = []
    var files: [String: LoadedRecipe] = [:]
    var fileOrder: [String] = []
    /// Opens an automatic step in the recipe editor (an AI proposal approved with "open in the recipe editor").
    var openInEditor: (@MainActor @Sendable (String) -> Void)?

    init() {
        for ext in RecipeBuiltInExtensions.all where builtIns[ext.id.lowercased()] == nil {
            builtIns[ext.id.lowercased()] = ext
            builtInOrder.append(ext.id.lowercased())
        }
    }
}

/// Automatic steps in recipe files (upstream `Greenshot/Recipes/RecipeManager.ExtensionFiles.cs`, a partial class of the
/// recipe manager like this extension of `RecipeLibrary`): loaded like recipe files, with their own approval in the trust
/// store. An automatic step changes other recipes, so the approval shows which ones; it is only used while its file is
/// approved, a file changed on disk drops it until it is approved again.
extension RecipeLibrary {
    // MARK: Hooks of RecipeLibrary.swift

    /// `loadFile` for a file whose recipes are automatic steps (`"kind": "extension"`): read once by `loadFile`, validated,
    /// approved (pinned to the SHA-256 of `content`), then used (upstream `LoadExtensionFromContent`).
    func loadExtensionFile(_ fileURL: URL, content: String, hash: String, definitions: [CaptureRecipe], interactive: Bool,
                           forcePrompt: Bool) async -> RecipeLoadResult {
        var result = RecipeLoadResult()
        let path = fileURL.path
        guard definitions.count == 1, let ext = definitions.first, ext.kind == .extension else {
            let message = definitions.contains(where: { $0.kind == .recipe })
                ? "The file mixes recipes and automatic steps (\"kind\": \"extension\"); an automatic step file holds one automatic step."
                : "The file holds \(definitions.count) automatic steps; an automatic step file holds one."
            result.errors.append(message)
            if interactive { await approver?.showValidationError(validationErrorRequest(fileURL, content, hash, recipe: nil, message: message)) }
            return result
        }
        let validation = validateExtension(ext)
        guard validation.isValid else {
            result.errors += validation.errors.map { "[\(ext.id.isEmpty ? "unknown" : ext.id)]: \($0)" }
            if interactive {
                let message = "The automatic step '\(ext.name.isEmpty ? ext.id : ext.name)' can't be used:\n" + validation.errors.joined(separator: "\n")
                var request = validationErrorRequest(fileURL, content, hash, recipe: ext, message: message)
                request.validation = validation
                await approver?.showValidationError(request)
            }
            return result
        }
        let key = ext.id.lowercased()
        let previousRecord = trustStore.record(forFile: path)
        var approval = forcePrompt ? nil : trustStore.approval(forFile: path, sha256: hash, recipeId: ext.id)
        var newlyApproved = false
        if approval == nil {
            // A file an AI tool wrote, changed on disk: like a proposal it needs its switch, the sheet says it starts off (S-N3).
            if previousRecord?.isAICreated == true, let problem = RecipeExtensionNames.aiProposalProblem(ext) {
                result.errors.append(problem)
                if interactive { await approver?.showValidationError(validationErrorRequest(fileURL, content, hash, recipe: ext, message: problem)) }
                return result
            }
            guard interactive, let approver else {
                result.errors.append("Automatic step '\(ext.name)' from '\(path)' is not approved and interactive approval is disabled.")
                return result
            }
            let mode: RecipeApprovalMode = forcePrompt ? .reVerify : (previousRecord == nil ? .newRecipe : .modified)
            let decision = await approver.requestApproval(extensionApprovalRequest(ext, fileURL, content, hash, validation, mode: mode))
            if var approved = decision?.approval {
                approved.recipeId = ext.id
                approved.approvedTriggers = []
                approved.replacesBuiltIn = extensionStore.builtIns[key] != nil
                do {
                    try trustStore.recordApproval(approved, forFile: path, sha256: hash, content: content, origin: previousRecord?.origin,
                                                  recipeName: ext.name, recipeVersion: ext.version)
                } catch {
                    log.error("The approval of automatic step '\(ext.id)' could not be saved.", error: error)
                    result.errors.append("The approval of automatic step '\(ext.name)' could not be saved: \(error.localizedDescription)")
                    return result
                }
                newlyApproved = previousRecord?.approval(for: ext.id) == nil
                approval = approved
            } else if decision?.isRevoked == true {
                try? trustStore.revokeApproval(recipeId: ext.id, forFile: path)
                if removeFileExtension(ext.id) { notify() }
                result.errors.append("The approval of automatic step '\(ext.name)' (\(ext.id)) was revoked.")
                return result
            } else if forcePrompt, let existing = trustStore.approval(forFile: path, sha256: hash, recipeId: ext.id) {
                log.info("The review of automatic step '\(ext.id)' was closed, its approval stays as it was.")
                approval = existing
            } else {
                result.errors.append("User rejected automatic step '\(ext.name)' (\(ext.id)) from '\(path)'.")
                return result
            }
        }
        let missing = RecipeApprovalPolicy.missingGates(validation, approval: approval)
        guard missing.isEmpty else {
            result.errors.append("Automatic step '\(ext.name)' needs \(missing.map(\.displayName).joined(separator: ", ")), but that was not allowed.")
            return result
        }
        result.warnings += validation.warnings.map { "[\(ext.id)]: \($0)" }
        let proposedBy = trustStore.record(forFile: path)?.proposedBy
        if newlyApproved, proposedBy != nil { switchOffNewAIExtension(ext) }
        registerFileExtension(LoadedRecipe(recipe: ext, source: .file(fileURL), replacesBuiltIn: extensionStore.builtIns[key] != nil,
                                           approval: approval, proposedBy: proposedBy, validation: validation))
        addFileToSettings(path)
        result.loadedRecipeIds.append(ext.id)
        if !loadingConfiguredFiles { notify() }
        return result
    }

    /// `reload()`: the automatic steps of files are loaded again with their files.
    func forgetFileExtensions() {
        extensionStore.files = [:]
        extensionStore.fileOrder = []
    }

    /// `fileDidChange`: whether the file is one of the loaded automatic steps.
    func isExtensionFile(_ path: String) -> Bool {
        extensionStore.files.values.contains { $0.fileURL.map { recipeEquals($0.path, path) } ?? false }
    }

    /// `fileDidChange`: the automatic steps of a changed file are not used until the change is approved (upstream
    /// `CheckChangedFile`, `DropExtension`).
    func dropExtensions(ofFile path: String) {
        let ids = extensionStore.files.values.filter { $0.fileURL.map { recipeEquals($0.path, path) } ?? false }.map(\.recipe.id)
        guard !ids.isEmpty else { return }
        for id in ids {
            extensionStore.files[id.lowercased()] = nil
            extensionStore.fileOrder.removeAll { $0 == id.lowercased() }
            log.info("Automatic step '\(id)' is not used anymore, until its file is approved (again).")
        }
        notify()
    }

    // MARK: For the other packages (names and signatures frozen by the prep)

    /// The automatic steps, built in and from files, by order then id; `recipe.kind == .extension`, `isEnabled` is the
    /// automatic step's `enabled` option (REDITOR's editor, MCP's catalog).
    public var extensions: [LoadedRecipe] {
        let values = optionValues
        var result: [LoadedRecipe] = []
        for key in extensionStore.builtInOrder where extensionStore.files[key] == nil {
            guard let ext = extensionStore.builtIns[key] else { continue }
            result.append(LoadedRecipe(recipe: ext, source: .builtIn, isEnabled: RecipeExtensionSettings.stored(for: ext, in: values).enabled))
        }
        for key in extensionStore.fileOrder {
            guard var loaded = extensionStore.files[key] else { continue }
            loaded.isEnabled = RecipeExtensionSettings.stored(for: loaded.recipe, in: values).enabled
            result.append(loaded)
        }
        return result.sorted { lhs, rhs in
            let left = lhs.recipe.extends?.order ?? 0
            let right = rhs.recipe.extends?.order ?? 0
            if left != right { return left < right }
            return lhs.recipe.id.lowercased() < rhs.recipe.id.lowercased()
        }
    }

    /// Saves an automatic step from the recipe editor (upstream `SaveExtensionToFile`): the approval is renewed for the
    /// saved content without asking, unless the change needs the user's decision (a new automatic step, it changes other
    /// recipes than before, a new permission) (REDITOR).
    public func saveExtension(_ ext: CaptureRecipe, to url: URL) async -> RecipeLoadResult {
        var result = RecipeLoadResult()
        guard ext.kind == .extension else {
            result.errors.append("This is a recipe, not an automatic step; save it as a recipe.")
            return result
        }
        let fileURL = URL(fileURLWithPath: RecipeTrustStore.standardized(url.path))
        let path = fileURL.path
        // The bytes which are approved are the bytes which are written.
        let content = RecipeSerializer.encode(ext)
        let data = Data(content.utf8)
        let hash = RecipeHash.sha256Hex(data)
        let validation = validateExtension(ext)
        guard validation.isValid else {
            result.errors += validation.errors
            return result
        }
        let record = trustStore.record(forFile: path)
        let previousApproval = record?.approval(for: ext.id)
        let reasons = extensionSaveReasons(ext, path: path, validation: validation)
        var approval: RecipeApproval
        if !reasons.isEmpty {
            log.info("The change of automatic step '\(ext.id)' needs the user's decision: \(reasons.joined(separator: " "))")
            var request = extensionApprovalRequest(ext, fileURL, content, hash, validation, mode: record == nil ? .newRecipe : .modified)
            request.startSwitchedOff = false
            request.ownEditReasons = reasons
            guard let decided = await approver?.requestApproval(request)?.approval else {
                result.errors.append("The automatic step was not saved, its changes were not approved.")
                return result
            }
            approval = decided
        } else {
            approval = RecipeApproval(recipeId: ext.id, allowedGates: previousApproval?.allowedGates ?? [])
        }
        approval.recipeId = ext.id
        approval.approvedTriggers = []
        approval.replacesBuiltIn = extensionStore.builtIns[ext.id.lowercased()] != nil
        do {
            // Recorded before writing, so the change on disk is known as Greenshot's own.
            try trustStore.recordApproval(approval, forFile: path, sha256: hash, content: content, origin: nil,
                                          recipeName: ext.name, recipeVersion: ext.version)
            try FileManager.default.createDirectory(at: fileURL.deletingLastPathComponent(), withIntermediateDirectories: true)
            try data.write(to: fileURL, options: .atomic)
        } catch {
            log.error("Could not save the automatic step '\(ext.id)' to '\(path)'.", error: error)
            result.errors.append("Could not save the automatic step: \(error.localizedDescription)")
            return result
        }
        askedForChangedFile[path.lowercased()] = hash
        monitor?.watch(fileURL)
        registerFileExtension(LoadedRecipe(recipe: ext, source: .file(fileURL), replacesBuiltIn: approval.replacesBuiltIn,
                                           approval: approval, validation: validation))
        addFileToSettings(path)
        result.loadedRecipeIds.append(ext.id)
        result.warnings += validation.warnings
        notify()
        return result
    }

    /// Why saving `ext` to `url` asks for approval; empty when it doesn't (like `saveDecisionReasons(for:at:)`; REDITOR).
    public func extensionSaveDecisionReasons(for ext: CaptureRecipe, at url: URL?) -> [String] {
        guard ext.kind == .extension else { return [] }
        let validation = validateExtension(ext)
        guard validation.isValid else { return [] }
        return extensionSaveReasons(ext, path: url.map { RecipeTrustStore.standardized($0.path) }, validation: validation)
    }

    /// The automatic steps that plug into `slot` of `recipe` (upstream `GetSlotExtensions`), by order then id; `isOn`:
    /// switched on for this recipe (REDITOR's slot inspector).
    public func extensionsPlugging(into slot: RecipeNode, of recipe: CaptureRecipe) -> [(loaded: LoadedRecipe, isOn: Bool)] {
        guard let slotName = RecipeComposer.slotName(of: slot) else { return [] }
        let values = optionValues
        return extensions.compactMap { loaded in
            let ext = loaded.recipe
            guard ext.extensionSlotName == slotName, RecipeComposer.accepts(slot, extensionId: ext.id),
                  RecipeComposer.targets(ext, recipe) else { return nil }
            return (loaded: loaded, isOn: RecipeExtensionSettings.stored(for: ext, in: values).allowsRecipe(recipe.id))
        }
    }

    /// An AI tool's proposed automatic step (upstream `AiRecipeIpcHandler` with `"kind": "extension"`): written to `url`
    /// after the user approved it; it starts switched off. The frozen `propose(content:...)` refuses extensions (MCP).
    /// Approved with "open in the recipe editor": opened there (CONFLICTS C20: the code that writes the file opens it).
    public func proposeExtension(content: String, proposedBy: String, aiRequest: String?, aiExplanation: String?,
                                 saveTo url: URL) async -> RecipeLoadResult {
        var result = RecipeLoadResult()
        let fileURL = URL(fileURLWithPath: RecipeTrustStore.standardized(url.path))
        guard content.utf8.count <= RecipeFileReader.maxBytes else {
            result.errors.append("The proposed automatic step is larger than \(RecipeFileReader.maxBytes / 1024 / 1024) MB.")
            return result
        }
        let data = Data(content.utf8)
        let hash = RecipeHash.sha256Hex(data)
        let definitions: [CaptureRecipe]
        do {
            definitions = try RecipeSerializer.decode(text: content)
        } catch {
            result.errors.append("The proposed automatic step can't be read: \((error as? RecipeFormatError)?.message ?? error.localizedDescription)")
            return result
        }
        guard definitions.count == 1, let ext = definitions.first, ext.kind == .extension else {
            result.errors.append("An AI tool can propose one automatic step at a time.")
            return result
        }
        // Security review S-N3 / SM-M3: what an AI tool wrote starts switched off, so it needs the switch.
        if let problem = RecipeExtensionNames.aiProposalProblem(ext) {
            result.errors.append(problem)
            return result
        }
        let validation = validateExtension(ext)
        guard validation.isValid else {
            result.errors += validation.errors
            var request = validationErrorRequest(fileURL, content, hash, recipe: ext,
                                                 message: "The automatic step '\(ext.name)' can't be used:\n" + validation.errors.joined(separator: "\n"))
            request.validation = validation
            request.proposedBy = proposedBy
            await approver?.showValidationError(request)
            return result
        }
        // Onto a file which holds an automatic step already (update_recipe): the sheet shows what changes (SM-M4).
        let previousContent = previousExtensionContent(at: fileURL)
        var request = extensionApprovalRequest(ext, fileURL, content, hash, validation, mode: previousContent == nil ? .newRecipe : .modified)
        if let previousContent {
            let previous = RecipeEditApproval.findRecipe(in: previousContent, id: ext.id)
                ?? (try? RecipeSerializer.decode(text: previousContent))?.first
            request.previousContent = previousContent
            request.diff = RecipeTextDiff.compare(previousContent, content)
            request.changes = RecipeDescriber(contracts: contracts, gates: gates()).describeChanges(from: previous, to: ext)
            if let previous { request.replacedRecipe = previous }
        }
        request.proposedBy = proposedBy
        request.aiRequest = aiRequest
        request.aiExplanation = aiExplanation
        request.startSwitchedOff = true
        guard let decision = await approver?.requestApproval(request), var approval = decision.approval else {
            result.errors.append("The user rejected the automatic step '\(ext.name)' proposed by \(proposedBy).")
            return result
        }
        approval.recipeId = ext.id
        approval.approvedTriggers = []
        approval.replacesBuiltIn = extensionStore.builtIns[ext.id.lowercased()] != nil
        do {
            try trustStore.recordApproval(approval, forFile: fileURL.path, sha256: hash, content: content,
                                          origin: RecipeTrustRecord.aiOriginPrefix + proposedBy, recipeName: ext.name, recipeVersion: ext.version)
            try FileManager.default.createDirectory(at: fileURL.deletingLastPathComponent(), withIntermediateDirectories: true)
            try data.write(to: fileURL, options: .atomic)
        } catch {
            result.errors.append("Could not save the proposed automatic step: \(error.localizedDescription)")
            return result
        }
        askedForChangedFile[fileURL.path.lowercased()] = hash
        let missing = RecipeApprovalPolicy.missingGates(validation, approval: approval)
        guard missing.isEmpty else {
            result.errors.append("Automatic step '\(ext.name)' needs \(missing.map(\.displayName).joined(separator: ", ")), but that was not allowed.")
            return result
        }
        monitor?.watch(fileURL)
        // The file holds only this automatic step now: another one loaded from it is gone.
        for key in extensionStore.fileOrder where !recipeEquals(key, ext.id) {
            guard let path = extensionStore.files[key]?.fileURL?.path, recipeEquals(path, fileURL.path) else { continue }
            extensionStore.files[key] = nil
            extensionStore.fileOrder.removeAll { $0 == key }
            log.info("Automatic step '\(key)' was replaced in '\(fileURL.path)'.")
        }
        // Approving is not switching on: what an AI tool wrote starts switched off.
        switchOffNewAIExtension(ext)
        registerFileExtension(LoadedRecipe(recipe: ext, source: .file(fileURL), replacesBuiltIn: approval.replacesBuiltIn,
                                           approval: approval, proposedBy: proposedBy, validation: validation))
        addFileToSettings(fileURL.path)
        result.loadedRecipeIds.append(ext.id)
        notify()
        if decision.openInEditor { extensionStore.openInEditor?(ext.id) }
        return result
    }

    /// The "Changes other recipes" lines of an automatic step (upstream `DescribeExtensionReach`; MCP's
    /// `changes_other_recipes`, the approval sheet).
    public func describeExtensionReach(_ ext: CaptureRecipe) -> [String] {
        var lines: [String] = []
        let names = recipes.map(\.recipe).filter { RecipeComposer.canExtend(ext, $0) }.map { $0.name.isEmpty ? $0.id : $0.name }
            .sorted { $0.localizedCaseInsensitiveCompare($1) == .orderedAscending }
        lines.append(names.isEmpty ? "• Changes no recipe now (none has a slot it fits in)."
                                   : "• Changes these recipes now: \(names.joined(separator: ", ")).")
        let targets = (ext.extends?.recipes ?? []).map { $0.trimmingCharacters(in: .whitespaces) }
        if targets.contains(RecipeExtensionNames.targetAll) {
            lines.append("• Also every recipe added later which has the slot (\"*\").")
        } else if targets.contains(where: { recipeEquals($0, RecipeExtensionNames.targetCaptures) }) {
            lines.append("• Also every capture recipe added later (\"*capture\").")
        }
        switch ext.extensionSlotName {
        case RecipeSlots.afterCapture?: lines.append("• Where: after the capture and the selection, before the processors.")
        case RecipeSlots.beforeExport?: lines.append("• Where: once before the destinations, when the image is final.")
        case RecipeSlots.afterExport?: lines.append("• Where: after the destinations.")
        case RecipeSlots.beforeDestination?: lines.append("• Where: for each destination, on its own copy of the capture.")
        default: lines.append("• Where: the slot '\(ext.extends?.slot ?? "")'.")
        }
        if let when = ext.when?.trimmingCharacters(in: .whitespaces), !when.isEmpty {
            lines.append("• Only when: \(when)")
        }
        lines.append(ext.extensionEnabledOption != nil
                     ? "• Switched on and off in Settings › Recipes; there you can also limit it to some recipes and destinations."
                     : "• It has no on/off switch: it is always used once approved. You can limit it in Settings › Recipes.")
        return lines
    }

    // MARK: Helpers

    /// What a file holds now, as approved (or as it is on disk), for a proposal onto it; nil when there is no such file.
    private func previousExtensionContent(at fileURL: URL) -> String? {
        if let approved = trustStore.record(forFile: fileURL.path)?.approvedContent { return approved }
        guard FileManager.default.fileExists(atPath: fileURL.path) else { return nil }
        return RecipeFileReader.data(fileURL).flatMap(RecipeSerializer.text(of:))
    }

    /// The validator's checks, and that it doesn't extend another automatic step (upstream `ValidateExtension`).
    func validateExtension(_ ext: CaptureRecipe) -> RecipeValidationResult {
        var result = RecipeValidator(contracts: contracts, gates: gates()).validate(ext)
        for raw in ext.extends?.recipes ?? [] {
            let target = raw.trimmingCharacters(in: .whitespaces)
            guard !target.isEmpty, !recipeEquals(target, ext.id) else { continue }
            let key = target.lowercased()
            if extensionStore.builtIns[key] != nil || extensionStore.files[key] != nil {
                result.errors.append("Automatic step '\(ext.id)' targets the automatic step '\(target)'; an automatic step can't extend another one.")
            }
        }
        return result
    }

    /// The approval sheet for an automatic step: its steps, which recipes it changes, the built-in it replaces.
    func extensionApprovalRequest(_ ext: CaptureRecipe, _ url: URL, _ content: String, _ hash: String, _ validation: RecipeValidationResult,
                                  mode: RecipeApprovalMode) -> RecipeApprovalRequest {
        var request = approvalRequest(ext, url, content, hash, validation, mode: mode)
        request.triggers = []
        request.extensionReach = describeExtensionReach(ext)
        if let builtIn = extensionStore.builtIns[ext.id.lowercased()] {
            let previous = RecipeSerializer.encode(builtIn)
            request.replacedRecipe = builtIn
            request.replacesBuiltIn = true
            request.previousContent = previous
            request.diff = RecipeTextDiff.compare(previous, content)
            request.changes = RecipeDescriber(contracts: contracts, gates: gates()).describeChanges(from: builtIn, to: ext)
        }
        return request
    }

    private func extensionSaveReasons(_ ext: CaptureRecipe, path: String?, validation: RecipeValidationResult) -> [String] {
        let record = path.flatMap { trustStore.record(forFile: $0) }
        let previousApproval = record?.approval(for: ext.id)
        var approvedContent = record?.approvedContent
        if approvedContent == nil, let record, let path, let data = RecipeFileReader.data(URL(fileURLWithPath: path)),
           recipeEquals(RecipeHash.sha256Hex(data), record.sha256) {
            approvedContent = RecipeSerializer.text(of: data)
        }
        let approved = RecipeEditApproval.findRecipe(in: approvedContent, id: ext.id).flatMap { $0.kind == .extension ? $0 : nil }
        var reasons: [String] = []
        guard let previousApproval, let approved else {
            reasons.append(extensionStore.builtIns[ext.id.lowercased()] != nil ? "It replaces a built-in automatic step."
                                                                              : "It is a new automatic step, which changes other recipes.")
            return reasons
        }
        if !Self.sameReach(approved, ext) {
            reasons.append("It changes other recipes than before (which recipes or where).")
        }
        let newGates = RecipeApprovalPolicy.missingGates(validation, approval: previousApproval)
        if !newGates.isEmpty {
            reasons.append("It needs a new permission: \(newGates.map(\.displayName).joined(separator: ", ")).")
        }
        return reasons
    }

    private static func sameReach(_ lhs: CaptureRecipe, _ rhs: CaptureRecipe) -> Bool {
        func targets(_ ext: CaptureRecipe) -> Set<String> {
            Set((ext.extends?.recipes ?? []).map { $0.trimmingCharacters(in: .whitespaces).lowercased() })
        }
        return targets(lhs) == targets(rhs) && lhs.extensionSlotName == rhs.extensionSlotName
    }

    func registerFileExtension(_ loaded: LoadedRecipe) {
        let key = loaded.recipe.id.lowercased()
        if extensionStore.files[key] == nil { extensionStore.fileOrder.append(key) }
        extensionStore.files[key] = loaded
        log.info(loaded.replacesBuiltIn ? "Overrode built-in automatic step '\(loaded.recipe.id)' with '\(loaded.fileURL?.path ?? "")'"
                                        : "Registered automatic step '\(loaded.recipe.id)' from '\(loaded.fileURL?.path ?? "")'")
    }

    /// Forgets a file automatic step; its file leaves the settings when nothing else of it is loaded. True when it was there.
    @discardableResult
    func removeFileExtension(_ id: String) -> Bool {
        let key = id.lowercased()
        guard let loaded = extensionStore.files.removeValue(forKey: key) else { return false }
        extensionStore.fileOrder.removeAll { $0 == key }
        if let path = loaded.fileURL?.path {
            let stillUsed = fileRecipes.values.contains { $0.fileURL.map { recipeEquals($0.path, path) } ?? false } || isExtensionFile(path)
            if !stillUsed { removeFileFromSettings(path) }
        }
        return true
    }

    /// Upstream: approving is not switching on, what an AI tool wrote starts switched off.
    private func switchOffNewAIExtension(_ ext: CaptureRecipe) {
        guard let enabled = ext.extensionEnabledOption else { return }
        storeOptionValue(.bool(false), of: enabled, ownerId: ext.id)
    }

    /// Stores one option value of a recipe or automatic step; true when it changed. No change signal.
    @discardableResult
    func storeOptionValue(_ value: JSONValue, of option: RecipeOption, ownerId: String) -> Bool {
        var values = optionValues
        guard values.setValue(value, of: option, recipeId: ownerId) else { return false }
        var settings = loadSettings()
        settings.optionValues = values.stored
        saveSettings(settings)
        return true
    }
}

private let log = Log("Recipes")
