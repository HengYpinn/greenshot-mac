// Greenshot for Mac (Community) - an unofficial macOS port of Greenshot
// Copyright (C) 2026 Greenshot for Mac (Community) contributors
// Based on Greenshot, Copyright (C) 2007-2026 Thomas Braun, Jens Klingen, Robin Krom
// SPDX-License-Identifier: GPL-3.0-or-later

import Foundation

/// What the approval window shows for a request and how its switches start (upstream `RecipeApprovalWindow` code-behind,
/// `TriggerApprovalViewModel`, `GateApprovalViewModel`, `RecipeValidationErrorViewModel`). Default-deny: closing the
/// window rejects; Approve needs every permission switch on, because without them the recipe isn't loaded.
public struct RecipeApprovalSheet: Sendable {
    public enum Style: Sendable, Equatable {
        case validationError, details, aiProposal, ownEdit, modified, review, newRecipe
    }

    public enum Tone: Sendable, Equatable {
        case neutral, accent, warning, error
    }

    /// One trigger's switch (upstream `TriggerApprovalViewModel`).
    public struct TriggerSwitch: Sendable, Equatable, Identifiable {
        /// The approval key (`RecipeApprovalPolicy.triggerKey` or the browser-invocation key).
        public var id: String
        public var title: String
        /// Why it matters, nil when it doesn't.
        public var explanation: String?
        public var isDisabledInRecipe: Bool
        public var isOn: Bool
    }

    /// One permission switch per kind of gated action (upstream `GateApprovalViewModel`).
    public struct GateSwitch: Sendable, Equatable, Identifiable {
        public var gate: RecipeGateType
        public var question: String
        public var explanation: String?
        /// What the recipe does of this kind ("Uploads to Jira", "Runs the program /usr/bin/pngquant").
        public var targets: [String]
        public var isOn: Bool

        public var id: String { gate.rawValue }
    }

    /// A validation error with what to change.
    public struct Problem: Sendable, Equatable {
        public var message: String
        public var hint: String?
    }

    public let request: RecipeApprovalRequest
    public let style: Style
    /// An automatic step (`"kind": "extension"`): no triggers, it changes other recipes.
    public let isExtension: Bool

    public var windowTitle: String
    public var headerTitle: String
    public var headerDescription: String
    public var badge: String
    public var badgeTone: Tone
    /// An SF Symbol.
    public var icon: String
    public var approveTitle: String
    public var rejectTitle: String

    public var recipeName: String
    public var recipeVersion: String
    public var recipeDescription: String
    public var recipeId: String
    /// "Built into Greenshot" for a built-in recipe.
    public var fileText: String
    public var fileHash: String
    public var previousApprovedAt: Date?
    public var previousHash: String?

    public var changesTitle: String?
    public var changeLines: [String]
    public var steps: [RecipeDescriptionLine]
    public var triggers: [TriggerSwitch]
    public var triggerHint: String
    public var triggerHintIsWarning: Bool
    public var gates: [GateSwitch]
    public var problems: [Problem]
    public var extensionReach: [String]

