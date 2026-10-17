// Greenshot for Mac (Community) - an unofficial macOS port of Greenshot
// Copyright (C) 2026 Greenshot for Mac (Community) contributors
// Based on Greenshot, Copyright (C) 2007-2026 Thomas Braun, Jens Klingen, Robin Krom
// SPDX-License-Identifier: GPL-3.0-or-later

import CoreGraphics
import Foundation

/// Where a loaded recipe comes from.
public enum RecipeSource: Sendable, Equatable {
    case builtIn
    case file(URL)
}

/// A recipe Greenshot knows (upstream `CaptureRecipe` with its runtime state): file content plus where it came from,
/// whether it is switched on, its approval.
public struct LoadedRecipe: Sendable {
    public var recipe: CaptureRecipe
    public var source: RecipeSource
    /// Not in `RecipeSettings.disabledRecipeIds`.
    public var isEnabled: Bool
    /// A file replaces the built-in recipe with the same id.
    public var replacesBuiltIn: Bool
    /// Nil for built-in recipes (always approved).
    public var approval: RecipeApproval?
    /// The AI tool that wrote the file.
    public var proposedBy: String?
    public var validation: RecipeValidationResult

    public init(recipe: CaptureRecipe, source: RecipeSource, isEnabled: Bool = true, replacesBuiltIn: Bool = false,
                approval: RecipeApproval? = nil, proposedBy: String? = nil, validation: RecipeValidationResult = RecipeValidationResult()) {
        self.recipe = recipe
        self.source = source
        self.isEnabled = isEnabled
        self.replacesBuiltIn = replacesBuiltIn
        self.approval = approval
        self.proposedBy = proposedBy
        self.validation = validation
    }

    public var isBuiltIn: Bool { source == .builtIn }
    /// Enabled in the recipe and approved (built-in: enabled), when the recipe is switched on (upstream `IsActive`).
    public func isTriggerActive(at index: Int) -> Bool {
        guard isEnabled, recipe.triggers.indices.contains(index) else { return false }
        let trigger = recipe.triggers[index]
        guard trigger.enabled else { return false }
        return isBuiltIn || (approval?.isTriggerApproved(RecipeApprovalPolicy.triggerKey(index: index, trigger: trigger)) ?? false)
    }
    /// A Commandline trigger's browser invocation is approved too.
    public func isBrowserInvocationApproved(at index: Int) -> Bool {
        guard isTriggerActive(at: index) else { return false }
        let trigger = recipe.triggers[index]
        guard trigger.allowsBrowserInvocation else { return false }
        return isBuiltIn || (approval?.isTriggerApproved(RecipeApprovalPolicy.browserInvocationKey(index: index, trigger: trigger)) ?? false)
    }

    /// The file the recipe was loaded from.
    var fileURL: URL? {
        if case .file(let url) = source { return url }
        return nil
    }
}

/// A trigger that may start its recipe now, for a trigger source (upstream `SyncRecipeTriggers`).
public struct ActiveRecipeTrigger: Sendable, Equatable {
    public var recipeId: String
    public var recipeName: String
    public var index: Int
    public var trigger: TriggerConfig
    /// The parsed hotkey of a Hotkey trigger.
    public var hotkey: KeyCombo?
    public var browserInvocationApproved: Bool

    public init(recipeId: String, recipeName: String, index: Int, trigger: TriggerConfig, hotkey: KeyCombo? = nil,
                browserInvocationApproved: Bool = false) {
        self.recipeId = recipeId
        self.recipeName = recipeName
        self.index = index
        self.trigger = trigger
        self.hotkey = hotkey
        self.browserInvocationApproved = browserInvocationApproved
    }

    public var key: String { RecipeApprovalPolicy.triggerKey(index: index, trigger: trigger) }
}

/// A recipe that can run as a command (Commandline trigger; upstream `--list-recipes`).
public struct RecipeCommand: Sendable, Equatable {
    public var recipeId: String
    /// The command name (the trigger's `Command`, else the recipe id).
    public var command: String
    public var description: String?
    public var arguments: [CommandlineArgument]
    public var fireAndForget: Bool
    /// The trigger's `Stdout` expression.
    public var stdout: String?
    public var triggerIndex: Int
    public var allowsBrowserInvocation: Bool

    public init(recipeId: String, command: String, description: String? = nil, arguments: [CommandlineArgument] = [],
                fireAndForget: Bool = false, stdout: String? = nil, triggerIndex: Int, allowsBrowserInvocation: Bool = false) {
        self.recipeId = recipeId
        self.command = command
        self.description = description
        self.arguments = arguments
        self.fireAndForget = fireAndForget
        self.stdout = stdout
        self.triggerIndex = triggerIndex
        self.allowsBrowserInvocation = allowsBrowserInvocation
    }
}

/// Who asks to run a command; browser callers need the `:browser` approval.
public enum RecipeInvocationSource: Sendable, Equatable {
    case commandLine
    case urlScheme
    case browser
    case aiTool(client: String)
}

/// The outcome of loading files (upstream `RecipeValidationResult` of `LoadRecipeFromFile`).
public struct RecipeLoadResult: Sendable, Equatable {
    public var errors: [String] = []
    public var warnings: [String] = []
    public var loadedRecipeIds: [String] = []

