// Greenshot for Mac (Community) - an unofficial macOS port of Greenshot
// Copyright (C) 2026 Greenshot for Mac (Community) contributors
// Based on Greenshot, Copyright (C) 2007-2026 Thomas Braun, Jens Klingen, Robin Krom
// SPDX-License-Identifier: GPL-3.0-or-later

import Foundation

/// The automatic steps in use (upstream `RecipeManager`: `GetEffectiveRecipe`, `GetExtensionsChanging`,
/// `UnregisterExtension`, `RevokeApproval`, `ReviewApproval`, `ShowRecipeDetails` for extensions) and the option values
/// of recipes and automatic steps.
extension RecipeLibrary {
    // MARK: Composing

    /// The recipe as it runs: with the switched-on automatic steps in its slots (`RecipeComposer`). The recipe itself
    /// (`==`) when no automatic step changes it. An automatic step from a file is only used while its file is the approved
    /// content; a file changed behind the monitor's back is asked about again and left out meanwhile.
    public func effectiveRecipe(_ recipe: CaptureRecipe) -> CaptureRecipe {
        guard recipe.composition == nil else { return recipe }
        let values = optionValues
        let settings: (CaptureRecipe) -> RecipeExtensionSettings = { RecipeExtensionSettings.stored(for: $0, in: values) }
        var usable = extensions.map(\.recipe)
        for ext in RecipeComposer.applicable(to: recipe, among: usable, settings: settings) {
            guard let loaded = extensionStore.files[ext.id.lowercased()], let url = loaded.fileURL else { continue }
            let current = RecipeFileReader.data(url).map(RecipeHash.sha256Hex)
            if let current, trustStore.approval(forFile: url.path, sha256: current, recipeId: ext.id) != nil { continue }
            log.warn("Automatic step '\(ext.id)': its file '\(url.path)' changed or can't be read, it isn't used until approved again.")
            usable.removeAll { recipeEquals($0.id, ext.id) }
            Task { @MainActor [weak self] in await self?.fileDidChange(url) }
        }
        let composed = RecipeComposer.compose(recipe, extensions: usable, settings: settings)
        if let applied = composed.composition?.appliedExtensions, composed != recipe {
            log.debug("Recipe '\(recipe.id)' runs with the automatic step(s) \(applied.map(\.id).joined(separator: ", ")).")
        }
        return composed
    }

    /// The automatic steps which change the recipe now (switched on, for this recipe; upstream `GetExtensionsChanging`).
    public func extensionsChanging(recipeId: String) -> [LoadedRecipe] {
        guard let loaded = recipe(id: recipeId) else { return [] }
        let applied = effectiveRecipe(loaded.recipe).composition?.appliedExtensions ?? []
        let all = extensions
        return applied.compactMap { ext in all.first { recipeEquals($0.recipe.id, ext.id) } }
    }

    /// An automatic step by id, built in or from a file.
    public func loadedExtension(id: String) -> LoadedRecipe? {
        extensions.first { recipeEquals($0.recipe.id, id) }
    }

    /// The built-in automatic step with the id (also while a file replaces it).
    public func builtInExtension(id: String) -> CaptureRecipe? {
        extensionStore.builtIns[id.lowercased()]
    }

    /// Opens an automatic step in the recipe editor, for a proposal approved with "open in the recipe editor" (the app
    /// sets it to REDITOR's `RecipeEditorService.openExtension(id:)`).
    public var openExtensionInEditor: (@MainActor @Sendable (String) -> Void)? {
        get { extensionStore.openInEditor }
        set { extensionStore.openInEditor = newValue }
    }

    // MARK: Settings of the automatic steps (Settings › Recipes, Quick Settings, the manager's switch)

    /// What the user picked for the automatic step.
    public func extensionSettings(id: String) -> RecipeExtensionSettings {
        guard let ext = loadedExtension(id: id)?.recipe else { return RecipeExtensionSettings(enabled: false) }
        return RecipeExtensionSettings.stored(for: ext, in: optionValues)
    }

    /// The value of an option of a recipe or an automatic step (the stored value or the default).
    public func optionValue(key: String, ownerId: String) -> JSONValue? {
        guard let option = optionDefinition(key: key, ownerId: ownerId) else { return nil }
        return optionValues.value(of: option, recipeId: ownerId)
    }

    /// Sets an option of a recipe or an automatic step (also an automatic step's scope keys); stored only when it differs
    /// from the default (upstream `RecipeOptionStore.SetValue`). Sends the change signal when something changed.
    public func setOption(_ value: JSONValue, key: String, ownerId: String) {
        guard let option = optionDefinition(key: key, ownerId: ownerId) else { return }
        if storeOptionValue(value, of: option, ownerId: ownerId) { notify() }
    }

    /// Switches an automatic step on or off (its `enabled` option); one without a switch is always on.
    public func setExtensionEnabled(_ enabled: Bool, id: String) {
        setOption(.bool(enabled), key: RecipeExtensionNames.enabledOptionKey, ownerId: id)
    }

