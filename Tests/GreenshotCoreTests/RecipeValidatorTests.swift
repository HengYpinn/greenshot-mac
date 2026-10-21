// Greenshot for Mac (Community) - an unofficial macOS port of Greenshot
// Copyright (C) 2026 Greenshot for Mac (Community) contributors
// Based on Greenshot, Copyright (C) 2007-2026 Thomas Braun, Jens Klingen, Robin Krom
// SPDX-License-Identifier: GPL-3.0-or-later

import Foundation
import Testing
@testable import GreenshotCore

/// A small recipe for the tests: nodes "a" -> "b" (Source, Clipboard) unless given.
func testRecipe(_ nodes: [RecipeNode] = [RecipeNode(id: "a", stepType: "Source"), RecipeNode(id: "b", stepType: "Clipboard")],
                transitions: [(String, [String])] = [("a", ["b"])], start: [String] = ["a"]) -> CaptureRecipe {
    var recipe = CaptureRecipe(id: "test_recipe", name: "Test")
    recipe.nodes = nodes
    recipe.flow.startNodes = start
    recipe.flow.transitions = transitions.map { RecipeTransition(from: $0.0, to: $0.1) }
    return recipe
}

/// Upstream RecipeValidatorTests, rule by rule.
@Suite struct RecipeValidatorTests {
    let validator = RecipeValidator()

    @Test func examplesAreValid() throws {
        for name in RecipeFixtures.exampleNames {
            let recipe = try RecipeFixtures.recipe(name)
            let result = validator.validate(recipe)
            #expect(result.errors.isEmpty, "\(name): \(result.errors)")
        }
    }

    @Test func validDagRecipe() {
        let result = validator.validate(testRecipe())
        #expect(result.isValid)
        #expect(result.gatedActions.isEmpty)
    }

    @Test(arguments: [(".png;.jpg", true), (".png", true), ("*.png;*.jpg", false), ("png", false), (".png,.jpg", false)])
    func openFileFilter(filter: String, valid: Bool) {
        var recipe = testRecipe()
        recipe.triggers = [TriggerConfig(triggerType: "OpenFile", parameters: ["Filter": .string(filter)])]
        let result = validator.validate(recipe)
        let hasFilterError = result.errors.contains { $0.contains("Filter") }
        #expect(hasFilterError == !valid)
    }

    @Test func cycleIsAnError() {
        let recipe = testRecipe([RecipeNode(id: "a", stepType: "Source"), RecipeNode(id: "b", stepType: "Effect"), RecipeNode(id: "c", stepType: "Clipboard")],
                                transitions: [("a", ["b"]), ("b", ["c"]), ("c", ["b"])])
        let result = validator.validate(recipe)
        #expect(result.errors == ["Cycle/loop detected in recipe flow: b -> c -> b. Loops are strictly disallowed in DAG flows."])
    }

    @Test func missingStartAndDuplicateIds() {
        let recipe = testRecipe([RecipeNode(id: "a", stepType: "Source"), RecipeNode(id: "A", stepType: "Clipboard")],
                                transitions: [], start: ["start"])
        let result = validator.validate(recipe)
        #expect(result.errors.contains("Duplicate node id 'A' found in recipe."))
        #expect(result.errors.contains("Flow start node 'start' does not match any defined node id."))
    }

    @Test func header() {
        var recipe = testRecipe()
        recipe.id = ""
        recipe.name = " "
        recipe.version = "2.0"
        let result = validator.validate(recipe)
        #expect(result.errors.contains("Unsupported recipe version '2.0'. This version of Greenshot supports version 1.x recipes."))
        #expect(result.errors.contains("Recipe 'id' is required and cannot be empty."))
        #expect(result.errors.contains("Recipe 'name' is required and cannot be empty."))
        recipe = testRecipe()
        recipe.version = ""
        #expect(validator.validate(recipe).warnings.contains("Recipe 'version' is missing; defaulting to '1.0'."))
    }

