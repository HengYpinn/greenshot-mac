// Greenshot for Mac (Community) - an unofficial macOS port of Greenshot
// Copyright (C) 2026 Greenshot for Mac (Community) contributors
// Based on Greenshot, Copyright (C) 2007-2026 Thomas Braun, Jens Klingen, Robin Krom
// SPDX-License-Identifier: GPL-3.0-or-later

import CoreGraphics
import Foundation

/// A line of what a recipe does (upstream `RecipeDescriptionLine`).
public struct RecipeDescriptionLine: Sendable, Equatable {
    public var text: String
    /// The kind of gated action the line is about, nil when harmless.
    public var risk: RecipeGateType?
    /// A detail of the line before (what a step uploads, which program it runs).
    public var isDetail: Bool

    public init(_ text: String, risk: RecipeGateType? = nil, isDetail: Bool = false) {
        self.text = text
        self.risk = risk
        self.isDetail = isDetail
    }
}

/// A trigger in words and why it matters (upstream `RecipeTriggerDescription`).
public struct RecipeTriggerDescription: Sendable, Equatable {
    /// The approval key (`RecipeApprovalPolicy.triggerKey`, or the browser-invocation key).
    public var key: String
    public var label: String
    /// Why it needs attention, nil when it only adds something the user starts (a hotkey, a menu entry).
    public var risk: String?
    /// Switched off in the recipe itself.
    public var isDisabled: Bool

    public init(key: String, label: String, risk: String? = nil, isDisabled: Bool = false) {
        self.key = key
        self.label = label
        self.risk = risk
        self.isDisabled = isDisabled
    }
}

/// What a recipe does in plain words, from the recipe itself (upstream `RecipeDescriber`).
public struct RecipeDescriber: Sendable {
    private let contracts: StepContractCatalog
    private let gates: GateEnvironment

    public init(contracts: StepContractCatalog = .builtIn, gates: GateEnvironment = .empty) {
        self.contracts = contracts
        self.gates = gates
    }

    public func describeTriggers(_ recipe: CaptureRecipe) -> [RecipeTriggerDescription] {
        var result: [RecipeTriggerDescription] = []
        for (index, trigger) in recipe.triggers.enumerated() {
            var description = describe(trigger, of: recipe)
            description.key = RecipeApprovalPolicy.triggerKey(index: index, trigger: trigger)
            description.isDisabled = !trigger.enabled
            result.append(description)
            if trigger.isType(WellKnownTriggerType.commandline), trigger.allowsBrowserInvocation {
                result.append(RecipeTriggerDescription(
                    key: RecipeApprovalPolicy.browserInvocationKey(index: index, trigger: trigger),
                    label: "Web pages and the browser extension can start \"\(trigger.command ?? recipe.id)\"",
                    risk: "Any web page you open can start this recipe with a Greenshot link, and the browser extension can too.",
                    isDisabled: !trigger.enabled))
            }
        }
        return result
    }

    private func describe(_ trigger: TriggerConfig, of recipe: CaptureRecipe) -> RecipeTriggerDescription {
        let menuText = trigger.menuItemText ?? recipe.name
        func plain(_ label: String, _ risk: String? = nil) -> RecipeTriggerDescription {
            RecipeTriggerDescription(key: "", label: label, risk: risk)
        }
        if trigger.isType(WellKnownTriggerType.hotkey) {
            let text = trigger.hotkey ?? ""
            let shown = RecipeHotkeyText.parse(text)?.displayString ?? (text.isEmpty ? "(none)" : text)
            return plain("Hotkey \(shown)")
        }
        if trigger.isType(WellKnownTriggerType.contextMenu) || trigger.isType(WellKnownTriggerType.systray) {
            return plain("Entry \"\(menuText)\" in the Greenshot menu")
        }
        if trigger.isType(WellKnownTriggerType.editor) { return plain("Entry \"\(menuText)\" in the editor") }
        if trigger.isType(WellKnownTriggerType.manual) { return plain("Started from the recipe list") }
        if trigger.isType(WellKnownTriggerType.clipboard) {
            return plain("When an image is copied to the clipboard", "Runs on its own every time you copy an image, without you starting it.")
        }
        if trigger.isType(WellKnownTriggerType.schedule) {
            return plain("On a schedule", "Runs on its own at the scheduled times, also when you are not looking at the screen.")
        }
        if trigger.isType(WellKnownTriggerType.commandline) {
            return plain("Command line command \"\(trigger.command ?? recipe.id)\"", "Programs and scripts on this Mac can start it.")
        }
        if trigger.isType(WellKnownTriggerType.openFile) {
            let filter = trigger.fileFilter?.trimmingCharacters(in: .whitespaces) ?? ""
            return plain(filter.isEmpty ? "When a file is opened with Greenshot" : "When a file (\(filter)) is opened with Greenshot",
                         "Runs for files opened with Greenshot, for example with \"Open With\" in Finder.")
        }
        if trigger.isType(WellKnownTriggerType.extension) {
            let browser = trigger.browser?.trimmingCharacters(in: .whitespaces) ?? ""
            return plain(browser.isEmpty ? "Captures from the browser extension" : "Captures from the browser extension (\(browser))",
                         "Handles the captures the Greenshot browser extension sends, instead of the default recipe.")
        }
        if trigger.isType(WellKnownTriggerType.aiTool) {
            return plain("AI tool \"\(trigger.toolName ?? trigger.name ?? "")\"",
                         "AI tools you allowed (e.g. Claude, Copilot, Gemini) can run this recipe and get its result, the image included.")
        }
        return plain("\(trigger.triggerType) trigger", "An unknown kind of trigger.")
    }

