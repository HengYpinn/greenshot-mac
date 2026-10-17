// Greenshot for Mac (Community) - an unofficial macOS port of Greenshot
// Copyright (C) 2026 Greenshot for Mac (Community) contributors
// Based on Greenshot, Copyright (C) 2007-2026 Thomas Braun, Jens Klingen, Robin Krom
// SPDX-License-Identifier: GPL-3.0-or-later
// Owned by RUI after the wave 4 prep.

import AppKit
import GreenshotCore

private let log = Log("Recipes")

/// The recipes' place in the app: trigger sources, the approval sheet as the library's approver, the recipe switch, the
/// failure notification (RCP-060, RCP-018). Upstream `TriggerManager` is Core's `RecipeTriggerHub`; the Hotkey and
/// Clipboard triggers are its sources here, the menus and Open With ask the library for their triggers when used.
@MainActor
enum RecipeAppUI {
    /// The app's settings, for the parts that run without an `AppDelegate` at hand (hotkey clash names).
    private(set) static weak var settings: SettingsStore?
    private static var sources: [any RecipeTriggerSource] = []
    private static var observations: [RecipeObservation] = []

    /// At launch, right after `app.recipes.start()` and before the menu bar icon, the hotkeys and the automation start.
    static func start(app: AppDelegate) {
        let recipes = app.recipes
        settings = app.settings
        recipes.approver.target = RecipeApprovalPresenter.shared

        let hotkeys = RecipeHotkeyTriggerSource { [weak app] in app?.reregisterHotkeys() }
        let clipboard = RecipeClipboardTriggerSource { trigger, variables in
            let info = RecipeRuntime.triggerInfo(for: trigger)
            guard let runtime = RecipeRuntime.shared else { return }
            if case .notStarted = runtime.fire(trigger, info: info, variables: variables) {
                log.info("The clipboard trigger of recipe '\(trigger.recipeId)' started nothing.")
            }
        }
        sources = [hotkeys, clipboard]
        sources.forEach(recipes.hub.register)

        observations.append(recipes.addChangeObserver { RecipeMenus.updateEditorMenu() })
        RecipeMenus.updateEditorMenu()

        // RCP-018: a failed flow says so, with the exports no notification announced.
        // The app delegate lives as long as the process.
        observations.append(recipes.addObserver { [app] event in
            switch event {
            case .flowFinished(let result):
                guard let notice = RecipeFlowNotice.failure(of: result) else { return }
                let recipeId = result.recipeId
                DispatchQueue.main.async {
                    MainActor.assumeIsolated { showFailure(notice, recipeId: recipeId, app: app) }
                }
            case .flowRejected(let recipeId, let reason):
                log.info("Recipe '\(recipeId)' didn't start: \(reason)")
            default:
                break
            }
        })

        // RCP-002: switching recipes on loads the files, switching them off drops them and every trigger.
        app.settings.onChange(of: \AppSettings.recipes.enabled) { [weak recipes] enabled in
            log.info(enabled ? "Recipes switched on" : "Recipes switched off")
            Task { @MainActor in _ = await recipes?.reload() }
        }
    }

    private static func showFailure(_ notice: RecipeFlowNotice, recipeId: String, app: AppDelegate) {
        app.saver.notify(notice.title, detail: notice.detail, kind: .error) { [weak app] in
            app?.showLogViewer(search: recipeId)
        }
    }
}
