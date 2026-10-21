// Greenshot for Mac (Community) - an unofficial macOS port of Greenshot
// Copyright (C) 2026 Greenshot for Mac (Community) contributors
// Based on Greenshot, Copyright (C) 2007-2026 Thomas Braun, Jens Klingen, Robin Krom
// SPDX-License-Identifier: GPL-3.0-or-later

import Foundation
import Testing
@testable import GreenshotCore

/// The recipe files of upstream's docs/examples and docs/recipe.schema.json (Fixtures/Recipes).
enum RecipeFixtures {
    static let folder = Bundle.module.url(forResource: "Fixtures", withExtension: nil)!.appendingPathComponent("Recipes")

    static var exampleNames: [String] {
        let names = (try? FileManager.default.contentsOfDirectory(atPath: folder.path)) ?? []
        return names.filter { $0.hasSuffix(".gsrecipe.json") }.sorted()
    }

    static func data(_ name: String) throws -> Data {
        try Data(contentsOf: folder.appendingPathComponent(name))
    }

    static func recipe(_ name: String) throws -> CaptureRecipe {
        let recipes = try RecipeSerializer.decode(data(name))
        return try #require(recipes.first)
    }
}

@Suite struct RecipeModelTests {
    @Test func allElevenExamplesDecode() throws {
        #expect(RecipeFixtures.exampleNames.count == 11)
        for name in RecipeFixtures.exampleNames {
            let recipes = try RecipeSerializer.decode(RecipeFixtures.data(name))
            #expect(recipes.count == 1, "\(name)")
            let recipe = try #require(recipes.first)
            #expect(!recipe.id.isEmpty, "\(name)")
            #expect(!recipe.nodes.isEmpty, "\(name)")
            #expect(recipe.kind == .recipe, "\(name)")
        }
    }

    @Test func examplesRoundTrip() throws {
        for name in RecipeFixtures.exampleNames {
            let recipe = try RecipeFixtures.recipe(name)
            let text = RecipeSerializer.encode(recipe)
            let again = try RecipeSerializer.decode(text: text)
            let first = try #require(again.first)
            #expect(first == recipe, "\(name)")
        }
    }

    @Test func blueBorderExample() throws {
        let recipe = try RecipeFixtures.recipe("region_blue_border.gsrecipe.json")
        #expect(recipe.id == "recipe_region_blue_border")
        #expect(recipe.schema == nil)
        #expect(recipe.version == "1.0")
        #expect(recipe.triggers.count == 2)
        let border = try #require(recipe.node("BORDER"))
        #expect(border.stepType == "Effect")
        #expect(border.parameters.string("Effect") == "Border")
        #expect(border.parameters.int("width") == 2)
        #expect(recipe.flow.startNodes == ["source"])
        #expect(recipe.flow.targets(from: "Source") == ["select"])
    }

    @Test func leakedRuntimeKeysStayInExtra() throws {
        let text = """
        {"id": "r", "name": "R", "isBuiltIn": true, "filePath": "C:\\\\x.json", "isOverridden": false,
         "nodes": [{"id": "a", "stepType": "Source"}], "flow": {"startNodes": ["a"]}}
        """
        let recipe = try #require(try RecipeSerializer.decode(text: text).first)
        #expect(recipe.extra["isBuiltIn"] == .bool(true))
        #expect(recipe.extra.count == 3)
        let written = RecipeSerializer.encode(recipe)
        #expect(written.contains("\"isBuiltIn\": true"))
    }

    @Test func layoutStartsWithKind() throws {
        let recipe = try RecipeFixtures.recipe("region_blue_border.gsrecipe.json")
        let object = try #require(RecipeSerializer.json(of: recipe).objectValue)
        #expect(object.keys.first == "kind")
        let text = RecipeSerializer.encode(recipe)
        #expect(text.hasPrefix("{\n  \"kind\": \"recipe\","))
    }

