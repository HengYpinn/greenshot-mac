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
            // A built-in recipe's name is English data: shown in the language of the app where upstream has the text.
            let shown = loaded.isBuiltIn ? L10nText.display(name) : name
            return RecipeSettingsRow(id: recipe.id, name: name.isEmpty ? recipe.id : shown,
                                     source: fileURL.map { ($0.path as NSString).abbreviatingWithTildeInPath }
                                        ?? String(localized: "Built into Greenshot"),
                                     fileURL: fileURL, isBuiltIn: loaded.isBuiltIn, isEnabled: loaded.isEnabled,
                                     replacesBuiltIn: loaded.replacesBuiltIn, proposedBy: loaded.proposedBy, triggers: triggerSummary(loaded))
        }
    }

    static func triggerSummary(_ loaded: LoadedRecipe) -> String {
        let triggers = loaded.recipe.triggers
        guard !triggers.isEmpty else { return String(localized: "No trigger: from the recipe list or the command line") }
        return triggers.enumerated().map { index, trigger in
            let label = shortLabel(trigger)
            if !trigger.enabled { return String(localized: "\(label) (disabled)") }
            return loaded.isEnabled && !loaded.isTriggerActive(at: index)
                ? String(localized: "\(label) (off)") : label
        }.joined(separator: " · ")
    }

    private static func shortLabel(_ trigger: TriggerConfig) -> String {
        if trigger.isType(WellKnownTriggerType.hotkey) {
            let text = trigger.hotkey ?? ""
            let hotkey = RecipeHotkeyText.parse(text)?.displayString ?? text
            return String(localized: "Hotkey \(hotkey)")
        }
        if trigger.isType(WellKnownTriggerType.contextMenu) || trigger.isType(WellKnownTriggerType.systray) { return String(localized: "Menu entry") }
        if trigger.isType(WellKnownTriggerType.editor) { return String(localized: "Editor menu") }
        if trigger.isType(WellKnownTriggerType.clipboard) { return String(localized: "Clipboard") }
        if trigger.isType(WellKnownTriggerType.commandline) {
            let command = trigger.command ?? ""
            return String(localized: "Command “\(command)”")
        }
        if trigger.isType(WellKnownTriggerType.openFile) { return String(localized: "Open With") }
        if trigger.isType(WellKnownTriggerType.extension) { return String(localized: "Browser extension") }
        if trigger.isType(WellKnownTriggerType.aiTool) {
            let tool = trigger.toolName ?? ""
            return String(localized: "AI tool “\(tool)”")
        }
        if trigger.isType(WellKnownTriggerType.manual) { return String(localized: "Manual", comment: "A recipe trigger: the recipe runs when the user starts it") }
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

    /// "Permissions": the approval window as a review (Save Changes, Keep as Is, Revoke Approval). What it did or
    /// couldn't do (a revocation or a change the trust store refused, a permission the recipe needs taken away) is
    /// shown, like the AI Tools tab and the recipe editor do.
    func review(_ row: RecipeSettingsRow) {
        guard let library = runtime?.library else { return }
        Task { @MainActor in
            let result = await library.reviewApproval(recipeId: row.id)
            guard !result.isValid else { return }
            log.info("Review of '\(row.id)': \(result.errors.joined(separator: " "))")
            Self.warn(String(localized: "Recipe Permissions"), detail: result.errors.joined(separator: "\n"))
        }
    }

    func revoke(_ row: RecipeSettingsRow) {
        let alert = NSAlert()
        alert.alertStyle = .warning
        let name = row.name
        alert.messageText = String(localized: "Revoke the approval of “\(name)”?")
        alert.informativeText = String(localized: "It stops running right away and isn't loaded again. Its file stays where it is: import it again to review and approve it.")
        alert.addButton(withTitle: String(localized: "Keep"))
        alert.addButton(withTitle: String(localized: "Revoke")).hasDestructiveAction = true
        guard alert.runModal() == .alertSecondButtonReturn, let library = runtime?.library else { return }
        // Refused (the trust store's key can't be read, e.g. the Keychain is locked): the recipe is still approved and
        // keeps running, so say so.
        guard !library.revokeApproval(recipeId: row.id) else { return }
        Self.warn(String(localized: "The approval of “\(name)” could not be revoked. It is unchanged; see the log for why."))
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

    /// A warning with OK.
    private static func warn(_ message: String, detail: String = "") {
        let alert = NSAlert()
        alert.alertStyle = .warning
        alert.messageText = message
        alert.informativeText = detail
        NSApp.activate()
        alert.runModal()
    }

    /// Asks first, like the recipe manager (W-L4): the action button, then Cancel.
    private static func confirm(_ confirmation: RecipeConfirmation) -> Bool {
        let alert = NSAlert()
        alert.alertStyle = .warning
        alert.messageText = confirmation.title
        alert.informativeText = confirmation.message
        alert.addButton(withTitle: confirmation.button)
        alert.addButton(withTitle: String(localized: "Cancel"))
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