    public init() {}

    public var isValid: Bool { errors.isEmpty }
}

/// The recipes Greenshot knows and their approvals (upstream `RecipeManager`): built-in recipes, files listed in
/// `RecipeSettings.files` (no folder scanning), default-deny approval of each recipe of a file pinned to the SHA-256 of
/// its bytes, override and reset of built-ins, switching recipes on and off, saving from the editor with the edit
/// decision table, revoke and review, details, commands for the CLI. Nothing here draws: questions go to the approver.
@MainActor
public final class RecipeLibrary {
    /// - Parameters:
    ///   - loadSettings / saveSettings: `AppSettings.recipes` (the app's settings store).
    ///   - gates: the settings' external commands and destinations, for the gate check.
    ///   - watchFiles: watch the loaded files (`RecipeFileMonitor`) and ask again right after one changes; off in tests.
    public init(loadSettings: @escaping @MainActor () -> RecipeSettings,
                saveSettings: @escaping @MainActor (RecipeSettings) -> Void,
                trustStore: any RecipeTrustStoring,
                approver: (any RecipeApprover)?,
                builtInRecipes: [CaptureRecipe] = [],
                contracts: StepContractCatalog = .builtIn,
                gates: @escaping @MainActor () -> GateEnvironment = { .empty },
                watchFiles: Bool = true) {
        self.loadSettings = loadSettings
        self.saveSettings = saveSettings
        self.trustStore = trustStore
        self.approver = approver
        self.contracts = contracts
        self.gates = gates
        for recipe in builtInRecipes where builtIns[recipe.id.lowercased()] == nil {
            builtIns[recipe.id.lowercased()] = recipe
            builtInOrder.append(recipe.id.lowercased())
        }
        if watchFiles {
            monitor = RecipeFileMonitor { [weak self] url in
                Task { @MainActor in await self?.fileDidChange(url) }
            }
        }
    }

    private let loadSettings: @MainActor () -> RecipeSettings
    private let saveSettings: @MainActor (RecipeSettings) -> Void
    private let trustStore: any RecipeTrustStoring
    /// Held strongly: the app may hand over a presenter that nothing else keeps.
    private let approver: (any RecipeApprover)?
    private let contracts: StepContractCatalog
    private let gates: @MainActor () -> GateEnvironment
    private var monitor: RecipeFileMonitor?
    private var builtIns: [String: CaptureRecipe] = [:]
    private var builtInOrder: [String] = []
    private var fileRecipes: [String: LoadedRecipe] = [:]
    private var fileOrder: [String] = []
    /// The content a changed file was already asked for (upstream `_askedForChangedFile`).
    private var askedForChangedFile: [String: String] = [:]
    private var loadingConfiguredFiles = false

    /// Called after recipes, approvals or the switch changed (resync triggers and menus).
    public var onChange: (@MainActor () -> Void)?

    /// Off: no recipe files are loaded, no recipe triggers (upstream `EnableRecipeFeature`).
    public var isFeatureEnabled: Bool { loadSettings().enabled }

    public var recipes: [LoadedRecipe] {
        let disabled = disabledIds()
        var result: [LoadedRecipe] = []
        for key in builtInOrder where fileRecipes[key] == nil {
            guard let recipe = builtIns[key] else { continue }
            result.append(LoadedRecipe(recipe: recipe, source: .builtIn, isEnabled: !disabled.contains(key)))
        }
        for key in fileOrder {
            guard var loaded = fileRecipes[key] else { continue }
            loaded.isEnabled = !disabled.contains(key)
            result.append(loaded)
        }
        return result
    }

    public func recipe(id: String) -> LoadedRecipe? {
        recipes.first { recipeEquals($0.recipe.id, id) }
    }

    public func builtInRecipe(id: String) -> CaptureRecipe? { builtIns[id.lowercased()] }

    /// The triggers that may start their recipes now, of the given types (all when nil).
    public func activeTriggers(ofTypes types: Set<String>? = nil) -> [ActiveRecipeTrigger] {
        guard isFeatureEnabled else { return [] }
        var result: [ActiveRecipeTrigger] = []
        for loaded in recipes where loaded.isEnabled {
            for (index, trigger) in loaded.recipe.triggers.enumerated() where loaded.isTriggerActive(at: index) {
                if let types, !types.contains(where: { trigger.isType($0) }) { continue }
                let hotkey = trigger.isType(WellKnownTriggerType.hotkey) ? trigger.hotkey.flatMap(RecipeHotkeyText.parse) : nil
                result.append(ActiveRecipeTrigger(recipeId: loaded.recipe.id, recipeName: loaded.recipe.name, index: index, trigger: trigger,
                                                  hotkey: hotkey, browserInvocationApproved: loaded.isBrowserInvocationApproved(at: index)))
            }
        }
        return result
    }

    /// The user's option values (RCP-006), for Settings > Recipes and the runs.
    public var optionValues: RecipeOptionValues { RecipeOptionValues(loadSettings().optionValues) }

