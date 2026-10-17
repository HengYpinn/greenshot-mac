// Greenshot for Mac (Community) - an unofficial macOS port of Greenshot
// Copyright (C) 2026 Greenshot for Mac (Community) contributors
// Based on Greenshot, Copyright (C) 2007-2026 Thomas Braun, Jens Klingen, Robin Krom
// SPDX-License-Identifier: GPL-3.0-or-later

// The frozen recipe API of wave 3 as a client (RAPP, AUT) uses it: this file only has to compile. A changed public
// signature breaks the build here. Plain import: everything used must be public.

import CoreGraphics
import Foundation
import GreenshotCore
import Testing

private struct DemoSourceExecutor: RecipeStepExecutor {
    func execute(_ step: RecipeStepInvocation, in context: RecipeFlowContext) async throws {
        let delay = step.resolved("DelayMs", overrideVariable: "CaptureDelay", in: context)?.asInt ?? 100
        _ = delay
        if context.isPayloadPreSupplied { return }
        try Task.checkCancellation()
        let image: CGImage? = await MainActor.run { nil }
        guard let image else { throw RecipeStepError("No image", errorType: "CaptureFailed") }
        context.payload = RecipePayload(image: image, scale: 2, title: "Demo")
        context[variable: "SelectedWindow"] = .number(42)
        context.exports.add(RecipeExportOutcome(designation: "Clipboard", succeeded: true))
    }
}

@MainActor private final class DemoApprover: RecipeApprover {
    func requestApproval(_ request: RecipeApprovalRequest) async -> RecipeApprovalDecision? {
        RecipeApprovalDecision(approval: request.suggestedApproval)
    }
    func showValidationError(_ request: RecipeApprovalRequest) async {}
}

@MainActor private final class DemoHotkeys: RecipeTriggerSource {
    weak var hub: RecipeTriggerHub?
    var triggerTypes: Set<String> { [WellKnownTriggerType.hotkey] }
    func sync(_ triggers: [ActiveRecipeTrigger]) {
        for t in triggers { _ = t.hotkey }
    }
    func stop() {}
    func pressed(_ t: ActiveRecipeTrigger) {
        hub?.fire(t, info: RecipeTriggerInfo(triggerType: t.trigger.triggerType, triggerIndex: t.index))
    }
}

private struct DemoSink: RecipeOutputSink {
    func writeStdout(_ text: String) async {}
    func writeStderr(_ text: String) async {}
}

@MainActor private func wire(settings: AppSettings) async {
    var stored = settings
    let trust = RecipeTrustStore(fileURL: URL(fileURLWithPath: "/tmp/t.json"), secrets: InMemorySecretStore())
    let library = RecipeLibrary(loadSettings: { stored.recipes }, saveSettings: { stored.recipes = $0 },
                                trustStore: trust, approver: DemoApprover(), gates: { GateEnvironment(settings: stored) })
    let steps = RecipeStepRegistry()
    steps.registerCoreExecutors()
    steps.registerCoreExecutors(clipboard: nil, cursorImages: nil)
    steps.register(WellKnownStepType.source, executor: DemoSourceExecutor())
    let snapshot = stored
    let runner = RecipeRunner(steps: steps, environment: { SystemRecipeEnvironment(settings: snapshot) },
                              preflight: { recipe in await library.ensureApprovedAndCurrent(recipe) },
                              recipeLookup: { id in await MainActor.run { library.recipe(id: id)?.recipe } },
                              selectionInProgress: { false }, bringSelectionToFront: {})
    let observation = runner.addObserver { event in
        if case .flowFinished(let result) = event, !result.isSuccess { print(result.reason ?? "") }
    }
    let hub = RecipeTriggerHub(library: library, runner: runner)
    let hotkeys = DemoHotkeys()
    hotkeys.hub = hub
    hub.register(hotkeys)
    library.onChange = { hub.sync() }
    _ = await library.reload()
    if var request = try? library.runRequest(command: "qr", arguments: ["file": "a.png"], source: .commandLine,
                                             resolvePath: { path, _ in path }) {
        request.output = DemoSink()
        request.onFinish = { context in
            let text = context.evaluator.evaluate("${Barcode.Text}", in: context.scope())
            await context.output?.writeStdout(text.interpolationText)
        }
        let handle = runner.start(request)
        let result = await handle.result
        _ = result.exitCode
    }
    observation.cancel()
    let validator = RecipeValidator(gates: GateEnvironment(settings: stored))
    if let recipes = try? RecipeSerializer.decode(Data()), let first = recipes.first {
        let v = validator.validate(first)
        _ = RecipeDescriber().describeSteps(first)
        _ = RecipeContractAnalyzer.analyze(first)
        _ = v.gateTypes
    }
    _ = RecipeHotkeyText.parse("Ctrl + Shift + B")
}

@Suite struct RecipeAPISurfaceTests {
    /// The usage above compiles; it is not run (it would start real flows).
    @Test func frozenAPICompiles() {
        let usage: @MainActor (AppSettings) async -> Void = wire
        _ = usage
        #expect(Bool(true))
    }
}
