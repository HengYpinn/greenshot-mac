// Greenshot for Mac (Community) - an unofficial macOS port of Greenshot
// Copyright (C) 2026 Greenshot for Mac (Community) contributors
// SPDX-License-Identifier: GPL-3.0-or-later
// Owned by RUI after the wave 4 prep.

import AppKit
import GreenshotCore
import SwiftUI

extension Snapshots {
    /// Renders of the approval window in each of its modes and with its viewers, Settings › Recipes (with recipes and
    /// with recipes off), the settings window on the Recipes tab at its 760 pt, and the two Recipes menus as text. The
    /// requests are built like `RecipeLibrary` builds them, from sample recipes; nothing is read from or written to disk.
    static func renderRecipeUIExtras(to folder: URL, sample: CGImage, settings: SettingsStore) throws {
        func out(_ name: String) -> URL { folder.appendingPathComponent(name) }
        let samples = RecipeUISamples()
        try write(approval(samples.newRequest()), to: out("recipe-approval-new.png"))
        try write(approval(samples.modifiedRequest()), to: out("recipe-approval-modified.png"))
        try write(approval(samples.modifiedRequest(), overlay: .changes), to: out("recipe-approval-diff.png"))
        try write(approval(samples.newRequest(), overlay: .json), to: out("recipe-approval-json.png"))
        try write(approval(samples.reviewRequest()), to: out("recipe-approval-review.png"))
        try write(approval(samples.ownEditRequest()), to: out("recipe-approval-own-edit.png"))
        try write(approval(samples.aiRequest()), to: out("recipe-approval-ai.png"))
        try write(approval(samples.builtInRequest()), to: out("recipe-approval-builtin.png"))
        try write(approval(samples.validationRequest()), to: out("recipe-approval-validation.png"))
        try write(approval(samples.detailsRequest()), to: out("recipe-approval-details.png"))
        try write(approval(samples.extensionRequest()), to: out("recipe-approval-extension.png"))

        let model = RecipeSettingsModel(rows: RecipeSettingsRow.rows(from: samples.loadedRecipes), clashes: [samples.clash])
        let on = isolatedStore("greenshot-mac-snapshots-recipes-on")
        try write(window(RecipesSettingsTab(store: on, model: model), size: NSSize(width: 760, height: 900)), to: out("settings-recipes.png"))
        let off = isolatedStore("greenshot-mac-snapshots-recipes-off")
        off.update { $0.recipes.enabled = false }
        try write(window(RecipesSettingsTab(store: off, model: model), size: NSSize(width: 760, height: 360)), to: out("settings-recipes-off.png"))
        // The real window's width with all ten tabs, on Recipes (no runtime here: the list says so).
        try write(window(SettingsView(store: on, status: SystemStatus(), initialTab: SettingsPane.recipes.rawValue),
                         size: NSSize(width: 760, height: 616)), to: out("settings-recipes-window.png"))

        let entries = RecipeMenuEntries.statusMenu(recipes: samples.loadedRecipes, active: samples.activeTriggers)
        try writeText(recipeMenuText(RecipeMenus.makeStatusMenu(entries: entries, canImport: true)), to: out("recipes-menu.txt"))
        let editorMenu = NSMenu(title: "Recipes")
        let editorEntries = RecipeMenuEntries.editorMenu(recipes: samples.loadedRecipes, active: samples.activeTriggers)
        RecipeMenus.fillEditorMenu(editorMenu, entries: editorEntries, editor: nil)
        try writeText(recipeMenuText(editorMenu), to: out("editor-recipes-menu.txt"))
    }

    private static func approval(_ request: RecipeApprovalRequest, overlay: RecipeApprovalModel.Overlay? = nil) -> NSBitmapImageRep? {
        let model = RecipeApprovalModel(request: request)
        model.overlay = overlay
        guard overlay == nil else {
            return window(RecipeApprovalView(model: model), size: NSSize(width: 680, height: 760))
        }
        // The whole content, as tall as it is.
        let view = RecipeApprovalView(model: model, scrolls: false)
        let probe = NSHostingView(rootView: view.frame(width: 680))
        let height = max(420, probe.fittingSize.height)
        return window(view, size: NSSize(width: 680, height: height))
    }

    private static func isolatedStore(_ suite: String) -> SettingsStore {
        let defaults = UserDefaults(suiteName: suite) ?? .standard
        defaults.removePersistentDomain(forName: suite)
        return SettingsStore(defaults: defaults)
    }