    public init(request: RecipeApprovalRequest) {
        self.request = request
        let recipe = request.recipe
        let isExtension = recipe?.kind == .extension
        self.isExtension = isExtension
        let isValidationError = request.mode == .validationError || request.validation.map { !$0.isValid } == true
        let isAIProposal = Self.isAIProposal(request)
        let style: Style
        if isValidationError {
            style = .validationError
        } else if request.isReadOnly {
            style = .details
        } else if isAIProposal {
            style = .aiProposal
        } else if request.ownEditReasons != nil {
            style = .ownEdit
        } else {
            switch request.mode {
            case .modified: style = .modified
            case .reVerify: style = .review
            case .newRecipe, .validationError: style = .newRecipe
            }
        }
        self.style = style

        let fallbackName = request.fileURL?.lastPathComponent ?? "Unnamed Recipe"
        let name = recipe?.name.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        recipeName = name.isEmpty ? fallbackName : name
        let version = recipe?.version.trimmingCharacters(in: .whitespaces) ?? ""
        recipeVersion = version.isEmpty ? "" : "v\(version)"
        let description = recipe?.description?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        recipeDescription = description.isEmpty
            ? (isValidationError ? "Recipe configuration failed validation." : "No description provided.") : description
        recipeId = recipe?.id ?? "unknown"
        fileText = request.fileURL?.path ?? "Built into Greenshot"
        fileHash = request.contentHash.isEmpty ? "Unknown" : request.contentHash
        if let record = request.previousRecord, style == .modified || style == .review || style == .ownEdit || style == .details {
            previousApprovedAt = record.approvedAt
            previousHash = record.sha256
        } else {
            previousApprovedAt = nil
            previousHash = nil
        }

        let texts = Self.texts(style: style, request: request, isExtension: isExtension)
        windowTitle = "Greenshot — " + texts.subtitle
        headerTitle = texts.title
        headerDescription = texts.description
        badge = texts.badge
        badgeTone = texts.tone
        icon = texts.icon
        approveTitle = texts.approve
        rejectTitle = style == .review ? "Revoke Approval" : "Reject / Block"

        // What changed: against the replaced recipe (built-in) or the previously approved version.
        if let replaced = request.replacedRecipe {
            changesTitle = request.replacesBuiltIn ? "Replaces the built-in recipe “\(replaced.name)”" : "Changes the recipe “\(replaced.name)”"
        } else if request.mode == .modified || (style == .ownEdit && request.previousContent != nil) {
            changesTitle = request.previousContent != nil ? "What changed since the last approval"
                : "The previous version is not known, review the whole recipe"
        } else {
            changesTitle = nil
        }
        if changesTitle != nil, request.previousContent != nil, !isValidationError {
            changeLines = request.changes.isEmpty ? ["No change in what the recipe does (only details like names or layout)."] : request.changes
        } else {
            changeLines = []
        }
        if isValidationError { changesTitle = nil }

        steps = isValidationError ? [] : request.steps
        extensionReach = isValidationError ? [] : (request.extensionReach ?? [])

        // Triggers (upstream PopulateTriggerItems): the suggestion when there is one, else what was approved before
        // (not for a changed file), else on unless everything starts switched off.
        let startOff = isAIProposal || request.startSwitchedOff
        let previousApproval = recipe.flatMap { request.previousRecord?.approval(for: $0.id) }
        let keepPrevious = request.previousRecord != nil && request.mode != .modified
        var triggerSwitches: [TriggerSwitch] = []
        if !isValidationError, !isExtension {
            for trigger in request.triggers {
                let isOn: Bool
                if let suggested = request.suggestedApproval {
                    isOn = suggested.isTriggerApproved(trigger.key)
                } else if keepPrevious, let previousApproval {
                    isOn = previousApproval.isTriggerApproved(trigger.key)
                } else {
                    isOn = !startOff
                }
                triggerSwitches.append(TriggerSwitch(id: trigger.key,
                                                     title: trigger.isDisabled ? "\(trigger.label) (disabled in the recipe)" : trigger.label,
                                                     explanation: trigger.risk, isDisabledInRecipe: trigger.isDisabled, isOn: isOn))
            }
        }
        triggers = triggerSwitches
        let switchedOffHint = request.suggestedApproval == nil && startOff
        triggerHint = switchedOffHint
            ? "The triggers start switched off. Switch on each one that may start this recipe: a trigger you leave off stays off "
                + "(you can switch it on later with Permissions). Without a trigger you can still run the recipe from the recipe list."
            : "Switch off the triggers you don't want."
        triggerHintIsWarning = switchedOffHint

        // Permissions (upstream :420-440): a review keeps what was allowed; otherwise external programs and custom actions
        // are always asked, the rest is on for a file the user loads themselves, off for AI tools.
        var gateSwitches: [GateSwitch] = []
        if !isValidationError {
            let kept = request.suggestedApproval ?? previousApproval
            let actions = request.validation?.gatedActions ?? []
            let describer = RecipeDescriber()
            for gate in request.gates.sorted() {
                let isOn: Bool
                if style == .details, request.fileURL == nil {
                    // A built-in recipe may do what it does.
                    isOn = true
                } else if style == .review || style == .details, let kept {
                    isOn = kept.isGateAllowed(gate)
                } else if style == .ownEdit, kept?.isGateAllowed(gate) == true {
                    isOn = true
                } else {
                    isOn = !startOff && gate != .externalCommand && gate != .custom
                }
                var targets: [String] = []
                for action in actions where action.gateType == gate {
                    let text = describer.describe(action)
                    if !targets.contains(text) { targets.append(text) }
                }
                gateSwitches.append(GateSwitch(gate: gate, question: Self.question(for: gate), explanation: Self.explanation(for: gate),
                                               targets: targets, isOn: isOn))
            }
        }
        gates = gateSwitches

        var problems: [Problem] = []
        if isValidationError {
            var messages = request.validation?.errors ?? []
            if messages.isEmpty {
                messages = (request.errorMessage ?? "").components(separatedBy: "\n")
                    .map { $0.trimmingCharacters(in: .whitespaces) }.filter { !$0.isEmpty }
            }
            if messages.isEmpty { messages = ["The recipe file could not be read."] }
            problems = messages.map { Problem(message: $0, hint: RecipeValidationHints.hint(for: $0)) }
        }
        self.problems = problems
    }

