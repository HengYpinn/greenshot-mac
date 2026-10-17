// Greenshot for Mac (Community) - an unofficial macOS port of Greenshot
// Copyright (C) 2026 Greenshot for Mac (Community) contributors
// Based on Greenshot, Copyright (C) 2007-2026 Thomas Braun, Jens Klingen, Robin Krom
// SPDX-License-Identifier: GPL-3.0-or-later

import Foundation
import Testing
@testable import GreenshotCore

/// A fixed environment for expression tests.
struct FixedRecipeEnvironment: RecipeEnvironment {
    var user: [String: String] = ["username": "jane", "temp": "/tmp/"]
    var machine: [String: String] = ["computername": "studio"]
    var config: [String: JSONValue] = ["capturemousepointer": .bool(true), "language": .string("en-US")]
    var date = Date(timeIntervalSince1970: 1_790_000_000)
    var zone = TimeZone(identifier: "Europe/Berlin")!

    func userValue(_ key: String) -> JSONValue? { user[key.lowercased()].map(JSONValue.string) }
    func machineValue(_ key: String) -> JSONValue? { machine[key.lowercased()].map(JSONValue.string) }
    func configValue(_ key: String) -> JSONValue? { config[key.lowercased()] }
    func now() -> Date { date }
    var timeZone: TimeZone { zone }
}

@Suite struct RecipeExpressionTests {
    let evaluator = ExpressionEvaluator(environment: FixedRecipeEnvironment())

    func scope(_ variables: [String: JSONValue] = [:], payload: PayloadMetrics? = nil) -> ExpressionScope {
        ExpressionScope(variables: RecipeVariables(variables), payload: payload, recipeId: "expr_test", recipeName: "Expression Test")
    }

    // Upstream ExpressionEvaluatorTests.

    @Test func interpolationAndContextProperties() {
        let result = evaluator.evaluate("prefix_${context.CustomTag}_${context.Count}",
                                        in: scope(["CustomTag": .string("BugReport"), "Count": .number(42)]))
        #expect(result == .string("prefix_BugReport_42"))
    }

    @Test func mathAndComparisons() {
        let values = scope(["Width": .number(1920), "Height": .number(1080)])
        #expect(evaluator.evaluate("${Width == 1920 && Height == 1080}", in: values) == .bool(true))
        #expect(evaluator.evaluate("${Width >= 3840}", in: values) == .bool(false))
        #expect(evaluator.evaluate("${Width * Height}", in: values) == .number(2_073_600))
    }

    @Test func payloadDimensionsAndText() {
        let payload = PayloadMetrics(width: 800, height: 600, extractedText: "Error Code: 404", title: "Application Window")
        let values = scope(payload: payload)
        #expect(evaluator.evaluate("${payload.width}", in: values) == .number(800))
        #expect(evaluator.evaluate("${payload.H}", in: values) == .number(600))
        #expect(evaluator.evaluate("${payload.extractedtext}", in: values) == .string("Error Code: 404"))
        #expect(evaluator.evaluate("${payload.title}", in: values) == .string("Application Window"))
        #expect(evaluator.evaluate("${payload.title}", in: scope()) == .number(0))
    }

    @Test func resolveParametersEverywhere() {
        let parameters: JSONObject = ["Path": .string("${context.TargetFolder}/${context.Prefix}_test.png"), "StaticNum": .number(123),
                                      "ConditionMet": .string("${1 + 1 == 2}"),
                                      "List": .array([.string("${context.Prefix}"), .bool(true)]),
                                      "Nested": .object(["x": .string("${2 * 3}")])]
        let resolved = evaluator.resolveParameters(parameters, in: scope(["TargetFolder": .string("/Captures"), "Prefix": .string("GS")]))
        #expect(resolved["Path"] == .string("/Captures/GS_test.png"))
        #expect(resolved["StaticNum"] == .number(123))
        #expect(resolved["ConditionMet"] == .bool(true))
        #expect(resolved["List"] == .array([.string("GS"), .bool(true)]))
        #expect(resolved["Nested"] == .object(["x": .number(6)]))
        #expect(resolved.keys == ["Path", "StaticNum", "ConditionMet", "List", "Nested"])
    }

    // Operators.

    @Test func precedenceAndAssociativity() {
        let none = scope()
        #expect(evaluator.evaluateExpression("2 + 3 * 4", in: none) == .number(14))
        #expect(evaluator.evaluateExpression("(2 + 3) * 4", in: none) == .number(20))
        #expect(evaluator.evaluateExpression("10 - 4 - 3", in: none) == .number(3))
        #expect(evaluator.evaluateExpression("100 / 10 / 5", in: none) == .number(2))
        #expect(evaluator.evaluateExpression("7 % 4", in: none) == .number(3))
        #expect(evaluator.evaluateExpression("-5 + 3", in: none) == .number(-2))
        #expect(evaluator.evaluateExpression("1 + 1 == 2 && 3 > 2 || false", in: none) == .bool(true))
    }

