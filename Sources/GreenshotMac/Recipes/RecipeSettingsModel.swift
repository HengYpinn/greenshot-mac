// Greenshot for Mac (Community) - an unofficial macOS port of Greenshot
// Copyright (C) 2026 Greenshot for Mac (Community) contributors
// Based on Greenshot, Copyright (C) 2007-2026 Thomas Braun, Jens Klingen, Robin Krom
// SPDX-License-Identifier: GPL-3.0-or-later

import AppKit
import GreenshotCore

private let log = Log("Recipes")

/// A recipe in Settings › Recipes.
struct RecipeSettingsRow: Identifiable, Equatable {
    var id: String
    var name: String
    /// "Built into Greenshot" or the file, with ~ for the home folder.
    var source: String
    var fileURL: URL?
    var isBuiltIn: Bool
    var isEnabled: Bool
    var replacesBuiltIn: Bool
    /// The AI tool that wrote the file.
    var proposedBy: String?
    /// "Hotkey ⌘⇧B · Menu entry · Clipboard (off)".
    var triggers: String

    /// The rows of the recipes the library knows, in its order.
    static func rows(from recipes: [LoadedRecipe]) -> [RecipeSettingsRow] {
        recipes.map { loaded in
            let recipe = loaded.recipe
            var fileURL: URL?
            if case .file(let url) = loaded.source { fileURL = url }
            let name = recipe.name.trimmingCharacters(in: .whitespaces)
            return RecipeSettingsRow(id: recipe.id, name: name.isEmpty ? recipe.id : name,
                                     source: fileURL.map { ($0.path as NSString).abbreviatingWithTildeInPath } ?? "Built into Greenshot",
                                     fileURL: fileURL, isBuiltIn: loaded.isBuiltIn, isEnabled: loaded.isEnabled,
                                     replacesBuiltIn: loaded.replacesBuiltIn, proposedBy: loaded.proposedBy, triggers: triggerSummary(loaded))
        }
    }

    static func triggerSummary(_ loaded: LoadedRecipe) -> String {
        let triggers = loaded.recipe.triggers
        guard !triggers.isEmpty else { return "No trigger: from the recipe list or the command line" }
        return triggers.enumerated().map { index, trigger in
            let label = shortLabel(trigger)
            if !trigger.enabled { return label + " (disabled)" }
            return loaded.isEnabled && !loaded.isTriggerActive(at: index) ? label + " (off)" : label
        }.joined(separator: " · ")
    }

    private static func shortLabel(_ trigger: TriggerConfig) -> String {
        if trigger.isType(WellKnownTriggerType.hotkey) {
            let text = trigger.hotkey ?? ""
            return "Hotkey " + (RecipeHotkeyText.parse(text)?.displayString ?? text)
        }
        if trigger.isType(WellKnownTriggerType.contextMenu) || trigger.isType(WellKnownTriggerType.systray) { return "Menu entry" }
        if trigger.isType(WellKnownTriggerType.editor) { return "Editor menu" }
        if trigger.isType(WellKnownTriggerType.clipboard) { return "Clipboard" }
        if trigger.isType(WellKnownTriggerType.commandline) { return "Command “\(trigger.command ?? "")”" }
        if trigger.isType(WellKnownTriggerType.openFile) { return "Open With" }
        if trigger.isType(WellKnownTriggerType.extension) { return "Browser extension" }
        if trigger.isType(WellKnownTriggerType.aiTool) { return "AI tool “\(trigger.toolName ?? "")”" }
        if trigger.isType(WellKnownTriggerType.manual) { return "Manual" }
        return trigger.triggerType
    }
}

/// Settings › Recipes' list (RCP-002, RCP-199, RCP-202, RCP-203, APP-095): the recipes with their switch, Details,
/// Permissions, Revoke, Reset Default, Unload; Import and Reload. Works without a started runtime (`--snapshot`): then it
/// is empty, or shows what it was given.
@MainActor
final class RecipeSettingsModel: ObservableObject {
    @Published private(set) var rows: [RecipeSettingsRow] = []
    @Published private(set) var clashes: [RecipeHotkeyClash] = []
    /// False before the recipes started (or in `--snapshot`).
    let isRunning: Bool

