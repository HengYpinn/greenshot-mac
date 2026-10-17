// Greenshot for Mac (Community) - an unofficial macOS port of Greenshot
// Copyright (C) 2026 Greenshot for Mac (Community) contributors
// Based on Greenshot, Copyright (C) 2007-2026 Thomas Braun, Jens Klingen, Robin Krom
// SPDX-License-Identifier: GPL-3.0-or-later

import CoreGraphics
import Foundation

/// Errors stop a recipe from loading, warnings are shown (upstream `RecipeValidationResult`).
public struct RecipeValidationResult: Sendable, Equatable {
    public var errors: [String] = []
    public var warnings: [String] = []
    /// Every gated action of the recipe, once.
    public var gatedActions: [RecipeGatedAction] = []

    public init() {}

    public var isValid: Bool { errors.isEmpty }
    /// The kinds of gated actions, sorted (upstream `RecipeApprovalPolicy.GetGateTypes`).
    public var gateTypes: [RecipeGateType] { Array(Set(gatedActions.map(\.gateType))).sorted() }
}

/// Structural rules (header, triggers, nodes, options, flow, cycles) then, when valid, the contract warnings
/// (upstream `RecipeValidator.Validate`). The messages are upstream's; they are the editor's diagnostics too.
public struct RecipeValidator: Sendable {
    public init(contracts: StepContractCatalog = .builtIn, triggers: TriggerContractCatalog = .builtIn,
                requirements: RecipeRequirementCatalog = .builtIn, gates: GateEnvironment = .empty) { rcoreStub() }
    public func validate(_ recipe: CaptureRecipe) -> RecipeValidationResult { rcoreStub() }
}
