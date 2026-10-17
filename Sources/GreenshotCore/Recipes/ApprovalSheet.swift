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

        let fallbackName = request.fileURL?.lastPathComponent ?? String(localized: "Unnamed Recipe")
        let name = recipe?.name.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        recipeName = name.isEmpty ? fallbackName : name
        let version = recipe?.version.trimmingCharacters(in: .whitespaces) ?? ""
        recipeVersion = version.isEmpty ? "" : "v\(version)"
        let description = recipe?.description?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        if !description.isEmpty {
            recipeDescription = description
        } else if isValidationError {
            recipeDescription = isExtension ? String(localized: "Automatic step configuration failed validation.")
                : String(localized: "Recipe configuration failed validation.")
        } else {
            recipeDescription = String(localized: "No description provided.")
        }
        recipeId = recipe?.id ?? String(localized: "unknown", comment: "The recipe file has no readable ID")
        fileText = request.fileURL?.path ?? String(localized: "Built into Greenshot")
        fileHash = request.contentHash.isEmpty ? String(localized: "Unknown", comment: "The checksum of the recipe file is not known") : request.contentHash
        if let record = request.previousRecord, style == .modified || style == .review || style == .ownEdit || style == .details {
            previousApprovedAt = record.approvedAt
            previousHash = record.sha256
        } else {
            previousApprovedAt = nil
            previousHash = nil
        }

        let texts = Self.texts(style: style, request: request, isExtension: isExtension)
        windowTitle = String(localized: "Greenshot — \(texts.subtitle)", comment: "Window title; %@ is e.g. \"Recipe Details\"")
        headerTitle = texts.title
        headerDescription = texts.description
        badge = texts.badge
        badgeTone = texts.tone
        icon = texts.icon
        approveTitle = texts.approve
        rejectTitle = style == .review ? String(localized: "Revoke Approval") : String(localized: "Reject / Block")

        // What changed: against the replaced recipe (built-in) or the previously approved version.
        if let replaced = request.replacedRecipe {
            changesTitle = Self.changesTitle(replacing: replaced.name, builtIn: request.replacesBuiltIn, isExtension: isExtension)
        } else if request.mode == .modified || (style == .ownEdit && request.previousContent != nil) {
            changesTitle = request.previousContent != nil ? String(localized: "What changed since the last approval")
                : String(localized: "The previous version is not known, review the whole recipe")
        } else {
            changesTitle = nil
        }
        if changesTitle != nil, request.previousContent != nil, !isValidationError {
            changeLines = request.changes.isEmpty ? [String(localized: "No change in what the recipe does (only details like names or layout).")] : request.changes
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
                                                     title: trigger.isDisabled ? Self.disabledTitle(trigger.label) : trigger.label,
                                                     explanation: trigger.risk, isDisabledInRecipe: trigger.isDisabled, isOn: isOn))
            }
        }
        triggers = triggerSwitches
        let switchedOffHint = request.suggestedApproval == nil && startOff
        triggerHint = switchedOffHint
            ? String(localized: "The triggers start switched off. Switch on each one that may start this recipe: a trigger you leave off stays off (you can switch it on later with Permissions). Without a trigger you can still run the recipe from the recipe list.")
            : String(localized: "Switch off the triggers you don't want.")
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
                gateSwitches.append(GateSwitch(gate: gate, question: Self.question(for: gate, isExtension: isExtension), explanation: Self.explanation(for: gate),
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
            if messages.isEmpty { messages = [String(localized: "The recipe file could not be read.")] }
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

    /// How long Approve stays unavailable when the window came up on its own (S-N2).
    public static let armingDelay: TimeInterval = 1.0

    /// Whether Approve waits `armingDelay` before it can be clicked: the window opened on its own (Greenshot wasn't the
    /// active app: launch, a changed file, a run's check, an AI tool), or it asks about an AI tool's proposal or a file
    /// changed outside Greenshot, so a click or key meant for something else can't approve it. Approve is never the
    /// default (Return) button either. Read-only windows and validation errors decide nothing.
    public static func needsArmingDelay(_ request: RecipeApprovalRequest, appWasActive: Bool) -> Bool {
        let sheet = RecipeApprovalSheet(request: request)
        guard sheet.isDecision else { return false }
        if !appWasActive { return true }
        return sheet.style == .aiProposal || sheet.style == .modified
    }
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
        let intro = off.count == 1 ? String(localized: "This trigger stays off, so it won't start the recipe:")
            : String(localized: "These triggers stay off, so they won't start the recipe:")
        let closing = String(localized: "You can switch triggers on later with Permissions, and run the recipe from the recipe list.")
        return intro + "\n\n" + off.map { "• " + $0 }.joined(separator: "\n") + "\n\n" + closing
    }

    /// "recipe", or "automatic step" for an extension file, in the window's texts (in the app's language; prefer whole
    /// sentences per `isExtension` to building them from this word).
    public var noun: String {
        isExtension ? String(localized: "automatic step", comment: "What the approval window is about, inside a sentence")
            : String(localized: "recipe", comment: "What the approval window is about, inside a sentence")
    }
    /// "Recipe" / "Automatic Step" for titles and buttons.
    public var titleNoun: String {
        isExtension ? String(localized: "Automatic Step", comment: "What the approval window is about, in a title or button")
            : String(localized: "Recipe", comment: "What the approval window is about, in a title or button")
    }

    /// The question before "Revoke Approval" (upstream `OnRejectClicked`).
    public var revokeText: String {
        String(localized: "Revoke the approval of “\(recipeName)”? It stops running right away and isn't loaded again. Its file stays where it is: open it again to review and approve it.")
    }

    // MARK: Texts

    /// "Replaces the built-in recipe “Region”", "Changes the automatic step “Border”".
    static func changesTitle(replacing name: String, builtIn: Bool, isExtension: Bool) -> String {
        switch (builtIn, isExtension) {
        case (true, false): return String(localized: "Replaces the built-in recipe “\(name)”")
        case (true, true): return String(localized: "Replaces the built-in automatic step “\(name)”")
        case (false, false): return String(localized: "Changes the recipe “\(name)”")
        case (false, true): return String(localized: "Changes the automatic step “\(name)”")
        }
    }

    /// A trigger the recipe itself switches off.
    static func disabledTitle(_ label: String) -> String {
        String(localized: "\(label) (disabled in the recipe)", comment: "%@ is a trigger of a recipe")
    }

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
            texts = Texts(subtitle: String(localized: "Recipe Validation Failed"), title: String(localized: "Recipe Validation Failed"),
                          description: String(localized: "Greenshot could not load or register this capture recipe because it contains configuration errors. Review the diagnostic details below:"),
                          badge: String(localized: "VALIDATION ERROR"), tone: .error, icon: "xmark.octagon", approve: String(localized: "Close"))
        case .details:
            let builtIn = request.fileURL == nil
            texts = Texts(subtitle: String(localized: "Recipe Details"), title: String(localized: "Recipe Details"),
                          description: builtIn ? String(localized: "What this built-in recipe does and which triggers start it.")
                              : String(localized: "What this recipe does and what you approved for it. Nothing can be changed here, use Permissions in Settings › Recipes or in the recipe manager for that."),
                          badge: builtIn ? String(localized: "BUILT-IN") : String(localized: "APPROVED"), tone: .neutral, icon: "doc.text", approve: String(localized: "Close"))
        case .aiProposal:
            texts = Texts(subtitle: String(localized: "Recipe Proposed by an AI Tool"),
                          title: request.replacedRecipe != nil ? String(localized: "An AI Tool Wants to Change a Recipe") : String(localized: "An AI Tool Proposes a Recipe"),
                          description: String(localized: "This recipe was written by an AI tool, not by Greenshot or by you. Check what it does below (Greenshot describes it from the recipe itself) and switch on only the triggers you want."),
                          badge: String(localized: "PROPOSED BY AI"), tone: .warning, icon: "sparkles", approve: String(localized: "Save Recipe"))
        case .ownEdit:
            texts = Texts(subtitle: String(localized: "Approve Your Changes"), title: String(localized: "Your Change Needs a Decision"),
                          description: String(localized: "You saved this recipe in the recipe editor. Most changes are approved without asking, but this one adds something that needs your decision: \(reasons)"),
                          badge: String(localized: "YOUR CHANGE"), tone: .accent, icon: "checkmark.shield", approve: String(localized: "Approve & Save"))
        case .modified:
            texts = Texts(subtitle: String(localized: "Recipe Modification Detected"), title: String(localized: "Recipe Changed Outside Greenshot"),
                          description: String(localized: "You approved this capture recipe before, but its file was changed outside Greenshot since then (by another program or by hand). Review the changes below before approving them."),
                          badge: String(localized: "MODIFIED ON DISK"), tone: .warning, icon: "exclamationmark.triangle", approve: String(localized: "Approve Changes"))
        case .review:
            texts = Texts(subtitle: String(localized: "Recipe Security Review"), title: String(localized: "Capture Recipe Review"),
                          description: String(localized: "Change which triggers may start this recipe and what it may do. “Keep as Is” or closing the window changes nothing."),
                          badge: String(localized: "ALREADY APPROVED"), tone: .neutral, icon: "checkmark.shield", approve: String(localized: "Save Changes"))
        case .newRecipe:
            texts = Texts(subtitle: String(localized: "Recipe Security Approval"), title: String(localized: "External Capture Recipe Detected"),
                          description: String(localized: "A new capture recipe file is requesting to be registered into Greenshot. Review its details, triggers, and execution steps before approving."),
                          badge: String(localized: "NEW RECIPE"), tone: .accent, icon: "checkmark.shield", approve: String(localized: "Approve & Enable"))
        }
        guard isExtension else { return texts }
        switch style {
        case .validationError:
            texts.subtitle = String(localized: "Automatic Step Validation Failed")
            texts.title = String(localized: "Automatic Step Validation Failed")
            texts.description = String(localized: "Greenshot could not use this automatic step because it contains errors. Review the details below:")
        case .details:
            texts.subtitle = String(localized: "Automatic Step Details")
            texts.title = String(localized: "Automatic Step Details")
            texts.description = String(localized: "What this automatic step does, which recipes it changes and what you approved for it.")
        case .aiProposal:
            texts.subtitle = String(localized: "Automatic Step Proposed by an AI Tool")
            texts.title = String(localized: "An AI Tool Proposes an Automatic Step")
            texts.description = String(localized: "This automatic step was written by an AI tool. It changes other recipes, the built-in ones included: check which ones and what it adds below. It starts switched off, switch it on in Settings › Recipes.")
        case .modified:
            texts.subtitle = String(localized: "Automatic Step Modification Detected")
            texts.title = String(localized: "Automatic Step Changed Outside Greenshot")
            texts.description = String(localized: "You approved this automatic step before, but its file was changed outside Greenshot since then. Until you approve the changes, it doesn't change any recipe.")
        case .review:
            texts.subtitle = String(localized: "Automatic Step Review")
            texts.title = String(localized: "Automatic Step Review")
            texts.description = String(localized: "Change what this automatic step may do. “Keep as Is” or closing the window changes nothing.")
        case .ownEdit:
            texts.description = String(localized: "You saved this automatic step in the recipe editor. Most changes are approved without asking, but this one needs your decision: \(reasons)")
        case .newRecipe:
            texts.subtitle = String(localized: "Automatic Step Approval")
            texts.title = String(localized: "Automatic Step File Detected")
            texts.description = String(localized: "A file wants to add an automatic step to other recipes, the built-in ones included. Review which recipes it changes and what it adds before approving.")
            texts.badge = String(localized: "NEW AUTOMATIC STEP")
        }
        return texts
    }

    /// Upstream `GetGateQuestion`, for a recipe or an automatic step (`isExtension`).
    static func question(for gate: RecipeGateType, isExtension: Bool = false) -> String {
        switch (gate, isExtension) {
        case (.externalCommand, false): return String(localized: "Allow this recipe to run programs on this Mac")
        case (.externalCommand, true): return String(localized: "Allow this automatic step to run programs on this Mac")
        case (.networkAccess, false): return String(localized: "Allow this recipe to upload captures to the internet")
        case (.networkAccess, true): return String(localized: "Allow this automatic step to upload captures to the internet")
        case (.fileSystemAccess, false): return String(localized: "Allow this recipe to read or write these files and folders")
        case (.fileSystemAccess, true): return String(localized: "Allow this automatic step to read or write these files and folders")
        case (.custom, _): return String(localized: "Allow these actions")
        }
    }

    /// Upstream `GetGateExplanation`.
    static func explanation(for gate: RecipeGateType) -> String? {
        switch gate {
        case .externalCommand: return String(localized: "A program started by a recipe can do anything you can do on this Mac.")
        case .networkAccess: return String(localized: "What is uploaded leaves this Mac, the service decides who can see it.")
        case .fileSystemAccess: return String(localized: "The recipe works with files outside Greenshot's usual output folder.")
        case .custom: return nil
        }
    }
}

