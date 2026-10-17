// Greenshot for Mac (Community) - an unofficial macOS port of Greenshot
// Copyright (C) 2026 Greenshot for Mac (Community) contributors
// Based on Greenshot, Copyright (C) 2007-2026 Thomas Braun, Jens Klingen, Robin Krom
// SPDX-License-Identifier: GPL-3.0-or-later

import CoreGraphics
import Foundation

/// What a trigger adds before the recipe runs (upstream `TriggerRecipePreparer`): a Source for its trigger when the
/// recipe has none, an editor destination when it has no destination (not for AI tools). Only `RecipeRunner` calls it
/// (once per flow, after the preflight); callers hand it the recipe as loaded.
public enum RecipeTriggerPreparer {
    public static func prepare(_ recipe: CaptureRecipe, triggerType: String) -> CaptureRecipe {
        ensureDestination(ensureSource(recipe, triggerType: triggerType), triggerType: triggerType)
    }

    /// Upstream `EnsureRequiredStartSource`: a recipe without a Source gets the trigger's source before its start nodes.
    static func ensureSource(_ recipe: CaptureRecipe, triggerType: String) -> CaptureRecipe {
        guard !recipe.hasSourceStep else { return recipe }
        var starts = recipe.flow.startNodes.filter { !$0.trimmingCharacters(in: .whitespaces).isEmpty }
        if starts.isEmpty, let first = recipe.nodes.first { starts = [first.id] }
        var prepared = recipe
        let id = uniqueId("trigger_source", in: prepared)
        let sourceType = TriggerContractCatalog.builtIn.contract(for: triggerType)?.defaultSourceType ?? "FullScreen"
        prepared.nodes.insert(RecipeNode(id: id, stepType: WellKnownStepType.source, name: "Acquire \(sourceType)",
                                         parameters: ["SourceType": .string(sourceType)]), at: 0)
        prepared.flow.startNodes = [id]
        for start in starts { prepared.flow.addTransition(from: id, to: start) }
        return prepared
    }

    /// Upstream `EnsureRequiredDestination`: a recipe without a destination exports at every end node; the result of an
    /// AI tool goes back to the AI tool instead.
    static func ensureDestination(_ recipe: CaptureRecipe, triggerType: String) -> CaptureRecipe {
        guard !recipe.hasDestinationStep, recipe.firstNode(ofType: WellKnownStepType.recordVideo) == nil,
              !recipeEquals(triggerType, WellKnownTriggerType.aiTool) else { return recipe }
        let transitions = recipe.flow.unifiedTransitions
        let ends = recipe.nodes.filter { !$0.id.isEmpty && (transitions[$0.id.lowercased()] ?? []).isEmpty }.map(\.id)
        guard !ends.isEmpty else { return recipe }
        var prepared = recipe
        for end in ends {
            let id = uniqueId("editor_destination", in: prepared)
            if recipeEquals(triggerType, WellKnownTriggerType.editor) {
                prepared.nodes.append(RecipeNode(id: id, stepType: WellKnownStepType.editor, name: "Open in Editor",
                                                 parameters: ["TargetEditor": .string("CurrentEditor")]))
            } else {
                prepared.nodes.append(RecipeNode(id: id, stepType: WellKnownStepType.destinations, name: "Export Destinations"))
            }
            prepared.flow.addTransition(from: end, to: id)
        }
        return prepared
    }

    private static func uniqueId(_ prefix: String, in recipe: CaptureRecipe) -> String {
        var id = "\(prefix)_\(UUID().uuidString.replacingOccurrences(of: "-", with: "").prefix(6).lowercased())"
        var suffix = 1
        while recipe.node(id) != nil {
            id += "_\(suffix)"
            suffix += 1
        }
        return id
    }
}
