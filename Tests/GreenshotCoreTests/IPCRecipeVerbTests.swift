// Greenshot for Mac (Community) - an unofficial macOS port of Greenshot
// Copyright (C) 2026 Greenshot for Mac (Community) contributors
// Based on Greenshot, Copyright (C) 2007-2026 Thomas Braun, Jens Klingen, Robin Krom
// SPDX-License-Identifier: GPL-3.0-or-later

import Foundation
import Testing
@testable import GreenshotCore

/// Upstream CliCommandParser.ParseRunRecipe / ParseJsonFlagOnly (CliProtocolTests) and CliTextRenderer.
@Suite struct IPCRecipeVerbTests {
    private func parse(_ argv: [String]) -> IPCParseResult {
        IPCCommandLine.parse(argv, source: .cli, cwd: "/Users/me")
    }

    @Test func runRecipeTakesEveryArgumentSpelling() throws {
        let result = parse(["--recipe", "ocr", "lang=de", "--format=png", "--size", "10", "-k", "-5", "--", "--json=x"])
        let envelope = try #require(result.envelope)
        #expect(envelope.command == IPCCommand.runRecipe)
        #expect(envelope.recipe == "ocr")
        #expect(envelope.parameter("lang") == "de")
        #expect(envelope.parameter("format") == "png")
        #expect(envelope.parameter("size") == "10")
        // Values are taken as they are, also with a dash
        #expect(envelope.parameter("k") == "-5")
        // After "--" everything is an argument
        #expect(envelope.parameter("--json") == "x")
        #expect(envelope.json == false)
        #expect(envelope.cwd == "/Users/me")
    }

    @Test func runRecipeOptions() throws {
        let envelope = try #require(parse(["-r", "ocr", "--json", "--async", "--query", "${OcrText}"]).envelope)
        #expect(envelope.json)
        #expect(envelope.async)
        #expect(envelope.query == "${OcrText}")
        let short = try #require(parse(["--recipe", "ocr", "-q", "${A}"]).envelope)
        #expect(short.query == "${A}")
        let inline = try #require(parse(["--recipe", "ocr", "--query=${B}"]).envelope)
        #expect(inline.query == "${B}")
    }

    @Test(arguments: [
        (["--recipe"], "missing recipe identifier after '--recipe'"),
        (["--recipe", "ocr", "--query"], "'--query' requires an expression."),
        (["--recipe", "ocr", "--size"], "missing value for argument '--size'"),
        (["--recipe", "ocr", "--=x"], "invalid argument '--=x'"),
        (["--recipe", "ocr", "loose"], "unexpected argument 'loose'. Pass recipe arguments as key=value"),
        (["--recipe", "ocr", "=x"], "unexpected argument '=x'"),
    ])
    func runRecipeErrors(argv: [String], message: String) {
        let result = parse(argv)
        #expect(!result.isSuccess)
        #expect(result.error?.contains(message) == true)
    }

    @Test func listAndInfoTakeOnlyJSON() throws {
        let list = try #require(parse(["--list-recipes", "--json"]).envelope)
        #expect(list.command == IPCCommand.listRecipes)
        #expect(list.json)
        let info = try #require(parse(["-i", "ocr"]).envelope)
        #expect(info.command == IPCCommand.describeRecipe)
        #expect(info.recipe == "ocr")
        #expect(info.json == false)
        let extra = parse(["-l", "now", "--json"])
        #expect(!extra.isSuccess)
        #expect(extra.json)
        #expect(extra.error?.contains("unexpected argument 'now'") == true)
        #expect(!parse(["--info"]).isSuccess)
    }

    @Test func listText() {
        let recipes: [JSONValue] = [
            .object(["id": .string("recipe_ocr"), "name": .string("OCR"), "command": .string("ocr"),
                     "description": .string("Reads the text"), "stdout": .string("${OcrText}"),
                     "arguments": .array([
                        .object(["name": .string("file"), "variable": .string("Filename"), "description": .string("The image"),
                                 "required": .bool(true), "type": .string("FilePath")]),
                        .object(["name": .string("lang"), "description": .string("Language"), "required": .bool(false),
                                 "default_value": .string("en"), "type": .string("Enum"),
                                 "allowed_values": .array([.string("en"), .string("de")])]),
                     ])]),
        ]
        let text = IPCRecipeText.recipeList(recipes)
        #expect(text.hasPrefix("Available recipes with CommandlineTrigger:\n\n"))
        #expect(text.contains("  ocr                  Reads the text (ID: recipe_ocr)\n"))
        #expect(text.contains("      Stdout  : ${OcrText}\n"))
        #expect(text.contains("        * --file           (required)          : The image <FilePath> -> ${Filename}\n"))
        #expect(text.contains("          --lang           (default: en      ) : Language [en|de] <Enum>\n"))
        #expect(IPCRecipeText.recipeList([]).contains("(No recipes currently configured with active CommandlineTrigger)"))
    }