    // MARK: State

    /// The window decides nothing (validation error, Details): only Close.
    public var isDecision: Bool { style != .validationError && style != .details }
    /// A review: "Keep as Is" (and Esc, and closing) changes nothing; the reject button revokes.
    public var isReview: Bool { style == .review }
    /// Upstream shows "Open in the recipe editor after saving" for AI proposals.
    public var offersOpenInEditor: Bool { style == .aiProposal }
    /// Without every permission the recipe isn't loaded, so Approve waits for them (upstream `UpdateApproveEnabled`).
    public var isApproveEnabled: Bool { gates.allSatisfy(\.isOn) }
    /// The triggers the user leaves off, asked about before approving (upstream "Triggers Left Off").
    public var leftOffTriggers: [String] { triggers.filter { !$0.isOn && !$0.isDisabledInRecipe }.map(\.title) }
    /// The AI tool's name and its own words, shown as the AI's (untrusted) text.
    public var proposedBy: String? { request.proposedBy }
    public var aiRequest: String? { Self.nonEmpty(request.aiRequest) }
    public var aiExplanation: String? { Self.nonEmpty(request.aiExplanation) }
    public var hasDiff: Bool { request.diff?.contains { $0.kind != .unchanged } ?? false }
    /// The hint the library found for the whole file (validation error).
    public var overallHint: String? { Self.nonEmpty(request.hint) }

    public mutating func setTrigger(_ key: String, on: Bool) {
        guard let index = triggers.firstIndex(where: { $0.id == key }) else { return }
        triggers[index].isOn = on
    }

    public mutating func setGate(_ gate: RecipeGateType, on: Bool) {
        guard let index = gates.firstIndex(where: { $0.gate == gate }) else { return }
        gates[index].isOn = on
    }

    /// The answer for Approve; nil while a permission is off (Approve is disabled then).
    public func approval(openInEditor: Bool) -> RecipeApprovalDecision? {
        guard isDecision, isApproveEnabled else { return nil }
        let approval = RecipeApproval(recipeId: request.recipe?.id ?? "", approvedTriggers: triggers.filter(\.isOn).map(\.id),
                                      allowedGates: gates.filter(\.isOn).map(\.gate))
        return RecipeApprovalDecision(approval: approval, openInEditor: openInEditor && offersOpenInEditor)
    }

    /// "Triggers Left Off" text, nil when none is left off.
    public var leftOffText: String? {
        let off = leftOffTriggers
        guard !off.isEmpty else { return nil }
        let intro = off.count == 1 ? "This trigger stays off, so it won't start the recipe:" : "These triggers stay off, so they won't start the recipe:"
        return intro + "\n\n" + off.map { "• " + $0 }.joined(separator: "\n")
            + "\n\nYou can switch triggers on later with Permissions, and run the recipe from the recipe list."
    }

    /// The question before "Revoke Approval" (upstream `OnRejectClicked`).
    public var revokeText: String {
        "Revoke the approval of “\(recipeName)”? It stops running right away and isn't loaded again. Its file stays where it is: "
            + "open it again to review and approve it."
    }

    // MARK: Texts

    static func isAIProposal(_ request: RecipeApprovalRequest) -> Bool {
        guard nonEmpty(request.proposedBy) != nil, !request.isReadOnly, request.mode != .reVerify else { return false }
        return nonEmpty(request.aiRequest) != nil || nonEmpty(request.aiExplanation) != nil || request.mode == .newRecipe
    }

