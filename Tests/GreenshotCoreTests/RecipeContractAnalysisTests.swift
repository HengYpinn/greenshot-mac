// Greenshot for Mac (Community) - an unofficial macOS port of Greenshot
// Copyright (C) 2026 Greenshot for Mac (Community) contributors
// Based on Greenshot, Copyright (C) 2007-2026 Thomas Braun, Jens Klingen, Robin Krom
// SPDX-License-Identifier: GPL-3.0-or-later

import Foundation
import Testing
@testable import GreenshotCore

/// The contract analysis along the flow (upstream StepContractTests, graph analysis part).
@Suite struct RecipeContractAnalysisTests {
    static func contract(_ type: String, raw: PayloadRequirement = .none, outputs: [VariableContract] = [],
                         parameters: [ParameterContract] = []) -> StepContract {
        StepContract(stepType: type, displayName: type, parameters: parameters, outputVariables: outputs,
                     payload: PayloadContract(rawCapture: raw))
    }

    static let catalog = StepContractCatalog([
        contract("Capture", raw: .created),
        contract("ProduceA", outputs: [VariableContract("A")]),
        contract("ProduceB", outputs: [VariableContract("B")]),
        contract("MaybeA", outputs: [VariableContract("A", conditional: true)]),
        contract("Use", parameters: [ParameterContract("Text")]),
        contract("NeedsImage", raw: .required),
        contract("Strict", parameters: [ParameterContract("Mode", .enumeration, required: true, allowedValues: ["Fast", "Slow"]),
                                        ParameterContract("Size", .integer)]),
        contract("Branch")
    ])

    func use(_ id: String, _ text: String) -> RecipeNode {
        RecipeNode(id: id, stepType: "Use", parameters: ["Text": .string(text)])
    }

    func warnings(_ recipe: CaptureRecipe) -> [String] {
        RecipeContractAnalyzer.analyze(recipe, contracts: Self.catalog).warnings
    }

    func recipe(_ nodes: [RecipeNode], start: [String], _ transitions: [(String, String)] = [],
                conditional: [(String, String, String)] = []) -> CaptureRecipe {
        var recipe = CaptureRecipe(id: "analysis", name: "Analysis")
        recipe.nodes = nodes
        recipe.flow.startNodes = start
        for (from, to) in transitions { recipe.flow.addTransition(from: from, to: to) }
        recipe.flow.conditionalTransitions = conditional.map { ConditionalTransition(from: $0.0, branch: $0.1, to: $0.2) }
        return recipe
    }

    @Test func followsTheFlowNotTheNodeList() {
        let right = recipe([use("use", "${A}"), RecipeNode(id: "produce", stepType: "ProduceA")], start: ["produce"], [("produce", "use")])
        #expect(warnings(right).isEmpty)
        let wrong = recipe([RecipeNode(id: "produce", stepType: "ProduceA"), use("use", "${A}")], start: ["use"], [("use", "produce")])
        #expect(warnings(wrong).contains("Node 'use' (Use) uses ${A}, which is only set by nodes that do not run before it."))
    }

    @Test func variableSetInOneBranchIsReportedAtTheMerge() {
        let branches = recipe([RecipeNode(id: "decide", stepType: "Branch"), RecipeNode(id: "left", stepType: "ProduceA"),
                               RecipeNode(id: "right", stepType: "ProduceB"), use("merge", "${A} ${B}")],
                              start: ["decide"], [("left", "merge"), ("right", "merge")],
                              conditional: [("decide", "yes", "left"), ("decide", "no", "right")])
        let found = warnings(branches)
        #expect(found.contains("Node 'merge' (Use) uses ${A}, which is not set on every path to it (it is only set in some branches)."))
        #expect(found.contains("Node 'merge' (Use) uses ${B}, which is not set on every path to it (it is only set in some branches)."))
    }

    @Test func variableSetInEveryBranchIsGuaranteed() {
        let both = recipe([RecipeNode(id: "decide", stepType: "Branch"), RecipeNode(id: "left", stepType: "ProduceA"),
                           RecipeNode(id: "right", stepType: "ProduceA"), use("merge", "${A}")],
                          start: ["decide"], [("left", "merge"), ("right", "merge")],
                          conditional: [("decide", "yes", "left"), ("decide", "no", "right")])
        #expect(warnings(both).isEmpty)
    }

    @Test func parallelBranchesJoining() {
        let fork = recipe([RecipeNode(id: "start", stepType: "Capture"), RecipeNode(id: "left", stepType: "ProduceA"),
                           RecipeNode(id: "right", stepType: "ProduceB"), use("join", "${A} ${B}")],
                          start: ["start"], [("start", "left"), ("start", "right"), ("left", "join"), ("right", "join")])
        #expect(warnings(fork).isEmpty)
        let siblings = recipe([RecipeNode(id: "start", stepType: "Capture"), RecipeNode(id: "left", stepType: "ProduceA"), use("right", "${A}")],
                              start: ["start"], [("start", "left"), ("start", "right")])
        #expect(warnings(siblings).contains { $0.contains("'right'") && $0.contains("do not run before it") })
    }