    public func setOptionValue(_ value: JSONValue, key: String, recipeId: String) {
        guard let option = recipe(id: recipeId)?.recipe.option(key) else { return }
        var values = optionValues
        guard values.setValue(value, of: option, recipeId: recipeId) else { return }
        var settings = loadSettings()
        settings.optionValues = values.stored
        saveSettings(settings)
        notify()
    }

    public func resetOptions(recipeId: String) {
        var values = optionValues
        guard values.reset(recipeId: recipeId) else { return }
        var settings = loadSettings()
        settings.optionValues = values.stored
        saveSettings(settings)
        notify()
    }

    // MARK: Loading

    /// Loads the files of the settings again (tray "Reload Recipes").
    public func reload() async -> RecipeLoadResult {
        var result = RecipeLoadResult()
        fileRecipes = [:]
        fileOrder = []
        if isFeatureEnabled {
            loadingConfiguredFiles = true
            for path in loadSettings().files where !path.trimmingCharacters(in: .whitespaces).isEmpty {
                let url = URL(fileURLWithPath: RecipeTrustStore.standardized(path))
                guard FileManager.default.fileExists(atPath: url.path) else {
                    log.warn("Configured recipe file '\(url.path)' was not found.")
                    result.warnings.append("Configured recipe file '\(url.path)' was not found.")
                    continue
                }
                let loaded = await loadFile(url, interactive: true)
                result.errors += loaded.errors
                result.warnings += loaded.warnings
                result.loadedRecipeIds += loaded.loadedRecipeIds
            }
            loadingConfiguredFiles = false
        }
        notify()
        return result
    }

    /// Reads the file once, hashes the bytes, validates each recipe and asks for the approval of those not approved for
    /// this content (`interactive`); approved and allowed ones replace what was loaded and the file joins the settings.
    public func loadFile(_ url: URL, interactive: Bool = true, forcePrompt: Bool = false) async -> RecipeLoadResult {
        var result = RecipeLoadResult()
        let fileURL = URL(fileURLWithPath: RecipeTrustStore.standardized(url.path))
        let path = fileURL.path
        guard isFeatureEnabled else {
            result.errors.append("Recipes are switched off.")
            return result
        }
        guard let data = try? Data(contentsOf: fileURL) else {
            result.errors.append("File not found: \(path)")
            return result
        }
        monitor?.watch(fileURL)
        // Read once: what is parsed, shown and approved are the same bytes.
        let content = RecipeSerializer.text(of: data) ?? ""
        let hash = RecipeHash.sha256Hex(data)
        let definitions: [CaptureRecipe]
        do {
            definitions = try RecipeSerializer.decode(text: content)
        } catch {
            let message = (error as? RecipeFormatError)?.message ?? error.localizedDescription
            log.warn("Failed to read recipe file '\(path)': \(message)")
            result.errors.append("Exception reading recipe file: \(message)")
            if interactive { await approver?.showValidationError(validationErrorRequest(fileURL, content, hash, recipe: nil, message: message)) }
            return result
        }
        if definitions.contains(where: { $0.kind == .extension }) {
            let message = "This file is an automatic step (\"kind\": \"extension\"), not a recipe. Automatic steps aren't available in this version yet."
            result.errors.append(message)
            if interactive { await approver?.showValidationError(validationErrorRequest(fileURL, content, hash, recipe: nil, message: message)) }
            return result
        }
        var anyChanged = false
        let validator = RecipeValidator(contracts: contracts, gates: gates())
        for recipe in definitions {
            let validation = validator.validate(recipe)
            guard validation.isValid else {
                result.errors += validation.errors.map { "[\(recipe.id.isEmpty ? "unknown" : recipe.id)]: \($0)" }
                if interactive {
                    var request = validationErrorRequest(fileURL, content, hash, recipe: recipe, message: validation.errors.joined(separator: "\n"))
                    request.validation = validation
                    await approver?.showValidationError(request)
                }
                continue
            }
            let previousRecord = trustStore.record(forFile: path)
            var approval = forcePrompt ? nil : trustStore.approval(forFile: path, sha256: hash, recipeId: recipe.id)
            if approval == nil {
                guard interactive, let approver else {
                    result.errors.append("Recipe '\(recipe.name)' from '\(path)' is not approved and interactive approval is disabled.")
                    continue
                }
                let mode: RecipeApprovalMode = forcePrompt ? .reVerify : (previousRecord == nil ? .newRecipe : .modified)
                let request = approvalRequest(recipe, fileURL, content, hash, validation, mode: mode)
                let decision = await approver.requestApproval(request)
                if var approved = decision?.approval {
                    approved.recipeId = recipe.id
                    approved.replacesBuiltIn = builtIns[recipe.id.lowercased()] != nil
                    do {
                        try trustStore.recordApproval(approved, forFile: path, sha256: hash, content: content, origin: previousRecord?.origin,
                                                      recipeName: recipe.name, recipeVersion: recipe.version)
                    } catch {
                        log.error("The approval of recipe '\(recipe.id)' could not be saved.", error: error)
                        result.errors.append("The approval of recipe '\(recipe.name)' could not be saved: \(error.localizedDescription)")
                        continue
                    }
                    approval = approved
                } else if decision?.isRevoked == true {
                    try? trustStore.revokeApproval(recipeId: recipe.id, forFile: path)
                    removeFileRecipe(recipe.id)
                    anyChanged = true
                    result.errors.append("The approval of recipe '\(recipe.name)' (\(recipe.id)) was revoked.")
                    continue
                } else if forcePrompt, let existing = trustStore.approval(forFile: path, sha256: hash, recipeId: recipe.id) {
                    // A review that was closed or kept as it is changes nothing.
                    approval = existing
                } else {
                    result.errors.append("User rejected recipe '\(recipe.name)' (\(recipe.id)) from '\(path)'.")
                    continue
                }
            }
            let missing = RecipeApprovalPolicy.missingGates(validation, approval: approval)
            guard missing.isEmpty else {
                result.errors.append("Recipe '\(recipe.name)' needs \(missing.map(\.displayName).joined(separator: ", ")), but that was not allowed.")
                continue
            }
            result.warnings += validation.warnings.map { "[\(recipe.id)]: \($0)" }
            register(LoadedRecipe(recipe: recipe, source: .file(fileURL), replacesBuiltIn: builtIns[recipe.id.lowercased()] != nil,
                                  approval: approval, proposedBy: trustStore.record(forFile: path)?.proposedBy, validation: validation))
            result.loadedRecipeIds.append(recipe.id)
            addFileToSettings(path)
            anyChanged = true
        }
        if anyChanged, !loadingConfiguredFiles { notify() }
        return result
    }