    static func nonEmpty(_ text: String?) -> String? {
        guard let trimmed = text?.trimmingCharacters(in: .whitespacesAndNewlines), !trimmed.isEmpty else { return nil }
        return trimmed
    }

    struct Texts {
        var subtitle: String
        var title: String
        var description: String
        var badge: String
        var tone: Tone
        var icon: String
        var approve: String
    }

    /// Upstream RecipeApprovalWindow.xaml.cs:250-361 and `ApplyExtensionTexts` (:464-513); "PC" is "Mac" here.
    static func texts(style: Style, request: RecipeApprovalRequest, isExtension: Bool) -> Texts {
        // The reasons are trigger labels and sentences: each one ends with a full stop here.
        let reasons = (request.ownEditReasons ?? []).map { $0.hasSuffix(".") ? $0 : $0 + "." }.joined(separator: " ")
        var texts: Texts
        switch style {
        case .validationError:
            texts = Texts(subtitle: "Recipe Validation Failed", title: "Recipe Validation Failed",
                          description: "Greenshot could not load or register this capture recipe because it contains configuration errors. Review the diagnostic details below:",
                          badge: "VALIDATION ERROR", tone: .error, icon: "xmark.octagon", approve: "Close")
        case .details:
            let builtIn = request.fileURL == nil
            texts = Texts(subtitle: "Recipe Details", title: "Recipe Details",
                          description: builtIn ? "What this built-in recipe does and which triggers start it."
                              : "What this recipe does and what you approved for it. Nothing can be changed here, use Permissions in Settings › Recipes or in the recipe manager for that.",
                          badge: builtIn ? "BUILT-IN" : "APPROVED", tone: .neutral, icon: "doc.text", approve: "Close")
        case .aiProposal:
            texts = Texts(subtitle: "Recipe Proposed by an AI Tool",
                          title: request.replacedRecipe != nil ? "An AI Tool Wants to Change a Recipe" : "An AI Tool Proposes a Recipe",
                          description: "This recipe was written by an AI tool, not by Greenshot or by you. Check what it does below (Greenshot describes it from the recipe itself) and switch on only the triggers you want.",
                          badge: "PROPOSED BY AI", tone: .warning, icon: "sparkles", approve: "Save Recipe")
        case .ownEdit:
            texts = Texts(subtitle: "Approve Your Changes", title: "Your Change Needs a Decision",
                          description: "You saved this recipe in the recipe editor. Most changes are approved without asking, but this one adds something that needs your decision: " + reasons,
                          badge: "YOUR CHANGE", tone: .accent, icon: "checkmark.shield", approve: "Approve & Save")
        case .modified:
            texts = Texts(subtitle: "Recipe Modification Detected", title: "Recipe Changed Outside Greenshot",
                          description: "You approved this capture recipe before, but its file was changed outside Greenshot since then (by another program or by hand). Review the changes below before approving them.",
                          badge: "MODIFIED ON DISK", tone: .warning, icon: "exclamationmark.triangle", approve: "Approve Changes")
        case .review:
            texts = Texts(subtitle: "Recipe Security Review", title: "Capture Recipe Review",
                          description: "Change which triggers may start this recipe and what it may do. “Keep as Is” or closing the window changes nothing.",
                          badge: "ALREADY APPROVED", tone: .neutral, icon: "checkmark.shield", approve: "Save Changes")
        case .newRecipe:
            texts = Texts(subtitle: "Recipe Security Approval", title: "External Capture Recipe Detected",
                          description: "A new capture recipe file is requesting to be registered into Greenshot. Review its details, triggers, and execution steps before approving.",
                          badge: "NEW RECIPE", tone: .accent, icon: "checkmark.shield", approve: "Approve & Enable")
        }
        guard isExtension else { return texts }
        switch style {
        case .validationError:
            texts.subtitle = "Automatic Step Validation Failed"
            texts.title = "Automatic Step Validation Failed"
            texts.description = "Greenshot could not use this automatic step because it contains errors. Review the details below:"
        case .details:
            texts.subtitle = "Automatic Step Details"
            texts.title = "Automatic Step Details"
            texts.description = "What this automatic step does, which recipes it changes and what you approved for it."
        case .aiProposal:
            texts.subtitle = "Automatic Step Proposed by an AI Tool"
            texts.title = "An AI Tool Proposes an Automatic Step"
            texts.description = "This automatic step was written by an AI tool. It changes other recipes, the built-in ones included: check which ones and what it adds below. It starts switched off, switch it on in Settings › Recipes."
        case .modified:
            texts.subtitle = "Automatic Step Modification Detected"
            texts.title = "Automatic Step Changed Outside Greenshot"
            texts.description = "You approved this automatic step before, but its file was changed outside Greenshot since then. Until you approve the changes, it doesn't change any recipe."
        case .review:
            texts.subtitle = "Automatic Step Review"
            texts.title = "Automatic Step Review"
            texts.description = "Change what this automatic step may do. “Keep as Is” or closing the window changes nothing."
        case .ownEdit:
            texts.description = "You saved this automatic step in the recipe editor. Most changes are approved without asking, but this one needs your decision: " + reasons
        case .newRecipe:
            texts.subtitle = "Automatic Step Approval"
            texts.title = "Automatic Step File Detected"
            texts.description = "A file wants to add an automatic step to other recipes, the built-in ones included. Review which recipes it changes and what it adds before approving."
            texts.badge = "NEW AUTOMATIC STEP"
        }
        return texts
    }

