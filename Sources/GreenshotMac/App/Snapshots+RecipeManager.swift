// Greenshot for Mac (Community) - an unofficial macOS port of Greenshot
// Copyright (C) 2026 Greenshot for Mac (Community) contributors
// Based on Greenshot, Copyright (C) 2007-2026 Thomas Braun, Jens Klingen, Robin Krom
// SPDX-License-Identifier: GPL-3.0-or-later
// Owned by RMANAGER after the wave 4 prep.

import AppKit
import GreenshotCore
import SwiftUI

extension Snapshots {
    /// Renders of the recipe manager, the option sections and Quick Settings › Automatic steps, on a library of their own
    /// (the app's recipes never start in `--snapshot`), and the sample capture after the built-in automatic steps ran.
    static func renderRecipeManagerExtras(to folder: URL, sample: CGImage, settings: SettingsStore) throws {
        let demo = RecipeManagerDemo.make()
        let manager = RecipeManagerModel(library: demo.library, runtime: nil)
        manager.selection = "recipe_window"
        manager.status = String(localized: "Loaded and registered \("team-window.gsrecipe.json")")
        try write(window(RecipeManagerView(model: manager), size: NSSize(width: 900, height: 1180)),
                  to: folder.appendingPathComponent("recipe-manager.png"))
        let filtered = RecipeManagerModel(library: demo.library, runtime: nil)
        filtered.filter = .custom
        filtered.query = "capture"
        try write(window(RecipeManagerView(model: filtered), size: NSSize(width: 900, height: 680)),
                  to: folder.appendingPathComponent("recipe-manager-filtered.png"))
        keepAlive += [manager, filtered]

        let options = Form { RecipeOptionsSections(store: demo.store, library: demo.library) }.formStyle(.grouped)
        try write(window(options, size: NSSize(width: 760, height: 1640)), to: folder.appendingPathComponent("settings-recipes-options.png"))

        let destinations = RecipeExtensionScope.destinationChoices(settings: demo.store.value)
        if let scope = demo.library.extensionScope(id: RecipeBuiltInExtensions.borderId, destinations: destinations) {
            let sheet = RecipeExtensionScopeSheet(name: "Border", model: RecipeScopeModel(scope: scope), done: { _ in }, cancel: {})
            try write(window(sheet, size: NSSize(width: 640, height: 560)), to: folder.appendingPathComponent("recipe-extension-scope.png"))
        }

        let quick = NSMenu(title: "Quick Settings")
        quick.addItem(NSMenuItem(title: "Capture Mouse Pointer", action: nil, keyEquivalent: ""))
        RecipeQuickSettingsMenu.append(to: quick, library: demo.library) {}
        try writeText(checkedMenuText(quick), to: folder.appendingPathComponent("quick-settings-automatic-steps.txt"))

        try write(automaticStepsApplied(library: demo.library, settings: demo.store.value),
                  to: folder.appendingPathComponent("automatic-steps-applied.png"))
        keepAlive.append(demo.store)
    }

    /// Like `menuText`, with "✓ " in front of checked items.
    private static func checkedMenuText(_ menu: NSMenu, indent: String = "") -> String {
        var lines = ""
        for item in menu.items {
            if item.isSeparatorItem {
                lines += indent + "---\n"
                continue
            }
            lines += indent + (item.state == .on ? "✓ " : "") + item.title + (item.isEnabled ? "" : " (disabled)") + "\n"
            if let submenu = item.submenu { lines += checkedMenuText(submenu, indent: indent + "    ") }
        }
        return lines
    }

