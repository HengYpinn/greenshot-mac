// Greenshot for Mac (Community) - an unofficial macOS port of Greenshot
// Copyright (C) 2026 Greenshot for Mac (Community) contributors
// Based on Greenshot, Copyright (C) 2007-2026 Thomas Braun, Jens Klingen, Robin Krom
// SPDX-License-Identifier: GPL-3.0-or-later

import Foundation
import Testing
@testable import GreenshotCore

/// The built-in recipes against upstream's `RecipeManager.InitializeDefaultRecipes` and the built-in recipe providers.
@Suite struct RecipeBuiltInTests {
    @Test func idsAndNamesAreUpstreams() {
        let ids = BuiltInRecipes.all.map(\.id)
        #expect(ids == ["recipe_region", "recipe_window", "recipe_active_window", "recipe_fullscreen", "recipe_lastregion",
                        "recipe_clipboard", "recipe_file", "recipe_ocr", "recipe_notification", "recipe_browser_extension",
                        "recipe_ai_capture_window", "recipe_ai_capture_region", "recipe_ai_capture_screen"])
        #expect(BuiltInRecipes.region.name == "Capture region")
        #expect(BuiltInRecipes.ocr.name == "OCR text to clipboard")
        #expect(BuiltInRecipes.file.name == "Open file")
        let found = BuiltInRecipes.recipe(id: "RECIPE_REGION")
        #expect(found?.id == "recipe_region")
    }

    @Test func everyBuiltInIsValid() {
        let validator = RecipeValidator(gates: GateEnvironment(defaultDestinations: ["Editor"]))
        for recipe in BuiltInRecipes.all {
            let result = validator.validate(recipe)
            #expect(result.errors.isEmpty, "\(recipe.id): \(result.errors)")
        }
    }

    @Test func everyBuiltInPassesTheContractAnalysis() {
        for recipe in BuiltInRecipes.all {
            let report = RecipeContractAnalyzer.analyze(recipe)
            #expect(report.warnings.isEmpty, "\(recipe.id): \(report.warnings)")
            #expect(report.acquiresImage, "\(recipe.id)")
        }
    }

    @Test func builtInsSurviveTheFileFormat() throws {
        for recipe in BuiltInRecipes.all {
            let text = RecipeSerializer.encode(recipe)
            let decoded = try RecipeSerializer.decode(text: text)
            let first = try #require(decoded.first)
            #expect(first.nodes == recipe.nodes, "\(recipe.id)")
            #expect(first.flow == recipe.flow, "\(recipe.id)")
            #expect(first.triggers == recipe.triggers, "\(recipe.id)")
        }
    }

    @Test func regionHasItsScansAndTheStandardSlots() {
        let recipe = BuiltInRecipes.region
        #expect(recipe.nodes.map(\.id) == ["acquire", "scan_pre", "select", "feedback", "after_capture", "scan_post",
                                           "before_export", "before_destination", "export", "after_export", "notify"])
        #expect(recipe.node("scan_pre")?.parameters.string("Timing") == "PreSelection")
        #expect(recipe.node("scan_post")?.parameters.string("Timing") == "PostSelection")
        #expect(recipe.node("scan_pre")?.name == "Scan Before Selection")
        #expect(recipe.flow.targets(from: "feedback") == ["after_capture"])
        #expect(recipe.flow.targets(from: "after_capture") == ["scan_post"])
        #expect(recipe.flow.targets(from: "scan_post") == ["before_export"])
        #expect(recipe.flow.targets(from: "before_destination") == ["export"])
        #expect(recipe.flow.targets(from: "export") == ["after_export"])
        #expect(recipe.flow.targets(from: "after_export") == ["notify"])
        #expect(recipe.node("select")?.parameters.string("SelectionMode") == "Region")
    }

    @Test func directCapturesHaveSlotsAroundTheirExport() {
        for recipe in [BuiltInRecipes.activeWindow, BuiltInRecipes.fullScreen, BuiltInRecipes.lastRegion] {
            #expect(recipe.flow.targets(from: "feedback") == ["after_capture"], "\(recipe.id)")
            #expect(recipe.flow.targets(from: "after_capture") == ["processors"], "\(recipe.id)")
            #expect(recipe.node("processors")?.parameters.string("Timing") == nil, "\(recipe.id)")
            #expect(recipe.firstNode(ofType: WellKnownStepType.notification) != nil, "\(recipe.id)")
        }
        #expect(BuiltInRecipes.clipboard.node("acquire")?.parameters.bool("CaptureMouseCursor") == false)
        #expect(BuiltInRecipes.clipboard.node("export")?.parameters.strings("DestinationDesignations") == ["Editor"])
        #expect(BuiltInRecipes.clipboard.flow.startNodes == ["acquire"])
        #expect(BuiltInRecipes.clipboard.flow.targets(from: "acquire") == ["after_capture"])
    }

    @Test func fileAndOCRHaveNoSlots() {
        for recipe in [BuiltInRecipes.file, BuiltInRecipes.ocr, BuiltInRecipes.notification] {
            #expect(recipe.firstNode(ofType: WellKnownStepType.slot) == nil, "\(recipe.id)")
        }
        let trigger = BuiltInRecipes.file.triggers.first
        #expect(trigger?.isType(WellKnownTriggerType.openFile) == true)
        #expect(trigger?.name == "Default Open With File Trigger")
        #expect(BuiltInRecipes.ocr.node("ocr")?.parameters.strings("ProcessorIds") == ["Windows10OcrProcessor"])
        #expect(BuiltInRecipes.ocr.node("export")?.stepType == WellKnownStepType.clipboard)
        #expect(BuiltInRecipes.ocr.node("export")?.parameters.string("ClipboardMode") == "TextOnly")
    }

    @Test func browserExtensionAndNotificationOfferTheFlyout() {
        let browser = BuiltInRecipes.browserExtension
        #expect(browser.node("acquire")?.parameters.string("SourceType") == "Extension")
        #expect(browser.node("export")?.stepType == WellKnownStepType.dynamicDestination)
        #expect(browser.node("export")?.parameters.string("Title") == "Export Browser Capture")
        #expect(browser.triggers.first?.isType(WellKnownTriggerType.extension) == true)
        #expect(browser.firstNode(ofType: WellKnownStepType.slot) != nil)
        #expect(BuiltInRecipes.notification.node("acquire")?.parameters.string("SourceType") == "File")
        #expect(BuiltInRecipes.notification.node("export")?.stepType == WellKnownStepType.dynamicDestination)
    }

    @Test func aiToolRecipesAreTools() throws {
        let window = BuiltInRecipes.aiCaptureWindow
        let trigger = try #require(window.triggers.first)
        #expect(trigger.isType(WellKnownTriggerType.aiTool))
        #expect(trigger.toolName == "capture_window")
        #expect(trigger.toolTitle == "Capture window")
        let arguments = trigger.arguments
        #expect(arguments.map(\.name) == ["window", "ocr"])
        #expect(arguments.first?.type == .window)
        #expect(arguments.first?.required == true)
        #expect(arguments.last?.effectiveVariable == "Ocr")
        #expect(arguments.last?.defaultValue == "false")
        #expect(window.node("acquire")?.parameters.string("WindowHandle") == "${Window}")
        #expect(window.node("acquire")?.parameters.int("DelayMs") == 0)
        #expect(window.flow.conditionalTransitions == [ConditionalTransition(from: "ocr_wanted", branch: "ocr", to: "ocr")])
        #expect(!window.hasDestinationStep)

        let region = try #require(BuiltInRecipes.aiCaptureRegion.triggers.first)
        #expect(region.arguments.first?.type == .region)
        #expect(region.arguments.first?.effectiveVariable == "PreSuppliedRegion")
        let screen = BuiltInRecipes.aiCaptureScreen
        #expect(screen.node("acquire")?.parameters.string("ScreenCaptureMode") == "FullScreen")
        #expect(screen.triggers.first?.arguments.map(\.name) == ["ocr"])
    }

    @Test func directCaptureIds() {
        #expect(BuiltInRecipes.isDirectCapture("recipe_file"))
        #expect(BuiltInRecipes.isDirectCapture("Recipe_Notification"))
        #expect(!BuiltInRecipes.isDirectCapture("recipe_browser_extension"))
        #expect(!BuiltInRecipes.isDirectCapture("recipe_ai_capture_window"))
    }

    @Test func aiToolRunWithoutOcrSkipsTheOcr() async {
        let recorder = RecipeRecorder()
        let registry = RecipeEngineHarness.registry(recorder)
        let source = ClosureExecutor { step, context in
            recorder.add(step.node.id)
            context.payload = RecipePayload(image: TestImage.solid(width: 4, height: 4, .white), scale: 1, title: "AI")
        }
        registry.register(WellKnownStepType.source, executor: source)
        registry.register(WellKnownStepType.processors, executor: ClosureExecutor { step, _ in recorder.add(step.node.id) })
        let context = RecipeFlowContext(recipe: BuiltInRecipes.aiCaptureScreen, environment: FixedRecipeEnvironment())
        context[variable: "Ocr"] = .bool(false)
        _ = await RecipeEngineHarness.run(BuiltInRecipes.aiCaptureScreen, registry, context: context)
        #expect(recorder.all == ["acquire"])
        let wanted = RecipeFlowContext(recipe: BuiltInRecipes.aiCaptureScreen, environment: FixedRecipeEnvironment())
        wanted[variable: "Ocr"] = .bool(true)
        let second = RecipeRecorder()
        let registry2 = RecipeEngineHarness.registry(second)
        registry2.register(WellKnownStepType.source, executor: ClosureExecutor { step, context in
            second.add(step.node.id)
            context.payload = RecipePayload(image: TestImage.solid(width: 4, height: 4, .white), scale: 1, title: "AI")
        })
        registry2.register(WellKnownStepType.processors, executor: ClosureExecutor { step, _ in second.add(step.node.id) })
        _ = await RecipeEngineHarness.run(BuiltInRecipes.aiCaptureScreen, registry2, context: wanted)
        #expect(second.all == ["acquire", "ocr"])
    }
}