    /// `menuText` with the badges (hotkeys a menu can't show as a key equivalent).
    private static func recipeMenuText(_ menu: NSMenu) -> String {
        var badges: [String] = []
        func collect(_ menu: NSMenu) {
            for item in menu.items {
                if let badge = item.badge?.stringValue { badges.append("\(item.title)\t[\(badge)]") }
                if let submenu = item.submenu { collect(submenu) }
            }
        }
        collect(menu)
        return menuText(menu) + (badges.isEmpty ? "" : "\nBadges:\n" + badges.joined(separator: "\n") + "\n")
    }
}

/// Sample recipes and the approval requests the library would build for them.
@MainActor
private struct RecipeUISamples {
    let folder = URL(fileURLWithPath: "/Users/me/Recipes")
    let describer = RecipeDescriber(gates: GateEnvironment())
    let validator = RecipeValidator()

    static let current = """
        {
          "id": "region_to_jira",
          "name": "Region to Jira",
          "version": "1.2",
          "description": "Select a region, make it smaller with pngquant, keep a copy and attach it to a Jira issue.",
          "triggers": [
            {"triggerType": "Hotkey", "parameters": {"Hotkey": "Ctrl + Shift + J"}},
            {"triggerType": "ContextMenu", "parameters": {"MenuItemText": "Region to Jira"}},
            {"triggerType": "Clipboard", "parameters": {"FormatFilter": "PNG"}},
            {"triggerType": "Commandline", "parameters": {"Command": "jira-shot", "AllowBrowserInvocation": true}}
          ],
          "nodes": [
            {"id": "acquire", "stepType": "Source", "parameters": {"SourceType": "Region"}},
            {"id": "border", "stepType": "Effect", "parameters": {"Effect": "Border", "Width": 2}},
            {"id": "shrink", "stepType": "ExternalCommand", "parameters": {"CommandLine": "/opt/homebrew/bin/pngquant"}},
            {"id": "keep", "stepType": "SaveFile", "parameters": {"SaveDirectory": "~/Shots/Jira"}},
            {"id": "upload", "stepType": "Jira"}
          ],
          "flow": {"startNodes": ["acquire"],
                   "transitions": {"acquire": "border", "border": "shrink", "shrink": "keep", "keep": "upload"}}
        }
        """

    static let previous = """
        {
          "id": "region_to_jira",
          "name": "Region to Jira",
          "version": "1.1",
          "description": "Select a region, keep a copy and attach it to a Jira issue.",
          "triggers": [
            {"triggerType": "Hotkey", "parameters": {"Hotkey": "Ctrl + Shift + J"}},
            {"triggerType": "ContextMenu", "parameters": {"MenuItemText": "Region to Jira"}}
          ],
          "nodes": [
            {"id": "acquire", "stepType": "Source", "parameters": {"SourceType": "Region"}},
            {"id": "border", "stepType": "Effect", "parameters": {"Effect": "Border", "Width": 2}},
            {"id": "keep", "stepType": "SaveFile", "parameters": {"SaveDirectory": "~/Shots/Jira"}},
            {"id": "upload", "stepType": "Jira"}
          ],
          "flow": {"startNodes": ["acquire"], "transitions": {"acquire": "border", "border": "keep", "keep": "upload"}}
        }
        """

    static let broken = """
        {
          "id": "shrink_and_mail",
          "name": "Shrink and mail",
          "triggers": [{"triggerType": "Hotkey", "parameters": {"Hotkey": "Ctrl + Shift + Foo"}}],
          "nodes": [
            {"id": "acquire", "stepType": "Source", "parameters": {"SourceType": "Region"}},
            {"id": "shrink", "stepType": "Compress"}
          ],
          "flow": {"startNodes": ["acquire"], "transitions": {"acquire": "shrink", "shrink": "mail"}}
        }
        """

    var fileURL: URL { folder.appendingPathComponent("region-to-jira.gsrecipe.json") }

    func recipe(_ text: String) -> CaptureRecipe {
        (try? RecipeSerializer.decode(text: text).first) ?? CaptureRecipe(id: "sample", name: "Sample")
    }

    func hash(_ text: String) -> String {
        RecipeHash.sha256Hex(Data(text.utf8))
    }

    /// Like `RecipeLibrary.approvalRequest`.
    func request(_ text: String, mode: RecipeApprovalMode) -> RecipeApprovalRequest {
        let recipe = recipe(text)
        var request = RecipeApprovalRequest(mode: mode, recipe: recipe, fileURL: fileURL, content: text, contentHash: hash(text))
        let validation = validator.validate(recipe)
        request.validation = validation
        request.steps = describer.describeSteps(recipe)
        request.triggers = describer.describeTriggers(recipe)
        request.gates = validation.gateTypes
        return request
    }

