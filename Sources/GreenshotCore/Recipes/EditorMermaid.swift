// Greenshot for Mac (Community) - an unofficial macOS port of Greenshot
// Copyright (C) 2026 Greenshot for Mac (Community) contributors
// Based on Greenshot, Copyright (C) 2007-2026 Thomas Braun, Jens Klingen, Robin Krom
// SPDX-License-Identifier: GPL-3.0-or-later

import Foundation

/// A recipe's flow as a graph: what the recipe editor's Flow view draws and the Mermaid text describes (both are made
/// from this, so they show the same).
public struct RecipeFlowGraph: Sendable, Equatable {
    public enum Shape: Sendable, Equatable {
        /// A step.
        case box
        /// A Conditional (Mermaid `{…}`).
        case diamond
        /// A trigger or the "Any step" source of error routes (Mermaid `([…])`).
        case stadium
    }

    public enum Role: Sendable, Equatable {
        case step
        case trigger
        /// "Any step" of error routes from `*`.
        case anyStep
        /// Another recipe an error route forwards to.
        case recipe
        /// A transition target that isn't a step of the recipe.
        case missing
        /// An automatic step's "Out".
        case out
    }

    public struct Node: Sendable, Equatable, Identifiable {
        /// The Mermaid id.
        public var id: String
        public var label: String
        public var shape: Shape
        public var role: Role
        /// The recipe step, for steps.
        public var nodeId: String?
        public var isStart: Bool
        public var isDisabled: Bool
    }

    public enum EdgeStyle: Sendable, Equatable {
        case normal
        case conditional
        case error
        case trigger
    }

    public struct Edge: Sendable, Equatable {
        public var from: String
        public var to: String
        public var label: String?
        public var style: EdgeStyle
    }

    public private(set) var nodes: [Node] = []
    public private(set) var edges: [Edge] = []

    /// A graph as it is given (for tests).
    init(nodes: [Node], edges: [Edge]) {
        self.nodes = nodes
        self.edges = edges
    }

    public init(_ recipe: CaptureRecipe) {
        let ids = RecipeMermaid.IdMap(recipe)
        let starts = RecipeMermaid.startNodes(recipe)
        for (index, trigger) in recipe.triggers.enumerated() {
            nodes.append(Node(id: "trigger_\(index)", label: RecipeMermaid.triggerLabel(trigger), shape: .stadium, role: .trigger,
                              nodeId: nil, isStart: false, isDisabled: !trigger.enabled))
        }
        for (index, node) in recipe.nodes.enumerated() {
            let isConditional = recipeEquals(node.stepType, WellKnownStepType.conditional)
            nodes.append(Node(id: ids.nodeIds[index], label: RecipeMermaid.nodeLabel(node), shape: isConditional ? .diamond : .box,
                              role: .step, nodeId: node.id, isStart: starts.contains { recipeEquals($0, node.id) },
                              isDisabled: node.enabled == .value(false)))
        }
        func ensure(_ target: String) -> String {
            let id = ids.id(target)
            if !nodes.contains(where: { $0.id == id }) {
                let isOut = recipe.kind == .extension && recipeEquals(target, "Out")
                nodes.append(Node(id: id, label: isOut ? "Out" : "\(target) (missing)", shape: isOut ? .stadium : .box,
                                  role: isOut ? .out : .missing, nodeId: nil, isStart: false, isDisabled: false))
            }
            return id
        }
        if !starts.isEmpty {
            for index in recipe.triggers.indices {
                for start in starts { edges.append(Edge(from: "trigger_\(index)", to: ensure(start), label: nil, style: .trigger)) }
            }
        }
        for transition in recipe.flow.transitions {
            for target in transition.to where !target.trimmingCharacters(in: .whitespaces).isEmpty {
                edges.append(Edge(from: ensure(transition.from), to: ensure(target), label: nil, style: .normal))
            }
        }
        for transition in recipe.flow.conditionalTransitions
        where !transition.from.trimmingCharacters(in: .whitespaces).isEmpty && !transition.to.trimmingCharacters(in: .whitespaces).isEmpty {
            edges.append(Edge(from: ensure(transition.from), to: ensure(transition.to),
                              label: RecipeMermaid.branchLabel(transition, in: recipe), style: .conditional))
        }
        for transition in recipe.flow.errorTransitions {
            guard let from = transition.from, !from.trimmingCharacters(in: .whitespaces).isEmpty else { continue }
            let source: String
            if from == "*" {
                source = RecipeMermaid.anyStepId
                if !nodes.contains(where: { $0.id == source }) {
                    nodes.append(Node(id: source, label: "Any step", shape: .stadium, role: .anyStep, nodeId: nil, isStart: false,
                                      isDisabled: false))
                }
            } else {
                source = ensure(from)
            }
            let target: String
            if let to = transition.to, !to.isEmpty {
                target = ensure(to)
            } else {
                let recipeId = transition.targetRecipeId ?? ""
                target = ids.recipe(recipeId)
                if !nodes.contains(where: { $0.id == target }) {
                    nodes.append(Node(id: target, label: "Recipe \(recipeId)", shape: .box, role: .recipe, nodeId: nil, isStart: false,
                                      isDisabled: false))
                }
            }
            edges.append(Edge(from: source, to: target, label: "Error: \(transition.errorType)", style: .error))
        }
    }
}