    @Test func emptyAndUnknownNodes() {
        let empty = testRecipe([], transitions: [], start: [])
        #expect(validator.validate(empty).errors == ["Recipe must contain at least one node in 'nodes'."])
        let unknown = testRecipe([RecipeNode(id: "a", stepType: "Teleport")], transitions: [])
        #expect(validator.validate(unknown).errors == ["Node 'a' uses stepType 'Teleport', which is not available in this version of Greenshot."])
    }

    @Test func singleNodeNeedsNoStart() {
        let recipe = testRecipe([RecipeNode(id: "only", stepType: "Source")], transitions: [], start: [])
        #expect(validator.validate(recipe).isValid)
    }

    @Test func triggerRules() {
        var recipe = testRecipe()
        recipe.triggers = [
            TriggerConfig(triggerType: "Hotkey", name: "Go"),
            TriggerConfig(triggerType: "Hotkey", name: "Bad", parameters: ["hotkey": .string("Ctrl + Banana")]),
            TriggerConfig(triggerType: "Hotkey", name: "Pause", parameters: ["hotkey": .string("Pause")]),
            TriggerConfig(triggerType: "AiTool", name: "Tool", parameters: ["ToolName": .string("bad name")]),
            TriggerConfig(triggerType: "Teleporter"),
            TriggerConfig(triggerType: "")
        ]
        let result = validator.validate(recipe)
        #expect(result.errors.contains("Hotkey trigger 'Go' at index 0 is missing required 'Hotkey' parameter."))
        #expect(result.errors.contains("Hotkey trigger 'Bad' at index 1 has invalid hotkey 'Ctrl + Banana': 'Banana' is not a key Greenshot knows."))
        #expect(!result.errors.contains { $0.contains("index 2") })
        #expect(result.errors.contains("AI tool trigger 'Tool' at index 3 needs a 'ToolName' of 1 to 64 letters, digits, '_' or '-', not 'bad name'."))
        #expect(result.warnings.contains("AI tool trigger 'Tool' at index 3 has no 'Description', the AI won't know what the tool does."))
        #expect(result.warnings.contains("Trigger at index 4 has unrecognized triggerType 'Teleporter'."))
        #expect(result.errors.contains("Trigger at index 5 is missing required 'triggerType'."))
    }

    /// A Border width of 2^63 in a file is checked without stopping the app (the file is validated before approval).
    @Test func aHugeBorderWidthIsChecked() throws {
        let width = try JSONValue.parse("9223372036854775807")
        let border = RecipeNode(id: "b", stepType: "Effect", parameters: ["Effect": .string("Border"), "Width": width])
        let result = validator.validate(testRecipe([RecipeNode(id: "a", stepType: "Source"), border]))
        #expect(!result.errors.contains { $0.contains("'Width'") })
    }

    @Test func nodeRules() {
        let nodes = [
            RecipeNode(id: "a", stepType: "Source", parameters: ["sourceType": .string("Teleport")]),
            RecipeNode(id: "b", stepType: "Effect", parameters: ["effect": .string("Border"), "width": .number(0)]),
            RecipeNode(id: "c", stepType: "InteractiveSelection", parameters: ["selectionMode": .string("Lasso")]),
            RecipeNode(id: "d", stepType: "Conditional"),
            RecipeNode(id: "e", stepType: "Annotation", parameters: ["annotations": .array([.object(["type": .string("Hologram")])])]),
            RecipeNode(id: "f", stepType: "Slot", parameters: ["name": .string("Middle"), "accept": .number(1)])
        ]
        let result = validator.validate(testRecipe(nodes, transitions: [("a", ["b", "c", "d", "e", "f"])]))
        #expect(result.errors.contains("Node 'a' [Source]: Unknown SourceType 'Teleport'."))
        #expect(result.errors.contains("Node 'b' [Border]: 'Width' must be greater than or equal to 1 (got 0)."))
        #expect(result.errors.contains("Node 'c' [InteractiveSelection]: Unknown SelectionMode 'Lasso'."))
        #expect(result.errors.contains("Node 'd' [Conditional]: Missing required 'branches' configuration list."))
        #expect(result.errors.contains { $0.hasPrefix("Node 'e' uses custom annotation type 'Hologram'") })
        #expect(result.errors.contains("Node 'f' [Slot]: 'name' must be one of AfterCapture, BeforeExport, AfterExport, BeforeDestination."))
        #expect(result.errors.contains("Node 'f' [Slot]: 'accept' must be \"all\", \"none\" or a list of extension ids."))
    }

