// Greenshot for Mac (Community) - an unofficial macOS port of Greenshot
// Copyright (C) 2026 Greenshot for Mac (Community) contributors
// Based on Greenshot, Copyright (C) 2007-2026 Thomas Braun, Jens Klingen, Robin Krom
// SPDX-License-Identifier: GPL-3.0-or-later

import CoreGraphics
import Foundation

/// The lifecycle of a flow (upstream `CaptureFlowState`).
public enum RecipeFlowState: String, Sendable, Codable, CaseIterable {
    case notStarted = "NotStarted"
    case acquiring = "Acquiring"
    case selecting = "Selecting"
    case processing = "Processing"
    case exporting = "Exporting"
    case completed = "Completed"
    case cancelled = "Cancelled"
    case failed = "Failed"
}

/// Who started a flow and what the world looked like then (upstream `FlowTriggerContext`, snapshotted synchronously
/// where the trigger fired).
public struct RecipeTriggerInfo: Sendable, Equatable {
    public var triggerType: String
    public var triggerName: String?
    /// The index of the trigger in the recipe, nil for a start without one (menu, test run, forwarding).
    public var triggerIndex: Int?
    public var triggeredAt: Date
    /// The frontmost application then (nil: Greenshot itself or unknown).
    public var frontmostProcessID: Int32?
    public var cursorLocation: CGPoint?

    public init(triggerType: String, triggerName: String? = nil, triggerIndex: Int? = nil, triggeredAt: Date = Date(),
                frontmostProcessID: Int32? = nil, cursorLocation: CGPoint? = nil) {
        self.triggerType = triggerType
        self.triggerName = triggerName
        self.triggerIndex = triggerIndex
        self.triggeredAt = triggeredAt
        self.frontmostProcessID = frontmostProcessID
        self.cursorLocation = cursorLocation
    }
}

/// Where Stdout and Stderr steps write (upstream `StdoutWriter`/`StderrWriter`): the CLI or AI-tool caller (AUT).
public protocol RecipeOutputSink: Sendable {
    func writeStdout(_ text: String) async
    func writeStderr(_ text: String) async
}

/// One export of a flow (upstream `ExportOutcome`), for the Notification step and the failure notification.
public struct RecipeExportOutcome: Sendable, Equatable {
    /// The designation of the destination that exported ("Clipboard", "FileNoDialog", "Jira").
    public var designation: String
    public var succeeded: Bool
    /// The file, URL or name it went to.
    public var target: String?
    public var uri: URL?
    public var errorMessage: String?

    public init(designation: String, succeeded: Bool, target: String? = nil, uri: URL? = nil, errorMessage: String? = nil) {
        self.designation = designation
        self.succeeded = succeeded
        self.target = target
        self.uri = uri
        self.errorMessage = errorMessage
    }
}

/// The exports of one flow, shared by its branch contexts (upstream `ExportLog`). Thread safe.
public final class RecipeExportLog: @unchecked Sendable {
    private let lock = NSLock()
    private var outcomes: [RecipeExportOutcome] = []
    private var notified = 0

    public init() {}

    public func add(_ outcome: RecipeExportOutcome) {
        lock.withLock { outcomes.append(outcome) }
    }

    public var all: [RecipeExportOutcome] { lock.withLock { outcomes } }

    /// The exports since the last call (a recipe with two Notification steps doesn't show an export twice).
    public func takeUnnotified() -> [RecipeExportOutcome] {
        lock.withLock {
            let unnotified = Array(outcomes[notified...])
            notified = outcomes.count
            return unnotified
        }
    }
}

/// The execution log of a flow, shared by its branch contexts.
final class RecipeExecutionLog: @unchecked Sendable {
    private let lock = NSLock()
    private var lines: [String] = []
    private static let timeFormat: DateFormatter = {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.timeZone = TimeZone(identifier: "UTC")
        formatter.dateFormat = "HH:mm:ss.SSS"
        return formatter
    }()

    func add(_ message: String) {
        let line = "[\(Self.timeFormat.string(from: Date()))] \(message)"
        lock.withLock { lines.append(line) }
    }

    var all: [String] { lock.withLock { lines } }
}

/// The state of one running flow (upstream `CaptureFlowContext`), handed to every step. Thread safe; a parallel branch
/// works on its own copy (`makeBranch()`), which shares the export log and the output sink.
public final class RecipeFlowContext: @unchecked Sendable {
    public let executionId: UUID
    /// The recipe as it runs (prepared for its trigger).
    public let recipe: CaptureRecipe
    public let trigger: RecipeTriggerInfo?
    public let environment: any RecipeEnvironment
    public let evaluator: ExpressionEvaluator
    /// The user's option values when the flow started.
    public let optionValues: RecipeOptionValues
    public let output: (any RecipeOutputSink)?
    public let exports: RecipeExportLog

    public init(recipe: CaptureRecipe, trigger: RecipeTriggerInfo? = nil, environment: any RecipeEnvironment,
                optionValues: RecipeOptionValues = RecipeOptionValues(), output: (any RecipeOutputSink)? = nil,
                executionId: UUID = UUID()) {
        self.executionId = executionId
        self.recipe = recipe
        self.trigger = trigger
        self.environment = environment
        self.evaluator = ExpressionEvaluator(environment: environment)
        self.optionValues = optionValues
        self.output = output
        self.exports = RecipeExportLog()
        self.sharedLog = RecipeExecutionLog()
    }

