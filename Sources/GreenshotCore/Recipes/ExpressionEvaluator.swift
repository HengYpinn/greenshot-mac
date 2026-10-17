// Greenshot for Mac (Community) - an unofficial macOS port of Greenshot
// Copyright (C) 2026 Greenshot for Mac (Community) contributors
// Based on Greenshot, Copyright (C) 2007-2026 Thomas Braun, Jens Klingen, Robin Krom
// SPDX-License-Identifier: GPL-3.0-or-later

import CoreGraphics
import Foundation

/// Flow variables (upstream `CaptureFlowContext.Properties`): case-insensitive names, the spelling of the first set kept.
public struct RecipeVariables: Sendable, Equatable, Sequence {
    private var members: [JSONMember] = []
    private var positions: [String: Int] = [:]

    public init(_ values: [String: JSONValue] = [:]) {
        for key in values.keys.sorted() {
            self[key] = values[key]
        }
    }

    public subscript(name: String) -> JSONValue? {
        get { positions[name.lowercased()].map { members[$0].value } }
        set {
            let key = name.lowercased()
            if let position = positions[key] {
                if let newValue {
                    members[position].value = newValue
                } else {
                    members.remove(at: position)
                    positions = [:]
                    for (index, member) in members.enumerated() { positions[member.key.lowercased()] = index }
                }
            } else if let newValue {
                positions[key] = members.count
                members.append(JSONMember(name, newValue))
            }
        }
    }

    public var names: [String] { members.map(\.key) }
    public var count: Int { members.count }
    public func makeIterator() -> IndexingIterator<[JSONMember]> { members.makeIterator() }

    /// The same names (case-insensitive) with the same values, in any order.
    public static func == (lhs: RecipeVariables, rhs: RecipeVariables) -> Bool {
        lhs.count == rhs.count && lhs.members.allSatisfy { rhs[$0.key] == $0.value }
    }
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
    private let environment: any RecipeEnvironment

    public init(environment: any RecipeEnvironment) {
        self.environment = environment
    }

