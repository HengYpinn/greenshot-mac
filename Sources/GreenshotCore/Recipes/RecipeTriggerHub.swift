// Greenshot for Mac (Community) - an unofficial macOS port of Greenshot
// Copyright (C) 2026 Greenshot for Mac (Community) contributors
// Based on Greenshot, Copyright (C) 2007-2026 Thomas Braun, Jens Klingen, Robin Krom
// SPDX-License-Identifier: GPL-3.0-or-later

import CoreGraphics
import Foundation

/// A kind of trigger the app provides (RAPP: hotkeys, the Recipes menu, the clipboard monitor, Open With, the editor
/// menu). The hub hands it the active triggers of its types whenever they change; it calls `RecipeTriggerHub.fire`.
@MainActor
public protocol RecipeTriggerSource: AnyObject {
    var triggerTypes: Set<String> { get }
    func sync(_ triggers: [ActiveRecipeTrigger])
    func stop()
}

/// Connects the trigger sources with the library and the runner (upstream `TriggerManager`).
@MainActor
public final class RecipeTriggerHub {
    private let library: RecipeLibrary
    private let runner: RecipeRunner
    private var sources: [any RecipeTriggerSource] = []

    public init(library: RecipeLibrary, runner: RecipeRunner) {
        self.library = library
        self.runner = runner
    }

    public func register(_ source: any RecipeTriggerSource) {
        guard !sources.contains(where: { $0 === source }) else { return }
        sources.append(source)
        source.sync(library.activeTriggers(ofTypes: source.triggerTypes))
    }

    /// Recomputes the active triggers and syncs every source (after reload, approval, settings change).
    public func sync() {
        for source in sources {
            source.sync(library.activeTriggers(ofTypes: source.triggerTypes))
        }
    }

    /// A trigger fired: starts its recipe with the trigger info (the runner prepares the recipe for the trigger). Nil
    /// when the trigger isn't active anymore.
    @discardableResult
    public func fire(_ trigger: ActiveRecipeTrigger, info: RecipeTriggerInfo, variables: [String: JSONValue] = [:],
                     objects: [String: any Sendable] = [:], payload: RecipePayload? = nil) -> RecipeFlowHandle? {
        guard let loaded = library.recipe(id: trigger.recipeId), loaded.isTriggerActive(at: trigger.index), library.isFeatureEnabled else {
            log.info("Trigger \(trigger.key) of recipe '\(trigger.recipeId)' isn't active any more, ignoring it.")
            return nil
        }
        var request = RecipeRunRequest(recipe: loaded.recipe, trigger: info)
        request.variables = variables
        request.objects = objects
        request.payload = payload
        request.optionValues = library.optionValues
        return runner.start(request)
    }

    public func stopAll() {
        for source in sources { source.stop() }
        sources = []
    }
}

private let log = Log("Recipes")
