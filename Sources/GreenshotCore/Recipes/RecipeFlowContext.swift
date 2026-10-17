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
    public init() {}
    public func add(_ outcome: RecipeExportOutcome) { rcoreStub() }
    public var all: [RecipeExportOutcome] { rcoreStub() }
    /// The exports since the last call (a recipe with two Notification steps doesn't show an export twice).
    public func takeUnnotified() -> [RecipeExportOutcome] { rcoreStub() }
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
        rcoreStub()
    }

    public var payload: RecipePayload? {
        get { rcoreStub() }
        set { rcoreStub() }
    }
    /// The payload was handed to the flow (forwarded, from the browser extension or the editor): Source keeps it,
    /// InteractiveSelection and ImmediateFeedback skip (upstream `IsPayloadPreSupplied`).
    public var isPayloadPreSupplied: Bool {
        get { rcoreStub() }
        set { rcoreStub() }
    }
    public var state: RecipeFlowState {
        get { rcoreStub() }
        set { rcoreStub() }
    }
    public var exitCode: Int {
        get { rcoreStub() }
        set { rcoreStub() }
    }
    public var abortReason: String? { rcoreStub() }
    public var errorDescription: String? { rcoreStub() }
    /// Cancelled or failed.
    public var isAborted: Bool { rcoreStub() }
    public func abort(_ reason: String) { rcoreStub() }
    public func fail(_ reason: String, error: Error? = nil) { rcoreStub() }

    /// A flow variable, case-insensitive (upstream `Properties`).
    public subscript(variable name: String) -> JSONValue? {
        get { rcoreStub() }
        set { rcoreStub() }
    }
    public var variables: RecipeVariables { rcoreStub() }
    /// Host objects that aren't values (the editor of an Editor trigger as "EditorForm", a chosen window as
    /// "SelectedWindow"); not readable by expressions. Case-insensitive keys.
    public func object(forKey key: String) -> (any Sendable)? { rcoreStub() }
    public func setObject(_ object: (any Sendable)?, forKey key: String) { rcoreStub() }

    public func log(_ message: String) { rcoreStub() }
    public var executionLog: [String] { rcoreStub() }

    /// The scope for expressions now: the variables, `payload.*` and the recipe's options.
    public func scope(extraVariables: [String: JSONValue] = [:]) -> ExpressionScope { rcoreStub() }
    /// A copy for a parallel branch: variables, payload and objects copied; export log, output and id shared.
    public func makeBranch() -> RecipeFlowContext { rcoreStub() }
}