/// The recipe as a Mermaid flowchart (upstream RecipeEditorViewModel.cs:2110 `GenerateMermaidDsl`, docs/capture-recipes.md
/// "Mermaid Workflow Diagram Export"; the docs' sample is simplified, the code's labels are "Name (StepType) [id]").
/// Mac changes: ids Mermaid can't read (other characters than letters, digits and '_', or keywords like `end`) are
/// written as `n<index>`, error routes from `*` start at an "Any step" node (upstream writes `* -.`, which Mermaid
/// rejects), and the only step of a recipe without start steps is styled as its start (where the recipe starts).
public enum RecipeMermaid {
    static let anyStepId = "any_step"
    static let keywords: Set<String> = ["end", "graph", "flowchart", "subgraph", "style", "class", "classdef", "click", "linkstyle",
                                        "direction", "default", "call", "href", "interpolate", "td", "tb", "bt", "rl", "lr"]

    /// Mermaid ids for the recipe's node ids, each node's its own: a step keeps its id when Mermaid can read it and no
    /// earlier step or trigger has it, else it is `n<index>`; a name that isn't a step (a missing target) is itself or
    /// `x_<name>`, another recipe `Recipe_<id>`. An id that is taken gets `_2`, `_3`… (steps that share an id, or are
    /// named `n0` or `trigger_0`, would be one node).
    struct IdMap {
        /// By lowercased name: the first step with that id, or a name the flow uses that isn't a step.
        private var map: [String: String] = [:]
        /// The id of each step, in order.
        private(set) var nodeIds: [String] = []
        /// By recipe id: the other recipes error routes forward to.
        private var recipes: [String: String] = [:]

        init(_ recipe: CaptureRecipe) {
            var used = Set(recipe.triggers.indices.map { "trigger_\($0)" } + [anyStepId])
            func claim(_ candidate: String) -> String {
                var id = candidate
                var number = 2
                while used.contains(id.lowercased()) {
                    id = "\(candidate)_\(number)"
                    number += 1
                }
                used.insert(id.lowercased())
                return id
            }
            var own = [String?](repeating: nil, count: recipe.nodes.count)
            for (index, node) in recipe.nodes.enumerated() where IdMap.isSafe(node.id) && !used.contains(node.id.lowercased()) {
                used.insert(node.id.lowercased())
                own[index] = node.id
            }
            nodeIds = recipe.nodes.indices.map { own[$0] ?? claim("n\($0)") }
            for (index, node) in recipe.nodes.enumerated() where map[node.id.lowercased()] == nil {
                map[node.id.lowercased()] = nodeIds[index]
            }
            let flow = recipe.flow
            var names = flow.startNodes
            for transition in flow.transitions { names += [transition.from] + transition.to }
            for transition in flow.conditionalTransitions { names += [transition.from, transition.to] }
            for transition in flow.errorTransitions {
                names += [transition.from, transition.to].compactMap { $0 }.filter { $0 != "*" }
                let recipeId = transition.targetRecipeId ?? ""
                if transition.to?.isEmpty ?? true, recipes[recipeId] == nil { recipes[recipeId] = claim("Recipe_" + IdMap.sanitized(recipeId)) }
            }
            for name in names where map[name.lowercased()] == nil && !name.trimmingCharacters(in: .whitespaces).isEmpty {
                map[name.lowercased()] = claim(IdMap.isSafe(name) ? name : "x_" + IdMap.sanitized(name))
            }
        }