    public func describeSteps(_ recipe: CaptureRecipe) -> [RecipeDescriptionLine] {
        var lines: [RecipeDescriptionLine] = []
        let recipeVariables = RecipeGates.variablesSet(by: recipe, contracts: contracts)
        for node in recipe.nodes {
            var actions: [RecipeGatedAction] = []
            if let contract = contracts.contract(for: node.stepType) {
                actions = RecipeGates.actions(of: node, contract: contract, environment: gates, recipeSets: recipeVariables)
            }
            var text = describeStep(node)
            switch node.enabled {
            case .value(false): text += " (disabled)"
            case .expression(let expression): text += " (only when \(expression))"
            case .value(true): break
            }
            lines.append(RecipeDescriptionLine(text, risk: actions.first?.gateType))
            for action in actions {
                lines.append(RecipeDescriptionLine(describe(action), risk: action.gateType, isDetail: true))
            }
        }
        return lines
    }

    /// "Adds: ..." / "Removes: ..." between two versions.
    public func describeChanges(from old: CaptureRecipe?, to new: CaptureRecipe?) -> [String] {
        let oldLines = summarize(old)
        let newLines = summarize(new)
        return newLines.filter { !oldLines.contains($0) }.map { "Adds: \($0)" }
            + oldLines.filter { !newLines.contains($0) }.map { "Removes: \($0)" }
    }

    /// "Uploads to Jira", "Runs the program /usr/local/bin/pngquant", or the file-access text.
    public func describe(_ action: RecipeGatedAction) -> String {
        switch action.gateType {
        case .networkAccess: return "Uploads to \(action.target)"
        case .externalCommand:
            // A command decided when the recipe runs isn't a program anyone can name yet.
            return action.target.hasPrefix("a command ") ? "Runs \(action.target)" : "Runs the program \(action.target)"
        case .fileSystemAccess, .custom: return action.target
        }
    }

    private func summarize(_ recipe: CaptureRecipe?) -> [String] {
        guard let recipe else { return [] }
        var lines: [String] = []
        for line in describeTriggers(recipe).map({ "trigger \($0.label)" }) + describeSteps(recipe).map(\.text) where !lines.contains(line) {
            lines.append(line)
        }
        return lines
    }

    // MARK: Steps

