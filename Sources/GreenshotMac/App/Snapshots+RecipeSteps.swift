// Greenshot for Mac (Community) - an unofficial macOS port of Greenshot
// Copyright (C) 2026 Greenshot for Mac (Community) contributors
// Based on Greenshot, Copyright (C) 2007-2026 Thomas Braun, Jens Klingen, Robin Krom
// SPDX-License-Identifier: GPL-3.0-or-later
// Owned by RSTEPS after the wave 4 prep.

import AppKit
import GreenshotCore
import SwiftUI

extension Snapshots {
    /// Renders of the recipe steps' panels (UserPrompt, the destination flyout) and the built-in recipes.
    static func renderRecipeStepExtras(to folder: URL, sample: CGImage, settings: SettingsStore) throws {
        try write(promptSnapshot(preview: sample, timeout: 0), to: folder.appendingPathComponent("recipe-user-prompt.png"))
        try write(promptSnapshot(preview: nil, timeout: 8), to: folder.appendingPathComponent("recipe-user-prompt-countdown.png"))
        try write(flyoutSnapshot(preview: sample, settings: settings, error: nil),
                  to: folder.appendingPathComponent("recipe-dynamic-destination.png"))
        try write(flyoutSnapshot(preview: sample, settings: settings, error: "Export to Jira failed: The server answered 401 (not signed in)."),
                  to: folder.appendingPathComponent("recipe-dynamic-destination-error.png"))
        try writeText(builtInRecipesText(), to: folder.appendingPathComponent("recipe-builtins.txt"))
    }

    private static func invocation(_ type: String, _ parameters: JSONObject) -> RecipeStepInvocation {
        RecipeStepInvocation(node: RecipeNode(id: "snapshot", stepType: type, parameters: parameters), parameters: parameters,
                             contract: StepContractCatalog.builtIn.contract(for: type))
    }

    private static func promptSnapshot(preview: CGImage?, timeout: Int) -> NSBitmapImageRep? {
        func choice(_ key: String, _ label: String, _ style: String, isDefault: Bool = false, isCancel: Bool = false) -> JSONValue {
            .object(["Key": .string(key), "Label": .string(label), "Style": .string(style), "IsDefault": .bool(isDefault),
                     "IsCancel": .bool(isCancel)])
        }
        let parameters: JSONObject = [
            "Title": .string("Upload this capture?"),
            "Message": .string("The capture shows a customer's name. Upload it to the team's Jira issue, keep it only on this Mac, or delete it."),
            "Choices": .array([choice("upload", "Upload", "Primary", isDefault: true), choice("keep", "Keep Local", "Secondary"),
                               choice("delete", "Delete", "Danger", isCancel: true)]),
            "TimeoutSeconds": .number(Double(timeout))
        ]
        let model = RecipePromptModel(prompt: RecipePrompt(invocation(WellKnownStepType.userPrompt, parameters)), preview: preview)
        return hosted(RecipePromptView(model: model), title: "Greenshot - Upload this capture?", titled: true)
    }

    private static func flyoutSnapshot(preview: CGImage, settings: SettingsStore, error: String?) -> NSBitmapImageRep? {
        var parameters: JSONObject = ["Title": .string("Export Capture"), "ShowPreview": .bool(true)]
        if error != nil { parameters["TimeoutSeconds"] = .number(20) }
        var values = settings.value
        values.externalCommands = [ExternalCommand(name: "Optimize PNG", command: "/usr/local/bin/optipng")]
        let available = RecipeFlyoutPresenter.destinations(settings: values)
        let recipes = BuiltInRecipes.all.filter { !$0.isAIToolRecipe }.map { RecipeFlyout.RecipeForwardChoice(id: $0.id, name: $0.name) }
        let flyout = RecipeFlyout(invocation(WellKnownStepType.dynamicDestination, parameters), lastError: error, available: available,
                                  recipes: recipes, runningRecipeId: BuiltInRecipes.browserExtensionId)
        let model = RecipeFlyoutModel(flyout: flyout, preview: preview)
        return hosted(RecipeFlyoutView(model: model), title: "Greenshot - Export Capture", titled: false)
    }

    private static func hosted<Content: View>(_ view: Content, title: String, titled: Bool) -> NSBitmapImageRep? {
        let hosting = NSHostingView(rootView: view)
        hosting.layoutSubtreeIfNeeded()
        hosting.frame = NSRect(origin: .zero, size: hosting.fittingSize)
        let window = NSWindow(contentRect: hosting.frame, styleMask: titled ? [.titled, .closable] : [.borderless], backing: .buffered,
                              defer: false)
        window.title = title
        window.contentView = hosting
        hosting.layoutSubtreeIfNeeded()
        return capture(hosting)
    }

    /// Each built-in recipe as the approval window describes it, and what the validator says.
    private static func builtInRecipesText() -> String {
        let describer = RecipeDescriber()
        let validator = RecipeValidator(gates: GateEnvironment(defaultDestinations: ["Editor"]))
        var lines: [String] = []
        for recipe in BuiltInRecipes.all {
            lines.append("\(recipe.id) — \(recipe.name)")
            for line in describer.describeSteps(recipe) { lines.append("  \(line.isDetail ? "  " : "")\(line.text)") }
            for trigger in describer.describeTriggers(recipe) { lines.append("  trigger: \(trigger.label)") }
            let result = validator.validate(recipe)
            lines.append("  valid: \(result.errors.isEmpty ? "yes" : result.errors.joined(separator: "; "))")
            lines.append("")
        }
        return lines.joined(separator: "\n")
    }
}
