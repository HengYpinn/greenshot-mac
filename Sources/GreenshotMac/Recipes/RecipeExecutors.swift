// Greenshot for Mac (Community) - an unofficial macOS port of Greenshot
// Copyright (C) 2026 Greenshot for Mac (Community) contributors
// Based on Greenshot, Copyright (C) 2007-2026 Thomas Braun, Jens Klingen, Robin Krom
// SPDX-License-Identifier: GPL-3.0-or-later

import AppKit
import GreenshotCore

/// The step registry of the app (upstream `StepRegistry` with the plug-ins' `IRecipeStepProvider`s, all built in on the
/// Mac): Core's steps (SetVariable, Conditional, Slot, Stdout, Stderr, Effect, Annotation, TextEffect, Processors,
/// BarcodeScan) and the app's: Source, InteractiveSelection, ImmediateFeedback, the destination steps and their aliases,
/// Notification, UserPrompt, DynamicDestination, RecordVideo, ExternalCommand, Jira, Confluence, Box, Dropbox, Office, Pdf.
@MainActor
enum RecipeExecutors {
    static func register(on runtime: RecipeRuntime) {
        let steps = runtime.steps
        steps.registerCoreExecutors(clipboard: RecipePasteboardWriter(), cursorImages: RecipeCursorImages())
        steps.register(WellKnownStepType.source, executor: RecipeSourceExecutor(runtime: runtime))
        steps.register(WellKnownStepType.interactiveSelection, executor: RecipeInteractiveSelectionExecutor(runtime: runtime))
        steps.register(WellKnownStepType.immediateFeedback, executor: RecipeImmediateFeedbackExecutor(runtime: runtime))

        let dispatcher = RecipeDestinationDispatcher(
            exporter: RecipeAppExporter(runtime: runtime), steps: steps,
            chains: { recipe in await MainActor.run { runtime.destinationChains?(recipe) ?? [] } },
            settingsDestinations: { [snapshot = RecipeDestinationsSnapshot(runtime: runtime)] in snapshot.designations })
        for stepType in [WellKnownStepType.destinations, WellKnownStepType.saveFile, WellKnownStepType.editor, WellKnownStepType.printer,
                         WellKnownStepType.email, WellKnownStepType.customDestination] {
            steps.register(stepType, executor: dispatcher)
        }
        steps.register(WellKnownStepType.clipboard, executor: RecipeClipboardStepExecutor(runtime: runtime, steps: steps))
        steps.register(contract: RecipeNotificationExecutor.contract,
                       executor: RecipeNotificationExecutor(presenter: RecipeAppNotificationPresenter(runtime: runtime)))
        steps.register(WellKnownStepType.userPrompt, executor: RecipeUserPromptExecutor(presenter: RecipePromptPresenter()))
        steps.register(WellKnownStepType.dynamicDestination,
                       executor: RecipeDynamicDestinationExecutor(presenter: RecipeFlyoutPresenter(runtime: runtime, steps: steps)))
        steps.register(WellKnownStepType.recordVideo, executor: RecipeRecordVideoExecutor(runtime: runtime))
        steps.register(WellKnownStepType.externalCommand, executor: RecipeExternalCommandExecutor(runtime: runtime))
        steps.register(WellKnownStepType.jira, executor: RecipeJiraExecutor(runtime: runtime))
        steps.register(WellKnownStepType.confluence, executor: RecipeConfluenceExecutor(runtime: runtime))
        steps.register(WellKnownStepType.box, executor: RecipeCloudExecutor(runtime: runtime, destination: .box))
        steps.register(WellKnownStepType.dropbox, executor: RecipeCloudExecutor(runtime: runtime, destination: .dropbox))
        steps.register(WellKnownStepType.office, executor: RecipeOfficeExecutor(runtime: runtime))
        steps.register(WellKnownStepType.pdf, executor: RecipePdfExecutor(runtime: runtime))
    }
}

/// The settings' destinations as designations, read off the main thread by the destination steps.
final class RecipeDestinationsSnapshot: @unchecked Sendable {
    private let lock = NSLock()
    private var current: [String]

    @MainActor
    init(runtime: RecipeRuntime) {
        current = Self.designations(runtime.app.settings.value.destinations)
        runtime.app.settings.onChange(of: \AppSettings.destinations) { [weak self] destinations in
            guard let self else { return }
            let designations = Self.designations(destinations)
            self.lock.withLock { self.current = designations }
        }
    }

    var designations: [String] { lock.withLock { current } }

    /// No destination set: the picker, as a capture of the app does (`OutputManager.handle`).
    static func designations(_ destinations: [CaptureDestination]) -> [String] {
        destinations.isEmpty ? ["Picker"] : destinations.map(RecipeDestinationDesignation.designation(for:))
    }
}

/// Names in recipes (step and trigger types, designations, keys) compare case-insensitively, like Core's (upstream
/// `StringComparison.OrdinalIgnoreCase`).
func recipeEquals(_ lhs: String, _ rhs: String) -> Bool {
    lhs.caseInsensitiveCompare(rhs) == .orderedSame
}
