// Greenshot for Mac (Community) - an unofficial macOS port of Greenshot
// Copyright (C) 2026 Greenshot for Mac (Community) contributors
// Based on Greenshot, Copyright (C) 2007-2026 Thomas Braun, Jens Klingen, Robin Krom
// SPDX-License-Identifier: GPL-3.0-or-later

import CoreGraphics
import Foundation
import Testing
@testable import GreenshotCore

/// Runs a BeforeDestination chain the way the export steps do: on its own context with a copy of the capture.
enum ChainHarness {
    static func run(_ chain: RecipeDestinationChain, on payload: RecipePayload, values: [String: String] = [:]) async -> RecipeFlowContext {
        let context = RecipeFlowContext(recipe: chain.flow, environment: FixedRecipeEnvironment(), optionValues: RecipeOptionValues(values))
        context.payload = payload
        context.isPayloadPreSupplied = true
        let registry = RecipeStepRegistry()
        registry.registerCoreExecutors()
        await RecipeFlowEngine(steps: registry).execute(context)
        return context
    }

    /// The capture recipe with every standard slot, composed with the switched-on built-in automatic steps.
    static func chains(_ values: [String: String]) -> [RecipeDestinationChain] {
        var recipe = CaptureRecipe(id: "recipe_region", name: "Region")
        recipe.nodes = [RecipeNode(id: "source", stepType: "Source"), RecipeNode(id: "export", stepType: "Destinations")]
        recipe.flow.startNodes = ["source"]
        recipe.flow.addTransition(from: "source", to: "export")
        RecipeSlotNodes.addStandardSlots(to: &recipe, afterCaptureBefore: "export", exportNode: "export")
        let stored = RecipeOptionValues(values)
        let composed = RecipeComposer.compose(recipe, extensions: RecipeBuiltInExtensions.all) {
            RecipeExtensionSettings.stored(for: $0, in: stored)
        }
        return composed.composition?.destinationChains ?? []
    }

    static func sample() -> RecipePayload {
        RecipePayload(image: TestImage.solid(width: 40, height: 30, .white), scale: 2, title: "Sample")
    }
}

/// Upstream BuiltInExtensions: caption, border and drop shadow at BeforeDestination of the capture recipes.
@Suite struct RecipeExtensionBuiltInTests {
    @Test func theyAreValidAutomaticStepsForEveryCapture() {
        let all = RecipeBuiltInExtensions.all
        #expect(all.map(\.id) == ["ext_border", "ext_dropshadow", "ext_caption"])
        for ext in all {
            let validation = RecipeValidator().validate(ext)
            #expect(validation.errors.isEmpty, "\(ext.id): \(validation.errors)")
            #expect(ext.kind == .extension)
            #expect(ext.extends?.recipes == ["*capture"])
            #expect(ext.extensionSlotName == "BeforeDestination")
            // Switched off until the user switches them on; the switch is in Quick Settings.
            #expect(ext.extensionEnabledOption?.resolvedDefault == .bool(false))
            #expect(ext.extensionEnabledOption?.quickSettings == true)
        }
        #expect(all.map { $0.extends?.order ?? 0 } == [200, 300, 100])
    }

    @Test func theDefaultsAreUpstreams() throws {
        let border = RecipeBuiltInExtensions.border()
        #expect(border.option("width")?.resolvedDefault == .number(2))
        #expect(border.option("width")?.max == 50)
        #expect(border.option("color")?.resolvedDefault == .string("#000000"))
        let shadow = RecipeBuiltInExtensions.dropShadow()
        #expect(shadow.option("size")?.resolvedDefault == .number(7))
        #expect(shadow.option("darkness")?.resolvedDefault == .number(0.6))
        #expect(shadow.option("offset")?.resolvedDefault == .number(-1))
        let caption = RecipeBuiltInExtensions.caption()
        let text = try #require(caption.option("text"))
        #expect(text.isTemplate)
        #expect(text.resolvedDefault == .string("${now:yyyy-MM-dd HH:mm:ss}"))
        #expect(caption.option("position")?.resolvedDefault == .string("Bottom"))
        #expect(caption.option("fontSize")?.resolvedDefault == .number(12))
        #expect(caption.option("barColor")?.resolvedDefault == .string("#FFFFFF"))
    }

    @Test func switchedOffTheyChangeNothing() {
        #expect(ChainHarness.chains([:]).isEmpty)
    }

    @Test func theChainsRunCaptionThenBorderThenShadow() {
        let chains = ChainHarness.chains(["ext_border.enabled": "True", "ext_dropshadow.enabled": "True", "ext_caption.enabled": "True"])
        #expect(chains.map(\.extensionId) == ["ext_caption", "ext_border", "ext_dropshadow"])
    }

    @Test func borderGrowsByItsWidth() async throws {
        let chain = try #require(ChainHarness.chains(["ext_border.enabled": "True"]).first)
        let context = await ChainHarness.run(chain, on: ChainHarness.sample(), values: ["ext_border.enabled": "True", "ext_border.width": "5"])
        let payload = try #require(context.payload)
        // 5 points on each side at 2 pixels per point.
        #expect(payload.image.width == 60)
        #expect(payload.image.height == 50)
        let edge = TestImage.pixel(payload.image, 0, 25)
        #expect(edge.isClose(to: .black))
    }

    @Test func captionAddsABarAndItsText() async throws {
        let values = ["ext_caption.enabled": "True"]
        let chain = try #require(ChainHarness.chains(values).first)
        let below = await ChainHarness.run(chain, on: ChainHarness.sample(), values: values)
        let payload = try #require(below.payload)
        // The bar is twice the font size (12 points) high, at 2 pixels per point.
        #expect(payload.image.width == 40)
        #expect(payload.image.height == 78)
        #expect(payload.annotations.count == 1)
        let label = try #require(payload.annotations.first)
        #expect(label.kind == .text)
        #expect(label.text.hasPrefix("20"))

        var top = values
        top["ext_caption.position"] = "Top"
        top["ext_caption.fontSize"] = "10"
        let above = await ChainHarness.run(chain, on: ChainHarness.sample(), values: top)
        let topPayload = try #require(above.payload)
        #expect(topPayload.image.height == 70)
        #expect(topPayload.annotations.count == 1)
        #expect(above.logMentions("bar_top"))
    }

    @Test func dropShadowGrowsTheCanvas() async throws {
        let values = ["ext_dropshadow.enabled": "True"]
        let chain = try #require(ChainHarness.chains(values).first)
        let context = await ChainHarness.run(chain, on: ChainHarness.sample(), values: values)
        let payload = try #require(context.payload)
        #expect(payload.image.width > 40)
        #expect(payload.image.height > 30)
        #expect(!context.isAborted)
    }

    @Test func onlyDestinationsLimitTheChain() {
        let chains = ChainHarness.chains(["ext_border.enabled": "True", "ext_border.onlyDestinations": "EMail"])
        let composition = RecipeComposition(appliedExtensions: [], destinationChains: chains)
        #expect(composition.chains(forDestination: "EMail").count == 1)
        #expect(composition.chains(forDestination: "FileNoDialog").isEmpty)
    }
}