    @Test func flowReferences() {
        var recipe = testRecipe(transitions: [("a", ["b", "ghost"]), ("phantom", ["b"])])
        recipe.flow.conditionalTransitions = [ConditionalTransition(from: "a", branch: "", to: "nowhere")]
        let result = validator.validate(recipe)
        #expect(result.errors.contains("Flow transition target node 'ghost' (from 'a') does not exist in 'nodes'."))
        #expect(result.errors.contains("Flow transition source node 'phantom' does not exist in 'nodes'."))
        #expect(result.errors.contains("Conditional transition from 'a' is missing 'branch' key."))
        #expect(result.warnings.contains("Conditional transition source node 'a' has stepType 'Source' rather than 'Conditional'."))
    }

    /// An error handler that isn't a node would let the failed node end the flow as a success.
    @Test func errorHandlerReferences() {
        var recipe = testRecipe([RecipeNode(id: "a", stepType: "Source"), RecipeNode(id: "b", stepType: "Clipboard"),
                                 RecipeNode(id: "handler", stepType: "Clipboard")])
        recipe.nodes[1].onErrorNodeId = "typo"
        // Errors of other types than these two reach "typo".
        recipe.flow.errorTransitions = [ErrorTransition(from: "a", to: "ghost"),
                                        ErrorTransition(from: "*", to: "HANDLER", errorType: "TimeoutException"),
                                        ErrorTransition(from: "b", to: "elsewhere", targetRecipeId: "recovery", errorType: "IOException")]
        let result = validator.validate(recipe)
        #expect(result.errors.contains("Error handler node 'typo' of node 'b' does not exist in 'nodes'."))
        #expect(result.errors.contains("Error transition target node 'ghost' (from 'a') does not exist in 'nodes'."))
        // Existing nodes (any case) and transitions to another recipe are fine.
        #expect(result.errors.count == 2)
        recipe.nodes[1].onErrorNodeId = "Handler"
        recipe.flow.errorTransitions.removeFirst()
        #expect(validator.validate(recipe).errors.isEmpty)
    }

    /// Only a target the engine really runs as a node is checked: a target recipe wins over it (the transition's or the
    /// node's own), a transition that matches every error hides the node's own target, a transition from no node is
    /// never used; one that many nodes reach is reported once.
    @Test func errorHandlerTargetsTheEngineNeverRunsAreFine() {
        let nodes = [RecipeNode(id: "a", stepType: "Source"), RecipeNode(id: "b", stepType: "Clipboard")]
        var forwardedByTheNode = testRecipe(nodes)
        forwardedByTheNode.nodes[1].onErrorRecipeId = "recovery"
        forwardedByTheNode.flow.errorTransitions = [ErrorTransition(from: "b", to: "ghost")]
        #expect(validator.validate(forwardedByTheNode).errors.isEmpty)

        var forwardedByAWildcard = testRecipe(nodes)
        forwardedByAWildcard.nodes[1].onErrorNodeId = "typo"
        forwardedByAWildcard.flow.errorTransitions = [ErrorTransition(from: "*", targetRecipeId: "recovery")]
        #expect(validator.validate(forwardedByAWildcard).errors.isEmpty)

        var fromNoNode = testRecipe(nodes)
        fromNoNode.flow.errorTransitions = [ErrorTransition(from: "nobody", to: "ghost")]
        #expect(validator.validate(fromNoNode).errors.isEmpty)

        var shadowed = testRecipe(nodes)
        shadowed.flow.errorTransitions = [ErrorTransition(from: "a", to: "b", errorType: "IOException"),
                                          ErrorTransition(from: "b", targetRecipeId: "recovery", errorType: "IOException"),
                                          ErrorTransition(from: "*", to: "ghost", errorType: "IOException")]
        #expect(validator.validate(shadowed).errors.isEmpty)

        var reachedByBoth = testRecipe(nodes)
        reachedByBoth.flow.errorTransitions = [ErrorTransition(from: "*", to: "ghost")]
        #expect(validator.validate(reachedByBoth).errors == ["Error transition target node 'ghost' (from '*') does not exist in 'nodes'."])
    }

