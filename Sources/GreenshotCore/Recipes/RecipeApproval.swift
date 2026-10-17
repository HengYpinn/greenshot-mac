// Greenshot for Mac (Community) - an unofficial macOS port of Greenshot
// Copyright (C) 2026 Greenshot for Mac (Community) contributors
// Based on Greenshot, Copyright (C) 2007-2026 Thomas Braun, Jens Klingen, Robin Krom
// SPDX-License-Identifier: GPL-3.0-or-later

import CoreGraphics
import Foundation

/// What an approval means at run time (upstream `RecipeApprovalPolicy`).
public enum RecipeApprovalPolicy {
    public static let browserInvocationSuffix = ":browser"
    /// "<index>:<TriggerType>": the approval belongs to one content, so the position identifies the trigger.
    public static func triggerKey(index: Int, trigger: TriggerConfig) -> String { "\(index):\(trigger.triggerType)" }
    public static func browserInvocationKey(index: Int, trigger: TriggerConfig) -> String {
        triggerKey(index: index, trigger: trigger) + browserInvocationSuffix
    }
    /// The gate types the approval doesn't allow; the recipe isn't loaded while there are any.
    public static func missingGates(_ validation: RecipeValidationResult, approval: RecipeApproval?) -> [RecipeGateType] { rcoreStub() }
}

/// Why the approval sheet is shown (upstream `RecipeApprovalMode`).
public enum RecipeApprovalMode: String, Sendable, CaseIterable {
    /// A file not approved before.
    case newRecipe
    /// An approved file changed outside Greenshot.
    case modified
    /// "Permissions" / Review: change the switches of an approved recipe.
    case reVerify
    /// The file can't load: the problem, a hint and "Edit Recipe File".
    case validationError
}

/// What the approval sheet shows (upstream `RecipeApprovalRequest`), all computed by Core.
public struct RecipeApprovalRequest: Sendable {
    public var mode: RecipeApprovalMode
    /// Nil when the file couldn't be read as a recipe (validation-error mode with `errorMessage`).
    public var recipe: CaptureRecipe?
    public var fileURL: URL?
    /// The text that was read once: shown, parsed and hashed, so the approval is for exactly this.
    public var content: String
    public var contentHash: String
    public var validation: RecipeValidationResult?
    public var previousRecord: RecipeTrustRecord?
    /// "What it does", from the recipe (never from its description or an AI's words).
    public var steps: [RecipeDescriptionLine] = []
    public var triggers: [RecipeTriggerDescription] = []
    /// The gate types it needs, one permission switch each.
    public var gates: [RecipeGateType] = []
    /// Modified / replaces a built-in: "Adds: ..." / "Removes: ..." lines and the line diff against `previousContent`.
    public var changes: [String] = []
    public var previousContent: String?
    public var diff: [RecipeDiffLine]?
    public var replacesBuiltIn: Bool = false
    public var replacedRecipe: CaptureRecipe?
    /// The AI tool that proposed it and its own words (untrusted, shown as such).
    public var proposedBy: String?
    public var aiRequest: String?
    public var aiExplanation: String?
    /// Every trigger and permission starts switched off (AI proposals and files an AI tool wrote).
    public var startSwitchedOff: Bool = false
    /// Saved in Greenshot's recipe editor: why the change needs a decision.
    public var ownEditReasons: [String]?
    /// The switches as they start (own edit: unchanged triggers keep theirs, new harmless ones on).
    public var suggestedApproval: RecipeApproval?
    /// Details: nothing can be switched, only Close.
    public var isReadOnly: Bool = false
    /// Validation-error mode: the problem and a hint what to change.
    public var errorMessage: String?
    public var hint: String?

    public init(mode: RecipeApprovalMode, recipe: CaptureRecipe?, fileURL: URL?, content: String, contentHash: String) {
        self.mode = mode
        self.recipe = recipe
        self.fileURL = fileURL
        self.content = content
        self.contentHash = contentHash
    }
}

/// The user's answer (upstream `ApprovalResult`).
public struct RecipeApprovalDecision: Sendable, Equatable {
    public var approval: RecipeApproval?
    /// "Open in the recipe editor after saving".
    public var openInEditor: Bool
    /// "Revoke Approval" in a review.
    public var isRevoked: Bool

    public init(approval: RecipeApproval?, openInEditor: Bool = false, isRevoked: Bool = false) {
        self.approval = approval
        self.openInEditor = openInEditor
        self.isRevoked = isRevoked
    }

    public static let revoked = RecipeApprovalDecision(approval: nil, isRevoked: true)
}

/// Shows the approval sheet (RAPP). Nil: rejected, or closed without a change in a review.
@MainActor
public protocol RecipeApprover: AnyObject {
    func requestApproval(_ request: RecipeApprovalRequest) async -> RecipeApprovalDecision?
    /// Validation-error mode: shows the problem; nothing to decide.
    func showValidationError(_ request: RecipeApprovalRequest) async
}

/// What the user must decide about a change saved in the recipe editor (upstream `RecipeEditDecision`).
public struct RecipeEditDecision: Sendable, Equatable {
    public var reasons: [String] = []
    /// The keys of the new triggers it is about.
    public var triggerKeys: [String] = []

    public init() {}

    public var isNeeded: Bool { !reasons.isEmpty }
}

/// The approval of a recipe saved in the recipe editor (upstream `RecipeEditApproval`): renewed without asking, unless
/// the change adds a trigger that starts it on its own or from outside, a new kind of permission, or first replaces a
/// built-in recipe.
public enum RecipeEditApproval {
    public static func create(edited: CaptureRecipe, validation: RecipeValidationResult, approvedVersion: CaptureRecipe?,
                              previousApproval: RecipeApproval?, replacesBuiltIn: Bool) -> (approval: RecipeApproval, decision: RecipeEditDecision) {
        rcoreStub()
    }
    /// The recipe with the id in an approved content.
    public static func findRecipe(in content: String?, id: String) -> CaptureRecipe? { rcoreStub() }
}
