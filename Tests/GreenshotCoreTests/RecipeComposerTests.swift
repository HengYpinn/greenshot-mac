// Greenshot for Mac (Community) - an unofficial macOS port of Greenshot
// Copyright (C) 2026 Greenshot for Mac (Community) contributors
// Based on Greenshot, Copyright (C) 2007-2026 Thomas Braun, Jens Klingen, Robin Krom
// SPDX-License-Identifier: GPL-3.0-or-later

import CoreGraphics
import Foundation
import Testing
@testable import GreenshotCore

/// Recipes and automatic steps for the composer tests.
enum ComposerFixture {
    /// source -> <slot per name> -> export, linear.
    static func recipe(_ id: String = "cap", slots: [String] = ["BeforeExport"], source: String = "Source",
                       export: String = "Clipboard") -> CaptureRecipe {
        var recipe = CaptureRecipe(id: id, name: "Capture \(id)")
        var nodes = [RecipeNode(id: "source", stepType: source)]
        for (index, slot) in slots.enumerated() {
            nodes.append(RecipeSlotNodes.slot(id: "slot\(index)", name: slot))
        }
        nodes.append(RecipeNode(id: "export", stepType: export))
        recipe.nodes = nodes
        recipe.flow.startNodes = ["source"]
        for index in 0..<(nodes.count - 1) { recipe.flow.addTransition(from: nodes[index].id, to: nodes[index + 1].id) }
        return recipe
    }

    /// An automatic step with a linear chain of SetVariable nodes, the last one leading to Out.
    static func ext(_ id: String, recipes: [String] = ["*capture"], slot: String = "BeforeExport", order: Int = 0,
                    nodes: [String] = ["a"]) -> CaptureRecipe {
        var ext = CaptureRecipe(id: id, name: "Ext \(id)")
        ext.kind = .extension
        ext.extends = ExtensionTarget(recipes: recipes, slot: slot, order: order)
        ext.nodes = nodes.map { RecipeNode(id: $0, stepType: "SetVariable", parameters: ["Variable": .string("v_\($0)"), "Value": .bool(true)]) }
        ext.flow.startNodes = [nodes[0]]
        for index in 0..<(nodes.count - 1) { ext.flow.addTransition(from: nodes[index], to: nodes[index + 1]) }
        ext.flow.addTransition(from: nodes[nodes.count - 1], to: "Out")
        return ext
    }

    static func ids(_ recipe: CaptureRecipe) -> [String] { recipe.nodes.map(\.id) }
}

@Suite struct RecipeComposerTests {
    typealias F = ComposerFixture

    // MARK: Which recipes

    @Test func targetsByIdAllAndCaptures() {
        let capture = F.recipe()
        #expect(RecipeComposer.targets(F.ext("e", recipes: ["*capture"]), capture))
        #expect(RecipeComposer.targets(F.ext("e", recipes: ["*"]), capture))
        #expect(RecipeComposer.targets(F.ext("e", recipes: ["CAP"]), capture))
        #expect(!RecipeComposer.targets(F.ext("e", recipes: ["other"]), capture))
        // Without a destination it isn't a capture recipe.
        let noExport = F.recipe(export: "SetVariable")
        #expect(!RecipeComposer.targets(F.ext("e", recipes: ["*capture"]), noExport))
        #expect(RecipeComposer.targets(F.ext("e", recipes: ["*"]), noExport))
    }

    @Test func aiToolRecipesOnlyById() {
        var ai = F.recipe("ai_tool")
        ai.triggers = [TriggerConfig(triggerType: "AiTool")]
        #expect(!RecipeComposer.targets(F.ext("e", recipes: ["*"]), ai))
        #expect(!RecipeComposer.targets(F.ext("e", recipes: ["*capture"]), ai))
        #expect(RecipeComposer.targets(F.ext("e", recipes: ["ai_tool"]), ai))
    }