    /// Import: load interactively.
    public func importFile(_ url: URL) async -> RecipeLoadResult { await loadFile(url) }

    /// The file monitor saw a change: asks right away when a recipe in use lost its approval (upstream `CheckChangedFile`).
    public func fileDidChange(_ url: URL) async {
        let path = RecipeTrustStore.standardized(url.path)
        let inUse = fileRecipes.values.contains { $0.fileURL.map { recipeEquals($0.path, path) } ?? false }
        guard inUse, let data = try? Data(contentsOf: URL(fileURLWithPath: path)) else { return }
        let hash = RecipeHash.sha256Hex(data)
        if let record = trustStore.record(forFile: path), recipeEquals(record.sha256, hash) { return }
        guard askedForChangedFile[path.lowercased()] != hash else { return }
        askedForChangedFile[path.lowercased()] = hash
        log.info("Recipe file '\(path)' was changed outside Greenshot, asking for approval.")
        _ = await loadFile(URL(fileURLWithPath: path), interactive: true)
    }

    /// Before a run: the recipe as it may run (its file still approved, or approved again), nil when not
    /// (upstream `EnsureRecipeApprovedAndUpToDateAsync`). The runner's `preflight`.
    public func ensureApprovedAndCurrent(_ recipe: CaptureRecipe) async -> CaptureRecipe? {
        guard let loaded = fileRecipes[recipe.id.lowercased()], let url = loaded.fileURL else { return recipe }
        guard let data = try? Data(contentsOf: url) else {
            log.warn("Recipe file '\(url.path)' no longer exists.")
            return nil
        }
        let hash = RecipeHash.sha256Hex(data)
        if trustStore.approval(forFile: url.path, sha256: hash, recipeId: recipe.id) != nil { return recipe }
        log.info("Recipe file '\(url.path)' was changed or isn't approved; asking before it runs.")
        let result = await loadFile(url, interactive: true)
        guard result.isValid else { return nil }
        return fileRecipes[recipe.id.lowercased()]?.recipe
    }

    // MARK: Saving