    @Test func conditionalOutputIsNotGuaranteed() throws {
        let maybe = recipe([RecipeNode(id: "scan", stepType: "MaybeA"), use("use", "${A}")], start: ["scan"], [("scan", "use")])
        let report = RecipeContractAnalyzer.analyze(maybe, contracts: Self.catalog)
        #expect(report.warnings.isEmpty)
        let step = try #require(report.steps.first { $0.nodeId == "use" })
        #expect(!step.guaranteedVariables.contains("A"))
        let output = try #require(report.outputs.first { $0.name == "A" })
        #expect(output.conditional)
    }

    @Test func errorTransitionProvidesTheErrorVariables() {
        var errors = recipe([RecipeNode(id: "risky", stepType: "ProduceA"), use("ok", "${A}"), use("handler", "${LastError} ${A}")],
                            start: ["risky"], [("risky", "ok")])
        errors.flow.errorTransitions = [ErrorTransition(from: "risky", to: "handler")]
        let found = warnings(errors)
        #expect(!found.contains { $0.contains("'ok'") })
        #expect(!found.contains { $0.contains("${LastError}") })
        #expect(found.contains { $0.contains("'handler'") && $0.contains("${A}") })
    }

    @Test func unreachableNodesAndMissingImages() {
        let unreachable = recipe([RecipeNode(id: "start", stepType: "NeedsImage"), RecipeNode(id: "orphan", stepType: "ProduceA")], start: ["start"])
        let found = warnings(unreachable)
        #expect(found.contains("Node 'orphan' (ProduceA) is never executed: no path from a start node leads to it."))
        #expect(found.contains("Node 'start' (NeedsImage) needs an image, but on some path to it no preceding node acquires one."))
    }

    @Test func extensionTriggerProvidesTheImage() {
        var fromBrowser = recipe([RecipeNode(id: "use", stepType: "NeedsImage")], start: ["use"])
        fromBrowser.triggers = [TriggerConfig(triggerType: "Extension", name: "Browser")]
        #expect(warnings(fromBrowser).isEmpty)
    }

    @Test func commandlineArgumentsAreInputs() throws {
        var cli = recipe([use("use", "${Required} ${WithDefault} ${Optional}")], start: ["use"])
        cli.triggers = [TriggerConfig(triggerType: "Commandline", parameters: [
            "Command": .string("cli"),
            "Arguments": .array([
                .object(["name": .string("required"), "variable": .string("Required"), "required": .bool(true)]),
                .object(["name": .string("with-default"), "variable": .string("WithDefault"), "defaultValue": .string("x")]),
                .object(["name": .string("optional"), "variable": .string("Optional")])
            ])
        ])]
        let report = RecipeContractAnalyzer.analyze(cli, contracts: Self.catalog)
        #expect(report.inputs.contains { $0.name == "Required" && $0.required })
        #expect(report.inputs.contains { $0.name == "Optional" && !$0.required })
        #expect(report.warnings.isEmpty)
        let step = try #require(report.steps.first)
        #expect(step.guaranteedVariables.contains("Required"))
        #expect(step.guaranteedVariables.contains("WithDefault"))
        #expect(!step.guaranteedVariables.contains("Optional"))
    }

    @Test func checksParameters() {
        var fine = RecipeNode(id: "fine", stepType: "Strict", parameters: ["Mode": .string("fast")])
        fine.onErrorNodeId = "missing"
        let params = recipe([RecipeNode(id: "missing", stepType: "Strict", parameters: ["Size": .number(3)]),
                             RecipeNode(id: "wrong", stepType: "Strict", parameters: ["Mode": .string("Medium"), "Colour": .string("red")]),
                             fine], start: ["missing", "wrong", "fine"])
        let found = warnings(params)
        #expect(found.contains("Node 'missing' (Strict) is missing required parameter 'Mode'."))
        #expect(found.contains("Node 'wrong' (Strict): parameter 'Mode' has value 'Medium'; allowed are Fast, Slow."))
        #expect(found.contains("Node 'wrong' (Strict) has parameter 'Colour', which the step does not read."))
        #expect(!found.contains { $0.contains("'fine'") })
        #expect(!found.contains { $0.contains("'Size'") })
    }

    @Test func nodeSpecificOutputNames() {
        let prompt = recipe([RecipeNode(id: "set", stepType: "SetVariable", parameters: ["Variable": .string("Greeting"), "Value": .string("hi")]),
                             RecipeNode(id: "print", stepType: "Stdout", parameters: ["Text": .string("${Greeting} ${UserChoice.set}")])],
                            start: ["set"], [("set", "print")])
        let report = RecipeContractAnalyzer.analyze(prompt)
        #expect(report.outputs.contains { $0.name == "Greeting" })
        #expect(report.warnings.isEmpty)
    }

    @Test func conditionalSourceIgnoresNormalTransitions() {
        let both = recipe([RecipeNode(id: "decide", stepType: "Branch"), RecipeNode(id: "a", stepType: "ProduceA"),
                           RecipeNode(id: "b", stepType: "ProduceB")],
                          start: ["decide"], [("decide", "b")], conditional: [("decide", "yes", "a")])
        #expect(warnings(both).contains("Node 'decide' has conditional transitions, so its normal transitions (b) are never followed."))
    }

    @Test func reportSummary() {
        let report = RecipeContractAnalyzer.analyze(testRecipe())
        #expect(report.acquiresImage)
        #expect(report.outputs.contains { $0.name == "Payload.Width" })
        #expect(report.steps.count == 2)
    }
}