    var previousRecord: RecipeTrustRecord {
        var record = RecipeTrustRecord(filePath: fileURL.path, sha256: hash(Self.previous),
                                       approvedAt: Date(timeIntervalSince1970: 1_791_000_000))
        record.approvedContent = Self.previous
        record.recipes = [RecipeApproval(recipeId: "region_to_jira", approvedTriggers: ["0:Hotkey", "1:ContextMenu"],
                                         allowedGates: [.fileSystemAccess, .networkAccess])]
        return record
    }

    func withChanges(_ request: RecipeApprovalRequest, from previousText: String, previous: CaptureRecipe) -> RecipeApprovalRequest {
        var changed = request
        changed.previousContent = previousText
        changed.diff = RecipeTextDiff.compare(previousText, request.content)
        changed.changes = describer.describeChanges(from: previous, to: request.recipe)
        return changed
    }

    func newRequest() -> RecipeApprovalRequest {
        request(Self.current, mode: .newRecipe)
    }

    func modifiedRequest() -> RecipeApprovalRequest {
        var request = request(Self.current, mode: .modified)
        request.previousRecord = previousRecord
        return withChanges(request, from: Self.previous, previous: recipe(Self.previous))
    }

    func reviewRequest() -> RecipeApprovalRequest {
        var request = request(Self.current, mode: .reVerify)
        var record = previousRecord
        record.sha256 = hash(Self.current)
        request.previousRecord = record
        request.suggestedApproval = RecipeApproval(recipeId: "region_to_jira", approvedTriggers: ["0:Hotkey", "1:ContextMenu", "3:Commandline"],
                                                   allowedGates: [.externalCommand, .fileSystemAccess, .networkAccess])
        return request
    }

    func ownEditRequest() -> RecipeApprovalRequest {
        var request = reviewRequest()
        request.mode = .modified
        request.ownEditReasons = ["When an image is copied to the clipboard", "It needs external commands."]
        request.suggestedApproval = RecipeApproval(recipeId: "region_to_jira", approvedTriggers: ["0:Hotkey", "1:ContextMenu"],
                                                   allowedGates: [.fileSystemAccess, .networkAccess])
        return withChanges(request, from: Self.previous, previous: recipe(Self.previous))
    }

    func aiRequest() -> RecipeApprovalRequest {
        var request = request(Self.current, mode: .newRecipe)
        request.fileURL = folder.appendingPathComponent("AI/region_to_jira.gsrecipe.json")
        request.proposedBy = "Claude — /Applications/Claude.app · Developer ID Application: Anthropic PBC"
        request.aiRequest = "Make me a hotkey that sends a region to Jira, smaller."
        request.aiExplanation = "This recipe captures a region, compresses it with pngquant and uploads it to Jira. It is safe and only does what you asked."
        request.startSwitchedOff = true
        return request
    }

    func builtInRequest() -> RecipeApprovalRequest {
        let text = """
            {"id": "recipe_region", "name": "Capture region", "version": "1.0",
             "nodes": [{"id": "acquire", "stepType": "Source", "parameters": {"SourceType": "Region", "DelayMs": 500}},
                       {"id": "export", "stepType": "Destinations", "parameters": {"DestinationDesignations": ["Clipboard", "FileNoDialog"]}}],
             "flow": {"startNodes": ["acquire"], "transitions": {"acquire": "export"}}}
            """
        let builtIn = """
            {"id": "recipe_region", "name": "Capture region", "version": "1.0",
             "nodes": [{"id": "acquire", "stepType": "Source", "parameters": {"SourceType": "Region"}},
                       {"id": "export", "stepType": "Destinations"}],
             "flow": {"startNodes": ["acquire"], "transitions": {"acquire": "export"}}}
            """
        var request = request(text, mode: .newRecipe)
        request.fileURL = folder.appendingPathComponent("region-with-delay.gsrecipe.json")
        request.replacesBuiltIn = true
        request.replacedRecipe = recipe(builtIn)
        return withChanges(request, from: builtIn, previous: recipe(builtIn))
    }

    func validationRequest() -> RecipeApprovalRequest {
        let recipe = recipe(Self.broken)
        var request = RecipeApprovalRequest(mode: .validationError, recipe: recipe, fileURL: folder.appendingPathComponent("shrink-and-mail.gsrecipe.json"),
                                            content: Self.broken, contentHash: hash(Self.broken))
        let validation = validator.validate(recipe)
        request.validation = validation
        request.errorMessage = validation.errors.joined(separator: "\n")
        return request
    }