    @Test func slotsAcceptAllNoneOrAList() {
        var recipe = F.recipe()
        #expect(RecipeComposer.canExtend(F.ext("e"), recipe))
        recipe.nodes[1].parameters["Accept"] = .string("none")
        #expect(!RecipeComposer.canExtend(F.ext("e"), recipe))
        recipe.nodes[1].parameters["Accept"] = .string("x, E")
        #expect(RecipeComposer.canExtend(F.ext("e"), recipe))
        recipe.nodes[1].parameters["Accept"] = .array([.string("x")])
        #expect(!RecipeComposer.canExtend(F.ext("e"), recipe))
        // Another slot name: no place for it.
        #expect(!RecipeComposer.canExtend(F.ext("e", slot: "AfterExport"), F.recipe()))
    }

    /// Upstream `RecipeStepConfig.AddStandardSlots`: the four slots of the built-in capture recipes.
    @Test func standardSlotsGoAroundTheExport() {
        var recipe = F.recipe(slots: [])
        recipe.nodes.insert(RecipeNode(id: "scan", stepType: "SetVariable"), at: 1)
        recipe.flow = RecipeFlow(startNodes: ["source"])
        recipe.flow.addTransition(from: "source", to: "scan")
        recipe.flow.addTransition(from: "scan", to: "export")
        RecipeSlotNodes.addStandardSlots(to: &recipe, afterCaptureBefore: "scan", exportNode: "export")
        #expect(F.ids(recipe) == ["source", "after_capture", "scan", "before_export", "before_destination", "export", "after_export"])
        #expect(recipe.flow.targets(from: "source") == ["after_capture"])
        #expect(recipe.flow.targets(from: "after_capture") == ["scan"])
        #expect(recipe.flow.targets(from: "scan") == ["before_export"])
        #expect(recipe.flow.targets(from: "before_export") == ["before_destination"])
        #expect(recipe.flow.targets(from: "before_destination") == ["export"])
        #expect(recipe.flow.targets(from: "export") == ["after_export"])
        let errors = RecipeValidator().validate(recipe).errors
        #expect(errors.isEmpty)
        #expect(RecipeComposer.slotName(of: recipe.nodes[1]) == "AfterCapture")
    }

    // MARK: Composing

    @Test func nothingApplicableReturnsTheRecipeItself() {
        let recipe = F.recipe()
        let composed = RecipeComposer.compose(recipe, extensions: [F.ext("e", slot: "AfterCapture")])
        #expect(composed == recipe)
        #expect(composed.composition == nil)
        let off = RecipeComposer.compose(recipe, extensions: [F.ext("e")]) { _ in RecipeExtensionSettings(enabled: false) }
        #expect(off == recipe)
    }

    @Test func theSlotIsReplacedByTheChain() {
        let recipe = F.recipe()
        let composed = RecipeComposer.compose(recipe, extensions: [F.ext("e", nodes: ["a", "b"])])
        #expect(F.ids(composed) == ["source", "e/a", "e/b", "export"])
        #expect(composed.flow.targets(from: "source") == ["e/a"])
        #expect(composed.flow.targets(from: "e/a") == ["e/b"])
        #expect(composed.flow.targets(from: "e/b") == ["export"])
        let applied = composed.composition?.appliedExtensions.map(\.id)
        #expect(applied == ["e"])
        #expect(composed.composition?.destinationChains.isEmpty == true)
        // Composing again changes nothing.
        let again = RecipeComposer.compose(composed, extensions: [F.ext("x")])
        #expect(again == composed)
    }

    @Test func chainsRunByOrderThenId() {
        let recipe = F.recipe()
        let composed = RecipeComposer.compose(recipe, extensions: [F.ext("b", order: 200), F.ext("z", order: 100), F.ext("a", order: 200)])
        #expect(F.ids(composed) == ["source", "z/a", "a/a", "b/a", "export"])
        #expect(composed.flow.targets(from: "source") == ["z/a"])
        #expect(composed.flow.targets(from: "z/a") == ["a/a"])
        #expect(composed.flow.targets(from: "a/a") == ["b/a"])
        #expect(composed.flow.targets(from: "b/a") == ["export"])
    }