    /// "Where it is used" (the scope dialog): all recipes but `exceptRecipes`, recipes added later included; `onlyDestinations`
    /// empty for all (upstream `RecipeOptionGroupViewModel.Save`).
    public func setExtensionScope(id: String, exceptRecipes: [String], onlyDestinations: [String]) {
        guard loadedExtension(id: id) != nil else { return }
        func joined(_ ids: [String]) -> String { ids.sorted { $0.lowercased() < $1.lowercased() }.joined(separator: ",") }
        var values = optionValues
        var changed = values.setValue(.string(RecipeExtensionNames.applyToAll), of: RecipeExtensionNames.applyToOption, recipeId: id)
        changed = values.setValue(.string(""), of: RecipeExtensionNames.onlyRecipesOption, recipeId: id) || changed
        changed = values.setValue(.string(joined(exceptRecipes)), of: RecipeExtensionNames.exceptRecipesOption, recipeId: id) || changed
        changed = values.setValue(.string(joined(onlyDestinations)), of: RecipeExtensionNames.onlyDestinationsOption, recipeId: id) || changed
        guard changed else { return }
        var settings = loadSettings()
        settings.optionValues = values.stored
        saveSettings(settings)
        notify()
    }

    private func optionDefinition(key: String, ownerId: String) -> RecipeOption? {
        if let ext = loadedExtension(id: ownerId)?.recipe {
            return ext.option(key) ?? RecipeExtensionNames.scopeOptions.first { recipeEquals($0.key, key) }
        }
        return recipe(id: ownerId)?.recipe.option(key)
    }

    // MARK: Managing automatic steps from files

    /// Stops using an automatic step from a file and forgets the file; a built-in one it replaced comes back (upstream
    /// `UnregisterExtension`). False for a built-in one.
    @discardableResult
    public func unloadExtension(id: String) -> Bool {
        guard removeFileExtension(id) else { return false }
        log.info("Unloaded automatic step '\(id)'.")
        notify()
        return true
    }

    /// Takes the approval of an automatic step's file back: it isn't used, and isn't loaded again until its file is opened
    /// again; a built-in one it replaced comes back. False for a built-in one.
    @discardableResult
    public func revokeExtensionApproval(id: String) -> Bool {
        guard let loaded = extensionStore.files[id.lowercased()], let url = loaded.fileURL else { return false }
        do {
            try trustStore.revokeApproval(recipeId: loaded.recipe.id, forFile: url.path)
        } catch {
            log.error("Could not revoke the approval of automatic step '\(id)'.", error: error)
            return false
        }
        removeFileExtension(id)
        log.info("The user revoked the approval of automatic step '\(id)' from '\(url.path)'.")
        notify()
        return true
    }

    /// "Permissions": the approval sheet in review mode for an automatic step's file.
    public func reviewExtensionApproval(id: String) async -> RecipeLoadResult {
        guard let url = extensionStore.files[id.lowercased()]?.fileURL else {
            var result = RecipeLoadResult()
            result.errors.append("Automatic step '\(id)' has no approval to review.")
            return result
        }
        return await loadFile(url, interactive: true, forcePrompt: true)
    }

    /// What it does, which recipes it changes and its approval (upstream `GetExtensionDetails`); the reach is
    /// `describeExtensionReach`.
    public func extensionDetails(id: String) -> RecipeDetails? {
        guard let loaded = loadedExtension(id: id) else { return nil }
        var details = RecipeDetails()
        details.whatItDoes = RecipeDescriber(contracts: contracts, gates: gates()).describeSteps(loaded.recipe)
        details.proposedBy = loaded.proposedBy
        if let url = loaded.fileURL, let record = trustStore.record(forFile: url.path) {
            details.approvedAt = record.approvedAt
            details.approvedHash = record.sha256
            if let data = RecipeFileReader.data(url) {
                details.isApprovalCurrent = recipeEquals(RecipeHash.sha256Hex(data), record.sha256)
            }
            details.permissions = record.approval(for: loaded.recipe.id)?.allowedGates ?? []
        }
        if loaded.replacesBuiltIn, let builtIn = extensionStore.builtIns[loaded.recipe.id.lowercased()] {
            details.builtInDiff = RecipeTextDiff.unifiedText(RecipeSerializer.encode(builtIn), RecipeSerializer.encode(loaded.recipe))
        }
        return details
    }

    /// The approval sheet read-only for an automatic step (upstream `ShowExtensionDetails`).
    public func extensionDetailsRequest(id: String) -> RecipeApprovalRequest? {
        guard let loaded = loadedExtension(id: id) else { return nil }
        var request: RecipeApprovalRequest
        if let url = loaded.fileURL, let data = RecipeFileReader.data(url) {
            let content = RecipeSerializer.text(of: data) ?? ""
            let fileVersion = ((try? RecipeSerializer.decode(text: content)) ?? []).first { recipeEquals($0.id, id) } ?? loaded.recipe
            request = extensionApprovalRequest(fileVersion, url, content, RecipeHash.sha256Hex(data), validateExtension(fileVersion), mode: .reVerify)
            request.startSwitchedOff = false
            request.suggestedApproval = loaded.approval
        } else {
            let content = RecipeSerializer.encode(loaded.recipe)
            request = RecipeApprovalRequest(mode: .reVerify, recipe: loaded.recipe, fileURL: nil, content: content,
                                            contentHash: RecipeHash.sha256Hex(Data(content.utf8)))
            let validation = validateExtension(loaded.recipe)
            request.validation = validation
            request.steps = RecipeDescriber(contracts: contracts, gates: gates()).describeSteps(loaded.recipe)
            request.gates = validation.gateTypes
            request.extensionReach = describeExtensionReach(loaded.recipe)
        }
        request.isReadOnly = true
        return request
    }

    /// "Details" of the recipe manager: the approval sheet read-only, for a recipe or an automatic step (through the
    /// library's approver: RUI's sheet).
    public func showDetails(id: String) async {
        guard let request = detailsRequest(recipeId: id) ?? extensionDetailsRequest(id: id) else { return }
        _ = await approver?.requestApproval(request)
    }
}

private let log = Log("Recipes")