    private func describeStep(_ node: RecipeNode) -> String {
        let type = node.stepType
        let parameters = node.parameters
        func isType(_ name: String) -> Bool { recipeEquals(type, name) }
        if isType(WellKnownStepType.source) { return describeSource(node) }
        if isType(WellKnownStepType.destinations) || isType(WellKnownStepType.customDestination) {
            var designations = parameters.strings("DestinationDesignations") ?? []
            if let custom = parameters.string("CustomDestinationId")?.trimmingCharacters(in: .whitespaces), !custom.isEmpty {
                designations.append(custom)
            }
            let names = designations.map { designation in
                RecipeGateValue.isRunTime(designation) ? "a destination decided when the recipe runs (\(designation))"
                    : RecipeDestinationDesignation(designation).displayName
            }
            return names.isEmpty ? "Sends the result to the destinations from the settings" : "Sends the result to \(names.joined(separator: ", "))"
        }
        if isType(WellKnownStepType.processors) {
            let processors = parameters.strings("ProcessorIds") ?? []
            return processors.isEmpty ? "Runs the processors from the settings"
                : "Runs \(processors.map { $0.hasSuffix("Processor") ? String($0.dropLast("Processor".count)) : $0 }.joined(separator: ", "))"
        }
        if isType(WellKnownStepType.conditional) { return "Decides how to continue" }
        if isType(WellKnownStepType.setVariable) {
            var names: [String] = []
            if let single = parameters.string("Variable"), !single.isEmpty { names.append(single) }
            names += parameters["Variables"]?.objectValue?.keys ?? []
            if names.count > 1 { return "Sets the variables \(names.joined(separator: ", "))" }
            return "Sets the variable \(names.first ?? "?")"
        }
        if isType(WellKnownStepType.clipboard) { return "Copies the result to the clipboard" }
        if isType(WellKnownStepType.editor) { return "Opens the result in the editor" }
        if isType(WellKnownStepType.printer) { return "Prints the result" }
        if isType(WellKnownStepType.email) { return "Creates an email with the result" }
        if isType(WellKnownStepType.saveFile) {
            switch RecipeGateValue(node, "SaveDirectory") {
            case .unset: return "Saves the result to the output folder from the settings"
            case .literal(let directory): return "Saves the result to \(directory)"
            case .runTime(let text): return "Saves the result to a folder decided when the recipe runs (\(text))"
            }
        }
        if isType(WellKnownStepType.interactiveSelection) { return "Lets you select a region" }
        if isType(WellKnownStepType.userPrompt) { return "Asks you a question" }
        if isType(WellKnownStepType.stdout) || isType(WellKnownStepType.stderr) { return "Writes text for the caller (command line or AI tool)" }
        if isType(WellKnownStepType.dynamicDestination) { return "Lets you choose where the result goes" }
        let contract = contracts.contract(for: type)
        let name = (contract?.displayName.isEmpty ?? true) ? type : contract!.displayName
        let summary = summarizeParameters(node, contract)
        return summary.isEmpty ? name : "\(name) (\(summary))"
    }

    private func describeSource(_ node: RecipeNode) -> String {
        let parameters = node.parameters
        let sourceType = parameters.string("SourceType") ?? "Region"
        let what: String
        switch sourceType.lowercased() {
        case "region":
            what = parameters.contains(key: "PreSuppliedRegion") ? "Captures a given part of the screen" : "Captures a region you select"
        case "window":
            let title = parameters.string("WindowTitle") ?? parameters.string("WindowTitlePattern")
            let process = parameters.string("ProcessName")
            if parameters.contains(key: "WindowHandle") {
                what = "Captures the window passed to the recipe"
            } else if let title, !title.trimmingCharacters(in: .whitespaces).isEmpty {
                what = "Captures the window \"\(title)\""
            } else if let process, !process.trimmingCharacters(in: .whitespaces).isEmpty {
                what = "Captures the window of \(process)"
            } else {
                what = "Captures a window you choose"
            }
        case "activewindow": what = "Captures the active window"
        case "fullscreen": what = "Captures the screen"
        case "clipboard": what = "Takes the image from the clipboard"
        case "file":
            switch RecipeGateValue(node, "Filename") {
            case .unset: what = "Loads an image file"
            case .literal(let filename): what = "Loads the image file \(filename)"
            case .runTime(let text): what = "Loads an image file named when the recipe runs (\(text))"
            }
        case "currenteditor": what = "Takes the image from the open editor"
        case "lastregion": what = "Captures the last region again"
        default: what = "Captures (\(sourceType))"
        }
        let delay = parameters.int("DelayMs") ?? 0
        return delay > 0 ? "\(what), after \(delay) ms" : what
    }

    /// Upstream `SummarizeParameters`: up to four parameters that differ from their default, short values only.
    private func summarizeParameters(_ node: RecipeNode, _ contract: StepContract?) -> String {
        var parts: [String] = []
        for member in node.parameters {
            guard let value = Self.format(member.value), value.count <= 60 else { continue }
            if let defaultValue = contract?.parameter(member.key)?.defaultValue.flatMap(Self.format), recipeEquals(defaultValue, value) { continue }
            parts.append("\(member.key): \(value)")
            if parts.count == 4 { break }
        }
        return parts.joined(separator: ", ")
    }

    private static func format(_ value: JSONValue) -> String? {
        switch value {
        case .string(let text): return text
        case .bool(let flag): return flag ? "yes" : "no"
        case .number(let number): return JSONValue.format(number)
        case .null, .array, .object: return nil
        }
    }
}

/// What the recipe manager's Details shows (upstream `RecipeDetails`).
public struct RecipeDetails: Sendable, Equatable {
    public var whatItDoes: [RecipeDescriptionLine] = []
    public var triggers: [RecipeTriggerDescription] = []
    public var approvedAt: Date?
    public var approvedHash: String?
    /// The file on disk is the approved content.
    public var isApprovalCurrent: Bool = false
    public var permissions: [RecipeGateType] = []
    public var proposedBy: String?
    /// The changed lines against the built-in recipe it replaces.
    public var builtInDiff: String?

    public init() {}
}