    @Test func startNodesConditionalsAndErrorRoutesIntoTheSlot() {
        var recipe = F.recipe()
        recipe.flow.startNodes = ["slot0"]
        recipe.flow.conditionalTransitions = [ConditionalTransition(from: "source", branch: "yes", to: "slot0")]
        recipe.flow.errorTransitions = [ErrorTransition(from: "*", to: "slot0"), ErrorTransition(from: "slot0", to: "export")]
        recipe.nodes[0].onErrorNodeId = "slot0"
        let composed = RecipeComposer.compose(recipe, extensions: [F.ext("e")])
        #expect(composed.flow.startNodes == ["e/a"])
        let conditional = composed.flow.conditionalTransitions.first { $0.from == "source" }
        #expect(conditional?.to == "e/a")
        #expect(composed.flow.errorTransitions.count == 1)
        #expect(composed.flow.errorTransitions.first?.to == "e/a")
        #expect(composed.nodes[0].onErrorNodeId == "e/a")
    }

    @Test func outRoutesAndBranchesLeadOnToTheRecipe() {
        var ext = F.ext("e", nodes: ["n1"])
        ext.nodes.insert(RecipeNode(id: "c", stepType: "Conditional", parameters: ["Branches": .array([
            .object(["Key": .string("yes"), "Expression": .string("${payload.width > 10}")]),
            .object(["Key": .string("no"), "Expression": .string("else")])
        ])]), at: 0)
        ext.flow.startNodes = ["c"]
        ext.flow.conditionalTransitions = [ConditionalTransition(from: "c", branch: "yes", to: "Out"),
                                           ConditionalTransition(from: "c", branch: "no", to: "n1")]
        let composed = RecipeComposer.compose(F.recipe(), extensions: [ext])
        #expect(composed.flow.targets(from: "source") == ["e/c"])
        let yes = composed.flow.conditionalTransitions.filter { $0.from == "e/c" && $0.branch == "yes" }.map(\.to)
        let no = composed.flow.conditionalTransitions.filter { $0.from == "e/c" && $0.branch == "no" }.map(\.to)
        #expect(yes == ["export"])
        #expect(no == ["e/n1"])
        #expect(composed.flow.targets(from: "e/n1") == ["export"])
        // The conditional node itself doesn't lead on with a plain transition.
        #expect(composed.flow.targets(from: "e/c").isEmpty)
    }

    @Test func whenStartsWithAConditionalThatSkipsTheChain() {
        var ext = F.ext("e")
        ext.when = "${payload.width > 800}"
        let composed = RecipeComposer.compose(F.recipe(), extensions: [ext])
        #expect(F.ids(composed) == ["source", "e/when", "e/a", "export"])
        #expect(composed.flow.targets(from: "source") == ["e/when"])
        let run = composed.flow.conditionalTransitions.first { $0.from == "e/when" && $0.branch == "run" }
        let skip = composed.flow.conditionalTransitions.first { $0.from == "e/when" && $0.branch == "skip" }
        #expect(run?.to == "e/a")
        #expect(skip?.to == "export")
        let branches = ConditionalBranch.read(composed.nodes[1])
        #expect(branches.map(\.key) == ["run", "skip"])
        #expect(branches.first?.expression == "${payload.width > 800}")
    }

    @Test func idsArePrefixedAndUnique() {
        // Two slots of the same name: the second insertion has the slot id in the prefix.
        var recipe = F.recipe(slots: ["AfterExport", "AfterExport"])
        recipe.nodes.insert(RecipeNode(id: "e/a", stepType: "SetVariable"), at: 1)
        let composed = RecipeComposer.compose(recipe, extensions: [F.ext("e", slot: "AfterExport")])
        #expect(F.ids(composed) == ["source", "e/a", "e/a_2", "e/slot1/a", "export"])
    }

