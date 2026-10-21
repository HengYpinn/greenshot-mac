// Greenshot for Mac (Community) - an unofficial macOS port of Greenshot
// Copyright (C) 2026 Greenshot for Mac (Community) contributors
// Based on Greenshot, Copyright (C) 2007-2026 Thomas Braun, Jens Klingen, Robin Krom
// SPDX-License-Identifier: GPL-3.0-or-later

import CoreGraphics
import Foundation
import Testing
@testable import GreenshotCore

/// An exporter that records what it got and answers from a table.
final class FakeExporter: RecipeExporting, @unchecked Sendable {
    private let lock = NSLock()
    private var calls: [String] = []
    private var widths: [Int] = []
    var results: [String: ExportResult] = [:]
    var picks: [String] = []
    var known: Set<String> = ["clipboard", "filenodialog", "editor", "jira", "printer", "email", "picker"]

    var exported: [String] { lock.withLock { calls } }
    var exportedWidths: [Int] { lock.withLock { widths } }

    func prepare(_ step: RecipeStepInvocation, payload: RecipePayload, in context: RecipeFlowContext) async {
        context[variable: "Destination.Prepared"] = .bool(true)
    }

    func target(for designation: String, step: RecipeStepInvocation, in context: RecipeFlowContext) async -> RecipeExportTarget? {
        known.contains(designation.lowercased()) ? RecipeExportTarget(designation: designation) : nil
    }

    func pick(_ payload: RecipePayload, in context: RecipeFlowContext) async -> RecipeExportTarget? {
        let next: String? = lock.withLock { picks.isEmpty ? nil : picks.removeFirst() }
        return next.map { RecipeExportTarget(designation: $0) }
    }

    func export(_ payload: RecipePayload, to target: RecipeExportTarget, step: RecipeStepInvocation,
                in context: RecipeFlowContext) async -> ExportResult {
        lock.withLock {
            calls.append(target.designation)
            widths.append(payload.image.width)
        }
        return results[target.designation.lowercased()] ?? .succeeded(target: target.designation)
    }
}

/// Upstream `DestinationExportStep` + `DestinationDispatcher`, the Clipboard step's plan and the Notification step.
@Suite struct RecipeStepsDestinationTests {
    func step(_ type: String, _ parameters: JSONObject = [:]) -> RecipeStepInvocation {
        RecipeStepInvocation(node: RecipeNode(id: "export", stepType: type, parameters: parameters), parameters: parameters,
                             contract: StepContractCatalog.builtIn.contract(for: type))
    }

    func context(width: Int = 10) -> RecipeFlowContext {
        let context = RecipeFlowContext(recipe: CaptureRecipe(id: "destination_test", name: "Destination Test"),
                                        environment: FixedRecipeEnvironment())
        context.payload = RecipePayload(image: TestImage.solid(width: width, height: 10, .white), scale: 1, title: "Capture")
        return context
    }

    func dispatcher(_ exporter: FakeExporter, chains: [RecipeDestinationChain] = [], settings: [String] = ["Editor"],
                    steps: RecipeStepRegistry = RecipeStepRegistry()) -> RecipeDestinationDispatcher {
        RecipeDestinationDispatcher(exporter: exporter, steps: steps, chains: { _ in chains }, settingsDestinations: { settings })
    }

    // MARK: Designations

    @Test func aliasStepTypesHaveTheirOwnDesignation() {
        #expect(RecipeDestinationPlan.designations(step("SaveFile"), overrides: .string("Jira"), settings: ["Editor"]) == ["FileNoDialog"])
        #expect(RecipeDestinationPlan.designations(step("Clipboard"), overrides: nil, settings: []) == ["Clipboard"])
        #expect(RecipeDestinationPlan.designations(step("Editor"), overrides: nil, settings: []) == ["Editor"])
        #expect(RecipeDestinationPlan.designations(step("Printer"), overrides: nil, settings: []) == ["Printer"])
        #expect(RecipeDestinationPlan.designations(step("Email"), overrides: nil, settings: []) == ["EMail"])
        let custom = step("CustomDestination", ["CustomDestinationId": .string(" External Paint ")])
        #expect(RecipeDestinationPlan.designations(custom, overrides: nil, settings: []) == ["External Paint"])
    }