        static func isSafe(_ id: String) -> Bool {
            guard let first = id.unicodeScalars.first, !keywords.contains(id.lowercased()), id != anyStepId else { return false }
            func isLetter(_ scalar: Unicode.Scalar) -> Bool { (scalar >= "a" && scalar <= "z") || (scalar >= "A" && scalar <= "Z") }
            guard isLetter(first) || first == "_" else { return false }
            return id.unicodeScalars.allSatisfy { isLetter($0) || ($0 >= "0" && $0 <= "9") || $0 == "_" }
        }

        static func sanitized(_ id: String) -> String {
            String(id.unicodeScalars.map { scalar -> Character in
                let ok = (scalar >= "a" && scalar <= "z") || (scalar >= "A" && scalar <= "Z") || (scalar >= "0" && scalar <= "9")
                return ok ? Character(scalar) : "_"
            })
        }

        /// A step's id, or a safe id for a name that isn't a step.
        func id(_ nodeId: String) -> String {
            map[nodeId.lowercased()] ?? (IdMap.isSafe(nodeId) ? nodeId : "x_" + IdMap.sanitized(nodeId))
        }

        /// The id of another recipe an error route forwards to.
        func recipe(_ recipeId: String) -> String {
            recipes[recipeId] ?? "Recipe_" + IdMap.sanitized(recipeId)
        }
    }

    /// The start steps, the only step of a recipe without any too (`RecipeOutline.startSteps`).
    static func startNodes(_ recipe: CaptureRecipe) -> [String] {
        RecipeOutline.startSteps(of: recipe)
    }

    static func nodeLabel(_ node: RecipeNode) -> String {
        let name = node.name?.trimmingCharacters(in: .whitespaces) ?? ""
        let label = name.isEmpty ? node.stepType : "\(name) (\(node.stepType))"
        return "\(label) [\(node.id)]".replacingOccurrences(of: "\"", with: "'")
    }

    static func branchLabel(_ transition: ConditionalTransition, in recipe: CaptureRecipe) -> String {
        var expression = ""
        if let source = recipe.node(transition.from) {
            expression = ConditionalBranch.read(source).first { recipeEquals($0.key, transition.branch) }?.expression ?? ""
        }
        let label = expression.isEmpty ? transition.branch : "\(transition.branch): \(expression)"
        return label.replacingOccurrences(of: "\"", with: "'")
    }