    @Test func optionReferencesReadTheAutomaticStepsOptions() {
        #expect(RecipeComposer.rewriteOptionReferences("${option.width}", extensionId: "ext_border") == "${option.ext_border.width}")
        #expect(RecipeComposer.rewriteOptionReferences("w ${Option.width * 2} px", extensionId: "e") == "w ${option.e.width * 2} px")
        #expect(RecipeComposer.rewriteOptionReferences("${payload.option.x} ${myoption.y}", extensionId: "e") == "${payload.option.x} ${myoption.y}")
        #expect(RecipeComposer.rewriteOptionReferences("option.width", extensionId: "e") == "option.width")
        var ext = F.ext("e")
        ext.nodes[0].parameters["Value"] = .array([.string("${option.width}"), .object(["k": .string("${option.color}")])])
        ext.nodes[0].enabled = .expression("${option.enabled}")
        let composed = RecipeComposer.compose(F.recipe(), extensions: [ext])
        let node = composed.nodes[1]
        #expect(node.parameters["Value"] == .array([.string("${option.e.width}"), .object(["k": .string("${option.e.color}")])]))
        #expect(node.enabled == .expression("${option.e.enabled}"))
    }

    @Test func settingsLimitTheRecipes() {
        let recipe = F.recipe()
        let except = RecipeComposer.compose(recipe, extensions: [F.ext("e")]) { _ in RecipeExtensionSettings(exceptRecipes: ["CAP"]) }
        #expect(except == recipe)
        let only = RecipeComposer.compose(recipe, extensions: [F.ext("e")]) { _ in RecipeExtensionSettings(applyToAll: false, onlyRecipes: ["x"]) }
        #expect(only == recipe)
        let picked = RecipeComposer.compose(recipe, extensions: [F.ext("e")]) { _ in RecipeExtensionSettings(applyToAll: false, onlyRecipes: ["cap"]) }
        #expect(picked != recipe)
    }

    @Test func beforeDestinationBecomesChainsForTheExportSteps() throws {
        let recipe = F.recipe(slots: ["BeforeDestination"])
        var ext = F.ext("e", slot: "BeforeDestination", nodes: ["a", "b"])
        ext.nodes[0].parameters["Value"] = .string("${option.width}")
        let composed = RecipeComposer.compose(recipe, extensions: [ext]) { _ in RecipeExtensionSettings(onlyDestinations: ["EMail"]) }
        // The slot stays where it is; the recipe still differs (it carries the chains).
        #expect(F.ids(composed) == F.ids(recipe))
        #expect(composed != recipe)
        let composition = try #require(composed.composition)
        let chain = try #require(composition.destinationChains.first)
        #expect(chain.extensionId == "e")
        #expect(chain.flow.id == "cap")
        #expect(chain.flow.name == "Capture cap")
        #expect(F.ids(chain.flow) == ["e/a", "e/b"])
        #expect(chain.flow.flow.startNodes == ["e/a"])
        #expect(chain.flow.flow.targets(from: "e/b").isEmpty)
        #expect(chain.flow.nodes[0].parameters["Value"] == .string("${option.e.width}"))
        #expect(chain.flow.composition?.appliedExtensions.map(\.id) == ["e"])
        #expect(composition.chains(forDestination: "email").count == 1)
        #expect(composition.chains(forDestination: "Clipboard").isEmpty)
    }

    @Test func optionsResolveForTheRecipeAndItsAutomaticSteps() {
        var recipe = F.recipe()
        recipe.options = [RecipeOption(key: "mine", type: .integer, defaultValue: .number(1))]
        var ext = F.ext("e")
        ext.options = [RecipeOption(key: "width", type: .integer, defaultValue: .number(2))]
        let composed = RecipeComposer.compose(recipe, extensions: [ext])
        let own = RecipeComposer.resolveOption("mine", in: composed)
        #expect(own?.ownerId == "cap")
        let fromExtension = RecipeComposer.resolveOption("E.width", in: composed)
        #expect(fromExtension?.ownerId == "e")
        #expect(fromExtension?.option.key == "width")
        #expect(RecipeComposer.resolveOption("x.width", in: composed) == nil)
        #expect(RecipeComposer.resolveOption("e.width", in: recipe) == nil)
        #expect(RecipeComposer.resolveOption(".width", in: composed) == nil)
    }