    @Test func overridesThenParameterThenSettings() {
        let listed = step("Destinations", ["DestinationDesignations": .array([.string("Clipboard"), .string(" "), .string("Jira")])])
        #expect(RecipeDestinationPlan.designations(listed, overrides: .array([.string("Printer")]), settings: ["Editor"]) == ["Printer"])
        #expect(RecipeDestinationPlan.designations(listed, overrides: .string("Email"), settings: ["Editor"]) == ["Email"])
        #expect(RecipeDestinationPlan.designations(listed, overrides: nil, settings: ["Editor"]) == ["Clipboard", "Jira"])
        #expect(RecipeDestinationPlan.designations(step("Destinations"), overrides: .null, settings: ["Editor", "FileNoDialog"])
                == ["Editor", "FileNoDialog"])
    }

    @Test func exportErrorsText() {
        let failures: [(designation: String, error: String)] = [("Jira", "401"), ("FileNoDialog", "disk full")]
        #expect(RecipeDestinationPlan.errorsText(failures) == "Jira: 401; FileNoDialog: disk full")
        let error = RecipeDestinationPlan.failure(failures)
        #expect(error?.errorType == "DestinationExportException")
        #expect(error?.message == "Export to Jira failed: 401")
        #expect(RecipeDestinationPlan.failure([]) == nil)
    }

    // MARK: File and clipboard options

    @Test func fileOptionsOnlyWhenSet() {
        #expect(RecipeFileExportOptions(step("Destinations")).isEmpty)
        let options = RecipeFileExportOptions(step("SaveFile", ["SaveDirectory": .string("~/Shots/${YYYY}"), "Format": .string("jpeg"),
                                                                "JpegQuality": .number(150), "AllowOverwrite": .bool(true)]))
        #expect(!options.isEmpty)
        #expect(options.saveDirectory == "~/Shots/${YYYY}")
        #expect(options.format == .jpg)
        #expect(options.jpegQuality == 100)
        #expect(options.allowOverwrite == true)
        #expect(options.promptQuality == nil)
        let variables = options.variables(defaultFormat: .png, defaultQuality: 80, defaultReduceColors: false)
        #expect(variables["Destination.AllowOverwrite"] == .bool(true))
        #expect(variables["Destination.PromptQuality"] == nil)
        let surface = variables["Destination.SurfaceOutputSettings"]?.objectValue
        #expect(surface?.string("Format") == "jpg")
        #expect(surface?.int("JpegQuality") == 100)
    }

    @Test func clipboardPlan() {
        let plain = RecipeClipboardPlan(step("Clipboard"))
        #expect(plain.mode == .imageOnly)
        #expect(plain.formats == [.png, .tiff, .html])
        #expect(!plain.needsText)
        let text = RecipeClipboardPlan(step("Clipboard", ["ClipboardMode": .string("TextOnly"), "ClipboardCustomText": .string("Found: ${ocr_text}")]))
        #expect(text.mode == .textOnly)
        #expect(text.customText == "Found: ${ocr_text}")
        let both = RecipeClipboardPlan(step("Clipboard", ["ClipboardFormatText": .bool(true), "ClipboardFormatDIB": .bool(false),
                                                          "ClipboardFormatHTML": .bool(false)]))
        #expect(both.mode == .imageAndText)
        #expect(both.formats == [.png])
        let none = RecipeClipboardPlan(step("Clipboard", ["ClipboardFormatPNG": .bool(false), "ClipboardFormatDIB": .bool(false),
                                                          "ClipboardFormatHTML": .bool(false)]))
        #expect(none.formats == [.png])
    }

    @Test func customTextTokens() {
        #expect(RecipeClipboardPlan.substitute("[${ocr_text}] ${PAYLOAD.TEXT}", text: "abc") == "[abc] abc")
        #expect(RecipeClipboardPlan.substitute("no tokens", text: "abc") == "no tokens")
    }

    // MARK: Dispatch

    @Test func exportsInTheRecipesOrderAndRecordsThem() async throws {
        let exporter = FakeExporter()
        exporter.results["editor"] = .declined
        let context = context()
        let invocation = step("Destinations", ["DestinationDesignations": .array([.string("Clipboard"), .string("Editor"), .string("Nowhere"),
                                                                                  .string("FileNoDialog")])])
        try await dispatcher(exporter).execute(invocation, in: context)
        #expect(exporter.exported == ["Clipboard", "Editor", "FileNoDialog"])
        // The declined export isn't in the flow's exports.
        #expect(context.exports.all.map(\.designation) == ["Clipboard", "FileNoDialog"])
        #expect(context.state == .exporting)
        #expect(context[variable: "Destination.Prepared"] == .bool(true))
        #expect(context[variable: "DestinationExportErrors"] == nil)
    }

    @Test func failedExportsComeAfterAllRan() async {
        let exporter = FakeExporter()
        exporter.results["jira"] = .failed("401", target: "Jira")
        let context = context()
        let invocation = step("Destinations", ["DestinationDesignations": .array([.string("Jira"), .string("Clipboard")])])
        await #expect(throws: RecipeStepError.self) {
            try await dispatcher(exporter).execute(invocation, in: context)
        }
        #expect(exporter.exported == ["Jira", "Clipboard"])
        #expect(context[variable: "DestinationExportErrors"] == .string("Jira: 401"))
        let outcome = context.exports.all.first
        #expect(outcome?.succeeded == false)
        #expect(outcome?.errorMessage == "401")
    }

    @Test func aFailedExportRoutesThroughTheErrorTransition() async {
        let exporter = FakeExporter()
        exporter.results["jira"] = .failed("offline", target: "Jira")
        let recorder = RecipeRecorder()
        let registry = RecipeEngineHarness.registry(recorder)
        registry.register(WellKnownStepType.destinations, executor: dispatcher(exporter))
        var recipe = RecipeEngineHarness.recipe(["fallback"], start: ["export"], [])
        recipe.nodes.insert(RecipeNode(id: "export", stepType: WellKnownStepType.destinations,
                                       parameters: ["DestinationDesignations": .array([.string("Jira")])]), at: 0)
        recipe.flow.errorTransitions = [ErrorTransition(from: "export", to: "fallback", errorType: "DestinationExportException")]
        let context = await RecipeEngineHarness.run(recipe, registry)
        #expect(recorder.all == ["fallback"])
        #expect(context[variable: "LastError"] == .string("Export to Jira failed: offline"))
        #expect(context.state != .failed)
    }

    @Test func settingsDestinationsWhenTheStepNamesNone() async throws {
        let exporter = FakeExporter()
        try await dispatcher(exporter, settings: ["Email", "Clipboard"]).execute(step("Destinations"), in: context())
        #expect(exporter.exported == ["Email", "Clipboard"])
    }

    @Test func thePickerComesBackUntilAnExportSucceeds() async throws {
        let exporter = FakeExporter()
        exporter.picks = ["Jira", "Clipboard", "Printer"]
        exporter.results["jira"] = .failed("offline", target: "Jira")
        let context = context()
        try await dispatcher(exporter, settings: ["Picker"]).execute(step("Destinations"), in: context)
        #expect(exporter.exported == ["Jira", "Clipboard"])
        #expect(context.exports.all.count == 2)
    }

    @Test func aClosedPickerExportsNothing() async throws {
        let exporter = FakeExporter()
        let context = context()
        try await dispatcher(exporter, settings: ["Picker"]).execute(step("Destinations"), in: context)
        #expect(exporter.exported.isEmpty)
        #expect(context.exports.all.isEmpty)
    }

    // MARK: Automatic steps per destination

    /// A chain that widens the image by `pixels` (an Effect step with a border).
    func border(_ id: String, only: [String] = [], fails: Bool = false) -> RecipeDestinationChain {
        var flow = CaptureRecipe(id: "destination_test", name: "Destination Test")
        let parameters: JSONObject = fails ? ["Fail": .bool(true)] : ["Effect": .string("Border"), "Width": .number(5), "Color": .string("#000000")]
        flow.nodes = [RecipeNode(id: "\(id)/step", stepType: fails ? "Failing" : WellKnownStepType.effect, parameters: parameters)]
        flow.flow.startNodes = ["\(id)/step"]
        return RecipeDestinationChain(extensionId: id, flow: flow, onlyDestinations: only)
    }

    func chainRegistry() -> RecipeStepRegistry {
        let registry = RecipeStepRegistry()
        registry.registerCoreExecutors()
        registry.register(contract: StepContract(stepType: "Failing", displayName: "Failing", acceptsUndeclaredParameters: true),
                          executor: ClosureExecutor { _, _ in throw RecipeStepError("broken") })
        return registry
    }

    @Test func chainsRunOnACopyPerCombination() async throws {
        let exporter = FakeExporter()
        let chains = [border("ext_border", only: ["Clipboard", "FileNoDialog"])]
        let context = context(width: 10)
        let invocation = step("Destinations", ["DestinationDesignations": .array([.string("Clipboard"), .string("Editor"), .string("FileNoDialog")])])
        try await dispatcher(exporter, chains: chains, steps: chainRegistry()).execute(invocation, in: context)
        #expect(exporter.exported == ["Clipboard", "Editor", "FileNoDialog"])
        #expect(exporter.exportedWidths == [20, 10, 20])
        // The flow's own capture stays as it was.
        let width = context.payload?.image.width
        #expect(width == 10)
    }

    @Test func aFailingChainExportsTheOriginal() async throws {
        let exporter = FakeExporter()
        let context = context(width: 10)
        let invocation = step("Destinations", ["DestinationDesignations": .array([.string("Clipboard")])])
        try await dispatcher(exporter, chains: [border("ext_broken", fails: true)], steps: chainRegistry()).execute(invocation, in: context)
        #expect(exporter.exportedWidths == [10])
    }

    @Test func externalCommandsAsTheAutomaticStepsNameThem() {
        #expect(RecipeDestinationPlan.externalCommandDesignation("External", commands: ["Preview"]) == "External Preview")
        #expect(RecipeDestinationPlan.externalCommandDesignation("External", commands: ["Preview", "Paint"]) == "External")
        #expect(RecipeDestinationPlan.externalCommandDesignation("external paint", commands: ["Preview", "Paint"]) == "External Paint")
        #expect(RecipeDestinationPlan.externalCommandDesignation("External Other", commands: ["Preview"]) == "External Other")
        #expect(RecipeDestinationPlan.externalCommandDesignation("Clipboard", commands: ["Preview"]) == "Clipboard")
        // The settings' destination is called "External".
        #expect(RecipeDestinationPlan.destination(of: "External").destination == .externalCommand)
        #expect(RecipeDestinationPlan.destination(of: "External Paint").commandName == "Paint")
        #expect(RecipeDestinationPlan.destination(of: "FileNoDialog").destination == .file)
        // A chain for one command runs for that command only; one without destinations for every one.
        let copies = RecipeDestinationCopies(chains: [border("ext_preview", only: ["External Preview"]), border("ext_all")],
                                             steps: RecipeStepRegistry())
        #expect(copies.chains(for: "External Preview").map(\.extensionId) == ["ext_preview", "ext_all"])
        #expect(copies.chains(for: "External Paint").map(\.extensionId) == ["ext_all"])
        #expect(copies.chains(for: "External").map(\.extensionId) == ["ext_all"])
    }

    @Test func aChainForOneExternalCommandChangesItsCopyOnly() async throws {
        let exporter = FakeExporter()
        exporter.known.insert("external preview")
        exporter.known.insert("external paint")
        let context = context(width: 10)
        let invocation = step("Destinations", ["DestinationDesignations": .array([.string("External Preview"), .string("External Paint")])])
        try await dispatcher(exporter, chains: [border("ext_preview", only: ["External Preview"])], steps: chainRegistry())
            .execute(invocation, in: context)
        #expect(exporter.exported == ["External Preview", "External Paint"])
        #expect(exporter.exportedWidths == [20, 10])
    }

    @Test func chainKeysAndFilters() {
        let chains = [border("a", only: ["clipboard"]), border("b")]
        let copies = RecipeDestinationCopies(chains: chains, steps: RecipeStepRegistry())
        #expect(copies.chains(for: "Clipboard").map(\.extensionId) == ["a", "b"])
        #expect(copies.chains(for: "Editor").map(\.extensionId) == ["b"])
        #expect(RecipeDestinationCopies.key(chains) == "a|b")
    }

    // MARK: Notification

    final class Announcements: RecipeNotificationPresenting, @unchecked Sendable {
        private let lock = NSLock()
        private var shown: [[String]] = []
        var all: [[String]] { lock.withLock { shown } }

        func announce(_ exports: [RecipeExportOutcome], in context: RecipeFlowContext) async {
            lock.withLock { shown.append(exports.map(\.designation)) }
        }
    }

    @Test func notificationShowsTheExportsSinceTheLastOne() async throws {
        let announcements = Announcements()
        let executor = RecipeNotificationExecutor(presenter: announcements)
        let context = context()
        context.exports.add(RecipeExportOutcome(designation: "Clipboard", succeeded: true))
        context.exports.add(RecipeExportOutcome(designation: "Jira", succeeded: false))
        try await executor.execute(step("Notification"), in: context)
        context.exports.add(RecipeExportOutcome(designation: "Editor", succeeded: true))
        try await executor.execute(step("Notification"), in: context)
        try await executor.execute(step("Notification"), in: context)
        #expect(announcements.all == [["Clipboard", "Jira"], ["Editor"]])
        #expect(context[variable: RecipeNotificationExecutor.announcedExportsVariable] == .number(3))
        #expect(context[variable: "EnableCompletionNotification"] == .bool(true))
    }

    @Test func notificationSwitchedOffTakesThemSilently() async throws {
        let announcements = Announcements()
        let executor = RecipeNotificationExecutor(presenter: announcements)
        let context = context()
        context.exports.add(RecipeExportOutcome(designation: "Clipboard", succeeded: true))
        try await executor.execute(step("Notification", ["ShowNotification": .bool(false)]), in: context)
        context[variable: "ShowNotification"] = .bool(true)
        try await executor.execute(step("Notification", ["ShowNotification": .bool(false)]), in: context)
        #expect(announcements.all.isEmpty)
        #expect(context[variable: "EnableCompletionNotification"] == .bool(true))
        #expect(context[variable: RecipeNotificationExecutor.announcedExportsVariable] == .number(0))
    }

    /// The count is the flow's, kept in the shared export log: a branch's Notification step adds to it.
    @Test func notificationCountsTheWholeFlow() async throws {
        let executor = RecipeNotificationExecutor(presenter: Announcements())
        let context = context()
        let branch = context.makeBranch()
        context.exports.add(RecipeExportOutcome(designation: "Clipboard", succeeded: true))
        try await executor.execute(step("Notification"), in: branch)
        context.exports.add(RecipeExportOutcome(designation: "Jira", succeeded: true))
        try await executor.execute(step("Notification"), in: context)
        #expect(branch[variable: RecipeNotificationExecutor.announcedExportsVariable] == .number(1))
        #expect(context[variable: RecipeNotificationExecutor.announcedExportsVariable] == .number(2))
        #expect(context.exports.announcedCount == 2)
    }

    @Test func notificationContractDeclaresTheCount() {
        let contract = RecipeNotificationExecutor.contract
        #expect(contract.stepType == WellKnownStepType.notification)
        #expect(contract.outputVariables.contains { $0.name == RecipeNotificationExecutor.announcedExportsVariable })
        #expect(contract.outputVariables.contains { $0.name == "EnableCompletionNotification" })
    }
}
