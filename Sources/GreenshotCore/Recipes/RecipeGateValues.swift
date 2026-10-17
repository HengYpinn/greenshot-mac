// Greenshot for Mac (Community) - an unofficial macOS port of Greenshot
// Copyright (C) 2026 Greenshot for Mac (Community) contributors
// Based on Greenshot, Copyright (C) 2007-2026 Thomas Braun, Jens Klingen, Robin Krom
// SPDX-License-Identifier: GPL-3.0-or-later

import Foundation

/// A parameter that decides a gate (a file, a folder, a command, a destination), as the approval sees it before the
/// recipe runs. A value with `${...}` (an argument, an option, a variable) is decided when the recipe runs: the gates
/// assume the dangerous case for it, and their targets say so instead of showing the expression as if it were the
/// value. Upstream reads the literal parameter only (`GetGatedActions`); this is stricter.
enum RecipeGateValue: Equatable {
    case unset
    case literal(String)
    /// The text as written, e.g. "${Arg}".
    case runTime(String)

    init(_ value: JSONValue?) {
        guard let value, !value.isNull else {
            self = .unset
            return
        }
        let text: String
        switch value {
        case .string(let string): text = string.trimmingCharacters(in: .whitespacesAndNewlines)
        case .number, .bool: text = value.asString ?? ""
        case .array, .object, .null: text = value.serialized(indented: false)
        }
        if text.isEmpty {
            self = .unset
        } else {
            self = Self.isRunTime(text) ? .runTime(text) : .literal(text)
        }
    }

    init(_ node: RecipeNode, _ key: String) {
        self.init(node.parameters[key])
    }

    static func isRunTime(_ text: String) -> Bool { text.contains("${") }

    /// The target of a command decided when the recipe runs; the describer says "Runs a command given ...".
    static func command(_ text: String) -> String { "a command given when the recipe runs (\(text))" }
}

/// The gated actions of a node in its recipe: the contract's, plus the dangerous case for a step input that picks a
/// gated target when the recipe itself can set that variable (a trigger argument, SetVariable, a step output named by
/// a parameter). Today that is `OverrideDestinations` of the destination steps: set by an argument, it could pick an
/// external command or an upload that was never approved.
enum RecipeGates {
    /// Inputs that choose where the result goes.
    static let destinationInputs = ["OverrideDestinations"]

    /// The variables the recipe can set, lower case; "*" when a step sets a variable whose name is decided when the
    /// recipe runs.
    static func variablesSet(by recipe: CaptureRecipe, contracts: StepContractCatalog) -> Set<String> {
        var names = Set(RecipeContractAnalyzer.triggerInputs(of: recipe).inputs.map { $0.name.lowercased() })
        for node in recipe.nodes {
            for output in contracts.contract(for: node.stepType)?.outputVariables ?? [] {
                for name in output.resolveNames(for: node) {
                    names.insert(RecipeGateValue.isRunTime(name) ? "*" : name.lowercased())
                }
            }
        }
        return names
    }

    static func actions(of node: RecipeNode, contract: StepContract, environment: GateEnvironment,
                        recipeSets variables: Set<String>) -> [RecipeGatedAction] {
        var actions: [RecipeGatedAction] = []
        for action in contract.gates(node, environment) where !actions.contains(action) {
            actions.append(action)
        }
        for input in destinationInputs where contract.inputVariables.contains(where: { recipeEquals($0.name, input) }) {
            guard variables.contains(input.lowercased()) || variables.contains("*") else { continue }
            for action in anyDestination("the variable \(input)") where !actions.contains(action) {
                actions.append(action)
            }
        }
        return actions
    }

    /// A destination decided when the recipe runs could be any of them: an external command or an upload.
    static func anyDestination(_ text: String) -> [RecipeGatedAction] {
        [RecipeGatedAction(.externalCommand, target: "a command chosen when the recipe runs (\(text))"),
         RecipeGatedAction(.networkAccess, target: "a destination chosen when the recipe runs (\(text))")]
    }
}