    /// A made-up capture after the switched-on built-in automatic steps (caption above, a red border, a drop shadow) ran
    /// through the recipe engine as the export steps run them: one chain after the other on the copy for a destination.
    private static func automaticStepsApplied(library: RecipeLibrary, settings: AppSettings) -> NSBitmapImageRep? {
        guard let region = library.recipe(id: "recipe_region")?.recipe else { return nil }
        let chains = library.effectiveRecipe(region).composition?.chains(forDestination: "FileNoDialog") ?? []
        let steps = RecipeStepRegistry()
        steps.registerCoreExecutors()
        let box = SnapshotResultBox()
        Task { @MainActor in
            var payload = RecipePayload(image: sampleImage(width: 420, height: 260), scale: 2, title: "Quarterly report")
            for chain in chains {
                let context = RecipeFlowContext(recipe: chain.flow, environment: SystemRecipeEnvironment(settings: settings),
                                                optionValues: library.optionValues)
                context.payload = payload
                context.isPayloadPreSupplied = true
                await RecipeFlowEngine(steps: steps).execute(context)
                if let changed = context.payload, !context.isAborted { payload = changed }
            }
            box.payload = payload
        }
        let deadline = Date().addingTimeInterval(10)
        while box.payload == nil, Date() < deadline {
            RunLoop.current.run(until: Date().addingTimeInterval(0.01))
        }
        guard let payload = box.payload, let image = payload.flattened() else { return nil }
        let rep = NSBitmapImageRep(cgImage: image)
        rep.size = NSSize(width: CGFloat(image.width) / payload.scale, height: CGFloat(image.height) / payload.scale)
        return rep
    }
}

@MainActor
private final class SnapshotResultBox {
    var payload: RecipePayload?
}

/// Approves everything, for the snapshots' made-up recipe files.
@MainActor
private final class SnapshotApprover: RecipeApprover {
    func requestApproval(_ request: RecipeApprovalRequest) async -> RecipeApprovalDecision? {
        RecipeApprovalDecision(approval: RecipeApproval(recipeId: request.recipe?.id ?? "", approvedTriggers: request.triggers.map(\.key),
                                                        allowedGates: request.gates))
    }

    func showValidationError(_ request: RecipeApprovalRequest) async {}
}

