// Greenshot for Mac (Community) - an unofficial macOS port of Greenshot
// Copyright (C) 2026 Greenshot for Mac (Community) contributors
// Based on Greenshot, Copyright (C) 2007-2026 Thomas Braun, Jens Klingen, Robin Krom
// SPDX-License-Identifier: GPL-3.0-or-later

import Foundation
import Testing
@testable import GreenshotCore

/// A flag the main-actor hooks of the runner set.
final class RecipeFlag: @unchecked Sendable {
    private let lock = NSLock()
    private var value = false

    var isSet: Bool { lock.withLock { value } }
    func set() { lock.withLock { value = true } }
}

/// Upstream CaptureFlowRunner: concurrency, cancellation, shutdown, the selection guard, preflight and preparation.
@Suite struct RecipeRunnerTests {
    func runner(_ registry: RecipeStepRegistry, preflight: (@Sendable (CaptureRecipe) async -> CaptureRecipe?)? = nil,
                selectionOpen: Bool = false, broughtToFront: RecipeFlag? = nil) -> RecipeRunner {
        RecipeRunner(steps: registry, environment: { FixedRecipeEnvironment() }, preflight: preflight,
                     selectionInProgress: { selectionOpen }, bringSelectionToFront: { broughtToFront?.set() })
    }

    func waitingRegistry(started: RecipeGate, release: RecipeGate) -> RecipeStepRegistry {
        RecipeEngineHarness.registry(RecipeRecorder()) { _, _ in
            started.open()
            await release.wait()
        }
    }

    func sleepingRegistry(started: RecipeGate) -> RecipeStepRegistry {
        RecipeEngineHarness.registry(RecipeRecorder()) { _, _ in
            started.open()
            try await Task.sleep(for: .seconds(60))
        }
    }

    func single(_ concurrency: FlowConcurrency? = nil) -> CaptureRecipe {
        var recipe = RecipeEngineHarness.recipe(["a"], start: ["a"], [])
        recipe.concurrency = concurrency
        return recipe
    }

    @Test func completesAndReportsEvents() async {
        let events = RecipeRecorder()
        let runner = runner(RecipeEngineHarness.registry(RecipeRecorder()))
        let observation = runner.addObserver { event in
            switch event {
            case .flowStarted: events.add("started")
            case .nodeStarted(_, let node, _): events.add("node \(node)")
            case .nodeFinished(_, let node): events.add("done \(node)")
            case .flowFinished(let result): events.add("finished \(result.state.rawValue)")
            default: break
            }
        }
        let handle = runner.start(RecipeRunRequest(recipe: single()))
        let result = await handle.result
        #expect(result.isSuccess)
        #expect(result.flowId == handle.id)
        #expect(events.all == ["started", "node a", "done a", "finished Completed"])
        observation.cancel()
        _ = await runner.start(RecipeRunRequest(recipe: single())).result
        #expect(events.all.count == 4)
    }

    @Test func parallelStartsBoth() async {
        let started = RecipeGate()
        let release = RecipeGate()
        let runner = runner(waitingRegistry(started: started, release: release))
        let first = runner.start(RecipeRunRequest(recipe: single()))
        await started.wait()
        let second = runner.start(RecipeRunRequest(recipe: single()))
        #expect(first.id != second.id)
        release.open()
        let one = await first.result
        let two = await second.result
        #expect(one.isSuccess)
        #expect(two.isSuccess)
    }

    @Test func exclusiveKeepsTheRunningFlow() async {
        let started = RecipeGate()
        let release = RecipeGate()
        let runner = runner(waitingRegistry(started: started, release: release))
        let first = runner.start(RecipeRunRequest(recipe: single(.exclusive)))
        await started.wait()
        let second = runner.start(RecipeRunRequest(recipe: single(.exclusive)))
        #expect(second.id == first.id)
        #expect(runner.running.count == 1)
        release.open()
        let result = await first.result
        #expect(result.isSuccess)
    }

    @Test func replacePreviousCancelsTheRunningFlow() async {
        let started = RecipeGate()
        let runner = runner(sleepingRegistry(started: started))
        let first = runner.start(RecipeRunRequest(recipe: single(.replacePrevious)))
        await started.wait()
        let second = runner.start(RecipeRunRequest(recipe: single(.replacePrevious)))
        let replaced = await first.result
        #expect(replaced.state == .cancelled)
        second.cancel()
        let last = await second.result
        #expect(last.state == .cancelled)
    }

    @Test func cancelAndShutdown() async {
        let started = RecipeGate()
        let runner = runner(sleepingRegistry(started: started))
        let handle = runner.start(RecipeRunRequest(recipe: single()))
        await started.wait()
        await runner.shutdown()
        let result = await handle.result
        #expect(result.state == .cancelled)
        let refused = await runner.start(RecipeRunRequest(recipe: single())).result
        #expect(refused.state == .cancelled)
        #expect(refused.reason == "Greenshot is shutting down.")
        #expect(runner.running.isEmpty)
    }

    @Test func openSelectionRefusesAnotherOne() async {
        let flag = RecipeFlag()
        let runner = runner(RecipeEngineHarness.registry(RecipeRecorder()), selectionOpen: true, broughtToFront: flag)
        var recipe = single()
        recipe.nodes.append(RecipeNode(id: "select", stepType: "InteractiveSelection"))
        let result = await runner.start(RecipeRunRequest(recipe: recipe)).result
        #expect(result.state == .cancelled)
        #expect(result.reason == "An interactive selection is already open.")
        #expect(flag.isSet)
        let other = await runner.start(RecipeRunRequest(recipe: single())).result
        #expect(other.isSuccess)
    }

