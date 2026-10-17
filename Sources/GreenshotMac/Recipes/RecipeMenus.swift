// Greenshot for Mac (Community) - an unofficial macOS port of Greenshot
// Copyright (C) 2026 Greenshot for Mac (Community) contributors
// Based on Greenshot, Copyright (C) 2007-2026 Thomas Braun, Jens Klingen, Robin Krom
// SPDX-License-Identifier: GPL-3.0-or-later
// Owned by RUI after the wave 4 prep.

import AppKit
import GreenshotCore

private let log = Log("Recipes")

/// The Recipes submenu of the menu bar icon (RCP-062/063, APP-011; upstream `TrayMenu.CreateRecipesItem`) and the
/// editor's Recipes menu (RCP-064; upstream `ImageEditorForm.UpdateRecipesMenu`).
@MainActor
enum RecipeMenus {
    /// The menu bar icon's "Recipes" item with its submenu; nil when recipes are off.
    static func statusMenuItem(app: AppDelegate) -> NSMenuItem? {
        guard let runtime = RecipeRuntime.shared, runtime.isEnabled else { return nil }
        let library = runtime.library
        let entries = RecipeMenuEntries.statusMenu(recipes: library.recipes, active: library.activeTriggers(ofTypes: menuTriggerTypes))
        let item = NSMenuItem(title: "Recipes", action: nil, keyEquivalent: "")
        item.submenu = makeStatusMenu(entries: entries, canImport: !app.settings.isLocked(\AppSettings.recipes.files))
        return item
    }

    /// The submenu: the entries, then Import Recipe…, Reload Recipes, Recipe Manager…, Recipe Editor….
    static func makeStatusMenu(entries: [RecipeMenuEntry], canImport: Bool) -> NSMenu {
        let menu = NSMenu(title: "Recipes")
        menu.autoenablesItems = false
        add(entries, to: menu) { entry in run(entry) }
        if !entries.isEmpty { menu.addItem(.separator()) }
        // Upstream hides nothing here; an administrator's lock of the recipe files leaves Import out.
        if canImport { menu.addItem(ClosureMenuItem(title: "Import Recipe…") { importRecipe() }) }
        menu.addItem(ClosureMenuItem(title: "Reload Recipes") { reloadRecipes() })
        menu.addItem(.separator())
        menu.addItem(ClosureMenuItem(title: "Recipe Manager…") { RecipeManagerService.show(selecting: nil) })
        menu.addItem(ClosureMenuItem(title: "Recipe Editor…") { RecipeEditorService.openEditor(recipeId: nil) })
        return menu
    }

    // MARK: The editor's menu

    private static weak var editorMenuItem: NSMenuItem?
    private static let editorMenuDelegate = EditorRecipesMenuDelegate()

    /// The main menu's "Recipes" menu between Image and View (rebuilt when it opens).
    static func addEditorMenu(to main: NSMenu) {
        let item = main.addItem(withTitle: "Recipes", action: nil, keyEquivalent: "")
        let menu = NSMenu(title: "Recipes")
        menu.autoenablesItems = false
        menu.delegate = editorMenuDelegate
        item.submenu = menu
        editorMenuItem = item
        updateEditorMenu()
    }

    /// Shows the editor's Recipes menu while recipes are on (upstream hides it when it would be empty).
    static func updateEditorMenu() {
        editorMenuItem?.isHidden = !(RecipeRuntime.shared?.isEnabled ?? false)
    }

    /// The editor menu's items for the editor in front (nil: none is, the entries are greyed out).
    static func fillEditorMenu(_ menu: NSMenu, entries: [RecipeMenuEntry], editor: EditorWindowController?) {
        menu.removeAllItems()
        // Badges, not key equivalents: the main menu's would take the editor's own shortcuts.
        add(entries, to: menu, enabled: editor != nil, keyEquivalents: false) { [weak editor] entry in
            guard let editor else { return }
            runInEditor(entry, editor: editor)
        }
        if !entries.isEmpty { menu.addItem(.separator()) }
        menu.addItem(ClosureMenuItem(title: "Recipe Manager…") { RecipeManagerService.show(selecting: nil) })
        menu.addItem(ClosureMenuItem(title: "Recipe Editor…") { RecipeEditorService.openEditor(recipeId: nil) })
    }

    // MARK: Entries

    static let menuTriggerTypes: Set<String> = [WellKnownTriggerType.contextMenu, WellKnownTriggerType.systray, WellKnownTriggerType.hotkey]
    static let editorTriggerTypes: Set<String> = [WellKnownTriggerType.editor, WellKnownTriggerType.hotkey]

    private static func add(_ entries: [RecipeMenuEntry], to menu: NSMenu, enabled: Bool = true, keyEquivalents: Bool = true,
                            action: @escaping (RecipeMenuEntry) -> Void) {
        for layout in RecipeMenuEntries.layout(entries) {
            switch layout {
            case .entry(let entry):
                menu.addItem(item(for: entry, enabled: enabled, keyEquivalents: keyEquivalents, action: action))
            case .group(let name, let members):
                let submenu = NSMenu(title: name)
                submenu.autoenablesItems = false
                for entry in members { submenu.addItem(item(for: entry, enabled: enabled, keyEquivalents: keyEquivalents, action: action)) }
                let groupItem = NSMenuItem(title: name, action: nil, keyEquivalent: "")
                groupItem.submenu = submenu
                menu.addItem(groupItem)
            }
        }
    }