    @Test func ternary() {
        let none = scope(["w": .number(1000)])
        #expect(evaluator.evaluateExpression("w > 800 ? 'large' : 'small'", in: none) == .string("large"))
        #expect(evaluator.evaluateExpression("w > 2000 ? 'huge' : w > 800 ? 'large' : 'small'", in: none) == .string("large"))
        #expect(evaluator.evaluateExpression("(w > 1) ? w / 2 : 0", in: none) == .number(500))
    }

    @Test func concatenationAndZeroDivision() {
        let none = scope(["name": .string("Shot")])
        #expect(evaluator.evaluateExpression("name + 2", in: none) == .string("Shot2"))
        #expect(evaluator.evaluateExpression("'a' + 'b c'", in: none) == .string("ab c"))
        #expect(evaluator.evaluateExpression("5 / 0", in: none) == .number(0))
        #expect(evaluator.evaluateExpression("5 % 0", in: none) == .number(0))
        #expect(evaluator.evaluateExpression("'10' - 4", in: none) == .number(6))
    }

    @Test func comparisonRules() {
        let none = scope(["text": .string("Hello")])
        #expect(evaluator.evaluateExpression("0.1 + 0.2 == 0.3", in: none) == .bool(true))
        #expect(evaluator.evaluateExpression("text == 'hello'", in: none) == .bool(true))
        #expect(evaluator.evaluateExpression("'10' < '9'", in: none) == .bool(true))
        #expect(evaluator.evaluateExpression("missing == null", in: none) == .bool(true))
        #expect(evaluator.evaluateExpression("missing != 1", in: none) == .bool(true))
        #expect(evaluator.evaluateExpression("missing < 1", in: none) == .bool(false))
        #expect(evaluator.evaluateExpression("true == TRUE", in: none) == .bool(true))
    }

    @Test func noFunctionsAndNoCoalescing() {
        let none = scope(["a": .string("x")])
        #expect(evaluator.evaluateExpression("a ?? 'y'", in: none) == .null)
        #expect(ExpressionEvaluator.syntaxProblem(in: "${a ?? 'y'}") != nil)
        #expect(ExpressionEvaluator.syntaxProblem(in: "${max(1, 2)}") != nil)
    }

    // Scopes.

    @Test func environmentScopes() {
        let none = scope()
        #expect(evaluator.evaluate("${user.username} on ${machine.ComputerName}", in: none) == .string("jane on studio"))
        #expect(evaluator.evaluate("${config.CaptureMousePointer}", in: none) == .bool(true))
        #expect(evaluator.evaluate("${user.unknown}", in: none) == .null)
    }

    @Test func dates() {
        let none = scope()
        // 1_790_000_000 is 2026-09-21 14:13:20 UTC, 16:13:20 in Berlin.
        #expect(evaluator.evaluate("${now:yyyy-MM-dd HH:mm:ss}", in: none) == .string("2026-09-21 16:13:20"))
        #expect(evaluator.evaluate("${utcnow:HH:mm}", in: none) == .string("14:13"))
        #expect(evaluator.evaluate("${now}", in: none) == .string("2026-09-21_16-13-20"))
        #expect(evaluator.evaluate("[${now:yyyy}]", in: none) == .string("[2026]"))
    }

    @Test func contextNames() {
        var values = scope(["Barcode.Text": .string("QR!")])
        values.executionId = "id-1"
        #expect(evaluator.evaluate("${Barcode.Text}", in: values) == .string("QR!"))
        #expect(evaluator.evaluate("${context.barcode.text}", in: values) == .string("QR!"))
        #expect(evaluator.evaluate("${context.RecipeId}", in: values) == .string("expr_test"))
        #expect(evaluator.evaluate("${context.ExecutionId}", in: values) == .string("id-1"))
    }

    @Test func optionsBeforeVariables() {
        var values = scope(["option.border": .bool(false)])
        values.option = { key in recipeEquals(key, "border") ? (value: .bool(true), isTemplate: false) : nil }
        #expect(evaluator.evaluate("${option.border}", in: values) == .bool(true))
        #expect(evaluator.evaluate("${option.missing}", in: values) == .null)
    }

    @Test func templateOptions() {
        var values = scope()
        values.option = { key in
            switch key.lowercased() {
            case "caption": return (value: .string("Captured ${now:yyyy} ${option.other} by ${user.username}"), isTemplate: true)
            case "other": return (value: .string("x"), isTemplate: false)
            case "plain": return (value: .string("${user.username}"), isTemplate: false)
            default: return nil
            }
        }
        #expect(evaluator.evaluate("${option.caption}", in: values) == .string("Captured 2026  by jane"))
        #expect(evaluator.evaluate("${option.plain}", in: values) == .string("${user.username}"))
    }