    @Test func extensionSettingsFromTheStoredValues() {
        var ext = F.ext("e")
        ext.options = [RecipeOption(key: "enabled", type: .boolean, defaultValue: .bool(false))]
        let off = RecipeExtensionSettings.stored(for: ext, in: RecipeOptionValues())
        #expect(!off.enabled)
        let values = RecipeOptionValues(["e.enabled": "True", "e.exceptRecipes": "a, b", "e.onlyDestinations": "EMail;Clipboard",
                                         "e.applyTo": "only", "e.onlyRecipes": "c"])
        let stored = RecipeExtensionSettings.stored(for: ext, in: values)
        #expect(stored.enabled)
        #expect(!stored.applyToAll)
        #expect(stored.onlyRecipes == ["c"])
        #expect(stored.exceptRecipes == ["a", "b"])
        #expect(stored.onlyDestinations == ["EMail", "Clipboard"])
        #expect(stored.allowsRecipe("C"))
        #expect(!stored.allowsRecipe("a"))
        #expect(!stored.allowsRecipe("d"))
        // Without an `enabled` option it is always on.
        #expect(RecipeExtensionSettings.stored(for: F.ext("x"), in: RecipeOptionValues()).enabled)
    }
}

/// A composed recipe through the engine with the core executors (proves the option resolution of `RecipeFlowContext`).
@Suite struct RecipeComposerRunTests {
    func borderExtension(when: String? = nil) -> CaptureRecipe {
        var ext = CaptureRecipe(id: "frame", name: "Frame")
        ext.kind = .extension
        ext.extends = ExtensionTarget(recipes: ["flow"], slot: "BeforeExport", order: 1)
        ext.options = [RecipeOption(key: "width", type: .integer, defaultValue: .number(1))]
        ext.nodes = [RecipeNode(id: "border", stepType: "Effect",
                                parameters: ["Effect": .string("Border"), "Width": .string("${option.width}"), "Color": .string("#FF0000")])]
        ext.flow.startNodes = ["border"]
        ext.when = when
        return ext
    }

    /// start (SetVariable) -> before_export -> end (SetVariable): runs with the core executors only.
    func flowRecipe() -> CaptureRecipe {
        var recipe = CaptureRecipe(id: "flow", name: "Flow")
        recipe.nodes = [RecipeNode(id: "start", stepType: "SetVariable", parameters: ["Variable": .string("started"), "Value": .bool(true)]),
                        RecipeSlotNodes.slot(id: "before_export", name: "BeforeExport"),
                        RecipeNode(id: "end", stepType: "SetVariable", parameters: ["Variable": .string("ended"), "Value": .bool(true)])]
        recipe.flow.startNodes = ["start"]
        recipe.flow.addTransition(from: "start", to: "before_export")
        recipe.flow.addTransition(from: "before_export", to: "end")
        return recipe
    }

    func run(_ recipe: CaptureRecipe, values: [String: String]) async -> RecipeFlowContext {
        let context = RecipeFlowContext(recipe: recipe, environment: FixedRecipeEnvironment(), optionValues: RecipeOptionValues(values))
        context.payload = RecipePayload(image: TestImage.solid(width: 40, height: 30, .white), scale: 2, title: "Run")
        let registry = RecipeStepRegistry()
        registry.registerCoreExecutors()
        await RecipeFlowEngine(steps: registry).execute(context)
        return context
    }

    @Test func theAutomaticStepReadsItsStoredOption() async throws {
        let composed = RecipeComposer.compose(flowRecipe(), extensions: [borderExtension()])
        let context = await run(composed, values: ["frame.width": "3"])
        let payload = try #require(context.payload)
        // 3 points on each side at 2 pixels per point.
        #expect(payload.image.width == 52)
        #expect(payload.image.height == 42)
        #expect(context[variable: "ended"] == .bool(true))
    }

    @Test func aFalseWhenSkipsTheAutomaticStep() async throws {
        let composed = RecipeComposer.compose(flowRecipe(), extensions: [borderExtension(when: "${payload.width > 800}")])
        let context = await run(composed, values: [:])
        let payload = try #require(context.payload)
        #expect(payload.image.width == 40)
        #expect(context[variable: "ended"] == .bool(true))
    }
}
