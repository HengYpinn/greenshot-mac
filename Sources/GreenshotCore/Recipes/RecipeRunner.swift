// Greenshot for Mac (Community) - an unofficial macOS port of Greenshot
// Copyright (C) 2026 Greenshot for Mac (Community) contributors
// Based on Greenshot, Copyright (C) 2007-2026 Thomas Braun, Jens Klingen, Robin Krom
// SPDX-License-Identifier: GPL-3.0-or-later

import CoreGraphics
import Foundation

/// Everything a start needs. The trigger hub, the CLI and the menu fill it.
public struct RecipeRunRequest: Sendable {
    public var recipe: CaptureRecipe
    public var trigger: RecipeTriggerInfo?
    /// Initial flow variables: bound arguments, "Filename" of an opened file, "PreSuppliedRegion", ...
    public var variables: [String: JSONValue] = [:]
    /// Initial host objects ("EditorForm", "TargetWindow").
    public var objects: [String: any Sendable] = [:]
    /// A capture handed to the flow (forwarded, browser extension, editor): `isPayloadPreSupplied` is set.
    public var payload: RecipePayload?
    public var output: (any RecipeOutputSink)?
    public var optionValues = RecipeOptionValues()
    /// Nil: the runner's environment.
    public var environment: (any RecipeEnvironment)?
    /// Runs once at the end, before the flow is gone (upstream `FlowFinishedAsync`): the CLI evaluates the trigger's
    /// `Stdout` and `--query` here with `context.evaluator.evaluate(_:in: context.scope())`.
    public var onFinish: (@Sendable (RecipeFlowContext) async -> Void)?

    public init(recipe: CaptureRecipe, trigger: RecipeTriggerInfo? = nil) {
        self.recipe = recipe
        self.trigger = trigger
    }
}

/// How a flow ended (upstream `CaptureFlowResult`). A flow never throws: errors end it as failed.
public struct RecipeFlowResult: Sendable {
    public var flowId: UUID
    public var recipeId: String
    public var recipeName: String
    /// Completed, cancelled or failed.
    public var state: RecipeFlowState
    public var reason: String?
    public var errorDescription: String?
    public var exitCode: Int
    public var variables: RecipeVariables
    public var executionLog: [String]
    public var exports: [RecipeExportOutcome]
    /// The final capture (nil when none was acquired or the flow didn't start).
    public var payload: RecipePayload?

    public init(flowId: UUID, recipeId: String, recipeName: String, state: RecipeFlowState, reason: String? = nil,
                errorDescription: String? = nil, exitCode: Int = 0, variables: RecipeVariables = RecipeVariables(),
                executionLog: [String] = [], exports: [RecipeExportOutcome] = [], payload: RecipePayload? = nil) {
        self.flowId = flowId
        self.recipeId = recipeId
        self.recipeName = recipeName
        self.state = state
        self.reason = reason
        self.errorDescription = errorDescription
        self.exitCode = exitCode
        self.variables = variables
        self.executionLog = executionLog
        self.exports = exports
        self.payload = payload
    }

    public var isSuccess: Bool { state == .completed }
}

/// What the runner reports while flows run: RAPP's failure notification (RCP-018) and running-flows list, AUT's
/// streaming. Delivered on an arbitrary thread.
public enum RecipeFlowEvent: Sendable {
    case flowStarted(flowId: UUID, recipeId: String, recipeName: String)
    /// A start that didn't run: exclusive recipe already running, a selection already open, shutting down.
    case flowRejected(recipeId: String, reason: String)
    case nodeStarted(flowId: UUID, nodeId: String, stepType: String)
    case nodeSkipped(flowId: UUID, nodeId: String, reason: String)
    case nodeFinished(flowId: UUID, nodeId: String)
    /// `handledBy`: the error node or recipe it went on with, nil when the flow failed.
    case nodeFailed(flowId: UUID, nodeId: String, message: String, handledBy: String?)
    case branchChosen(flowId: UUID, nodeId: String, branch: String?)
    /// Debug builds: a step did something its contract doesn't say (upstream `ContractViolation`).
    case contractViolation(flowId: UUID, message: String)
    case flowFinished(RecipeFlowResult)
}

/// A started flow (upstream `CaptureFlowHandle`).
public final class RecipeFlowHandle: Sendable {
    public let id: UUID
    public let recipeId: String
    public let recipeName: String

    public init(id: UUID, recipeId: String, recipeName: String, task: Task<RecipeFlowResult, Never>) { rcoreStub() }
    /// A start that was rejected; `result` is cancelled with the reason.
    public static func rejected(recipe: CaptureRecipe, reason: String) -> RecipeFlowHandle { rcoreStub() }
    /// Waits for the end; never throws.
    public var result: RecipeFlowResult { get async { rcoreStub() } }
    public func cancel() { rcoreStub() }
}

/// An observer registration; dropping it doesn't remove the observer, `cancel()` does.
public final class RecipeObservation: Sendable {
    public init(cancel: @escaping @Sendable () -> Void) { rcoreStub() }
    public func cancel() { rcoreStub() }
}

/// The one place that starts flows (upstream `CaptureFlowRunner`): runs each off the main thread, tracks the running
/// ones, applies the recipe's `concurrency`, refuses a second interactive selection, cancels everything on shutdown.
/// `start` returns at once. A flow runs `preflight`, then `RecipeTriggerPreparer.prepare` for the request's trigger type
/// (when it has a trigger), then the engine.
public final class RecipeRunner: @unchecked Sendable {
    /// - Parameters:
    ///   - preflight: before a flow starts: the recipe as it may run, nil to refuse (the library re-checks the approval
    ///     of a file recipe whose file changed, upstream `EnsureRecipeApprovedAndUpToDateAsync`).
    ///   - recipeLookup: for `onErrorRecipeId` / error transitions to another recipe.
    ///   - selectionInProgress: whether the capture screen is open (main actor); a recipe with an InteractiveSelection
    ///     node then brings it to the front via `bringSelectionToFront` and is rejected.
    public init(steps: RecipeStepRegistry,
                environment: @escaping @Sendable () -> any RecipeEnvironment,
                preflight: (@Sendable (CaptureRecipe) async -> CaptureRecipe?)? = nil,
                recipeLookup: @escaping @Sendable (String) async -> CaptureRecipe? = { _ in nil },
                selectionInProgress: (@MainActor @Sendable () -> Bool)? = nil,
                bringSelectionToFront: (@MainActor @Sendable () -> Void)? = nil) { rcoreStub() }

    @discardableResult
    public func start(_ request: RecipeRunRequest) -> RecipeFlowHandle { rcoreStub() }
    public var running: [RecipeFlowHandle] { rcoreStub() }
    public func addObserver(_ observer: @escaping @Sendable (RecipeFlowEvent) -> Void) -> RecipeObservation { rcoreStub() }
    /// Stops accepting flows, cancels the running ones and waits for them.
    public func shutdown() async { rcoreStub() }
}