    /// Saves from the recipe editor: the approval is renewed without asking unless `saveDecisionReasons` is not empty.
    public func save(_ recipe: CaptureRecipe, to url: URL) async -> RecipeLoadResult {
        var result = RecipeLoadResult()
        let fileURL = URL(fileURLWithPath: RecipeTrustStore.standardized(url.path))
        let path = fileURL.path
        // The bytes which are approved are the bytes which are written.
        let content = RecipeSerializer.encode(recipe)
        let data = Data(content.utf8)
        let hash = RecipeHash.sha256Hex(data)
        let validation = RecipeValidator(contracts: contracts, gates: gates()).validate(recipe)
        var approval: RecipeApproval?
        if validation.isValid {
            let edit = editApproval(recipe, path: path, validation: validation)
            var renewed = edit.approval
            if edit.decision.isNeeded {
                log.info("The change of recipe '\(recipe.id)' needs the user's decision: \(edit.decision.reasons.joined(separator: " "))")
                var request = approvalRequest(recipe, fileURL, content, hash, validation,
                                              mode: trustStore.record(forFile: path) == nil ? .newRecipe : .modified)
                request.startSwitchedOff = false
                request.ownEditReasons = edit.decision.reasons
                request.suggestedApproval = RecipeApproval(recipeId: recipe.id, approvedTriggers: renewed.approvedTriggers + edit.decision.triggerKeys,
                                                           allowedGates: renewed.allowedGates)
                if request.previousContent == nil, let approved = edit.approvedContent {
                    request.previousContent = approved
                    request.diff = RecipeTextDiff.compare(approved, content)
                }
                guard let decided = await approver?.requestApproval(request)?.approval else {
                    result.errors.append("The recipe was not saved, its changes were not approved.")
                    return result
                }
                renewed = decided
            }
            renewed.recipeId = recipe.id
            renewed.replacesBuiltIn = builtIns[recipe.id.lowercased()] != nil
            do {
                // Recorded before writing, so the change on disk is known as Greenshot's own.
                try trustStore.recordApproval(renewed, forFile: path, sha256: hash, content: content, origin: nil,
                                              recipeName: recipe.name, recipeVersion: recipe.version)
            } catch {
                result.errors.append("Could not save the approval of the recipe: \(error.localizedDescription)")
                return result
            }
            approval = renewed
        }
        do {
            try FileManager.default.createDirectory(at: fileURL.deletingLastPathComponent(), withIntermediateDirectories: true)
            try data.write(to: fileURL, options: .atomic)
        } catch {
            log.error("Could not save the recipe '\(recipe.id)' to '\(path)'.", error: error)
            result.errors.append("Could not save the recipe: \(error.localizedDescription)")
            return result
        }
        askedForChangedFile[path.lowercased()] = hash
        monitor?.watch(fileURL)
        // Without an approval (an invalid recipe, saved as work in progress) none of its triggers is active.
        register(LoadedRecipe(recipe: recipe, source: .file(fileURL), replacesBuiltIn: builtIns[recipe.id.lowercased()] != nil,
                              approval: approval, validation: validation))
        addFileToSettings(path)
        result.loadedRecipeIds.append(recipe.id)
        result.warnings += validation.warnings + validation.errors
        notify()
        return result
    }

    public func saveDecisionReasons(for recipe: CaptureRecipe, at url: URL?) -> [String] {
        let validation = RecipeValidator(contracts: contracts, gates: gates()).validate(recipe)
        guard validation.isValid else { return [] }
        let path = url.map { RecipeTrustStore.standardized($0.path) }
        return editApproval(recipe, path: path, validation: validation).decision.reasons
    }

    private func editApproval(_ recipe: CaptureRecipe, path: String?, validation: RecipeValidationResult)
        -> (approval: RecipeApproval, decision: RecipeEditDecision, approvedContent: String?) {
        let record = path.flatMap { trustStore.record(forFile: $0) }
        let previous = record?.approval(for: recipe.id)
        var approvedContent = record?.approvedContent
        // A record without the content: the file on disk while it is still the approved one.
        if approvedContent == nil, let record, let path, let data = try? Data(contentsOf: URL(fileURLWithPath: path)),
           recipeEquals(RecipeHash.sha256Hex(data), record.sha256) {
            approvedContent = RecipeSerializer.text(of: data)
        }
        let approvedVersion = RecipeEditApproval.findRecipe(in: approvedContent, id: recipe.id)
        let made = RecipeEditApproval.create(edited: recipe, validation: validation, approvedVersion: approvedVersion,
                                             previousApproval: previous, replacesBuiltIn: builtIns[recipe.id.lowercased()] != nil)
        return (made.approval, made.decision, approvedContent)
    }

    /// An AI tool's proposal (RCP-204): written to `url` after the user approved it, triggers and permissions off.
    public func propose(content: String, proposedBy: String, aiRequest: String?, aiExplanation: String?, saveTo url: URL) async -> RecipeLoadResult {
        var result = RecipeLoadResult()
        let fileURL = URL(fileURLWithPath: RecipeTrustStore.standardized(url.path))
        let data = Data(content.utf8)
        let hash = RecipeHash.sha256Hex(data)
        let definitions: [CaptureRecipe]
        do {
            definitions = try RecipeSerializer.decode(text: content)
        } catch {
            result.errors.append("The proposed recipe can't be read: \((error as? RecipeFormatError)?.message ?? error.localizedDescription)")
            return result
        }
        guard definitions.count == 1, let recipe = definitions.first, recipe.kind == .recipe else {
            result.errors.append("An AI tool can propose one recipe at a time.")
            return result
        }
        let validation = RecipeValidator(contracts: contracts, gates: gates()).validate(recipe)
        guard validation.isValid else {
            result.errors += validation.errors
            var request = validationErrorRequest(fileURL, content, hash, recipe: recipe, message: validation.errors.joined(separator: "\n"))
            request.validation = validation
            request.proposedBy = proposedBy
            await approver?.showValidationError(request)
            return result
        }
        var request = approvalRequest(recipe, fileURL, content, hash, validation, mode: .newRecipe)
        request.proposedBy = proposedBy
        request.aiRequest = aiRequest
        request.aiExplanation = aiExplanation
        request.startSwitchedOff = true
        guard var approval = await approver?.requestApproval(request)?.approval else {
            result.errors.append("The user rejected the recipe '\(recipe.name)' proposed by \(proposedBy).")
            return result
        }
        approval.recipeId = recipe.id
        approval.replacesBuiltIn = builtIns[recipe.id.lowercased()] != nil
        do {
            try trustStore.recordApproval(approval, forFile: fileURL.path, sha256: hash, content: content,
                                          origin: RecipeTrustRecord.aiOriginPrefix + proposedBy, recipeName: recipe.name, recipeVersion: recipe.version)
            try FileManager.default.createDirectory(at: fileURL.deletingLastPathComponent(), withIntermediateDirectories: true)
            try data.write(to: fileURL, options: .atomic)
        } catch {
            result.errors.append("Could not save the proposed recipe: \(error.localizedDescription)")
            return result
        }
        askedForChangedFile[fileURL.path.lowercased()] = hash
        let missing = RecipeApprovalPolicy.missingGates(validation, approval: approval)
        guard missing.isEmpty else {
            result.errors.append("Recipe '\(recipe.name)' needs \(missing.map(\.displayName).joined(separator: ", ")), but that was not allowed.")
            return result
        }
        monitor?.watch(fileURL)
        register(LoadedRecipe(recipe: recipe, source: .file(fileURL), replacesBuiltIn: approval.replacesBuiltIn, approval: approval,
                              proposedBy: proposedBy, validation: validation))
        addFileToSettings(fileURL.path)
        result.loadedRecipeIds.append(recipe.id)
        notify()
        return result
    }