    @Test func evaluatedOnlyOnce() {
        // A value from data that looks like an expression stays text.
        let values = scope(["Ocr": .string("${user.username}")])
        #expect(evaluator.evaluate("${Ocr}", in: values) == .string("${user.username}"))
        #expect(evaluator.evaluate("Text: ${Ocr}", in: values) == .string("Text: ${user.username}"))
        let resolved = evaluator.resolve(.string("${Ocr}"), in: values)
        #expect(resolved == .string("${user.username}"))
    }

    @Test func extraVariablesFirst() {
        var values = scope(["width": .number(1)])
        values.extraVariables = ["Width": .number(99)]
        #expect(evaluator.evaluateExpression("width + 1", in: values) == .number(100))
    }

    @Test func bools() {
        let none = scope(["yes": .string("TRUE"), "word": .string("abc")])
        #expect(evaluator.evaluateBool("${yes}", in: none, default: false))
        #expect(!evaluator.evaluateBool("${word}", in: none, default: false))
        #expect(evaluator.evaluateBool("${2 > 1}", in: none, default: false))
        #expect(evaluator.evaluateBool(nil, in: none, default: true))
        #expect(evaluator.evaluateBool("${1}", in: none, default: false))
    }

    @Test func malformedReadAsOneName() {
        let values = scope(["user name": .string("odd")])
        #expect(evaluator.evaluateExpression("user name", in: values) == .string("odd"))
        #expect(evaluator.evaluate("${}", in: values) == .null)
        #expect(evaluator.evaluate("a ${} b", in: values) == .string("a ${} b"))
        #expect(evaluator.evaluate("no expression", in: values) == .string("no expression"))
    }

    @Test func referenceScans() {
        let options = ExpressionEvaluator.optionReferences(in: "${option.width} and ${option.ext_border.color + 1} not option.x ${xoption.y}")
        #expect(options == ["width", "ext_border.color"])
        let names = ExpressionEvaluator.variableReferences(in: "${ Barcode.Text } ${payload.width - 2} ${1 + 2}")
        #expect(names == ["Barcode.Text", "payload.width"])
        #expect(ExpressionEvaluator.syntaxProblem(in: "${a + (b}") != nil)
        #expect(ExpressionEvaluator.syntaxProblem(in: "${now:yyyy-MM-dd} ${a + b}") == nil)
    }

    @Test func optionValueStore() {
        var width = RecipeOption(key: "width", type: .integer, defaultValue: .number(2))
        width.max = 50
        var store = RecipeOptionValues()
        #expect(store.value(of: width, recipeId: "ext_border") == .number(2))
        let set = store.setValue(.number(7), of: width, recipeId: "ext_border")
        #expect(set)
        #expect(store.stored == ["ext_border.width": "7"])
        let again = store.setValue(.number(7), of: width, recipeId: "EXT_BORDER")
        #expect(!again)
        #expect(store.value(of: width, recipeId: "EXT_border") == .number(7))
        let backToDefault = store.setValue(.number(2), of: width, recipeId: "ext_border")
        #expect(backToDefault)
        #expect(store.stored.isEmpty)
        let wrong = store.setValue(.string("wide"), of: width, recipeId: "ext_border")
        #expect(!wrong)
        _ = store.setValue(.number(9), of: width, recipeId: "ext_border")
        let reset = store.reset(recipeId: "Ext_Border")
        #expect(reset)
        #expect(store.stored.isEmpty)
        let damaged = RecipeOptionValues(["ext_border.width": "wide"])
        #expect(damaged.value(of: width, recipeId: "ext_border") == .number(2))
    }

    @Test func systemEnvironment() {
        var settings = AppSettings()
        settings.captureDelayMilliseconds = 250
        settings.recipes.files = ["/a.gsrecipe.json", "/b.gsrecipe.json"]
        let environment = SystemRecipeEnvironment(settings: settings)
        #expect(environment.configValue("CaptureDelay") == .number(250))
        #expect(environment.configValue("captureDelayMilliseconds") == .number(250))
        #expect(environment.configValue("recipefiles") == .string("/a.gsrecipe.json;/b.gsrecipe.json"))
        #expect(environment.configValue("outputFormat") == .string("png"))
        #expect(environment.configValue("jira") == nil)
        #expect(environment.userValue("username") == .string(NSUserName()))
        #expect(environment.machineValue("os") == .string("macOS"))
        #expect(environment.machineValue("is64bit") == .bool(true))
    }
}