    /// An entry with the recipe's hotkey: as the key equivalent when a menu can show it, else as a badge (several steps,
    /// a left or right modifier).
    private static func item(for entry: RecipeMenuEntry, enabled: Bool, keyEquivalents: Bool,
                             action: @escaping (RecipeMenuEntry) -> Void) -> NSMenuItem {
        let item = ClosureMenuItem(title: entry.title) { action(entry) }
        item.isEnabled = enabled
        if let combo = entry.hotkey {
            if keyEquivalents, let key = combo.menuKeyEquivalent {
                item.keyEquivalent = key
                item.keyEquivalentModifierMask = combo.modifierFlags
            } else {
                item.badge = NSMenuItemBadge(string: combo.displayString)
            }
        }
        return item
    }

    // MARK: Actions

    /// A menu bar entry: its trigger fires, or a recipe without a menu trigger starts by its id.
    static func run(_ entry: RecipeMenuEntry) {
        guard let runtime = RecipeRuntime.shared else { return }
        guard let trigger = entry.trigger else {
            if runtime.start(recipeId: entry.recipeId, triggerType: WellKnownTriggerType.contextMenu) == nil {
                log.info("Recipe '\(entry.recipeId)' from the Recipes menu didn't start: it is switched off or gone.")
            }
            return
        }
        if case .notStarted = runtime.fire(trigger, info: RecipeRuntime.triggerInfo(for: trigger)) {
            log.info("The menu entry of recipe '\(entry.recipeId)' started nothing.")
        }
    }

    /// An editor entry: the recipe works on this editor (host object EditorForm).
    private static func runInEditor(_ entry: RecipeMenuEntry, editor: EditorWindowController) {
        guard let runtime = RecipeRuntime.shared, let trigger = entry.trigger else { return }
        let info = RecipeRuntime.triggerInfo(for: trigger)
        if case .notStarted = runtime.fire(trigger, info: info, objects: ["EditorForm": runtime.editorForm(for: editor)]) {
            log.info("The editor entry of recipe '\(entry.recipeId)' started nothing.")
        }
    }

    /// Upstream `TrayActions.ImportRecipe`: pick a recipe file, approve it, add it to the recipe files.
    static func importRecipe() {
        let panel = NSOpenPanel()
        panel.title = "Import Capture Recipe"
        panel.prompt = "Import"
        panel.message = "Choose a recipe file (.gsrecipe.json). Greenshot shows what it does before it is used."
        panel.allowedContentTypes = [.json]
        panel.allowsMultipleSelection = false
        panel.canChooseDirectories = false
        NSApp.activate()
        guard panel.runModal() == .OK, let url = panel.url else { return }
        Task { @MainActor in
            guard let runtime = RecipeRuntime.shared else { return }
            let result = await runtime.library.importFile(url)
            guard result.isValid, !result.loadedRecipeIds.isEmpty else {
                // The approval window showed the problem, or the user said no.
                if !result.errors.isEmpty { log.info("Import of '\(url.lastPathComponent)': \(result.errors.joined(separator: " "))") }
                return
            }
            let names = result.loadedRecipeIds.map { id in runtime.library.recipe(id: id)?.recipe.name ?? id }
            notify("Recipe imported", detail: names.joined(separator: ", "), kind: .info)
        }
    }

    /// The menu's "Reload Recipes": the files again; says so only when one couldn't be loaded.
    static func reloadRecipes() {
        Task { @MainActor in
            guard let runtime = RecipeRuntime.shared else { return }
            let result = await runtime.reload()
            log.info("Reloaded recipes: \(result.loadedRecipeIds.count) from files, \(result.errors.count) problem(s)")
            guard !result.errors.isEmpty else { return }
            let detail = result.errors.prefix(3).joined(separator: "\n") + (result.errors.count > 3 ? "\n…" : "")
            notify(result.errors.count == 1 ? "A recipe could not be loaded" : "\(result.errors.count) recipes could not be loaded",
                   detail: detail, kind: .warning)
        }
    }

    private static func notify(_ message: String, detail: String, kind: MessageKind) {
        guard let app = NSApp.delegate as? AppDelegate else { return }
        app.saver.notify(message, detail: detail, kind: kind) { [weak app] in app?.showLogViewer(search: "Recipes") }
    }
}

/// Rebuilds the editor's Recipes menu when it opens: the Editor triggers, for the editor window in front.
@MainActor
private final class EditorRecipesMenuDelegate: NSObject, NSMenuDelegate {
    func menuNeedsUpdate(_ menu: NSMenu) {
        guard let runtime = RecipeRuntime.shared, runtime.isEnabled else {
            menu.removeAllItems()
            return
        }
        let library = runtime.library
        let entries = RecipeMenuEntries.editorMenu(recipes: library.recipes, active: library.activeTriggers(ofTypes: RecipeMenus.editorTriggerTypes))
        let window = NSApp.keyWindow ?? NSApp.mainWindow
        RecipeMenus.fillEditorMenu(menu, entries: entries, editor: window?.windowController as? EditorWindowController)
    }

    /// The entries show their hotkeys as badges, so the menu has no key equivalents: without this answer AppKit would
    /// rebuild it for every key pressed in an editor.
    func menuHasKeyEquivalent(_ menu: NSMenu, for event: NSEvent, target: AutoreleasingUnsafeMutablePointer<AnyObject?>,
                              action: UnsafeMutablePointer<Selector?>) -> Bool {
        false
    }
}