    @Test func gatedActions() {
        let nodes = [
            RecipeNode(id: "a", stepType: "Source", parameters: ["sourceType": .string("File"), "filename": .string("/tmp/x.png")]),
            RecipeNode(id: "b", stepType: "ExternalCommand", parameters: ["commandLine": .string("/bin/sh")]),
            RecipeNode(id: "c", stepType: "Destinations", parameters: ["destinationDesignations": .array([.string("External Paint"), .string("Jira")])])
        ]
        let gates = GateEnvironment(commandLine: { $0 == "Paint" ? "/Applications/Paint.app" : nil })
        let result = RecipeValidator(gates: gates).validate(testRecipe(nodes, transitions: [("a", ["b"]), ("b", ["c"])]))
        #expect(result.gatedActions.count == 4)
        #expect(result.gatedActions.contains(RecipeGatedAction(.externalCommand, target: "/Applications/Paint.app")))
        #expect(result.gateTypes == [.externalCommand, .networkAccess, .fileSystemAccess])
    }

    @Test func requirements() {
        var recipe = testRecipe()
        recipe.requires = [RecipeRequirement(id: "Greenshot.Plugin.Zxing", minVersion: "1.3.0"),
                           RecipeRequirement(id: "Acme.Plugin", url: "https://example.org/acme")]
        let result = validator.validate(recipe)
        #expect(result.errors.count == 1)
        #expect(result.errors.first?.contains("https://example.org/acme") == true)
    }

    @Test func optionRules() {
        var recipe = testRecipe([RecipeNode(id: "a", stepType: "Source"),
                                 RecipeNode(id: "b", stepType: "Effect", parameters: ["width": .string("${option.width}"), "color": .string("${option.missing}")]),
                                 RecipeNode(id: "c", stepType: "ExternalCommand", parameters: ["arguments": .string("${option.caption}")])],
                                transitions: [("a", ["b"]), ("b", ["c"])])
        recipe.nodes[1].enabled = .expression("option.border")
        var width = RecipeOption(key: "width", type: .integer, defaultValue: .string("wide"))
        width.min = 5
        width.max = 1
        var choice = RecipeOption(key: "mode", type: .enumeration)
        choice.quickSettings = true
        var follower = RecipeOption(key: "follower", type: .boolean)
        follower.enabledWhen = "width"
        recipe.options = [width, RecipeOption(key: "9bad"), RecipeOption(key: "Width"), choice, follower,
                          RecipeOption(key: "caption", type: .string)]
        let result = validator.validate(recipe)
        #expect(result.errors.contains("Option key '9bad' is invalid: use letters, digits and underscores, starting with a letter."))
        #expect(result.errors.contains("Duplicate option key 'Width'."))
        #expect(result.errors.contains("Option 'width': 'min' (5) is larger than 'max' (1)."))
        #expect(result.errors.contains("Option 'width': the default 'wide' is not a valid Integer."))
        #expect(result.errors.contains("Option 'mode' is an Enum and needs 'choices', each with a 'value'."))
        #expect(result.errors.contains("Option 'follower': 'enabledWhen' must be the key of another Boolean option of the recipe."))
        #expect(result.errors.contains("Node 'b': 'enabled' must be true, false or an expression like \"${option.key}\"."))
        #expect(result.errors.contains("Node 'b' uses the option 'missing', which the recipe doesn't declare in 'options'."))
        #expect(result.errors.contains("Node 'c' needs an approval and can't use the text option(s) 'caption'."))
    }