    /// Upstream `GetGateQuestion`.
    static func question(for gate: RecipeGateType) -> String {
        switch gate {
        case .externalCommand: return "Allow this recipe to run programs on this Mac"
        case .networkAccess: return "Allow this recipe to upload captures to the internet"
        case .fileSystemAccess: return "Allow this recipe to read or write these files and folders"
        case .custom: return "Allow these actions"
        }
    }

    /// Upstream `GetGateExplanation`.
    static func explanation(for gate: RecipeGateType) -> String? {
        switch gate {
        case .externalCommand: return "A program started by a recipe can do anything you can do on this Mac."
        case .networkAccess: return "What is uploaded leaves this Mac, the service decides who can see it."
        case .fileSystemAccess: return "The recipe works with files outside Greenshot's usual output folder."
        case .custom: return nil
        }
    }
}

/// What to change for a validation error (upstream `RecipeValidationErrorViewModel.Create`, with the Mac's messages).
public enum RecipeValidationHints {
    public static func hint(for message: String) -> String? {
        func has(_ text: String) -> Bool { message.range(of: text, options: .caseInsensitive) != nil }
        if has("not valid JSON") || (has("line") && has("position")) {
            return "Check the recipe JSON syntax for unescaped quotes, trailing commas, or mismatched brackets."
        }
        if has("which is not available in this version") {
            return "Use a step type this version of Greenshot for Mac has, or update Greenshot."
        }
        if has("which is not available because the required") || has("requires the extension") {
            return "The recipe needs a plug-in Greenshot for Mac doesn't have."
        }
        if has("Unknown SourceType") {
            return "Valid SourceType values are: Region, Window, ActiveWindow, FullScreen, LastRegion, Clipboard, File, TextOcr, CurrentEditor, Extension."
        }
        if has("does not exist in 'nodes'") || has("does not match any defined node id") {
            return "Verify that the target node ID matches an existing node's 'id' in the recipe's 'nodes' list."
        }
        if has("Duplicate node id") { return "Each node in the recipe must have a unique 'id'." }
        if has("Cycle/loop") {
            return "Recipes must form a directed acyclic graph (DAG). Make sure transitions and fallbacks don't loop back to earlier nodes."
        }
        if has("'id' is required") || has("'name' is required") {
            return "Every recipe requires a unique 'id' and a descriptive 'name' property."
        }
        if has("invalid hotkey") || has("missing required 'Hotkey'") {
            return "Write the hotkey like \"Ctrl + Shift + B\"; on the Mac Ctrl is ⌘ and Win is ⌃."
        }
        if has("in its Filter") { return "Write the extensions with their dot, separated by ';', e.g. \".png;.jpg\"." }
        if has("'ToolName'") { return "Give the AI tool trigger a 'ToolName' of letters, digits, '_' or '-'." }
        if has("Option key") || has("Option '") { return "Check the recipe's 'options': keys, types, defaults and choices." }
        return nil
    }
}