/// A library with three built-in capture recipes, a file that replaces one of them, a switched-off recipe, one written by
/// an AI tool (with options), an automatic step from a file, and Caption and Border switched on.
@MainActor
enum RecipeManagerDemo {
    static func make() -> (library: RecipeLibrary, store: SettingsStore) {
        let suite = "greenshot-mac-snapshots-recipe-manager"
        let defaults = UserDefaults(suiteName: suite)!
        defaults.removePersistentDomain(forName: suite)
        let store = SettingsStore(defaults: defaults)
        let folder = URL(fileURLWithPath: NSTemporaryDirectory()).appendingPathComponent("greenshot-snapshots-recipes", isDirectory: true)
        try? FileManager.default.removeItem(at: folder)
        try? FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        let library = RecipeLibrary(loadSettings: { store.value.recipes }, saveSettings: { recipes in store.update { $0.recipes = recipes } },
                                    trustStore: RecipeTrustStore(fileURL: folder.appendingPathComponent("trust.json"), secrets: InMemorySecretStore()),
                                    approver: SnapshotApprover(),
                                    builtInRecipes: [capture("recipe_region", "Capture region", "Region"),
                                                     capture("recipe_window", "Capture window", "Window"),
                                                     capture("recipe_fullscreen", "Capture full screen", "FullScreen")],
                                    watchFiles: false)

        var team = capture("recipe_window", "Capture window (team)", "Window")
        team.description = "The team's window capture: saved to the shared folder and copied."
        team.triggers = [TriggerConfig(triggerType: "Hotkey", parameters: ["Hotkey": .string("Ctrl + Shift + W")])]
        var jira = capture("region_to_clipboard", "Region to clipboard", "Region")
        jira.description = "Captures a region and copies it, from the menu or the clipboard."
        jira.triggers = [TriggerConfig(triggerType: "ContextMenu", parameters: ["MenuItemText": .string("Region to clipboard")]),
                         TriggerConfig(triggerType: "Clipboard")]
        var proposed = capture("ai_frame", "Framed capture", "Region")
        proposed.description = "A region with an optional frame, written by an AI tool."
        var frame = RecipeOption(key: "frame", type: .boolean, defaultValue: .bool(false))
        frame.label = "Add a frame"
        frame.quickSettings = true
        var size = RecipeOption(key: "size", type: .integer, defaultValue: .number(3))
        size.label = "Frame size (px)"
        size.min = 1
        size.max = 20
        size.enabledWhen = "frame"
        var style = RecipeOption(key: "style", type: .enumeration, defaultValue: .string("plain"))
        style.label = "Frame style"
        style.choices = [RecipeOptionChoice(value: "plain", label: "Plain"), RecipeOptionChoice(value: "shadow", label: "With shadow")]
        style.quickSettings = true
        proposed.options = [frame, size, style]
        var watermark = CaptureRecipe(id: "ext_watermark", name: "Watermark")
        watermark.kind = .extension
        watermark.description = "Writes “Confidential” into the bottom right corner."
        watermark.extends = ExtensionTarget(recipes: ["*capture"], slot: "BeforeExport", order: 400)
        watermark.options = [RecipeOption(key: "enabled", type: .boolean, defaultValue: .bool(true))]
        watermark.nodes = [RecipeNode(id: "text", stepType: "Annotation",
                                      parameters: ["Type": .string("Text"), "Text": .string("Confidential"), "Right": .number(8),
                                                   "Bottom": .number(8), "HorizontalAnchor": .string("Right"), "VerticalAnchor": .string("Bottom")])]
        watermark.flow.startNodes = ["text"]

        let done = SnapshotDoneBox()
        Task { @MainActor in
            for (recipe, name) in [(team, "team-window"), (jira, "region-to-clipboard"), (watermark, "watermark")] {
                let url = folder.appendingPathComponent("\(name).gsrecipe.json")
                try? Data(RecipeSerializer.encode(recipe).utf8).write(to: url)
                _ = await library.loadFile(url)
            }
            _ = await library.propose(content: RecipeSerializer.encode(proposed), proposedBy: "Claude", aiRequest: nil, aiExplanation: nil,
                                      saveTo: folder.appendingPathComponent("AI/framed.gsrecipe.json"))
            done.finished = true
        }
        let deadline = Date().addingTimeInterval(10)
        while !done.finished, Date() < deadline {
            RunLoop.current.run(until: Date().addingTimeInterval(0.01))
        }
        library.setEnabled(false, recipeId: "region_to_clipboard")
        library.setExtensionEnabled(true, id: RecipeBuiltInExtensions.captionId)
        library.setOption(.string("Top"), key: "position", ownerId: RecipeBuiltInExtensions.captionId)
        library.setExtensionEnabled(true, id: RecipeBuiltInExtensions.borderId)
        library.setOption(.number(4), key: "width", ownerId: RecipeBuiltInExtensions.borderId)
        library.setOption(.string("#E53935"), key: "color", ownerId: RecipeBuiltInExtensions.borderId)
        library.setExtensionEnabled(true, id: RecipeBuiltInExtensions.dropShadowId)
        library.setExtensionScope(id: RecipeBuiltInExtensions.borderId, exceptRecipes: ["recipe_fullscreen"], onlyDestinations: ["EMail", "FileNoDialog"])
        return (library, store)
    }

    /// Source -> Destinations with the standard slots, like the built-in capture recipes.
    static func capture(_ id: String, _ name: String, _ sourceType: String) -> CaptureRecipe {
        var recipe = CaptureRecipe(id: id, name: name)
        recipe.nodes = [RecipeNode(id: "source", stepType: "Source", parameters: ["SourceType": .string(sourceType)]),
                        RecipeNode(id: "export", stepType: "Destinations")]
        recipe.flow.startNodes = ["source"]
        recipe.flow.addTransition(from: "source", to: "export")
        RecipeSlotNodes.addStandardSlots(to: &recipe, afterCaptureBefore: "export", exportNode: "export")
        return recipe
    }
}

@MainActor
private final class SnapshotDoneBox {
    var finished = false
}
