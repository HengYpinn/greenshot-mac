// Greenshot for Mac (Community) - an unofficial macOS port of Greenshot
// Copyright (C) 2026 Greenshot for Mac (Community) contributors
// Based on Greenshot, Copyright (C) 2007-2026 Thomas Braun, Jens Klingen, Robin Krom
// SPDX-License-Identifier: GPL-3.0-or-later

import CoreGraphics
import Foundation
import Testing
@testable import GreenshotCore

/// A small picture for the recipe tests' Source steps.
func recipeTestImage(width: Int = 8, height: Int = 6) -> CGImage {
    let context = CGContext(data: nil, width: width, height: height, bitsPerComponent: 8, bytesPerRow: 0,
                            space: CGColorSpace(name: CGColorSpace.sRGB)!, bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue)!
    context.setFillColor(CGColor(red: 0.2, green: 0.6, blue: 0.9, alpha: 1))
    context.fill(CGRect(x: 0, y: 0, width: width, height: height))
    return context.makeImage()!
}

/// A library with approved recipes and a runner whose Source step makes a picture (no screen).
@MainActor
struct RecipeCommandHarness {
    let fixture = LibraryFixture()
    let runner: RecipeRunner
    let recorder = RecipeRecorder()

    init() {
        let registry = RecipeStepRegistry()
        registry.registerCoreExecutors()
        let recorder = recorder
        registry.register("Source", executor: ClosureExecutor { step, context in
            recorder.add("Source:" + (step.parameters.string("SourceType") ?? ""))
            if let region = context[variable: "PreSuppliedRegion"]?.asString { recorder.add("Region:" + region) }
            if let window = step.parameters.string("WindowHandle") { recorder.add("Window:" + window) }
            var payload = RecipePayload(image: recipeTestImage(), scale: 1, title: "Test capture")
            payload.extractedText = context[variable: "PresetText"]?.asString
            context.payload = payload
        })
        registry.register("Clipboard", executor: ClosureExecutor { _, _ in recorder.add("Clipboard") })
        // The preparer adds an export at the end of a command line recipe without a destination
        registry.register("Destinations", executor: ClosureExecutor { _, _ in })
        runner = RecipeRunner(steps: registry, environment: { FixedRecipeEnvironment() })
    }

    /// Writes and approves the recipe (every trigger and permission).
    func load(_ recipe: CaptureRecipe) async throws {
        let url = try fixture.write(recipe, name: "\(recipe.id).gsrecipe.json")
        let result = await fixture.library.loadFile(url)
        #expect(result.isValid, "\(result.errors)")
    }

    func cleanUp() { fixture.cleanUp() }

    /// RUN_RECIPE with a recording writer; the capture question answers `allow` and records its subject.
    func run(_ envelope: IPCEnvelope, source: IPCSource = .cli, text: Bool = true, allow: Bool = true) async -> (IPCReply, CollectingWriter, [String]) {
        let writer = CollectingWriter()
        let context = IPCReplyContext(envelope: envelope, source: source, writer: writer, usesTextFrames: text)
        let asked = SubjectBox()
        let runner = runner
        let reply = await IPCRecipeCommands.runRecipe(context, library: fixture.library, start: { runner.start($0) },
                                                      confirmCapture: { name, subject in
                                                          asked.subjects.append("\(name): \(subject)")
                                                          return allow
                                                      })
        return (reply, writer, asked.subjects)
    }
}

@MainActor
final class SubjectBox {
    var subjects: [String] = []
}

/// A recipe of the command line: `greet name=… [count=…]`, its Stdout "Hello ${Name}".
func commandLineRecipe(id: String = "recipe_greet", command: String = "greet", sourceType: String = "Region", browser: Bool = false,
                       extraNodes: [RecipeNode] = [], arguments: [JSONValue]? = nil) -> CaptureRecipe {
    var recipe = CaptureRecipe(id: id, name: "Greeter \(id)")
    let declared: [JSONValue] = arguments ?? [
        .object(["name": .string("name"), "variable": .string("Name"), "required": .bool(true), "description": .string("Who")]),
        .object(["name": .string("count"), "type": .string("Integer"), "defaultValue": .string("1")]),
    ]
    var parameters: JSONObject = ["Command": .string(command), "Description": .string("Says hello"), "Stdout": .string("Hello ${Name}"),
                                  "Arguments": .array(declared)]
    if browser { parameters["AllowBrowserInvocation"] = .bool(true) }
    recipe.triggers = [TriggerConfig(triggerType: "Commandline", parameters: parameters)]
    recipe.nodes = [RecipeNode(id: "acquire", stepType: "Source", parameters: ["SourceType": .string(sourceType)])] + extraNodes
    recipe.flow.startNodes = ["acquire"]
    var previous = "acquire"
    for node in extraNodes {
        recipe.flow.addTransition(from: previous, to: node.id)
        previous = node.id
    }
    return recipe
}