    @Test func expressionSyntaxWarnings() {
        let recipe = testRecipe([RecipeNode(id: "a", stepType: "Source"),
                                 RecipeNode(id: "b", stepType: "Clipboard", parameters: ["clipboardCustomText": .string("${a + (b}")])])
        let result = validator.validate(recipe)
        #expect(result.isValid)
        #expect(result.warnings.contains { $0.hasPrefix("Node 'b' parameter 'clipboardCustomText': the expression") })
    }

    @Test func extensionFiles() {
        var recipe = testRecipe([RecipeNode(id: "Out", stepType: "Source"),
                                 RecipeNode(id: "decide", stepType: "Conditional",
                                            parameters: ["branches": .array([.object(["key": .string("big"), "expression": .string("${payload.width > 9}")])])])],
                                transitions: [], start: ["decide"])
        recipe.kind = .extension
        recipe.id = "ext-bad"
        recipe.extends = ExtensionTarget(recipes: ["*"], slot: "Nowhere")
        recipe.when = "true"
        let result = validator.validate(recipe)
        #expect(result.errors.contains("Extension id 'ext-bad' is invalid: use letters, digits and underscores, starting with a letter."))
        #expect(result.errors.contains("Extension slot 'Nowhere' is unknown, use AfterCapture, BeforeExport, AfterExport, BeforeDestination."))
        #expect(result.errors.contains("Extension 'when' must be an expression like \"${payload.width > 800}\"."))
        #expect(result.errors.contains("Node id 'Out' is reserved in extensions (In and Out are where the extension starts and ends)."))
        #expect(result.errors.contains("Node 'Out': an extension can't capture, it works on the capture of the recipe it extends."))
        #expect(result.errors.contains("Node 'decide' [Conditional]: in an extension a decision needs an \"else\" branch, so the recipe always goes on."))
        #expect(result.errors.contains("Node 'decide' [Conditional]: branch 'big' leads nowhere; route it to a node or to \"Out\"."))
    }

    /// A chain of `count` Stdout nodes; with `loop`, the last one leads back to the first.
    static func chain(_ count: Int, loop: Bool = false) -> CaptureRecipe {
        var recipe = CaptureRecipe(id: "chain", name: "Chain")
        recipe.nodes = (0..<count).map { RecipeNode(id: "n\($0)", stepType: "Stdout") }
        recipe.flow.startNodes = ["n0"]
        // Built directly: addTransition looks for the source first, which is slow for twenty thousand nodes.
        recipe.flow.transitions = (1..<count).map { RecipeTransition(from: "n\($0 - 1)", to: ["n\($0)"]) }
        if loop { recipe.flow.transitions.append(RecipeTransition(from: "n\(count - 1)", to: ["n0"])) }
        return recipe
    }

    /// Security review: the cycle search used one recursion per node and overflowed the stack of a background thread at a
    /// few hundred nodes; the flow analysis takes minutes at twenty thousand. Both run before approval.
    @Test func longFlowsDontCrashOrHang() async {
        let long = Self.chain(20_000)
        let ids = Set(long.nodes.map { $0.id.lowercased() })
        let none = await Task.detached { RecipeValidator.findCycle(long, starts: ["n0"], ids: ids) }.value
        #expect(none == nil)
        let looped = Self.chain(20_000, loop: true)
        let cycle = await Task.detached { RecipeValidator.findCycle(looped, starts: ["n0"], ids: ids) }.value
        #expect(cycle?.count == 20_001)
        #expect(cycle?.first == "n0")
        let refused = await Task.detached { RecipeValidator().validate(long) }.value
        #expect(refused.errors == ["The recipe has 20000 nodes; at most 200 are allowed."])
        let largest = await Task.detached { RecipeValidator().validate(Self.chain(200)) }.value
        #expect(largest.isValid)
        var noisy = testRecipe()
        noisy.triggers = Array(repeating: TriggerConfig(triggerType: "Clipboard"), count: 51)
        #expect(validator.validate(noisy).errors == ["The recipe has 51 triggers; at most 50 are allowed."])
    }
}