    @Test func arrayFilesAndExtensions() throws {
        let text = """
        [{"id": "a", "name": "A", "nodes": [], "flow": {}},
         {"kind": "Extension", "id": "ext_x", "name": "X", "extends": {"recipes": ["*"], "slot": "BeforeExport", "order": 5},
          "when": "${payload.width > 10}", "nodes": [], "flow": {}}]
        """
        let recipes = try RecipeSerializer.decode(text: text)
        #expect(recipes.count == 2)
        #expect(recipes[1].kind == .extension)
        let extends = try #require(recipes[1].extends)
        #expect(extends.slot == "BeforeExport")
        #expect(extends.order == 5)
        let again = try RecipeSerializer.decode(text: RecipeSerializer.encode(recipes))
        #expect(again == recipes)
    }

    @Test func badShapesAreReported() {
        #expect(throws: RecipeFormatError.self) { try RecipeSerializer.decode(text: "") }
        #expect(throws: RecipeFormatError.self) { try RecipeSerializer.decode(text: "42") }
        #expect(throws: RecipeFormatError.self) { try RecipeSerializer.decode(text: #"{"kind": "macro"}"#) }
        #expect(throws: RecipeFormatError.self) { try RecipeSerializer.decode(text: #"{"nodes": ["x"]}"#) }
        #expect(throws: RecipeFormatError.self) { try RecipeSerializer.decode(text: #"{"concurrency": "Sometimes"}"#) }
        #expect(throws: RecipeFormatError.self) { try RecipeSerializer.decode(text: #"{"options": [{"key": "a", "type": "Nope"}]}"#) }
    }

    @Test func transitionsAsStringOrList() throws {
        let text = #"{"id": "r", "name": "R", "nodes": [], "flow": {"startNodes": "a", "transitions": {"a": "b", "b": ["c", "d"]}}}"#
        let recipe = try #require(try RecipeSerializer.decode(text: text).first)
        #expect(recipe.flow.startNodes == ["a"])
        #expect(recipe.flow.targets(from: "a") == ["b"])
        #expect(recipe.flow.targets(from: "B") == ["c", "d"])
    }

    @Test func nodeEnabledForms() throws {
        let text = """
        {"id": "r", "name": "R", "flow": {}, "nodes": [
          {"id": "a", "stepType": "Source", "enabled": false},
          {"id": "b", "stepType": "Source", "enabled": "False"},
          {"id": "c", "stepType": "Source", "enabled": " ${option.border} "},
          {"id": "d", "stepType": "Source"}]}
        """
        let recipe = try #require(try RecipeSerializer.decode(text: text).first)
        #expect(recipe.nodes[0].enabled == .value(false))
        #expect(recipe.nodes[1].enabled == .value(false))
        #expect(recipe.nodes[2].enabled == .expression("${option.border}"))
        #expect(recipe.nodes[3].enabled == .value(true))
    }

    @Test func triggerTypedReads() throws {
        let recipe = try RecipeFixtures.recipe("cli_qr_decode.gsrecipe.json")
        let trigger = try #require(recipe.triggers.first)
        #expect(recipe.schema == "../recipe.schema.json")
        #expect(trigger.isType("COMMANDLINE"))
        #expect(trigger.command == "qr")
        #expect(trigger.fireAndForget == false)
        #expect(trigger.stdout == "${Barcode.Text}")
        let argument = try #require(trigger.arguments.first)
        #expect(argument.name == "file")
        #expect(argument.effectiveVariable == "Filename")
        #expect(argument.type == .filePath)
        #expect(argument.required)
        let menu = TriggerConfig(triggerType: "ContextMenu")
        #expect(menu.group == "Recipes")
        #expect(menu.order == 0)
        #expect(menu.onImageCopied)
    }