    /// An automatic step (RMANAGER's files): no triggers, the recipes it changes.
    func extensionRequest() -> RecipeApprovalRequest {
        let text = """
            {"kind": "extension", "id": "ext_jira_copy", "name": "Copy to Jira",
             "description": "Attaches a copy of every capture to the Jira issue you work on.",
             "extends": {"recipes": ["*capture"], "slot": "AfterExport", "order": 400},
             "options": [{"key": "enabled", "type": "Boolean", "default": false, "label": "Attach a copy to Jira"}],
             "nodes": [{"id": "upload", "stepType": "Jira"}],
             "flow": {"startNodes": ["upload"], "transitions": {"upload": "Out"}}}
            """
        var request = request(text, mode: .newRecipe)
        request.fileURL = folder.appendingPathComponent("jira-copy.gsrecipe.json")
        request.extensionReach = ["Changes these recipes now: Capture region, Capture window, Capture full screen, Capture last region",
                                  "Also every capture recipe added later.",
                                  "Where: after the export, on its own copy of the capture.",
                                  "Switched on and off in Settings › Recipes."]
        return request
    }

    func detailsRequest() -> RecipeApprovalRequest {
        var request = reviewRequest()
        request.isReadOnly = true
        request.startSwitchedOff = false
        return request
    }

    // MARK: Library contents

    var loadedRecipes: [LoadedRecipe] {
        let jira = recipe(Self.current)
        var qr = CaptureRecipe(id: "scan_qr", name: "Scan QR code")
        qr.triggers = [TriggerConfig(triggerType: WellKnownTriggerType.systray, parameters: ["MenuItemText": .string("Scan QR Code"), "Group": .string("Tools"), "Order": .number(5)]),
                       TriggerConfig(triggerType: WellKnownTriggerType.hotkey, parameters: ["Hotkey": .string("Ctrl + K, Q")]),
                       TriggerConfig(triggerType: WellKnownTriggerType.editor, parameters: ["MenuItemText": .string("Find QR Codes")])]
        var slack = CaptureRecipe(id: "window_to_slack", name: "Window to Slack")
        slack.triggers = [TriggerConfig(triggerType: WellKnownTriggerType.openFile, parameters: ["Filter": .string(".png")])]
        let region = recipe("""
            {"id": "recipe_region", "name": "Capture region", "nodes": [{"id": "acquire", "stepType": "Source"}], "flow": {"startNodes": ["acquire"]}}
            """)
        return [
            LoadedRecipe(recipe: region, source: .builtIn),
            LoadedRecipe(recipe: jira, source: .file(fileURL),
                         approval: RecipeApproval(recipeId: jira.id, approvedTriggers: ["0:Hotkey", "1:ContextMenu", "3:Commandline"],
                                                  allowedGates: [.externalCommand, .fileSystemAccess, .networkAccess])),
            LoadedRecipe(recipe: qr, source: .file(folder.appendingPathComponent("AI/scan_qr.gsrecipe.json")),
                         approval: RecipeApproval(recipeId: qr.id, approvedTriggers: ["0:Systray", "1:Hotkey", "2:Editor"]), proposedBy: "Claude"),
            LoadedRecipe(recipe: slack, source: .file(folder.appendingPathComponent("window-to-slack.gsrecipe.json")), isEnabled: false,
                         approval: RecipeApproval(recipeId: slack.id))
        ]
    }

    var activeTriggers: [ActiveRecipeTrigger] {
        var result: [ActiveRecipeTrigger] = []
        for loaded in loadedRecipes where loaded.isEnabled {
            for (index, trigger) in loaded.recipe.triggers.enumerated() where loaded.isTriggerActive(at: index) {
                let hotkey = trigger.isType(WellKnownTriggerType.hotkey) ? trigger.hotkey.flatMap(RecipeHotkeyText.parse) : nil
                result.append(ActiveRecipeTrigger(recipeId: loaded.recipe.id, recipeName: loaded.recipe.name, index: index,
                                                  trigger: trigger, hotkey: hotkey))
            }
        }
        return result
    }

    var clash: RecipeHotkeyClash {
        let combo = RecipeHotkeyText.parse("Ctrl + K, Q") ?? KeyCombo.defaultRegion
        return RecipeHotkeyClash(name: "Recipe “Scan QR code”", combo: combo,
                                 problem: "It is the beginning of “Capture text” (⌘K, Q, T), which would then never fire.")
    }
}