    private weak var runtime: RecipeRuntime?
    private var observation: RecipeObservation?
    private var clashObserver: NSObjectProtocol?

    convenience init() {
        self.init(runtime: RecipeRuntime.shared)
    }

    init(runtime: RecipeRuntime?) {
        self.runtime = runtime
        isRunning = runtime != nil
        refresh()
        observation = runtime?.addChangeObserver { [weak self] in self?.refresh() }
        clashObserver = NotificationCenter.default.addObserver(forName: RecipeHotkeyBindings.clashesDidChange, object: nil,
                                                               queue: .main) { [weak self] _ in
            MainActor.assumeIsolated { self?.clashes = RecipeHotkeyBindings.clashes }
        }
    }

    /// Fixed content (`--snapshot`).
    init(rows: [RecipeSettingsRow], clashes: [RecipeHotkeyClash]) {
        isRunning = true
        self.rows = rows
        self.clashes = clashes
    }

    deinit {
        observation?.cancel()
        if let clashObserver { NotificationCenter.default.removeObserver(clashObserver) }
    }

    func refresh() {
        guard let runtime else { return }
        rows = RecipeSettingsRow.rows(from: runtime.library.recipes)
        clashes = RecipeHotkeyBindings.clashes
    }

    // MARK: Actions

    func setEnabled(_ enabled: Bool, recipeId: String) {
        runtime?.library.setEnabled(enabled, recipeId: recipeId)
    }

    /// The approval window read-only (upstream "Details").
    func showDetails(_ row: RecipeSettingsRow) {
        guard let request = runtime?.library.detailsRequest(recipeId: row.id) else { return }
        Task { @MainActor in _ = await RecipeApprovalPresenter.shared.requestApproval(request) }
    }

    /// "Permissions": the approval window as a review (Save Changes, Keep as Is, Revoke Approval).
    func review(_ row: RecipeSettingsRow) {
        guard let library = runtime?.library else { return }
        Task { @MainActor in
            let result = await library.reviewApproval(recipeId: row.id)
            if !result.errors.isEmpty { log.info("Review of '\(row.id)': \(result.errors.joined(separator: " "))") }
        }
    }

    func revoke(_ row: RecipeSettingsRow) {
        let alert = NSAlert()
        alert.alertStyle = .warning
        alert.messageText = "Revoke the approval of “\(row.name)”?"
        alert.informativeText = "It stops running right away and isn't loaded again. Its file stays where it is: import it again to review and approve it."
        alert.addButton(withTitle: "Keep")
        alert.addButton(withTitle: "Revoke").hasDestructiveAction = true
        guard alert.runModal() == .alertSecondButtonReturn else { return }
        runtime?.library.revokeApproval(recipeId: row.id)
    }

    /// "Reset Default": the built-in recipe instead of the file that replaces it.
    func resetToDefault(_ row: RecipeSettingsRow) {
        guard Self.confirm(.resetToDefault(name: row.name)) else { return }
        runtime?.library.resetToDefault(recipeId: row.id)
    }

    /// "Unload": out of the recipe files; its approval stays.
    func unload(_ row: RecipeSettingsRow) {
        guard Self.confirm(.unload(name: row.name, appName: AppInfo.name)) else { return }
        runtime?.library.unload(recipeId: row.id)
    }

    /// Asks first, like the recipe manager (W-L4): the action button, then Cancel.
    private static func confirm(_ confirmation: RecipeConfirmation) -> Bool {
        let alert = NSAlert()
        alert.alertStyle = .warning
        alert.messageText = confirmation.title
        alert.informativeText = confirmation.message
        alert.addButton(withTitle: confirmation.button)
        alert.addButton(withTitle: "Cancel")
        NSApp.activate()
        return alert.runModal() == .alertFirstButtonReturn
    }

    func showInFinder(_ row: RecipeSettingsRow) {
        guard let url = row.fileURL else { return }
        NSWorkspace.shared.activateFileViewerSelecting([url])
    }

    func importRecipe() {
        RecipeMenus.importRecipe()
    }

    func reload() {
        RecipeMenus.reloadRecipes()
    }
}