private func runEnvelope(_ argv: [String], cwd: String? = "/Users/me") throws -> IPCEnvelope {
    try #require(IPCCommandLine.parse(argv, source: .cli, cwd: cwd).envelope)
}

/// Upstream IpcSecurityDispatcher's LIST_RECIPES / DESCRIBE_RECIPE / RUN_RECIPE (RecipeCliTests, CliProtocolTests).
@MainActor
@Suite struct IPCRecipeCommandsTests {
    @Test func listsTheCommandLineRecipes() async throws {
        let harness = RecipeCommandHarness()
        defer { harness.cleanUp() }
        try await harness.load(commandLineRecipe())
        let context = IPCReplyContext(envelope: IPCEnvelope(command: IPCCommand.listRecipes), source: .cli, usesTextFrames: true)
        let reply = IPCRecipeCommands.listRecipes(context, library: harness.fixture.library)
        let recipes = reply.extra["recipes"]?.arrayValue ?? []
        #expect(recipes.count == 1)
        let first = try #require(recipes.first?.objectValue)
        #expect(first.string("command") == "greet")
        #expect(first["arguments"]?.arrayValue?.count == 2)
        #expect(reply.stdout?.contains("greet") == true)
        // JSON clients get no console text
        var json = IPCEnvelope(command: IPCCommand.listRecipes)
        json.json = true
        let jsonReply = IPCRecipeCommands.listRecipes(IPCReplyContext(envelope: json, source: .cli, usesTextFrames: true),
                                                     library: harness.fixture.library)
        #expect(jsonReply.stdout == nil)
    }

    @Test func describesByCommandIdOrName() async throws {
        let harness = RecipeCommandHarness()
        defer { harness.cleanUp() }
        try await harness.load(commandLineRecipe())
        for target in ["greet", "recipe_greet", "Greeter recipe_greet"] {
            var envelope = IPCEnvelope(command: IPCCommand.describeRecipe)
            envelope.recipe = target
            let reply = IPCRecipeCommands.describeRecipe(IPCReplyContext(envelope: envelope, source: .cli), library: harness.fixture.library)
            #expect(reply.extra["recipe"]?.objectValue?.string("id") == "recipe_greet")
        }
        var unknown = IPCEnvelope(command: IPCCommand.describeRecipe)
        unknown.recipe = "nope"
        let reply = IPCRecipeCommands.describeRecipe(IPCReplyContext(envelope: unknown, source: .cli), library: harness.fixture.library)
        #expect(reply.isError)
        #expect(reply.stderr == "Recipe 'nope' not found.")
    }

    @Test func runsWithTheTriggersStdout() async throws {
        let harness = RecipeCommandHarness()
        defer { harness.cleanUp() }
        try await harness.load(commandLineRecipe())
        let (reply, _, asked) = await harness.run(try runEnvelope(["--recipe", "greet", "name=Ann"]))
        #expect(reply.status == "ok")
        #expect(reply.stdout == "Hello Ann")
        #expect(reply.exitCode == 0)
        // A region the user selects: no question
        #expect(asked.isEmpty)
    }

