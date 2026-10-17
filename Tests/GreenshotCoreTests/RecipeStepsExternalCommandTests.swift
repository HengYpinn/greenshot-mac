// Greenshot for Mac (Community) - an unofficial macOS port of Greenshot
// Copyright (C) 2026 Greenshot for Mac (Community) contributors
// Based on Greenshot, Copyright (C) 2007-2026 Thomas Braun, Jens Klingen, Robin Krom
// SPDX-License-Identifier: GPL-3.0-or-later

import Foundation
import Testing
@testable import GreenshotCore

/// Upstream `ExternalCommandStep`: which program with which arguments, and what goes into the flow afterwards.
@Suite struct RecipeStepsExternalCommandTests {
    let commands = [ExternalCommand(name: "Optimize", command: "/usr/local/bin/optipng", arguments: "-o2 \"{0}\"", runInBackground: true,
                                    copyURLFromOutput: true, copyOutputToClipboard: false, format: .png)]

    func step(_ parameters: JSONObject) -> RecipeStepInvocation {
        RecipeStepInvocation(node: RecipeNode(id: "cmd", stepType: WellKnownStepType.externalCommand, parameters: parameters),
                             parameters: parameters, contract: StepContractCatalog.builtIn.contract(for: WellKnownStepType.externalCommand))
    }

    @Test func aConfiguredCommand() throws {
        let plan = try #require(RecipeExternalCommandPlan(step(["Command": .string("optimize")]), commands: commands))
        #expect(plan.name == "optimize")
        #expect(plan.commandLine == "/usr/local/bin/optipng")
        #expect(plan.arguments == "-o2 \"{0}\"")
        #expect(plan.runInBackground)
        #expect(plan.uriToClipboard)
        #expect(!plan.outputToClipboard)
        #expect(plan.format == .png)
        #expect(plan.jpegQuality == 90)
        #expect(!plan.reloadAfterExecution)
    }

