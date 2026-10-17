// Greenshot for Mac (Community) - an unofficial macOS port of Greenshot
// Copyright (C) 2026 Greenshot for Mac (Community) contributors
// Based on Greenshot, Copyright (C) 2007-2026 Thomas Braun, Jens Klingen, Robin Krom
// SPDX-License-Identifier: GPL-3.0-or-later
// Owned by RMANAGER after the wave 4 prep.

import Foundation

/// Slot nodes: the named places where automatic steps put their steps (upstream `RecipeStepConfig.CreateSlot` and
/// `AddStandardSlots`, Greenshot.Base/Recipes/RecipeStepConfig.cs). Used by the built-in capture recipes (RSTEPS) and the
/// recipe editor's new recipe (REDITOR).
public enum RecipeSlotNodes {
    /// A Slot node named `name` (AfterCapture, BeforeExport, AfterExport or BeforeDestination).
    public static func slot(id: String, name: String) -> RecipeNode {
        RecipeNode(id: id, stepType: WellKnownStepType.slot, name: name, parameters: ["Name": .string(name)])
    }

    /// Adds the standard slots to a linear capture flow: AfterCapture before `afterCaptureBefore`, BeforeExport and
    /// BeforeDestination before `exportNode` and AfterExport after it. The BeforeDestination slot does nothing where it
    /// is: its automatic steps run in the export steps, per destination.
    public static func addStandardSlots(to recipe: inout CaptureRecipe, afterCaptureBefore: String, exportNode: String) {
        insert(slot(id: "after_capture", name: RecipeSlots.afterCapture), before: afterCaptureBefore, in: &recipe)
        insert(slot(id: "before_export", name: RecipeSlots.beforeExport), before: exportNode, in: &recipe)
        insert(slot(id: "before_destination", name: RecipeSlots.beforeDestination), before: exportNode, in: &recipe)
        insert(slot(id: "after_export", name: RecipeSlots.afterExport), after: exportNode, in: &recipe)
    }

    /// Upstream `InsertBefore`: what led to the target (transitions and start nodes) leads to the node, which leads to the target.
    private static func insert(_ node: RecipeNode, before targetId: String, in recipe: inout CaptureRecipe) {
        for t in recipe.flow.transitions.indices {
            for i in recipe.flow.transitions[t].to.indices where recipeEquals(recipe.flow.transitions[t].to[i], targetId) {
                recipe.flow.transitions[t].to[i] = node.id
            }
        }
        for i in recipe.flow.startNodes.indices where recipeEquals(recipe.flow.startNodes[i], targetId) {
            recipe.flow.startNodes[i] = node.id
        }
        let index = recipe.nodes.firstIndex { recipeEquals($0.id, targetId) } ?? 0
        recipe.nodes.insert(node, at: index)
        recipe.flow.addTransition(from: node.id, to: targetId)
    }

    /// Upstream `InsertAfter`: the source leads to the node only, the node to where the source led.
    private static func insert(_ node: RecipeNode, after sourceId: String, in recipe: inout CaptureRecipe) {
        var next: [String] = []
        if let index = recipe.flow.transitions.firstIndex(where: { recipeEquals($0.from, sourceId) }) {
            next = recipe.flow.transitions[index].to
            recipe.flow.transitions[index].to = [node.id]
        } else {
            recipe.flow.transitions.append(RecipeTransition(from: sourceId, to: [node.id]))
        }
        for target in next { recipe.flow.addTransition(from: node.id, to: target) }
        if let index = recipe.nodes.firstIndex(where: { recipeEquals($0.id, sourceId) }) {
            recipe.nodes.insert(node, at: index + 1)
        } else {
            recipe.nodes.append(node)
        }
    }
}