    @Test func streamsStdoutStepsAndCollectsThemForJSON() async throws {
        let harness = RecipeCommandHarness()
        defer { harness.cleanUp() }
        let stdout = RecipeNode(id: "print", stepType: "Stdout", parameters: ["Text": .string("line one")])
        try await harness.load(commandLineRecipe(extraNodes: [stdout]))
        let (plain, writer, _) = await harness.run(try runEnvelope(["-r", "greet", "--name", "Ann"]))
        #expect(writer.textFrames.contains(.stdout(Data("line one\n".utf8))))
        // Streamed already: not repeated in the final reply
        #expect(plain.stdout == nil)

        let (json, _, _) = await harness.run(try runEnvelope(["-r", "greet", "--name=Bo", "--json"]))
        #expect(json.stdout == "line one")
        #expect(json.extra["recipe"]?.stringValue == "recipe_greet")
        let variables = try #require(json.extra["variables"]?.objectValue)
        #expect(variables.string("Name") == "Bo")
        #expect(variables.int("count") == 1)
        let payload = try #require(json.extra["payload"]?.objectValue)
        #expect(payload.int("width") == 8)
    }

    @Test func queryReplacesTheOutputAndIsOnlyForTheCommandLine() async throws {
        let harness = RecipeCommandHarness()
        defer { harness.cleanUp() }
        try await harness.load(commandLineRecipe(browser: true))
        let (reply, _, _) = await harness.run(try runEnvelope(["-r", "greet", "name=Ann", "--query", "${Name}!"]))
        #expect(reply.stdout == "Ann!")

        var link = IPCEnvelope(command: IPCCommand.runRecipe)
        link.recipe = "greet"
        link.setParameter("name", "Ann")
        link.query = "${env.HOME}"
        let (refused, _, _) = await harness.run(link, source: .urlScheme, text: false)
        #expect(refused.isError)
        #expect(refused.stderr?.contains("Queries are only allowed from the command line") == true)
    }

    @Test func linksNeedTheRecipesBrowserPermission() async throws {
        let harness = RecipeCommandHarness()
        defer { harness.cleanUp() }
        try await harness.load(commandLineRecipe())
        try await harness.load(commandLineRecipe(id: "recipe_web", command: "web", browser: true))
        var link = IPCEnvelope(command: IPCCommand.runRecipe)
        link.recipe = "greet"
        link.setParameter("name", "Ann")
        let (refused, _, _) = await harness.run(link, source: .urlScheme, text: false)
        #expect(refused.isError)
        #expect(refused.stderr?.hasPrefix("[SECURITY] Recipe 'greet' does not allow invocation from a browser") == true)
        // The browser extension is a browser too
        let (extensionRefused, _, _) = await harness.run(link, source: .nativeMessaging, text: false)
        #expect(extensionRefused.isError)

        link.recipe = "web"
        let (allowed, _, _) = await harness.run(link, source: .urlScheme, text: false)
        #expect(allowed.status == "ok")
        #expect(allowed.stdout == "Hello Ann")
    }

    @Test func argumentErrorsAreUsageErrors() async throws {
        let harness = RecipeCommandHarness()
        defer { harness.cleanUp() }
        let window: [JSONValue] = [.object(["name": .string("win"), "variable": .string("Window"), "type": .string("Window")]),
                                   .object(["name": .string("area"), "variable": .string("PreSuppliedRegion"), "type": .string("Region")])]
        try await harness.load(commandLineRecipe(arguments: window))
        let (unknown, _, _) = await harness.run(try runEnvelope(["-r", "greet", "colour=red"]))
        #expect(unknown.exitCode == IPCExitCode.usage)
        #expect(unknown.stderr?.contains("unknown argument 'colour'") == true)
        let (windowArgument, _, _) = await harness.run(try runEnvelope(["-r", "greet", "win=123"]))
        #expect(windowArgument.exitCode == IPCExitCode.usage)
        #expect(windowArgument.stderr?.contains("window arguments are only available to AI tools") == true)
        let (badRegion, _, _) = await harness.run(try runEnvelope(["-r", "greet", "area=1,2,0,4"]))
        #expect(badRegion.exitCode == IPCExitCode.usage)
        let (missing, _, _) = await harness.run(try runEnvelope(["-r", "nothing"]))
        #expect(missing.stderr == "Recipe 'nothing' not found or does not have an active CommandlineTrigger.")
    }

    @Test func requiredArgumentMissing() async throws {
        let harness = RecipeCommandHarness()
        defer { harness.cleanUp() }
        try await harness.load(commandLineRecipe())
        let (reply, _, _) = await harness.run(try runEnvelope(["-r", "greet"]))
        #expect(reply.exitCode == IPCExitCode.usage)
        #expect(reply.stderr?.contains("missing required argument '--name' (Who)") == true)
    }

