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

    private let task: Task<RecipeFlowResult, Never>

    public init(id: UUID, recipeId: String, recipeName: String, task: Task<RecipeFlowResult, Never>) {
        self.id = id
        self.recipeId = recipeId
        self.recipeName = recipeName
        self.task = task
    }

    /// A start that was rejected; `result` is cancelled with the reason.
    public static func rejected(recipe: CaptureRecipe, reason: String) -> RecipeFlowHandle {
        let id = UUID()
        let result = RecipeFlowResult(flowId: id, recipeId: recipe.id, recipeName: recipe.name, state: .cancelled, reason: reason)
        return RecipeFlowHandle(id: id, recipeId: recipe.id, recipeName: recipe.name, task: Task { result })
    }

    /// Waits for the end; never throws.
    public var result: RecipeFlowResult { get async { await task.value } }

    public func cancel() { task.cancel() }
}

/// An observer registration; dropping it doesn't remove the observer, `cancel()` does.
public final class RecipeObservation: Sendable {
    private let onCancel: @Sendable () -> Void

    public init(cancel: @escaping @Sendable () -> Void) {
        onCancel = cancel
    }

    public func cancel() { onCancel() }
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
                bringSelectionToFront: (@MainActor @Sendable () -> Void)? = nil) {
        self.steps = steps
        self.environment = environment
        self.preflight = preflight
        self.recipeLookup = recipeLookup
        self.selectionInProgress = selectionInProgress
        self.bringSelectionToFront = bringSelectionToFront
    }

    private let steps: RecipeStepRegistry
    private let environment: @Sendable () -> any RecipeEnvironment
    private let preflight: (@Sendable (CaptureRecipe) async -> CaptureRecipe?)?
    private let recipeLookup: @Sendable (String) async -> CaptureRecipe?
    private let selectionInProgress: (@MainActor @Sendable () -> Bool)?
    private let bringSelectionToFront: (@MainActor @Sendable () -> Void)?

    private let lock = NSLock()
    private var flows: [(handle: RecipeFlowHandle, recipeId: String)] = []
    private var observers: [UUID: @Sendable (RecipeFlowEvent) -> Void] = [:]
    private var stopped = false

    #if DEBUG
    private static let checkContracts = true
    #else
    private static let checkContracts = false
    #endif

    @discardableResult
    public func start(_ request: RecipeRunRequest) -> RecipeFlowHandle {
        let recipe = request.recipe
        let decision: Result<RecipeFlowHandle, RejectedStart> = lock.withLock {
            if stopped { return .failure(RejectedStart(reason: "Greenshot is shutting down.")) }
            let sameRecipe = flows.filter { recipeEquals($0.recipeId, recipe.id) }.map(\.handle)
            switch recipe.concurrency ?? .parallel {
            case .exclusive where !sameRecipe.isEmpty:
                log.info("Recipe '\(recipe.id)' is exclusive and already running, ignoring the start.")
                return .success(sameRecipe[0])
            case .replacePrevious:
                for previous in sameRecipe {
                    log.info("Cancelling running flow \(previous.id) of recipe '\(recipe.id)', it is replaced.")
                    previous.cancel()
                }
            default:
                break
            }
            let id = UUID()
            let task = Task.detached(priority: .userInitiated) { [self] in
                await self.run(id: id, request: request)
            }
            let handle = RecipeFlowHandle(id: id, recipeId: recipe.id, recipeName: recipe.name, task: task)
            flows.append((handle, recipe.id))
            return .success(handle)
        }
        switch decision {
        case .success(let handle):
            return handle
        case .failure(let rejected):
            log.warn("Not starting recipe '\(recipe.id)': \(rejected.reason)")
            emit(.flowRejected(recipeId: recipe.id, reason: rejected.reason))
            return RecipeFlowHandle.rejected(recipe: recipe, reason: rejected.reason)
        }
    }

    private struct RejectedStart: Error {
        let reason: String
    }

    public var running: [RecipeFlowHandle] { lock.withLock { flows.map(\.handle) } }

    public func addObserver(_ observer: @escaping @Sendable (RecipeFlowEvent) -> Void) -> RecipeObservation {
        let id = UUID()
        lock.withLock { observers[id] = observer }
        return RecipeObservation { [weak self] in
            guard let self else { return }
            self.lock.withLock { self.observers[id] = nil }
        }
    }

    /// Stops accepting flows, cancels the running ones and waits for them.
    public func shutdown() async {
        let running: [RecipeFlowHandle] = lock.withLock {
            stopped = true
            return flows.map(\.handle)
        }
        guard !running.isEmpty else { return }
        log.info("Cancelling \(running.count) running flow(s) for shutdown")
        for handle in running { handle.cancel() }
        for handle in running { _ = await handle.result }
    }

    private func emit(_ event: RecipeFlowEvent) {
        let current = lock.withLock { Array(observers.values) }
        for observer in current { observer(event) }
    }

    private func finish(_ id: UUID) {
        lock.withLock { flows.removeAll { $0.handle.id == id } }
    }

    // MARK: One flow

    private func run(id: UUID, request: RecipeRunRequest) async -> RecipeFlowResult {
        defer { finish(id) }
        var recipe = request.recipe
        // Only one interactive selection at a time: a second start brings the open one to the front.
        if let selectionInProgress, recipe.firstNode(ofType: WellKnownStepType.interactiveSelection) != nil, await selectionInProgress() {
            if let bringSelectionToFront { await bringSelectionToFront() }
            let reason = "An interactive selection is already open."
            emit(.flowRejected(recipeId: recipe.id, reason: reason))
            return RecipeFlowResult(flowId: id, recipeId: recipe.id, recipeName: recipe.name, state: .cancelled, reason: reason)
        }
        emit(.flowStarted(flowId: id, recipeId: recipe.id, recipeName: recipe.name))
        if let preflight {
            guard let checked = await preflight(recipe) else {
                let result = RecipeFlowResult(flowId: id, recipeId: recipe.id, recipeName: recipe.name, state: .cancelled,
                                              reason: "Recipe execution aborted: approval denied or file verification failed.")
                emit(.flowFinished(result))
                return result
            }
            recipe = checked
        }
        if let trigger = request.trigger {
            recipe = RecipeTriggerPreparer.prepare(recipe, triggerType: trigger.triggerType)
        }
        let context = RecipeFlowContext(recipe: recipe, trigger: request.trigger, environment: request.environment ?? environment(),
                                        optionValues: request.optionValues, output: request.output, executionId: id)
        for (name, value) in request.variables { context[variable: name] = value }
        for (key, object) in request.objects { context.setObject(object, forKey: key) }
        if let payload = request.payload {
            context.payload = payload
            context.isPayloadPreSupplied = true
        }
        context.log("Starting DAG flow '\(recipe.name)' with \(recipe.nodes.count) configured node(s)")
        log.info("Starting recipe '\(recipe.id)' (\(recipe.nodes.count) node(s))")
        let engine = RecipeFlowEngine(steps: steps, recipeLookup: recipeLookup, checkContracts: Self.checkContracts,
                                      events: { [weak self] event in self?.emit(event) })
        await engine.execute(context)
        if Task.isCancelled, !context.isAborted {
            context.abort("Flow was cancelled.")
        }
        if !context.isAborted {
            context.state = .completed
            context.log("Capture flow completed successfully.")
        }
        if let onFinish = request.onFinish {
            await onFinish(context)
        }
        let result = RecipeFlowResult(flowId: id, recipeId: recipe.id, recipeName: recipe.name, state: context.state,
                                      reason: context.abortReason, errorDescription: context.errorDescription, exitCode: context.exitCode,
                                      variables: context.variables, executionLog: context.executionLog, exports: context.exports.all,
                                      payload: context.payload)
        if result.state == .failed {
            log.error("Recipe '\(recipe.id)' failed: \(result.reason ?? "")")
        }
        emit(.flowFinished(result))
        return result
    }
}

private let log = Log("Recipes")
