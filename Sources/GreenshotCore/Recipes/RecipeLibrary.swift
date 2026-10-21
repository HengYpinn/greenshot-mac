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

extension RecipeInvocationSource {
    var isAITool: Bool {
        if case .aiTool = self { return true }
        return false
    }
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

    // Internal, not private: RMANAGER's automatic-step loader (ExtensionFiles.swift) is an extension of this class.
    let loadSettings: @MainActor () -> RecipeSettings
    let saveSettings: @MainActor (RecipeSettings) -> Void
    let trustStore: any RecipeTrustStoring
    /// Held strongly: the app may hand over a presenter that nothing else keeps.
    let approver: (any RecipeApprover)?
    let contracts: StepContractCatalog
    let gates: @MainActor () -> GateEnvironment
    var monitor: RecipeFileMonitor?
    var builtIns: [String: CaptureRecipe] = [:]
    private var builtInOrder: [String] = []
    var fileRecipes: [String: LoadedRecipe] = [:]
    private var fileOrder: [String] = []
    /// The content a changed file was already asked for (upstream `_askedForChangedFile`).
    var askedForChangedFile: [String: String] = [:]
    var loadingConfiguredFiles = false
    /// Automatic steps (extensions): RMANAGER's ExtensionFiles.swift.
    var extensionStore = RecipeExtensionStore()

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
        forgetFileExtensions()
        if isFeatureEnabled {
            loadingConfiguredFiles = true
            for path in loadSettings().files where !path.trimmingCharacters(in: .whitespaces).isEmpty {
                let url = URL(fileURLWithPath: RecipeTrustStore.standardized(path))
                guard FileManager.default.fileExists(atPath: url.path) else {
                    log.warn("Configured recipe file '\(url.path)' was not found.")
                    result.warnings.append("Configured recipe file '\(url.path)' was not found.")
                    continue
                }
                let loaded = await load(url, interactive: true, forcePrompt: false, skippingUnloaded: true)
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
    /// A load the user asked for (import, the manager's Load, opening it in the editor) brings back the recipes of the
    /// file that were unloaded, reset or revoked before; Greenshot's own loads (reload, a changed file, a review) skip them.
    public func loadFile(_ url: URL, interactive: Bool = true, forcePrompt: Bool = false) async -> RecipeLoadResult {
        await load(url, interactive: interactive, forcePrompt: forcePrompt, skippingUnloaded: false)
    }

    private func load(_ url: URL, interactive: Bool, forcePrompt: Bool, skippingUnloaded: Bool) async -> RecipeLoadResult {
        var result = RecipeLoadResult()
        let fileURL = URL(fileURLWithPath: RecipeTrustStore.standardized(url.path))
        let path = fileURL.path
        guard isFeatureEnabled else {
            result.errors.append("Recipes are switched off.")
            return result
        }
        let data: Data
        switch RecipeFileReader.read(fileURL) {
        case .success(let bytes):
            data = bytes
        case .failure(let failure):
            let message = RecipeFileReader.message(failure, path: path)
            result.errors.append(message)
            if failure != .unreadable {
                log.warn(message)
                if interactive { await approver?.showValidationError(validationErrorRequest(fileURL, "", "", recipe: nil, message: message)) }
            }
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
        if definitions.count > RecipeFileReader.maxRecipes {
            let message = "The recipe file holds \(definitions.count) recipes; at most \(RecipeFileReader.maxRecipes) are allowed."
            result.errors.append(message)
            if interactive { await approver?.showValidationError(validationErrorRequest(fileURL, content, hash, recipe: nil, message: message)) }
            return result
        }
        if definitions.contains(where: { $0.kind == .extension }) {
            return await loadExtensionFile(fileURL, content: content, hash: hash, definitions: definitions,
                                           interactive: interactive, forcePrompt: forcePrompt)
        }
        var anyChanged = false
        let validator = RecipeValidator(contracts: contracts, gates: gates())
        let unloaded = unloadedIds(inFile: path)
        // The record before this load: approving the first recipe of a new file records it, which mustn't make the
        // second one "changed outside Greenshot" (and a changed file's recipes are each compared with the old content).
        let previousRecord = trustStore.record(forFile: path)
        for recipe in definitions {
            // W-M4: a recipe the user unloaded, reset or revoked stays out while the file is loaded for its others.
            if skippingUnloaded, unloaded.contains(recipe.id.lowercased()) {
                log.info("Recipe '\(recipe.id)' of '\(path)' was unloaded by the user; it isn't loaded again.")
                continue
            }
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
            var approval = forcePrompt ? nil : trustStore.approval(forFile: path, sha256: hash, recipeId: recipe.id)
            if approval == nil {
                guard interactive, let approver else {
                    result.errors.append("Recipe '\(recipe.name)' from '\(path)' is not approved and interactive approval is disabled.")
                    continue
                }
                let mode: RecipeApprovalMode = forcePrompt ? .reVerify : (previousRecord == nil ? .newRecipe : .modified)
                let request = approvalRequest(recipe, fileURL, content, hash, validation, mode: mode, previousRecord: previousRecord)
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
            forgetUnloaded(recipe.id, inFile: path)
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
        let extensionFile = isExtensionFile(path)
        let inUse = fileRecipes.values.contains { $0.fileURL.map { recipeEquals($0.path, path) } ?? false } || extensionFile
        guard inUse, let data = RecipeFileReader.data(URL(fileURLWithPath: path)) else { return }
        let hash = RecipeHash.sha256Hex(data)
        if let record = trustStore.record(forFile: path), recipeEquals(record.sha256, hash) { return }
        guard askedForChangedFile[path.lowercased()] != hash else { return }
        askedForChangedFile[path.lowercased()] = hash
        log.info("Recipe file '\(path)' was changed outside Greenshot, asking for approval.")
        if extensionFile { dropExtensions(ofFile: path) }
        _ = await load(URL(fileURLWithPath: path), interactive: true, forcePrompt: false, skippingUnloaded: true)
    }

    /// Before a run: the recipe as it may run (its file still approved, or approved again), nil when not
    /// (upstream `EnsureRecipeApprovedAndUpToDateAsync`). The runner's `preflight`.
    ///
    /// The recipe handed in may be a copy (the editor's Test Run of unsaved changes, or a file opened in the editor that
    /// reuses the id of an approved recipe or a built-in): it runs only when each of its gated actions is an action of
    /// the approved version too (the loaded recipe, else the built-in, else none at all). Security review S-M2, R-F12.
    public func ensureApprovedAndCurrent(_ recipe: CaptureRecipe) async -> CaptureRecipe? {
        guard let loaded = fileRecipes[recipe.id.lowercased()], let url = loaded.fileURL else {
            return runnable(recipe, approvedVersion: builtIns[recipe.id.lowercased()])
        }
        guard let data = RecipeFileReader.data(url) else {
            log.warn("Recipe file '\(url.path)' no longer exists or can't be read.")
            return nil
        }
        let hash = RecipeHash.sha256Hex(data)
        if trustStore.approval(forFile: url.path, sha256: hash, recipeId: recipe.id) != nil {
            return runnable(recipe, approvedVersion: loaded.recipe)
        }
        log.info("Recipe file '\(url.path)' was changed or isn't approved; asking before it runs.")
        let result = await load(url, interactive: true, forcePrompt: false, skippingUnloaded: true)
        // This recipe must be loaded again; an error of another recipe of the file doesn't stop it (upstream checks
        // `IsValid`, which holds the errors of every recipe of the file).
        guard result.loadedRecipeIds.contains(where: { recipeEquals($0, recipe.id) }) else { return nil }
        return fileRecipes[recipe.id.lowercased()]?.recipe
    }

    /// `recipe` when it is the approved version, or a copy without gated actions beyond it; nil (logged) otherwise.
    private func runnable(_ recipe: CaptureRecipe, approvedVersion: CaptureRecipe?) -> CaptureRecipe? {
        if let approvedVersion, recipe == approvedVersion { return recipe }
        let changes = RecipeGates.unapprovedChanges(of: recipe, comparedWith: approvedVersion, contracts: contracts, environment: gates())
        guard changes.isEmpty else {
            log.warn("Recipe '\(recipe.id)' was not run: this copy does what its approved version doesn't (\(changes.joined(separator: "; "))). Save it to approve it.")
            return nil
        }
        return recipe
    }

    // MARK: Saving

    /// Saves from the recipe editor: the approval is renewed without asking unless `saveDecisionReasons` is not empty.
    /// `loadedSha256`: the SHA-256 of the bytes the editor loaded the recipe from (nil: not from a file the editor read).
    public func save(_ recipe: CaptureRecipe, to url: URL, loadedSha256: String? = nil) async -> RecipeLoadResult {
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
            let edit = editApproval(recipe, path: path, validation: validation, loadedSha256: loadedSha256)
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
        // Saved to another file (Save As): the recipe moves there. The old file keeps its other recipes, without this one
        // after a reload too, or leaves the settings when it held only this one.
        if let previous = fileRecipes[recipe.id.lowercased()]?.fileURL, !recipeEquals(previous.path, path) {
            removeFileRecipe(recipe.id)
        }
        // Without an approval (an invalid recipe, saved as work in progress) none of its triggers is active.
        register(LoadedRecipe(recipe: recipe, source: .file(fileURL), replacesBuiltIn: builtIns[recipe.id.lowercased()] != nil,
                              approval: approval, validation: validation))
        addFileToSettings(path)
        forgetUnloaded(recipe.id, inFile: path)
        result.loadedRecipeIds.append(recipe.id)
        result.warnings += validation.warnings + validation.errors
        notify()
        return result
    }

    public func saveDecisionReasons(for recipe: CaptureRecipe, at url: URL?, loadedSha256: String? = nil) -> [String] {
        let validation = RecipeValidator(contracts: contracts, gates: gates()).validate(recipe)
        guard validation.isValid else { return [] }
        let path = url.map { RecipeTrustStore.standardized($0.path) }
        return editApproval(recipe, path: path, validation: validation, loadedSha256: loadedSha256).decision.reasons
    }

    func editApproval(_ recipe: CaptureRecipe, path: String?, validation: RecipeValidationResult, loadedSha256: String? = nil)
        -> (approval: RecipeApproval, decision: RecipeEditDecision, approvedContent: String?) {
        let record = path.flatMap { trustStore.record(forFile: $0) }
        let previous = record?.approval(for: recipe.id)
        var approvedContent = record?.approvedContent
        // A record without the content: the file on disk while it is still the approved one.
        if approvedContent == nil, let record, let path, let data = RecipeFileReader.data(URL(fileURLWithPath: path)),
           recipeEquals(RecipeHash.sha256Hex(data), record.sha256) {
            approvedContent = RecipeSerializer.text(of: data)
        }
        let approvedVersion = RecipeEditApproval.findRecipe(in: approvedContent, id: recipe.id)
        let made = RecipeEditApproval.create(edited: recipe, validation: validation, approvedVersion: approvedVersion,
                                             previousApproval: previous, replacesBuiltIn: builtIns[recipe.id.lowercased()] != nil)
        var decision = made.decision
        // The approval is per kind of permission, but it belongs to the approved bytes: a file on disk that isn't those bytes
        // any more (changed behind Greenshot's back, then opened without approval) isn't a version the user approved, so
        // each command, upload target or folder that the approved version lacks needs a decision of its own.
        if let record, let path, Self.isNotApprovedBytes(record, at: path, loadedSha256: loadedSha256) {
            for change in RecipeGates.unapprovedChanges(of: recipe, comparedWith: approvedVersion, contracts: contracts, environment: gates())
            where !decision.reasons.contains(change) {
                decision.reasons.append(change)
            }
        }
        return (made.approval, decision, approvedContent)
    }

    /// The bytes of a recipe file, read with the size and regular-file limits of every other recipe read; nil (logged) otherwise.
    public static func readRecipeFile(_ url: URL) -> Data? { RecipeFileReader.data(url) }

    /// True when what the edit grew from isn't the bytes `record` approved. The editor says which bytes it loaded: the
    /// file on disk at save time proves nothing (it can be put back after a change, or deleted). Without that, the file
    /// on disk counts; a file that is gone while a record exists counts as changed.
    private static func isNotApprovedBytes(_ record: RecipeTrustRecord, at path: String, loadedSha256: String?) -> Bool {
        if let loadedSha256 { return !recipeEquals(loadedSha256, record.sha256) }
        guard FileManager.default.fileExists(atPath: path) else { return true }
        guard let data = RecipeFileReader.data(URL(fileURLWithPath: path)) else { return true }
        return !recipeEquals(RecipeHash.sha256Hex(data), record.sha256)
    }

    /// An AI tool's proposal (RCP-204): written to `url` after the user approved it, triggers and permissions off.
    public func propose(content: String, proposedBy: String, aiRequest: String?, aiExplanation: String?, saveTo url: URL) async -> RecipeLoadResult {
        var result = RecipeLoadResult()
        let fileURL = URL(fileURLWithPath: RecipeTrustStore.standardized(url.path))
        // The same limit as for files: the text is read and validated before anyone approved it.
        guard content.utf8.count <= RecipeFileReader.maxBytes else {
            result.errors.append("The proposed recipe is larger than \(RecipeFileReader.maxBytes / 1024 / 1024) MB.")
            return result
        }
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
        forgetUnloaded(recipe.id, inFile: fileURL.path)
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
        return await load(url, interactive: true, forcePrompt: true, skippingUnloaded: true)
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
            if let data = RecipeFileReader.data(url) {
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
        if let url = loaded.fileURL, let data = RecipeFileReader.data(url) {
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
                // Trimmed like AIToolCatalog offers the tools, so the name offered is the name that runs (MC-M1).
                let named = (isAITool ? trigger.toolName : trigger.command)?.trimmingCharacters(in: .whitespaces) ?? ""
                let name = named.isEmpty ? loaded.recipe.id : named
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
        let wanted = command.trimmingCharacters(in: .whitespaces)
        var match = available.first(where: { recipeEquals($0.command, wanted) })
        // The command line may name the recipe by its id; an AI tool is only ever its tool name.
        if match == nil, source.isAITool == false { match = available.first(where: { recipeEquals($0.recipeId, wanted) }) }
        guard let match else {
            if source == .browser, commands(for: .commandLine).contains(where: { recipeEquals($0.command, wanted) || recipeEquals($0.recipeId, wanted) }) {
                throw Self.browserRefusal(command)
            }
            throw RecipeStepError("Error: unknown recipe command '\(command)'.", errorType: "ArgumentException")
        }
        return try runRequest(match: match, arguments: arguments, source: source, resolvePath: resolvePath)
    }

    /// A run request for exactly the recipe and trigger of `match` (an entry of `commands(for: source)`), without
    /// searching the command again: two recipes may share a command or tool name, and the one that was matched (and
    /// checked: browser approval, arguments, capture consent) is the one that runs (security review MC-M1). Throws like
    /// `runRequest(command:)` when the entry isn't available to the source any more.
    public func runRequest(match: RecipeCommand, arguments: [String: String], source: RecipeInvocationSource,
                           resolvePath: (String, ContractDataType) throws -> String) throws -> RecipeRunRequest {
        func same(_ command: RecipeCommand) -> Bool { recipeEquals(command.recipeId, match.recipeId) && command.triggerIndex == match.triggerIndex }
        guard let current = commands(for: source).first(where: same),
              let loaded = recipe(id: current.recipeId), current.triggerIndex < loaded.recipe.triggers.count else {
            if source == .browser, commands(for: .commandLine).contains(where: same) { throw Self.browserRefusal(match.command) }
            throw RecipeStepError("Error: unknown recipe command '\(match.command)'.", errorType: "ArgumentException")
        }
        let variables: [String: JSONValue]
        switch RecipeArgumentBinder.bind(declared: current.arguments, supplied: arguments, recipeName: current.command, resolvePath: resolvePath) {
        case .success(let bound): variables = bound
        case .failure(let error): throw error
        }
        let trigger = loaded.recipe.triggers[current.triggerIndex]
        var request = RecipeRunRequest(recipe: loaded.recipe, trigger: RecipeTriggerInfo(triggerType: trigger.triggerType, triggerName: trigger.name,
                                                                                         triggerIndex: current.triggerIndex))
        request.variables = variables
        request.optionValues = optionValues
        return request
    }

    private static func browserRefusal(_ command: String) -> RecipeStepError {
        RecipeStepError("[SECURITY] Recipe '\(command)' does not allow invocation from a browser. Set 'AllowBrowserInvocation' on its Commandline trigger to enable this.",
                        errorType: "UnauthorizedAccessException")
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

    /// Unloads a file recipe; its file leaves the settings when no other recipe of it is loaded. While it stays for the
    /// others, the recipe is remembered as unloaded so that a reload doesn't bring it back (W-M4).
    private func removeFileRecipe(_ recipeId: String) {
        let key = recipeId.lowercased()
        guard let loaded = fileRecipes.removeValue(forKey: key) else { return }
        fileOrder.removeAll { $0 == key }
        guard let path = loaded.fileURL?.path else { return }
        let stillUsed = fileRecipes.values.contains { $0.fileURL.map { recipeEquals($0.path, path) } ?? false }
        if stillUsed {
            rememberUnloaded(loaded.recipe.id, inFile: path)
        } else {
            removeFileFromSettings(path)
            forgetUnloaded(nil, inFile: path)
        }
    }

    /// The recipe ids (lower case) a reload skips in the file.
    private func unloadedIds(inFile path: String) -> Set<String> {
        let settings = loadSettings()
        guard let key = unloadedKey(settings, path) else { return [] }
        return Set((settings.unloadedRecipes[key] ?? []).map { $0.lowercased() })
    }

    private func unloadedKey(_ settings: RecipeSettings, _ path: String) -> String? {
        settings.unloadedRecipes.keys.first { recipeEquals(RecipeTrustStore.standardized($0), path) }
    }

    private func rememberUnloaded(_ recipeId: String, inFile path: String) {
        var settings = loadSettings()
        let key = unloadedKey(settings, path) ?? path
        var ids = settings.unloadedRecipes[key] ?? []
        guard !ids.contains(where: { recipeEquals($0, recipeId) }) else { return }
        ids.append(recipeId.lowercased())
        settings.unloadedRecipes[key] = ids
        saveSettings(settings)
    }

    /// Brings `recipeId` (nil: every recipe) of the file back for reloads.
    private func forgetUnloaded(_ recipeId: String?, inFile path: String) {
        var settings = loadSettings()
        guard let key = unloadedKey(settings, path) else { return }
        var ids = settings.unloadedRecipes[key] ?? []
        if let recipeId { ids.removeAll { recipeEquals($0, recipeId) } } else { ids = [] }
        settings.unloadedRecipes[key] = ids.isEmpty ? nil : ids
        saveSettings(settings)
    }

    func addFileToSettings(_ path: String) {
        var settings = loadSettings()
        guard !settings.files.contains(where: { recipeEquals(RecipeTrustStore.standardized($0), path) }) else { return }
        settings.files.append(path)
        saveSettings(settings)
    }

    func removeFileFromSettings(_ path: String) {
        var settings = loadSettings()
        let before = settings.files.count
        settings.files.removeAll { recipeEquals(RecipeTrustStore.standardized($0), path) }
        if settings.files.count != before { saveSettings(settings) }
    }

    func notify() {
        onChange?()
    }

    func approvalRequest(_ recipe: CaptureRecipe, _ url: URL, _ content: String, _ hash: String, _ validation: RecipeValidationResult,
                         mode: RecipeApprovalMode) -> RecipeApprovalRequest {
        approvalRequest(recipe, url, content, hash, validation, mode: mode, previousRecord: trustStore.record(forFile: url.path))
    }

    /// `previousRecord`: the file's record before the load that asks (`load` reads it once for all recipes of the file).
    func approvalRequest(_ recipe: CaptureRecipe, _ url: URL, _ content: String, _ hash: String, _ validation: RecipeValidationResult,
                         mode: RecipeApprovalMode, previousRecord record: RecipeTrustRecord?) -> RecipeApprovalRequest {
        let describer = RecipeDescriber(contracts: contracts, gates: gates())
        var request = RecipeApprovalRequest(mode: mode, recipe: recipe, fileURL: url, content: content, contentHash: hash)
        request.validation = validation
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

    func validationErrorRequest(_ url: URL, _ content: String, _ hash: String, recipe: CaptureRecipe?, message: String) -> RecipeApprovalRequest {
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
        if message.contains("does not exist in 'nodes'") || message.contains("does not match any defined node id") {
            return "Check the node ids in 'flow': each must be the id of a node."
        }
        return "Edit the recipe file and load it again."
    }
}

private let log = Log("Recipes")

/// The preflight's comparison of a copy with its approved version (`RecipeLibrary.ensureApprovedAndCurrent`).
extension RecipeGates {
    /// Every gated action of the recipe's nodes, as the validator collects them.
    static func actions(of recipe: CaptureRecipe, contracts: StepContractCatalog, environment: GateEnvironment) -> [RecipeGatedAction] {
        let variables = variablesSet(by: recipe, contracts: contracts)
        var result: [RecipeGatedAction] = []
        for node in recipe.nodes {
            guard let contract = contracts.contract(for: node.stepType) else { continue }
            for action in actions(of: node, contract: contract, environment: environment, recipeSets: variables)
            where !result.contains(action) {
                result.append(action)
            }
        }
        return result
    }

    /// What `recipe` does with permissions that `approved` doesn't (empty: it may run under the approval of `approved`):
    /// - a gated action `approved` lacks: same kind and exactly the same target text, so another command line, folder or
    ///   upload target is another action (case counts, as it may on disk);
    /// - a node with gated actions whose step and parameters aren't those of a node of `approved`, so other arguments, a
    ///   working folder or a file format of the same program count too.
    /// Each entry is a line for the log.
    static func unapprovedChanges(of recipe: CaptureRecipe, comparedWith approved: CaptureRecipe?, contracts: StepContractCatalog,
                                  environment: GateEnvironment) -> [String] {
        let allowed = approved.map { actions(of: $0, contracts: contracts, environment: environment) } ?? []
        let describer = RecipeDescriber(contracts: contracts, gates: environment)
        var changes: [String] = []
        for action in actions(of: recipe, contracts: contracts, environment: environment)
        where !allowed.contains(where: { $0.gateType == action.gateType && $0.target == action.target }) {
            changes.append(describer.describe(action))
        }
        let variables = variablesSet(by: recipe, contracts: contracts)
        for node in recipe.nodes {
            guard let contract = contracts.contract(for: node.stepType),
                  !actions(of: node, contract: contract, environment: environment, recipeSets: variables).isEmpty else { continue }
            let same = approved?.nodes.contains { recipeEquals($0.stepType, node.stepType) && $0.parameters == node.parameters } ?? false
            if !same { changes.append("node '\(node.id)' (\(node.stepType)) differs from the approved recipe") }
        }
        return changes
    }
}