    @Test func describeText() {
        let contract: JSONObject = [
            "lifecycle": .object(["acquires_image": .bool(true), "mutates_pixels": .bool(false), "extracts_text": .bool(true)]),
            "inputs": .array([.object(["name": .string("Filename"), "type": .string("FilePath"), "required": .bool(true),
                                       "description": .string("The image")])]),
            "outputs": .array([.object(["name": .string("OcrText"), "type": .string("String"), "conditional": .bool(true),
                                        "description": .string("The text")])]),
            "steps": .array([.object(["step_type": .string("Source"), "display_name": .string("Load"), "requires_image": .bool(false),
                                      "reachable": .bool(true)]),
                             .object(["step_type": .string("Processors"), "display_name": .string("OCR"), "requires_image": .bool(true),
                                      "reachable": .bool(false)])]),
            "warnings": .array([.string("Something to know")]),
        ]
        let recipe: JSONValue = .object(["id": .string("recipe_ocr"), "name": .string("OCR"), "description": .string(""),
                                         "triggers": .array([.object(["type": .string("Commandline"), "command": .string("ocr")])]),
                                         "contract": .object(contract)])
        let text = IPCRecipeText.recipeDescription(recipe)
        #expect(text.hasPrefix("Recipe: OCR (ID: recipe_ocr, Category: General)\nDescription: (None)\n\nCommand: ocr\n"))
        #expect(text.contains("Payload Lifecycle:\n  Acquires Image: Yes\n  Mutates Pixels: No\n  Extracts Text : Yes\n"))
        #expect(text.contains("  * Filename             (FilePath, required) : The image\n"))
        #expect(text.contains("    OcrText              (String, not always set) : The text\n"))
        #expect(text.contains("   1. Source               [Load]\n"))
        #expect(text.contains("   2. Processors           [OCR] (requires image) (never executed)\n"))
        #expect(text.contains("Validation Warnings:\n  [!] Something to know\n"))
    }

    @Test func recipeCaptureQuestionOnlyForCommandLineCapturesWithoutTheUser() {
        func recipe(_ type: String, _ parameters: JSONObject = [:]) -> CaptureRecipe {
            var parameters = parameters
            parameters["SourceType"] = .string(type)
            return testRecipe([RecipeNode(id: "a", stepType: "Source", parameters: parameters), RecipeNode(id: "b", stepType: "Clipboard")])
        }
        #expect(AutomationConsent.recipeCaptureSubject(recipe("FullScreen"), variables: [:], source: .cli) == "a screenshot of the whole screen")
        #expect(AutomationConsent.recipeCaptureSubject(recipe("ActiveWindow"), variables: [:], source: .cli) != nil)
        #expect(AutomationConsent.recipeCaptureSubject(recipe("Window", ["WindowTitle": .string("Mail")]), variables: [:], source: .cli) != nil)
        #expect(AutomationConsent.recipeCaptureSubject(recipe("Region"), variables: ["PreSuppliedRegion": .string("0,0,9,9")], source: .cli) != nil)
        // The user selects: no question
        #expect(AutomationConsent.recipeCaptureSubject(recipe("Region"), variables: [:], source: .cli) == nil)
        #expect(AutomationConsent.recipeCaptureSubject(recipe("Window"), variables: [:], source: .cli) == nil)
        #expect(AutomationConsent.recipeCaptureSubject(recipe("File"), variables: [:], source: .cli) == nil)
        // Links: the recipe's own browser approval
        #expect(AutomationConsent.recipeCaptureSubject(recipe("FullScreen"), variables: [:], source: .urlScheme) == nil)
    }

    @Test func argumentPathsNeedTheWorkingDirectoryWhenRelative() throws {
        let absolute = try IPCPathValidator.sanitize("/tmp/../tmp/out.png", cwd: nil).get()
        #expect(absolute.path == "/tmp/out.png")
        let relative = try IPCPathValidator.sanitize("shots/out.png", cwd: "/Users/me").get()
        #expect(relative.path == "/Users/me/shots/out.png")
        #expect((try? IPCPathValidator.sanitize("out.png", cwd: nil).get()) == nil)
        #expect((try? IPCPathValidator.sanitize("/tmp/a\u{202E}b.png", cwd: nil).get()) == nil)
    }
}
