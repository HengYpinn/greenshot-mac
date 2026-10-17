// Greenshot for Mac (Community) - an unofficial macOS port of Greenshot
// Copyright (C) 2026 Greenshot for Mac (Community) contributors
// Based on Greenshot, Copyright (C) 2007-2026 Thomas Braun, Jens Klingen, Robin Krom
// SPDX-License-Identifier: GPL-3.0-or-later

import CoreGraphics
import Foundation

/// Executes a recipe on a context to the end (upstream `DagExecutionEngine`): start nodes; fork into merge clusters
/// (siblings that meet again run one after the other on the same context, independent ones in parallel on branch
/// copies, merged back after); join when all parents finished or were bypassed; Conditional's first true branch and
/// UserPrompt's choice with dead-path elimination; disabled nodes pass the flow on; error transitions and
/// `onErrorNodeId`/`onErrorRecipeId` with `LastError`, `LastErrorType`, `FailedNodeId`; cancellation aborts.
public struct RecipeFlowEngine: Sendable {
    public init(steps: RecipeStepRegistry,
                recipeLookup: @escaping @Sendable (String) async -> CaptureRecipe? = { _ in nil },
                checkContracts: Bool = false,
                events: (@Sendable (RecipeFlowEvent) -> Void)? = nil) { rcoreStub() }
    public func execute(_ context: RecipeFlowContext) async { rcoreStub() }
}
