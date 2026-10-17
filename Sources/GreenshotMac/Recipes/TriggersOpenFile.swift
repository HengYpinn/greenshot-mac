// Greenshot for Mac (Community) - an unofficial macOS port of Greenshot
// Copyright (C) 2026 Greenshot for Mac (Community) contributors
// Based on Greenshot, Copyright (C) 2007-2026 Thomas Braun, Jens Klingen, Robin Krom
// SPDX-License-Identifier: GPL-3.0-or-later
// Owned by RUI after the wave 4 prep.

import AppKit
import GreenshotCore

private let log = Log("Recipes")

/// The OpenFile triggers (RCP-069, upstream `IpcSecurityDispatcher.HandleOpenFileAsync`).
@MainActor
enum RecipeOpenFileTrigger {
    /// The files OPEN_FILE accepted (Finder's Open With, greenshot-cli, AppleScript, Services): runs the recipes of the
    /// active OpenFile triggers and returns the reply; nil when no recipe has an OpenFile trigger (the caller opens the
    /// files in the editor). A stock `recipe_file` (`RecipeRuntime.fire` answers `.direct`) opens the file in the editor.
    static func open(_ files: [URL], app: AppDelegate) async -> IPCReply? {
        let recipes = app.recipes
        // Files from a launch by Open With come before the recipe files are read.
        await recipes.whenLoaded()
        guard recipes.isEnabled else { return nil }
        let library = recipes.library
        let plan = RecipeOpenFileRouting.plan(files: files, active: library.activeTriggers(ofTypes: [WellKnownTriggerType.openFile]),
                                              anyDefined: RecipeOpenFileRouting.definesOpenFileTrigger(library.recipes))
        switch plan.kind {
        case .editor:
            return nil
        case .skipped:
            log.info("All OpenFile trigger recipes are switched off: \(files.count) file(s) not opened.")
            return .ok(RecipeOpenFileRouting.skippedReply)
        case .run:
            var executed = 0
            for run in plan.runs {
                if await start(run, recipes: recipes, app: app) { executed += 1 }
            }
            let unmatched = files.filter { file in !plan.runs.contains { $0.file == file } }
            if !unmatched.isEmpty {
                log.info("No OpenFile trigger's filter matches \(unmatched.map(\.lastPathComponent).joined(separator: ", ")).")
            }
            return .ok(RecipeOpenFileRouting.summary(files: files.count, runs: executed))
        }
    }

    /// Starts one recipe for one file (variable Filename) and waits for it unless the trigger is `FireAndForget`.
    private static func start(_ run: RecipeOpenFilePlan.Run, recipes: RecipeRuntime, app: AppDelegate) async -> Bool {
        let trigger = run.trigger
        let info = RecipeRuntime.triggerInfo(for: trigger)
        switch recipes.fire(trigger, info: info, variables: ["Filename": .string(run.file.path)]) {
        case .started(let handle):
            log.info("Opening \(run.file.lastPathComponent) with recipe '\(trigger.recipeId)'")
            if !trigger.trigger.fireAndForget { _ = await handle.result }
            return true
        case .direct:
            app.editors.open(fileURL: run.file)
            return true
        case .notStarted:
            // Until the step executors run the stock built-in recipes, a built-in's trigger opens the file as before.
            if recipes.library.recipe(id: trigger.recipeId)?.isBuiltIn == true {
                app.editors.open(fileURL: run.file)
                return true
            }
            log.info("Recipe '\(trigger.recipeId)' didn't start for \(run.file.lastPathComponent).")
            return false
        }
    }
}