/// What to change for a validation error (upstream `RecipeValidationErrorViewModel.Create`, with the Mac's messages). The
/// validator's messages are English (recipe-file data), so the patterns stay English; the hints are in the app's language.
public enum RecipeValidationHints {
    public static func hint(for message: String) -> String? {
        func has(_ text: String) -> Bool { message.range(of: text, options: .caseInsensitive) != nil }
        if has("not valid JSON") || (has("line") && has("position")) {
            return String(localized: "Check the recipe JSON syntax for unescaped quotes, trailing commas, or mismatched brackets.")
        }
        if has("which is not available in this version") {
            return String(localized: "Use a step type this version of Greenshot for Mac has, or update Greenshot.")
        }
        if has("which is not available because the required") || has("requires the extension") {
            return String(localized: "The recipe needs a plug-in Greenshot for Mac doesn't have.")
        }
        if has("Unknown SourceType") {
            return String(localized: "Valid SourceType values are: Region, Window, ActiveWindow, FullScreen, LastRegion, Clipboard, File, TextOcr, CurrentEditor, Extension.")
        }
        if has("does not exist in 'nodes'") || has("does not match any defined node id") {
            return String(localized: "Verify that the target node ID matches an existing node's 'id' in the recipe's 'nodes' list.")
        }
        if has("Duplicate node id") { return String(localized: "Each node in the recipe must have a unique 'id'.") }
        if has("Cycle/loop") {
            return String(localized: "Recipes must form a directed acyclic graph (DAG). Make sure transitions and fallbacks don't loop back to earlier nodes.")
        }
        if has("'id' is required") || has("'name' is required") {
            return String(localized: "Every recipe requires a unique 'id' and a descriptive 'name' property.")
        }
        if has("invalid hotkey") || has("missing required 'Hotkey'") {
            return String(localized: "Write the hotkey like \"Ctrl + Shift + B\"; on the Mac Ctrl is ⌘ and Win is ⌃.")
        }
        if has("in its Filter") { return String(localized: "Write the extensions with their dot, separated by ';', e.g. \".png;.jpg\".") }
        if has("'ToolName'") { return String(localized: "Give the AI tool trigger a 'ToolName' of letters, digits, '_' or '-'.") }
        if has("Option key") || has("Option '") { return String(localized: "Check the recipe's 'options': keys, types, defaults and choices.") }
        return nil
    }
}