    /// A branch: shares the id, the export log, the output and the execution log.
    private init(branchOf parent: RecipeFlowContext, state: State) {
        self.executionId = parent.executionId
        self.recipe = parent.recipe
        self.trigger = parent.trigger
        self.environment = parent.environment
        self.evaluator = parent.evaluator
        self.optionValues = parent.optionValues
        self.output = parent.output
        self.exports = parent.exports
        self.sharedLog = parent.sharedLog
        self.current = state
    }

    private struct State {
        var payload: RecipePayload?
        var isPayloadPreSupplied = false
        var state = RecipeFlowState.notStarted
        var exitCode = 0
        var abortReason: String?
        var errorDescription: String?
        var variables = RecipeVariables()
        var objects: [String: (key: String, value: any Sendable)] = [:]
    }

    private let lock = NSLock()
    private var current = State()
    private let sharedLog: RecipeExecutionLog

    private func read<T>(_ body: (State) -> T) -> T {
        lock.withLock { body(current) }
    }

    private func write(_ body: (inout State) -> Void) {
        lock.withLock { body(&current) }
    }

    public var payload: RecipePayload? {
        get { read { $0.payload } }
        set { write { $0.payload = newValue } }
    }
    /// The payload was handed to the flow (forwarded, from the browser extension or the editor): Source keeps it,
    /// InteractiveSelection and ImmediateFeedback skip (upstream `IsPayloadPreSupplied`).
    public var isPayloadPreSupplied: Bool {
        get { read { $0.isPayloadPreSupplied } }
        set { write { $0.isPayloadPreSupplied = newValue } }
    }
    public var state: RecipeFlowState {
        get { read { $0.state } }
        set { write { $0.state = newValue } }
    }
    public var exitCode: Int {
        get { read { $0.exitCode } }
        set { write { $0.exitCode = newValue } }
    }
    public var abortReason: String? { read { $0.abortReason } }
    public var errorDescription: String? { read { $0.errorDescription } }
    /// Cancelled or failed.
    public var isAborted: Bool { read { $0.state == .cancelled || $0.state == .failed } }

    public func abort(_ reason: String) {
        write {
            $0.state = .cancelled
            $0.abortReason = reason
        }
        log("Flow cancelled: \(reason)")
    }

    public func fail(_ reason: String, error: Error? = nil) {
        write {
            $0.state = .failed
            $0.abortReason = reason
            $0.errorDescription = error.map { $0.localizedDescription }
        }
        log("Flow failed: \(reason)")
    }

    /// A flow variable, case-insensitive (upstream `Properties`).
    public subscript(variable name: String) -> JSONValue? {
        get { read { $0.variables[name] } }
        set { write { $0.variables[name] = newValue } }
    }
    public var variables: RecipeVariables { read { $0.variables } }
    /// Host objects that aren't values (the editor of an Editor trigger as "EditorForm", a chosen window as
    /// "SelectedWindow"); not readable by expressions. Case-insensitive keys.
    public func object(forKey key: String) -> (any Sendable)? { read { $0.objects[key.lowercased()]?.value } }
    public func setObject(_ object: (any Sendable)?, forKey key: String) {
        write { state in
            if let object { state.objects[key.lowercased()] = (key, object) } else { state.objects[key.lowercased()] = nil }
        }
    }

    public func log(_ message: String) { sharedLog.add(message) }
    public var executionLog: [String] { sharedLog.all }

    /// The scope for expressions now: the variables, `payload.*` and the recipe's options.
    public func scope(extraVariables: [String: JSONValue] = [:]) -> ExpressionScope {
        let snapshot = read { $0 }
        let recipe = self.recipe
        let values = optionValues
        return ExpressionScope(variables: snapshot.variables, payload: snapshot.payload?.metrics,
                               option: { key in
                                   // `option.<key>` of the recipe, or of an automatic step it was composed with (RMANAGER).
                                   guard let resolved = RecipeComposer.resolveOption(key, in: recipe) else { return nil }
                                   return (value: values.value(of: resolved.option, recipeId: resolved.ownerId),
                                           isTemplate: resolved.option.isTemplate)
                               },
                               extraVariables: extraVariables, recipeId: recipe.id, recipeName: recipe.name,
                               executionId: executionId.uuidString, state: snapshot.state.rawValue, abortReason: snapshot.abortReason)
    }

    /// A copy for a parallel branch: variables, payload and objects copied; export log, output and id shared.
    public func makeBranch() -> RecipeFlowContext {
        RecipeFlowContext(branchOf: self, state: read { $0 })
    }

    /// After a branch: its variables into this context (upstream `foreach Properties`), then its outcome
    /// (upstream `MergeOutcome`): the first non-zero exit code, a failure, a cancellation.
    func merge(branch: RecipeFlowContext, variables mergeVariables: Bool) {
        let child = branch.read { $0 }
        write { state in
            if mergeVariables {
                for member in child.variables { state.variables[member.key] = member.value }
            }
            if child.exitCode != 0, state.exitCode == 0 { state.exitCode = child.exitCode }
            if child.state == .failed, state.state != .failed {
                state.state = .failed
                state.abortReason = child.abortReason
                state.errorDescription = child.errorDescription
            } else if child.state == .cancelled, state.state != .cancelled, state.state != .failed {
                state.state = .cancelled
                state.abortReason = child.abortReason
            }
        }
    }

    /// The host objects as given (for a forwarded flow).
    var objects: [String: any Sendable] {
        read { state in Dictionary(uniqueKeysWithValues: state.objects.values.map { ($0.key, $0.value) }) }
    }
}