    @Test func recipeHelpers() throws {
        let recipe = try RecipeFixtures.recipe("dag_watermark_branching.gsrecipe.json")
        #expect(recipe.hasSourceStep)
        #expect(recipe.hasDestinationStep)
        #expect(!recipe.isAIToolRecipe)
        #expect(recipe.firstNode(ofType: "annotation")?.id == "watermark_node")
        let unified = recipe.flow.unifiedTransitions
        #expect(unified["select_node"] == ["feedback_branch", "set_vars_node"])
    }

    @Test func errorTransitionPrecedence() {
        var flow = RecipeFlow()
        flow.errorTransitions = [
            ErrorTransition(from: "*", to: "any"),
            ErrorTransition(from: "*", to: "anyTimeout", errorType: "Timeout"),
            ErrorTransition(from: "a", to: "aAny"),
            ErrorTransition(from: "a", to: "aTimeout", errorType: "Timeout")
        ]
        #expect(flow.errorTransition(from: "A", errorType: "timeout")?.to == "aTimeout")
        #expect(flow.errorTransition(from: "a", errorType: "Other")?.to == "aAny")
        #expect(flow.errorTransition(from: "b", errorType: "Timeout")?.to == "anyTimeout")
        #expect(flow.errorTransition(from: "b", errorType: "Other")?.to == "any")
        #expect(flow.errorTransition(from: "b", errorType: "Wrapper", innerErrorType: "Timeout")?.to == "anyTimeout")
    }

    @Test func optionConversions() {
        var width = RecipeOption(key: "width", type: .integer, defaultValue: .number(2))
        width.min = 1
        width.max = 50
        #expect(width.convert(.string("70")) == .number(50))
        #expect(width.convert(.string("2.5")) == nil)
        #expect(width.resolvedDefault == .number(2))
        #expect(width.storageString(.number(7)) == "7")
        let color = RecipeOption(key: "c", type: .color, defaultValue: .string("#ff0000"))
        #expect(color.resolvedDefault == .string("#FF0000"))
        #expect(color.convert(.string("red")) == nil)
        let flag = RecipeOption(key: "b", type: .boolean)
        #expect(flag.storageString(.bool(true)) == "True")
        #expect(flag.resolvedDefault == .bool(false))
        var choice = RecipeOption(key: "e", type: .enumeration)
        choice.choices = [RecipeOptionChoice(value: "Above"), RecipeOptionChoice(value: "Below")]
        #expect(choice.convert(.string("below")) == .string("Below"))
        #expect(choice.resolvedDefault == .string("Above"))
        var template = RecipeOption(key: "t", type: .string)
        template.format = "Template"
        #expect(template.isTemplate)
    }

    /// A crafted file with thousands of targets of one step (the recipe editor opens it before it is approved): each
    /// target is added once, compared like `recipeEquals`, in file order.
    @Test func thousandsOfTargetsOfOneStep() async {
        let xs = (0..<20_000).map { "x\($0)" }
        var flow = RecipeFlow(startNodes: ["a"])
        flow.transitions = [RecipeTransition(from: "a", to: xs + ["X0", "x1", " "]), RecipeTransition(from: "A", to: ["y"])]
        flow.conditionalTransitions = (0..<20_000).map { ConditionalTransition(from: "a", branch: "b\($0)", to: "z\($0 % 10_000)") }
        let crafted = flow
        let unified = await Task.detached { crafted.unifiedTransitions["a"] ?? [] }.value
        #expect(unified.count == 30_001)
        #expect(Array(unified.prefix(2)) == ["x0", "x1"])
        #expect(unified[20_000] == "y")
        #expect(unified.last == "z9999")
        let plain = await Task.detached { crafted.targets(from: "A") }.value
        #expect(plain.count == 20_001)
        flow.addTransitions(from: "b", to: xs + xs.map { $0.uppercased() })
        #expect(flow.targets(from: "b") == xs)
    }