    // MARK: Managing

    public func setEnabled(_ enabled: Bool, recipeId: String) {
        var settings = loadSettings()
        let had = settings.disabledRecipeIds.contains { recipeEquals($0, recipeId) }
        guard had == enabled else { return }
        if enabled {
            settings.disabledRecipeIds.removeAll { recipeEquals($0, recipeId) }
        } else {
            settings.disabledRecipeIds.append(recipeId)
        }
        saveSettings(settings)
        notify()
    }

    /// Drops the file recipe and brings the built-in back ("Reset Default").
    @discardableResult
    public func resetToDefault(recipeId: String) -> Bool {
        guard builtIns[recipeId.lowercased()] != nil else { return false }
        if fileRecipes[recipeId.lowercased()] != nil { removeFileRecipe(recipeId) }
        log.info("Reset recipe '\(recipeId)' back to the built-in recipe.")
        notify()
        return true
    }

    public func resetAllToDefault() {
        for key in builtInOrder where fileRecipes[key] != nil {
            removeFileRecipe(key)
        }
        notify()
    }

    /// Forgets a file recipe (manager "Unload"): out of the settings, approval kept.
    public func unload(recipeId: String) {
        guard fileRecipes[recipeId.lowercased()] != nil else { return }
        removeFileRecipe(recipeId)
        notify()
    }

    @discardableResult
    public func revokeApproval(recipeId: String) -> Bool {
        guard let loaded = fileRecipes[recipeId.lowercased()], let url = loaded.fileURL else { return false }
        do {
            try trustStore.revokeApproval(recipeId: loaded.recipe.id, forFile: url.path)
        } catch {
            log.error("Could not revoke the approval of '\(recipeId)'.", error: error)
            return false
        }
        removeFileRecipe(recipeId)
        log.info("The user revoked the approval of recipe '\(recipeId)' from '\(url.path)'.")
        notify()
        return true
    }

    /// "Permissions": the approval sheet in review mode.
    public func reviewApproval(recipeId: String) async -> RecipeLoadResult {
        guard let url = fileRecipes[recipeId.lowercased()]?.fileURL else {
            var result = RecipeLoadResult()
            result.errors.append("Recipe '\(recipeId)' has no approval to review.")
            return result
        }
        return await loadFile(url, interactive: true, forcePrompt: true)
    }

    public func details(recipeId: String) -> RecipeDetails? {
        guard let loaded = recipe(id: recipeId) else { return nil }
        let describer = RecipeDescriber(contracts: contracts, gates: gates())
        var details = RecipeDetails()
        details.whatItDoes = describer.describeSteps(loaded.recipe)
        details.triggers = describer.describeTriggers(loaded.recipe).map { description in
            var described = description
            let index = Int(description.key.prefix { $0 != ":" }) ?? -1
            let on = description.key.hasSuffix(RecipeApprovalPolicy.browserInvocationSuffix)
                ? loaded.isBrowserInvocationApproved(at: index) : loaded.isTriggerActive(at: index)
            described.label += description.isDisabled ? " (disabled)" : on ? " (on)" : " (off, not approved)"
            return described
        }
        details.proposedBy = loaded.proposedBy
        if let url = loaded.fileURL, let record = trustStore.record(forFile: url.path) {
            details.approvedAt = record.approvedAt
            details.approvedHash = record.sha256
            if let data = try? Data(contentsOf: url) {
                details.isApprovalCurrent = recipeEquals(RecipeHash.sha256Hex(data), record.sha256)
            }
            details.permissions = record.approval(for: loaded.recipe.id)?.allowedGates ?? []
        }
        if loaded.replacesBuiltIn, let builtIn = builtIns[loaded.recipe.id.lowercased()] {
            details.builtInDiff = RecipeTextDiff.unifiedText(RecipeSerializer.encode(builtIn), RecipeSerializer.encode(loaded.recipe))
        }
        return details
    }

