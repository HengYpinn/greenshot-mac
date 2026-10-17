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
    public init(contracts: StepContractCatalog = .builtIn, gates: GateEnvironment = .empty) { rcoreStub() }
    public func describeTriggers(_ recipe: CaptureRecipe) -> [RecipeTriggerDescription] { rcoreStub() }
    public func describeSteps(_ recipe: CaptureRecipe) -> [RecipeDescriptionLine] { rcoreStub() }
    /// "Adds: ..." / "Removes: ..." between two versions.
    public func describeChanges(from old: CaptureRecipe?, to new: CaptureRecipe?) -> [String] { rcoreStub() }
    /// "Uploads to Jira", "Runs the program /usr/local/bin/pngquant", or the file-access text.
    public func describe(_ action: RecipeGatedAction) -> String { rcoreStub() }
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