    /// Targets count as one when `recipeEquals` matches them: case, "ß" and "SS", canonically equivalent spellings (also
    /// "ᾳ" with an accent written after it and "ᾴ"); "ᾈ" and "ἀι" are two.
    @Test func targetsCountAsOneWhenRecipeEqualsMatchesThem() {
        var flow = RecipeFlow()
        flow.transitions = [RecipeTransition(from: "a", to: ["ß", "SS", "ss", "ᾈ", "ἀι", "e\u{301}", "É",
                                                              "\u{1FB3}\u{301}", "\u{1FB4}", "\u{391}\u{345}\u{301}"])]
        let once = ["ß", "ᾈ", "ἀι", "e\u{301}", "\u{1FB3}\u{301}"]
        #expect(flow.targets(from: "a") == once)
        #expect(flow.unifiedTransitions["a"] == once)
        flow.addTransitions(from: "a", to: ["SS", "x", "X"])
        #expect(flow.targets(from: "a") == once + ["x"])
    }

    /// `recipeEquals` (CFStringCompare) is neither symmetric nor transitive for a few Unicode quirks, so no lookup key can
    /// follow it exactly. These ids count as two (documented behaviour; the engine, which compares lowercased text, sees two
    /// steps too): matches in one direction only (CF's expansions), and a U+0345 written as its own mark before another.
    @Test func recipeEqualsUnicodeQuirksCountAsTwo() {
        #expect(recipeEquals("f\u{212A}", "\u{FB01}"))
        #expect(!recipeEquals("\u{FB01}", "f\u{212A}"))
        #expect(recipeEquals("\u{345}\u{301}", "\u{399}\u{301}"))
        let quirks = ["f\u{212A}", "\u{FB01}", "S\u{212A}", "\u{DF}", "A\u{3A3}", "\u{C5}", "\u{345}\u{301}", "\u{399}\u{301}"]
        var flow = RecipeFlow()
        flow.transitions = [RecipeTransition(from: "a", to: quirks)]
        #expect(flow.targets(from: "a") == quirks)
        for index in stride(from: 0, to: quirks.count, by: 2) {
            #expect(quirks[index].lowercased() != quirks[index + 1].lowercased())
        }
    }

    /// Every property name of the schema's definitions is a member the model reads.
    @Test func schemaCoverage() throws {
        let schema = try JSONValue.parse(RecipeFixtures.data("recipe.schema.json"))
        let root = try #require(schema.objectValue)
        let properties = try #require(root["properties"]?.objectValue)
        // Read by the model; "enabled" at the top is kept in `extra` (the library decides that from the settings).
        let topLevel: Set<String> = ["$schema", "kind", "version", "id", "name", "description", "enabled", "requires", "triggers",
                                     "nodes", "flow", "options", "extends", "when", "concurrency"]
        for key in properties.keys {
            #expect(topLevel.contains(key), "\(key)")
        }
        let definitions = try #require(root["definitions"]?.objectValue)
        let known: [String: Set<String>] = [
            "RecipeOption": ["key", "type", "default", "label", "description", "min", "max", "choices", "enabledWhen", "quickSettings", "format"],
            "RecipeFlowConfig": ["startNodes", "transitions", "conditionalTransitions", "errorTransitions"],
            "ConditionalTransitionConfig": ["from", "branch", "to"],
            "RecipeNodeConfig": ["id", "stepType", "name", "enabled", "parameters", "onErrorNodeId", "onErrorRecipeId"],
            "RecipeRequirement": ["id", "name", "minVersion", "url"],
            "TriggerConfig": ["triggerType", "name", "enabled", "parameters"],
            "CommandlineArgument": ["name", "variable", "description", "required", "defaultValue", "type", "allowedValues"]
        ]
        for (definition, keys) in known {
            let entry = try #require(definitions[definition]?.objectValue, "\(definition)")
            let names = entry["properties"]?.objectValue?.keys ?? []
            for name in names {
                #expect(keys.contains(name), "\(definition).\(name)")
            }
        }
    }
}
