// Greenshot for Mac (Community) - an unofficial macOS port of Greenshot
// Copyright (C) 2026 Greenshot for Mac (Community) contributors
// Based on Greenshot, Copyright (C) 2007-2026 Thomas Braun, Jens Klingen, Robin Krom
// SPDX-License-Identifier: GPL-3.0-or-later

import Foundation
import Testing
@testable import GreenshotCore

/// Security review: a gated value that is decided when the recipe runs (an expression, or a variable the recipe can set)
/// still needs its permission, and the approval says it is decided at run time.
@MainActor
@Suite struct RecipeGateTests {
    func gates(_ node: RecipeNode, _ environment: GateEnvironment = .empty) -> [RecipeGatedAction] {
        StepContractCatalog.builtIn.contract(for: node.stepType)?.gates(node, environment) ?? []
    }

    func node(_ type: String, _ parameters: JSONObject) -> RecipeNode {
        RecipeNode(id: "n", stepType: type, parameters: parameters)
    }

    func details(_ recipe: CaptureRecipe) -> [String] {
        RecipeDescriber().describeSteps(recipe).map(\.text)
    }

    @Test func aSourceFileFromAnArgumentStillNeedsFileAccess() {
        let fromArgument = node("Source", ["SourceType": .string("File"), "Filename": .string("${Arg}")])
        let expected = RecipeGatedAction(.fileSystemAccess, target: "Reads an image file named when the recipe runs (${Arg})")
        #expect(gates(fromArgument) == [expected])
        let lines = details(testRecipe([fromArgument]))
        #expect(lines.contains("Loads an image file named when the recipe runs (${Arg})"))
        #expect(lines.contains("Reads an image file named when the recipe runs (${Arg})"))
        // Upstream parses the source type with Enum.TryParse, which takes numbers: only known names skip the gate.
        let numbered = gates(node("Source", ["SourceType": .string("6")]))
        #expect(numbered.map(\.gateType) == [.fileSystemAccess])
        let decided = gates(node("Source", ["SourceType": .string("${Kind}")]))
        #expect(decided == [RecipeGatedAction(.fileSystemAccess,
                                              target: "May read an image file (the source type is decided when the recipe runs (${Kind}))")])
        #expect(gates(node("Source", ["SourceType": .string("Region")])).isEmpty)
        #expect(gates(node("Source", [:])).isEmpty)
        let literal = gates(node("Source", ["SourceType": .string("file"), "Filename": .string("/tmp/a.png")]))
        #expect(literal == [RecipeGatedAction(.fileSystemAccess, target: "Reads the image file /tmp/a.png")])
    }

    @Test func aCommandFromAnArgumentIsNotShownAsAProgram() {
        let fromArgument = node("ExternalCommand", ["CommandLine": .string("${Arg}")])
        let action = RecipeGatedAction(.externalCommand, target: "a command given when the recipe runs (${Arg})")
        #expect(gates(fromArgument) == [action])
        #expect(RecipeDescriber().describe(action) == "Runs a command given when the recipe runs (${Arg})")
        #expect(details(testRecipe([fromArgument])).contains("Runs a command given when the recipe runs (${Arg})"))
        let named = gates(node("ExternalCommand", ["Command": .string("${option.tool}")]))
        #expect(named.first?.target == "a command given when the recipe runs (${option.tool})")
        let arguments = gates(node("ExternalCommand", ["CommandLine": .string("/bin/sh"), "Arguments": .string("-c ${Arg}")]))
        #expect(arguments.first?.target == "/bin/sh with arguments given when the recipe runs (-c ${Arg})")
        // Literal commands read as before.
        let configured = GateEnvironment(commandLine: { $0 == "Optimize" ? "/usr/local/bin/pngquant" : nil })
        let optimize = gates(node("ExternalCommand", ["Command": .string("Optimize")]), configured)
        #expect(optimize.first?.target == "Optimize (/usr/local/bin/pngquant)")
        #expect(RecipeDescriber().describe(optimize[0]) == "Runs the program Optimize (/usr/local/bin/pngquant)")
    }

    @Test func destinationsDecidedAtRunTimeNeedEveryPermission() {
        let decided = node("Destinations", ["DestinationDesignations": .array([.string("${Dest}")])])
        let types = Set(gates(decided).map(\.gateType))
        #expect(types == [.externalCommand, .networkAccess])
        #expect(details(testRecipe([decided])).contains("Sends the result to a destination decided when the recipe runs (${Dest})"))
        let custom = gates(node("CustomDestination", ["CustomDestinationId": .string("External ${Name}")]))
        #expect(Set(custom.map(\.gateType)) == [.externalCommand, .networkAccess])
        let folder = gates(node("SaveFile", ["SaveDirectory": .string("${Dir}")]))
        #expect(folder == [RecipeGatedAction(.fileSystemAccess, target: "Writes files to a folder decided when the recipe runs (${Dir})")])
        #expect(gates(node("Destinations", ["DestinationDesignations": .array([.string("Clipboard")])])).isEmpty)
        let video = gates(node("RecordVideo", ["OutputDirectory": .string("${Dir}")]))
        #expect(video.first?.target == "Writes the video to a place decided when the recipe runs (${Dir})")
    }

    @Test func overrideDestinationsSetByTheRecipe() {
        let nodes = [RecipeNode(id: "a", stepType: "Source"), node("Destinations", ["DestinationDesignations": .array([.string("Clipboard")])])]
        var plain = testRecipe(nodes, transitions: [("a", ["n"])])
        #expect(RecipeValidator().validate(plain).gateTypes.isEmpty)
        var fromArgument = plain
        fromArgument.triggers = [TriggerConfig(triggerType: "Commandline", parameters: [
            "Command": .string("send"),
            "Arguments": .array([.object(["name": .string("to"), "variable": .string("OverrideDestinations")])])
        ])]
        let bound = RecipeValidator().validate(fromArgument)
        #expect(bound.gateTypes == [.externalCommand, .networkAccess])
        #expect(details(fromArgument).contains("Runs a command chosen when the recipe runs (the variable OverrideDestinations)"))
        // The destination aliases read OverrideDestinations too (upstream registers DestinationExportStep under them).
        var clipboard = fromArgument
        clipboard.nodes[1] = RecipeNode(id: "n", stepType: "Clipboard")
        #expect(RecipeValidator().validate(clipboard).gateTypes == [.externalCommand, .networkAccess])
        plain.nodes.insert(node("SetVariable", ["Variable": .string("OverrideDestinations"), "Value": .string("${Arg}")]), at: 0)
        plain.nodes[0].id = "set"
        plain.flow.startNodes = ["set"]
        plain.flow.addTransition(from: "set", to: "a")
        #expect(RecipeValidator().validate(plain).gateTypes == [.externalCommand, .networkAccess])
    }

    @Test func theLibraryAsksForTheseActions() async throws {
        let fixture = LibraryFixture(approver: StubApprover { request in
            RecipeApprovalDecision(approval: RecipeApproval(recipeId: "x", approvedTriggers: request.triggers.map(\.key)))
        })
        defer { fixture.cleanUp() }
        let decided = RecipeNode(id: "send", stepType: "Destinations", parameters: ["DestinationDesignations": .string("${Dest}")])
        let url = try fixture.write(libraryRecipe(extraNode: decided))
        let result = await fixture.library.loadFile(url)
        #expect(fixture.library.recipes.isEmpty)
        #expect(result.errors.first?.contains("needs") == true)
        let request = try #require(fixture.approver.requests.first)
        #expect(request.gates == [.externalCommand, .networkAccess])
    }
}