    @Test func capturesWithoutTheUserAskFirst() async throws {
        let harness = RecipeCommandHarness()
        defer { harness.cleanUp() }
        try await harness.load(commandLineRecipe(sourceType: "FullScreen"))
        let (denied, _, asked) = await harness.run(try runEnvelope(["-r", "greet", "name=Ann"]), allow: false)
        #expect(asked == ["Greeter recipe_greet: a screenshot of the whole screen"])
        #expect(denied.isError)
        #expect(harness.recorder.all.isEmpty)
        let (allowed, _, _) = await harness.run(try runEnvelope(["-r", "greet", "name=Ann"]), allow: true)
        #expect(allowed.status == "ok")
        #expect(harness.recorder.all == ["Source:FullScreen"])
    }

    @Test func asyncRepliesAtOnce() async throws {
        let harness = RecipeCommandHarness()
        defer { harness.cleanUp() }
        try await harness.load(commandLineRecipe())
        let (reply, writer, _) = await harness.run(try runEnvelope(["-r", "greet", "name=Ann", "--async"]))
        #expect(reply.stdout == "Recipe 'Greeter recipe_greet' triggered in background.")
        #expect(writer.frames.isEmpty)
        for handle in harness.runner.running { _ = await handle.result }
    }

    @Test func failuresGiveTheStderrStepsExitCode() async throws {
        let harness = RecipeCommandHarness()
        defer { harness.cleanUp() }
        let stderr = RecipeNode(id: "fail", stepType: "Stderr", parameters: ["Text": .string("no luck"), "ExitCode": .number(7)])
        try await harness.load(commandLineRecipe(extraNodes: [stderr]))
        let (reply, writer, _) = await harness.run(try runEnvelope(["-r", "greet", "name=Ann"]))
        #expect(reply.status == "error")
        #expect(reply.exitCode == 7)
        // Streamed already: the abort reason isn't printed twice
        #expect(reply.stderr == nil)
        #expect(writer.textFrames.contains(.stderr(Data("no luck\n".utf8))))
    }

    @Test func fallbackOutput() {
        let recipe = CaptureRecipe(id: "r", name: "Plain")
        let quiet = RecipeFlowResult(flowId: UUID(), recipeId: "r", recipeName: "Plain", state: .completed)
        #expect(IPCRecipeCommands.fallbackOutput(quiet, recipe: recipe) == "Recipe 'Plain' completed successfully.")
        let ocr = RecipeFlowResult(flowId: UUID(), recipeId: "r", recipeName: "Plain", state: .completed,
                                   variables: RecipeVariables(["OcrText": .string("words"), "Destination.Filename": .string("/a.png")]))
        #expect(IPCRecipeCommands.fallbackOutput(ocr, recipe: recipe) == "words")
    }
}

/// Security review SM-M1: what RUN_RECIPE's up-front check can't see is asked when the step runs, but only for runs from
/// greenshot-cli (any program can start it); the subject already allowed up front isn't asked again.
@MainActor
struct RecipeCaptureConsentObjectTests {
    private func objects(source: IPCSource) async throws -> [String: any Sendable] {
        let harness = RecipeCommandHarness()
        defer { harness.cleanUp() }
        try await harness.load(commandLineRecipe())
        let envelope = try #require(IPCCommandLine.parse(["--recipe", "greet", "name=Ann"], source: .cli, cwd: "/Users/me").envelope)
        let context = IPCReplyContext(envelope: envelope, source: source, writer: CollectingWriter(), usesTextFrames: true)
        let seen = ObjectsBox()
        let runner = harness.runner
        _ = await IPCRecipeCommands.runRecipe(context, library: harness.fixture.library, start: { request in
            seen.objects = request.objects
            return runner.start(request)
        }, confirmCapture: { _, _ in true })
        return seen.objects
    }

    @Test func aCommandLineRunCarriesTheConsentForItsSteps() async throws {
        let cli = try await objects(source: .cli)
        #expect(cli[RecipeCaptureConsent.objectKey] is RecipeCaptureConsent)
        let shortcut = try await objects(source: .shortcuts)
        #expect(shortcut[RecipeCaptureConsent.objectKey] == nil)
    }
}

@MainActor
private final class ObjectsBox {
    var objects: [String: any Sendable] = [:]
}