    @Test func preflightCanRefuseOrReplace() async {
        let recorder = RecipeRecorder()
        let refusing = runner(RecipeEngineHarness.registry(recorder), preflight: { _ in nil })
        let refused = await refusing.start(RecipeRunRequest(recipe: single())).result
        #expect(refused.state == .cancelled)
        #expect(recorder.all.isEmpty)
        let replacement = RecipeEngineHarness.recipe(["b"], start: ["b"], [])
        let replacing = runner(RecipeEngineHarness.registry(recorder), preflight: { _ in replacement })
        _ = await replacing.start(RecipeRunRequest(recipe: single())).result
        #expect(recorder.all == ["b"])
    }

    @Test func triggerPreparationAddsSourceAndDestination() async {
        let recorder = RecipeRecorder()
        let registry = RecipeEngineHarness.registry(recorder)
        for type in [WellKnownStepType.source, WellKnownStepType.destinations] {
            registry.register(type, executor: ClosureExecutor { step, _ in
                recorder.add("\(step.node.stepType):\(step.parameters.string("SourceType") ?? "")")
            })
        }
        let runner = runner(registry)
        let request = RecipeRunRequest(recipe: single(), trigger: RecipeTriggerInfo(triggerType: "Clipboard"))
        let result = await runner.start(request).result
        #expect(result.isSuccess)
        #expect(recorder.all == ["Source:Clipboard", "a", "Destinations:"])
    }

    @Test func requestValuesReachTheFlow() async {
        let seen = RecipeRecorder()
        let registry = RecipeEngineHarness.registry(RecipeRecorder()) { _, context in
            seen.add(context[variable: "Filename"]?.asString ?? "")
            seen.add(context.isPayloadPreSupplied ? "pre-supplied" : "captured")
            seen.add(context.object(forKey: "editorform") as? String ?? "")
        }
        var request = RecipeRunRequest(recipe: single())
        request.variables = ["Filename": .string("/tmp/a.png")]
        request.objects = ["EditorForm": "editor-1"]
        request.payload = RecipePayload(image: TestImage.solid(width: 4, height: 4, .red), scale: 1, title: "Forwarded")
        let finished = RecipeRecorder()
        request.onFinish = { context in finished.add(context.state.rawValue) }
        let result = await runner(registry).start(request).result
        #expect(seen.all == ["/tmp/a.png", "pre-supplied", "editor-1"])
        #expect(finished.all == ["Completed"])
        #expect(result.payload?.title == "Forwarded")
    }

    @Test func preparerLeavesCompleteRecipesAlone() {
        var recipe = RecipeEngineHarness.recipe(["s", "d"], start: ["s"], [("s", "d")])
        recipe.nodes[0].stepType = "Source"
        recipe.nodes[1].stepType = "Clipboard"
        #expect(RecipeTriggerPreparer.prepare(recipe, triggerType: "Hotkey") == recipe)
        let bare = single()
        let forAI = RecipeTriggerPreparer.prepare(bare, triggerType: "AiTool")
        #expect(forAI.nodes.count == 2)
        #expect(!forAI.hasDestinationStep)
        let forEditor = RecipeTriggerPreparer.prepare(bare, triggerType: "Editor")
        let source = forEditor.nodes.first { $0.stepType == "Source" }
        #expect(source?.parameters.string("SourceType") == "CurrentEditor")
        let editor = forEditor.nodes.first { $0.stepType == "Editor" }
        #expect(editor?.parameters.string("TargetEditor") == "CurrentEditor")
    }
}

/// Upstream CommandlineArgumentBinder.
@Suite struct RecipeArgumentBinderTests {
    let declared: [CommandlineArgument] = {
        var file = CommandlineArgument(name: "file", type: .filePath)
        file.variable = "Filename"
        file.required = true
        var count = CommandlineArgument(name: "count", type: .integer)
        count.defaultValue = "3"
        var mode = CommandlineArgument(name: "mode", type: .enumeration)
        mode.allowedValues = ["Fast", "Slow"]
        let flag = CommandlineArgument(name: "flag", type: .boolean)
        return [file, count, mode, flag]
    }()

    func bind(_ supplied: [String: String]) -> Result<[String: JSONValue], RecipeStepError> {
        RecipeArgumentBinder.bind(declared: declared, supplied: supplied, recipeName: "cli") { path, _ in
            if path.contains("..") { throw RecipeStepError("the path leaves the working directory") }
            return "/work/" + path
        }
    }

    @Test func bindsAndConverts() throws {
        let variables = try bind(["FILE": "a.png", "mode": "fast", "flag": "yes"]).get()
        #expect(variables["Filename"] == .string("/work/a.png"))
        #expect(variables["count"] == .number(3))
        #expect(variables["mode"] == .string("Fast"))
        #expect(variables["flag"] == .bool(true))
    }

    @Test func reportsWhatIsWrong() {
        #expect(throws: RecipeStepError.self) { try bind(["file": "a.png", "colour": "red"]).get() }
        #expect(throws: RecipeStepError.self) { try bind([:]).get() }
        #expect(throws: RecipeStepError.self) { try bind(["file": "a.png", "count": "many"]).get() }
        #expect(throws: RecipeStepError.self) { try bind(["file": "a.png", "mode": "medium"]).get() }
        #expect(throws: RecipeStepError.self) { try bind(["file": "a.png", "flag": "perhaps"]).get() }
        #expect(throws: RecipeStepError.self) { try bind(["file": "../a.png"]).get() }
        if case .failure(let error) = bind(["file": "a.png", "colour": "red"]) {
            #expect(error.message == "Error: unknown argument 'colour' for recipe 'cli'. Accepted arguments: --file, --count, --mode, --flag.")
        }
        if case .failure(let error) = bind([:]) {
            #expect(error.message == "Error: missing required argument '--file'.")
        }
    }
}
