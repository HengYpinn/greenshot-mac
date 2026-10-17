// Greenshot for Mac (Community) - an unofficial macOS port of Greenshot
// Copyright (C) 2026 Greenshot for Mac (Community) contributors
// Based on Greenshot, Copyright (C) 2007-2026 Thomas Braun, Jens Klingen, Robin Krom
// SPDX-License-Identifier: GPL-3.0-or-later

import CoreGraphics
import Foundation

/// One node in the contract report (upstream `StepSummaryContract`).
public struct RecipeStepSummary: Sendable, Equatable {
    public var nodeId: String
    public var stepType: String
    public var displayName: String
    public var requiredInputs: [String]
    public var producedOutputs: [String]
    public var reachable: Bool
    /// Variables set on every path to the node (by earlier nodes or the trigger).
    public var guaranteedVariables: [String]

    public init(nodeId: String, stepType: String, displayName: String, requiredInputs: [String] = [],
                producedOutputs: [String] = [], reachable: Bool = true, guaranteedVariables: [String] = []) {
        self.nodeId = nodeId
        self.stepType = stepType
        self.displayName = displayName
        self.requiredInputs = requiredInputs
        self.producedOutputs = producedOutputs
        self.reachable = reachable
        self.guaranteedVariables = guaranteedVariables
    }
}

/// The contract of a recipe along its graph (upstream `RecipeContract`): what it needs from the caller, what it
/// produces, and the warnings of docs section 8. `--info` (AUT) prints it.
public struct RecipeContractReport: Sendable, Equatable {
    public var recipeId: String
    public var recipeName: String
    public var description: String
    public var inputs: [VariableContract]
    public var outputs: [VariableContract]
    public var steps: [RecipeStepSummary]
    public var warnings: [String]
    public var acquiresImage: Bool
    public var mutatesPixels: Bool
    public var extractsText: Bool

    public init(recipeId: String, recipeName: String, description: String = "", inputs: [VariableContract] = [],
                outputs: [VariableContract] = [], steps: [RecipeStepSummary] = [], warnings: [String] = [],
                acquiresImage: Bool = false, mutatesPixels: Bool = false, extractsText: Bool = false) {
        self.recipeId = recipeId
        self.recipeName = recipeName
        self.description = description
        self.inputs = inputs
        self.outputs = outputs
        self.steps = steps
        self.warnings = warnings
        self.acquiresImage = acquiresImage
        self.mutatesPixels = mutatesPixels
        self.extractsText = extractsText
    }
}

public enum RecipeContractAnalyzer {
    /// The variables the triggers hand to the flow, and whether one hands the image (upstream `GetTriggerInputs`).
    public static func triggerInputs(of recipe: CaptureRecipe) -> (inputs: [VariableContract], providesPayload: Bool) { rcoreStub() }
    public static func analyze(_ recipe: CaptureRecipe, contracts: StepContractCatalog = .builtIn) -> RecipeContractReport { rcoreStub() }
}