    /// The approval sheet read-only (Details).
    public func detailsRequest(recipeId: String) -> RecipeApprovalRequest? {
        guard let loaded = recipe(id: recipeId) else { return nil }
        let validator = RecipeValidator(contracts: contracts, gates: gates())
        var request: RecipeApprovalRequest
        if let url = loaded.fileURL, let data = try? Data(contentsOf: url) {
            let content = RecipeSerializer.text(of: data) ?? ""
            let fileRecipe = ((try? RecipeSerializer.decode(text: content)) ?? []).first { recipeEquals($0.id, recipeId) } ?? loaded.recipe
            request = approvalRequest(fileRecipe, url, content, RecipeHash.sha256Hex(data), validator.validate(fileRecipe), mode: .reVerify)
            request.startSwitchedOff = false
            request.suggestedApproval = loaded.approval
        } else {
            let content = RecipeSerializer.encode(loaded.recipe)
            request = RecipeApprovalRequest(mode: .reVerify, recipe: loaded.recipe, fileURL: nil, content: content,
                                            contentHash: RecipeHash.sha256Hex(Data(content.utf8)))
            let validation = validator.validate(loaded.recipe)
            request.validation = validation
            let describer = RecipeDescriber(contracts: contracts, gates: gates())
            request.steps = describer.describeSteps(loaded.recipe)
            request.triggers = describer.describeTriggers(loaded.recipe)
            request.gates = validation.gateTypes
        }
        request.isReadOnly = true
        return request
    }

    // MARK: Commands (AUT: the command line, links, AI tools)

    /// The recipes with an active Commandline (or, for `.aiTool`, AiTool) trigger the source may start.
    public func commands(for source: RecipeInvocationSource) -> [RecipeCommand] {
        guard isFeatureEnabled else { return [] }
        var result: [RecipeCommand] = []
        let isAITool: Bool
        if case .aiTool = source { isAITool = true } else { isAITool = false }
        for loaded in recipes where loaded.isEnabled {
            for (index, trigger) in loaded.recipe.triggers.enumerated() where loaded.isTriggerActive(at: index) {
                if isAITool {
                    guard trigger.isType(WellKnownTriggerType.aiTool) else { continue }
                } else {
                    guard trigger.isType(WellKnownTriggerType.commandline) else { continue }
                    if source == .browser, !loaded.isBrowserInvocationApproved(at: index) { continue }
                }
                let name = isAITool ? (trigger.toolName ?? loaded.recipe.id) : (trigger.command ?? loaded.recipe.id)
                result.append(RecipeCommand(recipeId: loaded.recipe.id, command: name,
                                            description: trigger.commandDescription ?? loaded.recipe.description,
                                            arguments: trigger.arguments, fireAndForget: trigger.fireAndForget, stdout: trigger.stdout,
                                            triggerIndex: index, allowsBrowserInvocation: trigger.allowsBrowserInvocation))
            }
        }
        return result
    }

    /// A run request for a command with bound arguments (`RecipeArgumentBinder`) and a Commandline (or AiTool) trigger
    /// info; the runner prepares the recipe for it. Throws `RecipeStepError` with a message for stderr (unknown command,
    /// not approved, bad arguments).
    public func runRequest(command: String, arguments: [String: String], source: RecipeInvocationSource,
                           resolvePath: (String, ContractDataType) throws -> String) throws -> RecipeRunRequest {
        let available = commands(for: source)
        guard let match = available.first(where: { recipeEquals($0.command, command) })
                ?? available.first(where: { recipeEquals($0.recipeId, command) }),
              let loaded = recipe(id: match.recipeId) else {
            if source == .browser, commands(for: .commandLine).contains(where: { recipeEquals($0.command, command) || recipeEquals($0.recipeId, command) }) {
                throw RecipeStepError("[SECURITY] Recipe '\(command)' does not allow invocation from a browser. Set 'AllowBrowserInvocation' on its Commandline trigger to enable this.",
                                      errorType: "UnauthorizedAccessException")
            }
            throw RecipeStepError("Error: unknown recipe command '\(command)'.", errorType: "ArgumentException")
        }
        let variables: [String: JSONValue]
        switch RecipeArgumentBinder.bind(declared: match.arguments, supplied: arguments, recipeName: match.command, resolvePath: resolvePath) {
        case .success(let bound): variables = bound
        case .failure(let error): throw error
        }
        let trigger = loaded.recipe.triggers[match.triggerIndex]
        var request = RecipeRunRequest(recipe: loaded.recipe, trigger: RecipeTriggerInfo(triggerType: trigger.triggerType, triggerName: trigger.name,
                                                                                         triggerIndex: match.triggerIndex))
        request.variables = variables
        request.optionValues = optionValues
        return request
    }

    /// A run request for a recipe by id (menu entry, test run, forwarding) with a trigger info of this type; the runner
    /// prepares the recipe for it.
    public func runRequest(recipeId: String, triggerType: String = WellKnownTriggerType.manual) -> RecipeRunRequest? {
        guard let loaded = recipe(id: recipeId) else { return nil }
        var request = RecipeRunRequest(recipe: loaded.recipe, trigger: RecipeTriggerInfo(triggerType: triggerType))
        request.optionValues = optionValues
        return request
    }

