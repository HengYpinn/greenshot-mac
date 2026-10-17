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

    @Test func fileOfAStepBeforeInTheCommandsFormat() throws {
        let plan = try #require(RecipeExternalCommandPlan(step(["CommandLine": .string("/bin/echo")]), commands: []))
        let existing: Set<String> = ["/tmp/shot.png", "/tmp/shot.jpg"]
        let reused = plan.reusableFile([nil, "/tmp/missing.png", "/tmp/shot.jpg", "/tmp/shot.png"], exists: existing.contains)
        #expect(reused?.path == "/tmp/shot.png")
        #expect(plan.reusableFile(["/tmp/shot.jpg"], exists: existing.contains) == nil)
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