    static func triggerLabel(_ trigger: TriggerConfig) -> String {
        func parameter(_ key: String, _ fallback: String) -> String { trigger.parameters.string(key) ?? fallback }
        var label: String
        switch trigger.triggerType.lowercased() {
        case WellKnownTriggerType.hotkey.lowercased():
            label = "⚡ Hotkey: \(parameter("Hotkey", "Shortcut"))"
        case WellKnownTriggerType.contextMenu.lowercased(), WellKnownTriggerType.systray.lowercased():
            label = "🖱️ Menu: \(parameter("MenuItemText", trigger.name ?? "Context Menu"))"
        case WellKnownTriggerType.editor.lowercased():
            label = "🎨 Editor: \(parameter("MenuItemText", trigger.name ?? "Editor Menu"))"
        case WellKnownTriggerType.clipboard.lowercased():
            label = "📋 Clipboard Monitor"
        case WellKnownTriggerType.manual.lowercased():
            label = "⚡ Manual: \(trigger.name ?? "User Action")"
        case WellKnownTriggerType.schedule.lowercased():
            label = "⏰ Schedule: \(parameter("CronExpression", parameter("IntervalSeconds", "Timer")))"
        case WellKnownTriggerType.commandline.lowercased():
            label = "💻 CLI: \(parameter("Command", trigger.name ?? "command"))"
        case WellKnownTriggerType.openFile.lowercased():
            label = "📂 Open With File"
        case WellKnownTriggerType.extension.lowercased():
            let browser = parameter("Browser", "")
            label = browser.isEmpty ? "🌐 Browser Extension" : "🌐 Browser Extension (\(browser))"
        case WellKnownTriggerType.aiTool.lowercased():
            label = "🤖 AI tool: \(parameter("ToolName", trigger.name ?? "tool"))"
        default:
            label = "⚡ \(trigger.name ?? trigger.triggerType)"
        }
        if !trigger.enabled { label += " (Disabled)" }
        return label.replacingOccurrences(of: "\"", with: "'")
    }

    /// The flowchart text.
    public static func text(of recipe: CaptureRecipe?) -> String {
        guard let recipe else { return "flowchart TD\n" }
        let graph = RecipeFlowGraph(recipe)
        let ids = IdMap(recipe)
        var lines = ["flowchart TD"]
        let triggers = graph.nodes.filter { $0.role == .trigger }
        if !triggers.isEmpty {
            lines.append("    %% Triggers")
            lines.append("    subgraph Triggers [\"🚀 Triggers\"]")
            for trigger in triggers { lines.append("        \(trigger.id)([\"\(trigger.label)\"])") }
            lines.append("    end")
            lines.append("")
        }
        lines.append("    %% Node Definitions")
        for node in graph.nodes where node.role == .step {
            lines.append(node.shape == .diamond ? "    \(node.id){\"\(node.label)\"}" : "    \(node.id)[\"\(node.label)\"]")
        }
        if graph.nodes.contains(where: { $0.role == .anyStep }) { lines.append("    \(anyStepId)([\"Any step\"])") }
        let starts = startNodes(recipe)
        func section(_ title: String, _ style: RecipeFlowGraph.EdgeStyle, always: Bool = false, _ format: (RecipeFlowGraph.Edge) -> String) {
            let edges = graph.edges.filter { $0.style == style }
            guard always || !edges.isEmpty else { return }
            lines.append("")
            lines.append("    %% \(title)")
            lines += edges.map(format)
        }
        section("Trigger Invocations", .trigger) { "    \($0.from) -.-> \($0.to)" }
        section("Unconditional Transitions", .normal, always: true) { "    \($0.from) --> \($0.to)" }
        section("Conditional Branch Transitions", .conditional) { "    \($0.from) -- \"\($0.label ?? "")\" --> \($0.to)" }
        section("Error Handling Fallbacks", .error) { "    \($0.from) -. \"\($0.label ?? "")\" .-> \($0.to)" }
        if !starts.isEmpty {
            lines.append("")
            lines.append("    %% Start Nodes Styling")
            lines.append("    classDef startNode fill:#238636,stroke:#2ea043,stroke-width:2px,color:#ffffff;")
            for start in starts { lines.append("    class \(ids.id(start)) startNode;") }
        }
        if !triggers.isEmpty {
            lines.append("")
            lines.append("    %% Triggers Styling")
            lines.append("    classDef triggerNode fill:#d97706,stroke:#f59e0b,stroke-width:2px,color:#ffffff;")
            lines.append("    class \(triggers.map(\.id).joined(separator: ",")) triggerNode;")
        }
        return lines.joined(separator: "\n") + "\n"
    }
}
