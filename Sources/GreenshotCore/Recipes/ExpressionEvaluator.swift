// Greenshot for Mac (Community) - an unofficial macOS port of Greenshot
// Copyright (C) 2026 Greenshot for Mac (Community) contributors
// Based on Greenshot, Copyright (C) 2007-2026 Thomas Braun, Jens Klingen, Robin Krom
// SPDX-License-Identifier: GPL-3.0-or-later

import CoreGraphics
import Foundation

/// Flow variables (upstream `CaptureFlowContext.Properties`): case-insensitive names, the spelling of the first set kept.
public struct RecipeVariables: Sendable, Equatable, Sequence {
    public init(_ values: [String: JSONValue] = [:]) { rcoreStub() }
    public subscript(name: String) -> JSONValue? {
        get { rcoreStub() }
        set { rcoreStub() }
    }
    public var names: [String] { rcoreStub() }
    public var count: Int { rcoreStub() }
    public func makeIterator() -> IndexingIterator<[JSONMember]> { rcoreStub() }
}

/// What `payload.*` reads (upstream `ResolvePayloadProperty`). Sizes are points (image pixels / pixels per point), the
/// unit of every geometry in a recipe on the Mac, see `RecipePayload`.
public struct PayloadMetrics: Sendable, Equatable {
    public var width: Double
    public var height: Double
    public var extractedText: String
    public var title: String
    public var filename: String
    public var metadata: [String: JSONValue]

    public init(width: Double, height: Double, extractedText: String = "", title: String = "", filename: String = "",
                metadata: [String: JSONValue] = [:]) {
        self.width = width
        self.height = height
        self.extractedText = extractedText
        self.title = title
        self.filename = filename
        self.metadata = metadata
    }
}

/// Everything an expression can read besides the environment. The runner makes it from the flow context
/// (`RecipeFlowContext.scope(extraVariables:)`); tests make it directly.
public struct ExpressionScope: Sendable {
    public var variables: RecipeVariables
    /// Nil before an image was acquired: `payload.*` is then 0, like upstream.
    public var payload: PayloadMetrics?
    /// `option.<key>`: the user's value of an option of the recipe (and its template flag), nil when not declared.
    /// Read before the variables, so a run can't override an option (upstream `ResolveSingleToken`).
    public var option: @Sendable (String) -> (value: JSONValue, isTemplate: Bool)?
    /// Node-local variables, read first (e.g. the Annotation step's surface size).
    public var extraVariables: [String: JSONValue]
    /// `context.RecipeId`, `context.RecipeName`, `context.ExecutionId`, `context.State`, `context.AbortReason`.
    public var recipeId: String
    public var recipeName: String
    public var executionId: String
    public var state: String
    public var abortReason: String?

    public init(variables: RecipeVariables = RecipeVariables(), payload: PayloadMetrics? = nil,
                option: @escaping @Sendable (String) -> (value: JSONValue, isTemplate: Bool)? = { _ in nil },
                extraVariables: [String: JSONValue] = [:], recipeId: String = "", recipeName: String = "",
                executionId: String = "", state: String = "NotStarted", abortReason: String? = nil) {
        self.variables = variables
        self.payload = payload
        self.option = option
        self.extraVariables = extraVariables
        self.recipeId = recipeId
        self.recipeName = recipeName
        self.executionId = executionId
        self.state = state
        self.abortReason = abortReason
    }
}

/// `${...}` in recipe values (upstream `ExpressionEvaluator`), same semantics: a value that is one `${...}` gives the typed
/// result, text around or several `${...}` interpolate into a string. Inside: `now:<.NET format>`, `utcnow:<format>`,
/// ternary `a ? b : c`, `||`, `&&`, `== != < <= > >=` (numbers with an epsilon, else case-insensitive text), `+ -`
/// (`+` joins when a side is text), `* / %` (by zero: 0), parentheses, literals ('text', "text", numbers, true, false,
/// null), scopes `user.` `machine.` `config.` `option.` `context.` `payload.`, bare `now`/`utcnow`, and bare names of
/// flow variables (`${Barcode.Text}`). Unknown names are null, syntax errors give null (logged): a recipe never fails
/// on an expression. No functions and no `??`: upstream has none, and recipes must stay portable.
public struct ExpressionEvaluator: Sendable {
    public init(environment: any RecipeEnvironment) { rcoreStub() }

    /// A value from a recipe: `${...}` evaluated, other text unchanged (upstream `Evaluate`).
    public func evaluate(_ text: String, in scope: ExpressionScope) -> JSONValue { rcoreStub() }
    /// The inside of `${...}` (upstream `EvaluateExpression`).
    public func evaluateExpression(_ expression: String, in scope: ExpressionScope) -> JSONValue { rcoreStub() }
    /// True when the value is true (upstream `ConvertToBoolean`: null false, numbers not 0, "true"/"false", other text
    /// when not empty); `defaultValue` when the text is nil or empty.
    public func evaluateBool(_ text: String?, in scope: ExpressionScope, default defaultValue: Bool) -> Bool { rcoreStub() }
    /// Every string with `${` in the value, recursively (upstream `ResolveParameters`/`ResolveObject`). Evaluated once:
    /// a result is never evaluated again, so `${...}` text from data (OCR, QR codes, window titles) stays text.
    public func resolve(_ value: JSONValue, in scope: ExpressionScope) -> JSONValue { rcoreStub() }
    public func resolveParameters(_ parameters: JSONObject, in scope: ExpressionScope) -> JSONObject { rcoreStub() }

    /// The syntax problem of the first `${...}` that has one, nil when all parse (validator and editor diagnostics).
    public static func syntaxProblem(in text: String) -> String? { rcoreStub() }
    /// The option keys `${...}` in the text read ("key", or "extension.key"; upstream `FindOptionReferences`).
    public static func optionReferences(in text: String) -> Set<String> { rcoreStub() }
    /// The variable names `${...}` in the text start with (upstream `RecipeContract.VariableReference`).
    public static func variableReferences(in text: String) -> [String] { rcoreStub() }
}