    /// A value from a recipe: `${...}` evaluated, other text unchanged (upstream `Evaluate`).
    public func evaluate(_ text: String, in scope: ExpressionScope) -> JSONValue {
        guard text.contains("${") else { return .string(text) }
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        // A whole `${...}` keeps its type (upstream: starts with "${", ends with "}" and has no second "${").
        if trimmed.hasPrefix("${"), trimmed.hasSuffix("}"), trimmed.count >= 3,
           !trimmed.dropFirst(2).contains("${") {
            let inner = String(trimmed.dropFirst(2).dropLast()).trimmingCharacters(in: .whitespacesAndNewlines)
            return evaluateExpression(inner, in: scope)
        }
        return .string(Self.replaceTokens(in: text) { evaluateExpression($0, in: scope).interpolationText })
    }
    /// The inside of `${...}` (upstream `EvaluateExpression`).
    public func evaluateExpression(_ expression: String, in scope: ExpressionScope) -> JSONValue {
        let trimmed = expression.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return .null }
        if trimmed.lowercased().hasPrefix("now:") {
            return .string(formatDate(format: String(trimmed.dropFirst(4)), utc: false))
        }
        if trimmed.lowercased().hasPrefix("utcnow:") {
            return .string(formatDate(format: String(trimmed.dropFirst(7)), utc: true))
        }
        do {
            return value(of: try ExpressionParser.parse(trimmed), in: scope)
        } catch {
            // Upstream resolves what it can't split into operators as one token: a literal or a name.
            log.debug("Expression '\(trimmed)' read as one name: \((error as? ExpressionSyntaxError)?.message ?? "\(error)")")
            return singleToken(trimmed, in: scope)
        }
    }
    /// The value as a bool like upstream's `Evaluate<bool>` (`Convert.ChangeType`): a bool, a number not 0, the text
    /// "true"/"false"; `defaultValue` for anything else and when the text is nil or empty.
    public func evaluateBool(_ text: String?, in scope: ExpressionScope, default defaultValue: Bool) -> Bool {
        guard let text, !text.trimmingCharacters(in: .whitespaces).isEmpty else { return defaultValue }
        switch evaluate(text, in: scope) {
        case .bool(let flag): return flag
        case .number(let number): return number != 0
        case .string(let value):
            switch value.trimmingCharacters(in: .whitespaces).lowercased() {
            case "true": return true
            case "false": return false
            default: return defaultValue
            }
        case .null, .array, .object:
            return defaultValue
        }
    }
    /// Every string with `${` in the value, recursively (upstream `ResolveParameters`/`ResolveObject`). Evaluated once:
    /// a result is never evaluated again, so `${...}` text from data (OCR, QR codes, window titles) stays text.
    public func resolve(_ value: JSONValue, in scope: ExpressionScope) -> JSONValue {
        switch value {
        case .string(let text):
            return text.contains("${") ? evaluate(text, in: scope) : value
        case .array(let items):
            return .array(items.map { resolve($0, in: scope) })
        case .object(let object):
            return .object(resolveParameters(object, in: scope))
        case .null, .bool, .number:
            return value
        }
    }

    public func resolveParameters(_ parameters: JSONObject, in scope: ExpressionScope) -> JSONObject {
        JSONObject(parameters.members.map { JSONMember($0.key, resolve($0.value, in: scope)) })
    }

    /// The syntax problem of the first `${...}` that has one, nil when all parse (validator and editor diagnostics).
    public static func syntaxProblem(in text: String) -> String? {
        for inner in tokens(in: text) {
            let trimmed = inner.trimmingCharacters(in: .whitespacesAndNewlines)
            let lower = trimmed.lowercased()
            if lower.hasPrefix("now:") || lower.hasPrefix("utcnow:") { continue }
            do {
                _ = try ExpressionParser.parse(trimmed)
            } catch let error as ExpressionSyntaxError {
                return "'${\(inner)}': \(error.message)"
            } catch {
                return "'${\(inner)}': \(error)"
            }
        }
        return nil
    }

    /// The option keys `${...}` in the text read ("key", or "extension.key"; upstream `FindOptionReferences`).
    public static func optionReferences(in text: String) -> Set<String> {
        var keys = Set<String>()
        for inner in tokens(in: text) {
            let range = NSRange(inner.startIndex..., in: inner)
            for match in optionReference.matches(in: inner, range: range) {
                if let keyRange = Range(match.range(at: 1), in: inner) { keys.insert(String(inner[keyRange])) }
            }
        }
        return keys
    }

    /// The variable names `${...}` in the text start with (upstream `RecipeContract.VariableReference`).
    public static func variableReferences(in text: String) -> [String] {
        let range = NSRange(text.startIndex..., in: text)
        return variableReference.matches(in: text, range: range).compactMap { match in
            Range(match.range(at: 1), in: text).map { String(text[$0]).trimmingCharacters(in: CharacterSet(charactersIn: ".")) }
        }
    }

    // MARK: - Tokens of a text

    /// Upstream `TokenRegex`: `${` up to the next `}`, at least one character inside.
    private static let tokenPattern = try! NSRegularExpression(pattern: #"\$\{([^}]+)\}"#)
    private static let optionReference = try! NSRegularExpression(
        pattern: #"(?<![A-Za-z0-9_.])option\.([A-Za-z0-9_]+(?:\.[A-Za-z0-9_]+)?)"#, options: .caseInsensitive)
    private static let variableReference = try! NSRegularExpression(pattern: #"\$\{\s*([A-Za-z_][\w.]*)"#)

    static func tokens(in text: String) -> [String] {
        let range = NSRange(text.startIndex..., in: text)
        return tokenPattern.matches(in: text, range: range).compactMap { match in
            Range(match.range(at: 1), in: text).map { String(text[$0]) }
        }
    }

    /// Every `${...}` of the text replaced by `transform` of its inside.
    static func replaceTokens(in text: String, _ transform: (String) -> String) -> String {
        let range = NSRange(text.startIndex..., in: text)
        var result = ""
        var last = text.startIndex
        for match in tokenPattern.matches(in: text, range: range) {
            guard let whole = Range(match.range, in: text), let inner = Range(match.range(at: 1), in: text) else { continue }
            result += text[last..<whole.lowerBound]
            result += transform(String(text[inner]).trimmingCharacters(in: .whitespacesAndNewlines))
            last = whole.upperBound
        }
        result += text[last...]
        return result
    }

    // MARK: - Evaluation

    private func value(of node: ExpressionNode, in scope: ExpressionScope) -> JSONValue {
        switch node {
        case .literal(let value):
            return value
        case .name(let name):
            return singleToken(name, in: scope)
        case .negate(let inner):
            return .number(-Self.number(value(of: inner, in: scope)))
        case .ternary(let condition, let whenTrue, let whenFalse):
            return Self.truth(value(of: condition, in: scope)) ? value(of: whenTrue, in: scope) : value(of: whenFalse, in: scope)
        case .binary(let symbol, let leftNode, let rightNode):
            let left = value(of: leftNode, in: scope)
            let right = value(of: rightNode, in: scope)
            return Self.apply(symbol, left, right)
        }
    }

    private static func apply(_ symbol: String, _ left: JSONValue, _ right: JSONValue) -> JSONValue {
        switch symbol {
        case "||": return .bool(truth(left) || truth(right))
        case "&&": return .bool(truth(left) && truth(right))
        case "==", "!=", "<", "<=", ">", ">=": return .bool(compare(left, symbol, right))
        case "+":
            if case .string = left { return .string(left.interpolationText + right.interpolationText) }
            if case .string = right { return .string(left.interpolationText + right.interpolationText) }
            return .number(number(left) + number(right))
        case "-": return .number(number(left) - number(right))
        case "*": return .number(number(left) * number(right))
        case "/":
            let divisor = number(right)
            return .number(divisor == 0 ? 0 : number(left) / divisor)
        case "%":
            let divisor = number(right)
            return .number(divisor == 0 ? 0 : number(left).truncatingRemainder(dividingBy: divisor))
        default:
            return .null
        }
    }

    /// Upstream `EvaluateComparison`.
    private static func compare(_ left: JSONValue, _ symbol: String, _ right: JSONValue) -> Bool {
        if left.isNull, right.isNull { return symbol == "==" || symbol == "<=" || symbol == ">=" }
        if left.isNull || right.isNull { return symbol == "!=" }
        if case .bool(let one) = left, case .bool(let two) = right {
            return symbol == "==" ? one == two : one != two
        }
        if case .number(let one) = left, case .number(let two) = right {
            switch symbol {
            case "==": return abs(one - two) < 0.0000001
            case "!=": return abs(one - two) >= 0.0000001
            case "<": return one < two
            case "<=": return one <= two
            case ">": return one > two
            default: return one >= two
            }
        }
        let order = left.interpolationText.caseInsensitiveCompare(right.interpolationText)
        switch symbol {
        case "==": return order == .orderedSame
        case "!=": return order != .orderedSame
        case "<": return order == .orderedAscending
        case "<=": return order != .orderedDescending
        case ">": return order == .orderedDescending
        default: return order != .orderedAscending
        }
    }

    /// Upstream `ConvertToDouble`: numbers, numeric text, else 0.
    static func number(_ value: JSONValue) -> Double {
        switch value {
        case .number(let number): return number
        case .string(let text):
            let trimmed = text.trimmingCharacters(in: .whitespaces)
            return Double(trimmed) ?? Double(trimmed.replacingOccurrences(of: ",", with: "")) ?? 0
        default: return 0
        }
    }

    /// Upstream `ConvertToBoolean`: null false, numbers not 0, "true"/"false", other text when not empty.
    static func truth(_ value: JSONValue) -> Bool {
        switch value {
        case .null: return false
        case .bool(let flag): return flag
        case .number(let number): return number != 0
        case .string(let text):
            switch text.trimmingCharacters(in: .whitespaces).lowercased() {
            case "true": return true
            case "false": return false
            default: return !text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
            }
        case .array, .object:
            return true
        }
    }

    /// Upstream `ResolveSingleToken`: a literal, a node-local variable, a scope, `now`, or a flow variable.
    private func singleToken(_ token: String, in scope: ExpressionScope) -> JSONValue {
        let trimmed = token.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return .null }
        if trimmed.count >= 2, let first = trimmed.first, first == trimmed.last, first == "\"" || first == "'" {
            return .string(String(trimmed.dropFirst().dropLast()))
        }
        if let number = Double(trimmed) { return .number(number) }
        let lower = trimmed.lowercased()
        switch lower {
        case "true": return .bool(true)
        case "false": return .bool(false)
        case "null": return .null
        default: break
        }
        if let extra = scope.extraVariables.first(where: { recipeEquals($0.key, trimmed) }) { return extra.value }
        if lower.hasPrefix("user.") { return environment.userValue(String(trimmed.dropFirst(5))) ?? .null }
        if lower.hasPrefix("machine.") { return environment.machineValue(String(trimmed.dropFirst(8))) ?? .null }
        if lower.hasPrefix("config.") { return environment.configValue(String(trimmed.dropFirst(7))) ?? .null }
        // Options before the flow variables: a value for one run (trigger, command line) can't replace them.
        if lower.hasPrefix("option.") {
            guard let option = scope.option(String(trimmed.dropFirst(7))) else { return .null }
            if option.isTemplate, case .string(let template) = option.value { return .string(evaluateTemplate(template, in: scope)) }
            return option.value
        }
        if lower.hasPrefix("context.") { return contextValue(String(trimmed.dropFirst(8)), in: scope) }
        if lower.hasPrefix("payload.") { return payloadValue(String(trimmed.dropFirst(8)), in: scope) }
        if lower == "now" { return .string(formatDate(format: "yyyy-MM-dd_HH-mm-ss", utc: false)) }
        if lower == "utcnow" { return .string(formatDate(format: "yyyy-MM-dd_HH-mm-ss", utc: true)) }
        return scope.variables[trimmed] ?? .null
    }

    /// A template option's value with its `${...}` evaluated; options can't be used in it (no template expands another).
    private func evaluateTemplate(_ template: String, in scope: ExpressionScope) -> String {
        guard template.contains("${") else { return template }
        var inner = scope
        inner.option = { _ in nil }
        return Self.replaceTokens(in: template) { expression in
            expression.lowercased().contains("option.") ? "" : evaluateExpression(expression, in: inner).interpolationText
        }
    }

    private func contextValue(_ key: String, in scope: ExpressionScope) -> JSONValue {
        switch key.lowercased() {
        case "executionid": return .string(scope.executionId)
        case "state": return .string(scope.state)
        case "recipename": return .string(scope.recipeName)
        case "recipeid": return .string(scope.recipeId)
        case "abortreason": return scope.abortReason.map(JSONValue.string) ?? .null
        default: return scope.variables[key] ?? .null
        }
    }

    private func payloadValue(_ key: String, in scope: ExpressionScope) -> JSONValue {
        guard let payload = scope.payload else { return .number(0) }
        switch key.lowercased() {
        case "width", "w": return .number(payload.width)
        case "height", "h": return .number(payload.height)
        case "text", "extractedtext": return .string(payload.extractedText)
        case "title": return .string(payload.title)
        case "filename": return .string(payload.filename)
        default: return payload.metadata.first { recipeEquals($0.key, key) }?.value ?? .null
        }
    }

    private func formatDate(format: String, utc: Bool) -> String {
        let zone = utc ? TimeZone(identifier: "UTC") ?? environment.timeZone : environment.timeZone
        return DotNetDateFormat.string(from: environment.now(), format: format, locale: Locale(identifier: "en_US_POSIX"), timeZone: zone)
    }
}

private let log = Log("Recipes")