    @Test func theStepsValuesWin() throws {
        let plan = try #require(RecipeExternalCommandPlan(step([
            "Command": .string("Optimize"), "Arguments": .string("{0} --out x"), "RunInBackground": .bool(false),
            "UriToClipboard": .bool(false), "Format": .string("jpeg"), "JpegQuality": .number(150),
            "ReloadAfterExecution": .bool(true), "SetOutputVariable": .string("Result"), "Verb": .string("runas")
        ]), commands: commands))
        #expect(plan.arguments == "{0} --out x")
        #expect(!plan.runInBackground)
        #expect(!plan.uriToClipboard)
        #expect(plan.format == .jpg)
        #expect(plan.jpegQuality == 100)
        #expect(plan.reloadAfterExecution)
        #expect(plan.setOutputVariable == "Result")
        #expect(plan.verb == "runas")
    }

    @Test func aProgramOfItsOwn() throws {
        let plan = try #require(RecipeExternalCommandPlan(step(["CommandLine": .string("/usr/bin/curl")]), commands: commands))
        #expect(plan.name == "curl")
        #expect(plan.arguments == "{0}")
        #expect(!plan.runInBackground)
        #expect(plan.format == .png)
    }

    @Test func nothingToRun() {
        #expect(RecipeExternalCommandPlan(step(["Command": .string("Missing")]), commands: commands) == nil)
        #expect(RecipeExternalCommandPlan(step([:]), commands: commands) == nil)
    }

    @Test func onlyAFileTheFlowSavedOfTheCaptureAsItIs() throws {
        let plan = try #require(RecipeExternalCommandPlan(step(["CommandLine": .string("/bin/echo")]), commands: []))
        let existing: Set<String> = ["/tmp/shot.png", "/tmp/shot.jpg"]
        let reused = plan.reusableFile("/tmp/shot.png", unchangedSinceSaved: true, exists: existing.contains)
        #expect(reused?.path == "/tmp/shot.png")
        // Changed since it was saved (an effect, a blur): a new file of the capture as it is (R-F3).
        #expect(plan.reusableFile("/tmp/shot.png", unchangedSinceSaved: false, exists: existing.contains) == nil)
        // Another format, gone, none.
        #expect(plan.reusableFile("/tmp/shot.jpg", unchangedSinceSaved: true, exists: existing.contains) == nil)
        #expect(plan.reusableFile("/tmp/missing.png", unchangedSinceSaved: true, exists: existing.contains) == nil)
        #expect(plan.reusableFile(nil, unchangedSinceSaved: true, exists: existing.contains) == nil)
    }

    // MARK: Arguments split before they are filled (S-L1, SM-M5, S-N1)

    @Test func argumentsAreSplitBeforeTheirValuesAreFilled() throws {
        let parameters: JSONObject = ["CommandLine": .string("/usr/bin/curl"), "Arguments": .string("-F \"file=@{0}\" --title ${Title} ${Empty}")]
        let plan = try #require(RecipeExternalCommandPlan(step(parameters), commands: []))
        #expect(plan.argumentsFromRecipe)
        #expect(plan.commandLineFromRecipe)
        let values = ["${Title}": "a --output=/Users/me/.zshrc x.png", "${Empty}": ""]
        let arguments = plan.argumentList(file: "/tmp/shot png.png", evaluate: { values[$0] ?? $0 }, fill: { _ in "FILLED" })
        #expect(arguments == ["-F", "file=@/tmp/shot png.png", "--title", "a --output=/Users/me/.zshrc x.png"])
    }

    @Test func aConfiguredCommandsArgumentsGetTheFilePatterns() throws {
        let plan = try #require(RecipeExternalCommandPlan(step(["Command": .string("Optimize")]), commands: commands))
        #expect(!plan.argumentsFromRecipe)
        #expect(!plan.commandLineFromRecipe)
        let arguments = plan.argumentList(file: "/tmp/a.png", evaluate: { _ in "EVALUATED" }, fill: { $0.replacingOccurrences(of: "-o2", with: "-o7") })
        #expect(arguments == ["-o7", "/tmp/a.png"])
        // As its destination runs it: an argument filled empty stays an (empty) argument.
        let emptied = plan.argumentList(file: "/tmp/a.png", evaluate: { $0 }, fill: { $0 == "-o2" ? "" : $0 })
        #expect(emptied == ["", "/tmp/a.png"])
    }

    @Test func theStepsOwnProgramIsNotFilledAgain() throws {
        // The flow evaluated CommandLine already: a value with ${HOME} in it stays as it is.
        let own = try #require(RecipeExternalCommandPlan(step(["CommandLine": .string("/opt/${HOME}/tool")]), commands: []))
        #expect(own.program(fill: { _ in "/bin/rm" }) == .executable("/opt/${HOME}/tool"))
        let configured = try #require(RecipeExternalCommandPlan(step(["Command": .string("Optimize")]), commands: commands))
        #expect(configured.program(fill: { $0.replacingOccurrences(of: "local", with: "other") }) == .executable("/usr/other/bin/optipng"))
    }

    @Test func theFlowDoesntFillTheArgumentsBeforeTheStep() async {
        let contract = StepContractCatalog.builtIn.contract(for: WellKnownStepType.externalCommand)
        #expect(contract?.parameter("Arguments")?.supportsExpressions == false)
        // Through the engine: the step gets "${Title}" as written.
        let seen = RecipeRecorder()
        let registry = RecipeStepRegistry()
        registry.register(WellKnownStepType.externalCommand, executor: ClosureExecutor { step, _ in
            seen.add(step.string("Arguments") ?? "")
            seen.add(step.string("WorkingDirectory") ?? "")
        })
        var recipe = CaptureRecipe(id: "args", name: "Args")
        recipe.nodes = [RecipeNode(id: "cmd", stepType: WellKnownStepType.externalCommand,
                                   parameters: ["CommandLine": .string("/bin/echo"), "Arguments": .string("{0} ${Title}"),
                                                "WorkingDirectory": .string("/tmp/${Folder}")])]
        recipe.flow.startNodes = ["cmd"]
        let context = RecipeEngineHarness.context(recipe)
        context[variable: "Title"] = .string("a b")
        context[variable: "Folder"] = .string("x")
        _ = await RecipeEngineHarness.run(recipe, registry, context: context)
        #expect(seen.all == ["{0} ${Title}", "/tmp/x"])
    }

    @Test func variablesAfterTheRun() throws {
        let plan = try #require(RecipeExternalCommandPlan(step(["CommandLine": .string("/bin/echo"), "SetOutputVariable": .string("Out"),
                                                               "SetExitCodeVariable": .string("Code")]), commands: []))
        let outputs = plan.outputs(exitCode: 0, output: "Uploaded to https://example.com/i/42 done", error: "")
        #expect(outputs["ExternalCommand.ExitCode"] == .number(0))
        #expect(outputs["ExternalCommand.Uri"] == .string("https://example.com/i/42"))
        #expect(outputs["Out"] == .string("Uploaded to https://example.com/i/42 done"))
        #expect(outputs["Code"] == .number(0))
        let file = URL(fileURLWithPath: "/tmp/shot.png")
        let succeeded = plan.result(exitCode: 0, output: "https://example.com/i/42", error: "", file: file)
        #expect(succeeded.isSucceeded)
        #expect(succeeded.link?.absoluteString == "https://example.com/i/42")
        #expect(succeeded.fileURL == file)
        let failed = plan.result(exitCode: 2, output: "", error: "  bad option \n", file: file)
        #expect(failed.status == .failed)
        #expect(failed.error == "bad option")
        let silent = plan.result(exitCode: 3, output: "", error: "", file: file)
        #expect(silent.error == "Exit code 3")
    }
}