    /// The contract report of a recipe (`--info`).
    public func contractReport(recipeId: String) -> RecipeContractReport? {
        recipe(id: recipeId).map { RecipeContractAnalyzer.analyze($0.recipe, contracts: contracts) }
    }

    // MARK: Helpers

    private func disabledIds() -> Set<String> {
        Set(loadSettings().disabledRecipeIds.map { $0.lowercased() })
    }

    private func register(_ loaded: LoadedRecipe) {
        let key = loaded.recipe.id.lowercased()
        if fileRecipes[key] == nil { fileOrder.append(key) }
        fileRecipes[key] = loaded
        log.info(loaded.replacesBuiltIn ? "Overrode built-in recipe '\(loaded.recipe.id)' with '\(loaded.fileURL?.path ?? "")'"
                                        : "Registered recipe '\(loaded.recipe.id)' from '\(loaded.fileURL?.path ?? "")'")
    }

    /// Unloads a file recipe; its file leaves the settings when no other recipe of it is loaded.
    private func removeFileRecipe(_ recipeId: String) {
        let key = recipeId.lowercased()
        guard let loaded = fileRecipes.removeValue(forKey: key) else { return }
        fileOrder.removeAll { $0 == key }
        guard let path = loaded.fileURL?.path else { return }
        let stillUsed = fileRecipes.values.contains { $0.fileURL.map { recipeEquals($0.path, path) } ?? false }
        if !stillUsed { removeFileFromSettings(path) }
    }

    private func addFileToSettings(_ path: String) {
        var settings = loadSettings()
        guard !settings.files.contains(where: { recipeEquals(RecipeTrustStore.standardized($0), path) }) else { return }
        settings.files.append(path)
        saveSettings(settings)
    }

    private func removeFileFromSettings(_ path: String) {
        var settings = loadSettings()
        let before = settings.files.count
        settings.files.removeAll { recipeEquals(RecipeTrustStore.standardized($0), path) }
        if settings.files.count != before { saveSettings(settings) }
    }

    private func notify() {
        onChange?()
    }

    private func approvalRequest(_ recipe: CaptureRecipe, _ url: URL, _ content: String, _ hash: String, _ validation: RecipeValidationResult,
                                 mode: RecipeApprovalMode) -> RecipeApprovalRequest {
        let describer = RecipeDescriber(contracts: contracts, gates: gates())
        var request = RecipeApprovalRequest(mode: mode, recipe: recipe, fileURL: url, content: content, contentHash: hash)
        request.validation = validation
        let record = trustStore.record(forFile: url.path)
        request.previousRecord = record
        request.steps = describer.describeSteps(recipe)
        request.triggers = describer.describeTriggers(recipe)
        request.gates = validation.gateTypes
        // A file an AI tool wrote, changed on disk: it starts switched off, like a proposal.
        request.startSwitchedOff = record?.isAICreated == true
        request.proposedBy = record?.proposedBy
        if mode == .reVerify {
            request.suggestedApproval = trustStore.approval(forFile: url.path, sha256: hash, recipeId: recipe.id)
        }
        var previousRecipe: CaptureRecipe?
        if let builtIn = builtIns[recipe.id.lowercased()] {
            request.replacedRecipe = builtIn
            request.replacesBuiltIn = true
            request.previousContent = RecipeSerializer.encode(builtIn)
            previousRecipe = builtIn
        } else if let record, !recipeEquals(record.sha256, hash), let approved = record.approvedContent {
            request.previousContent = approved
            previousRecipe = RecipeEditApproval.findRecipe(in: approved, id: recipe.id)
        }
        if let previous = request.previousContent {
            request.diff = RecipeTextDiff.compare(previous, content)
            request.changes = describer.describeChanges(from: previousRecipe, to: recipe)
        }
        return request
    }

    private func validationErrorRequest(_ url: URL, _ content: String, _ hash: String, recipe: CaptureRecipe?, message: String) -> RecipeApprovalRequest {
        var request = RecipeApprovalRequest(mode: .validationError, recipe: recipe, fileURL: url, content: content, contentHash: hash)
        request.errorMessage = message
        request.hint = Self.hint(for: message)
        request.previousRecord = trustStore.record(forFile: url.path)
        return request
    }

    /// What to change, for the validation-error mode.
    static func hint(for message: String) -> String {
        if message.contains("not valid JSON") { return "Check the file for a missing comma, quote or bracket." }
        if message.contains("Cycle/loop") { return "Remove a transition that leads back to an earlier step: recipes run from start to end." }
        if message.contains("which is not available in this version") { return "Use a step type of this version of Greenshot, or update Greenshot." }
        if message.contains("invalid hotkey") { return "Write the hotkey like \"Ctrl + Shift + B\"; on the Mac Ctrl is ⌘ and Win is ⌃." }
        if message.contains("requires the extension") { return "The recipe needs a plug-in Greenshot for Mac doesn't have." }
        if message.contains("automatic step") { return "Automatic steps (extensions) will come with a later version." }
        if message.contains("does not exist in 'nodes'") || message.contains("does not match any defined node id") {
            return "Check the node ids in 'flow': each must be the id of a node."
        }
        return "Edit the recipe file and load it again."
    }
}

private let log = Log("Recipes")
