// Greenshot for Mac (Community) - an unofficial macOS port of Greenshot
// Copyright (C) 2026 Greenshot for Mac (Community) contributors
// Based on Greenshot, Copyright (C) 2007-2026 Thomas Braun, Jens Klingen, Robin Krom
// SPDX-License-Identifier: GPL-3.0-or-later

import CoreGraphics
import Foundation
import Testing
@testable import GreenshotCore

/// The values of the capture steps (upstream `SourceAcquisitionStep`, `ImmediateFeedbackStep`): the three-tier precedence
/// of docs/capture-recipes.md §5, regions, window references.
@Suite struct RecipeStepsSourceTests {
    func step(_ type: String, _ parameters: JSONObject) -> RecipeStepInvocation {
        RecipeStepInvocation(node: RecipeNode(id: "n", stepType: type, parameters: parameters), parameters: parameters,
                             contract: StepContractCatalog.builtIn.contract(for: type))
    }

    func context(_ variables: [String: JSONValue] = [:]) -> RecipeFlowContext {
        let context = RecipeFlowContext(recipe: CaptureRecipe(id: "source_test", name: "Source Test"), environment: FixedRecipeEnvironment())
        for (name, value) in variables { context[variable: name] = value }
        return context
    }

    @Test func sourceTypeComesFromTheParameterOnly() {
        #expect(RecipeSourceValues.sourceType(step("Source", [:])) == .region)
        #expect(RecipeSourceValues.sourceType(step("Source", ["SourceType": .string("fullscreen")])) == .fullScreen)
        #expect(RecipeSourceValues.sourceType(step("Source", ["SourceType": .string("6")])) == .file)
        #expect(RecipeSourceValues.sourceType(step("Source", ["SourceType": .string("Desktop")])) == nil)
        // A variable of the same name never changes it (a caller must not turn a screen capture into a file read).
        let invocation = step("Source", ["SourceType": .string("Region")])
        _ = context(["SourceType": .string("File")])
        #expect(RecipeSourceValues.sourceType(invocation) == .region)
        #expect(RecipeSourceValues.SourceType.textOcr.isScreen)
        #expect(!RecipeSourceValues.SourceType.clipboard.isScreen)
    }

    @Test func variableBeatsParameterBeatsSetting() {
        let none = step("Source", [:])
        let given = step("Source", ["CaptureMouseCursor": .bool(false), "DelayMs": .number(250)])
        #expect(RecipeSourceValues.bool(none, "CaptureMouseCursor", variable: "CaptureMouseCursor", in: context(), setting: true))
        #expect(!RecipeSourceValues.bool(given, "CaptureMouseCursor", variable: "CaptureMouseCursor", in: context(), setting: true))
        #expect(RecipeSourceValues.bool(given, "CaptureMouseCursor", variable: "CaptureMouseCursor",
                                        in: context(["CaptureMouseCursor": .bool(true)]), setting: false))
        #expect(RecipeSourceValues.int(none, "DelayMs", variable: "CaptureDelay", in: context(), setting: 100) == 100)
        #expect(RecipeSourceValues.int(given, "DelayMs", variable: "CaptureDelay", in: context(), setting: 100) == 250)
        #expect(RecipeSourceValues.int(given, "DelayMs", variable: "CaptureDelay", in: context(["CaptureDelay": .number(5)]), setting: 100) == 5)
        let sound = step("ImmediateFeedback", ["PlaySound": .bool(false)])
        #expect(RecipeSourceValues.bool(sound, "PlaySound", variable: "PlayShutterSound", in: context(["PlayShutterSound": .bool(true)]),
                                        setting: false))
    }

    @Test func emptyTextIsNotSet() {
        let blank = step("ImmediateFeedback", ["SoundFilePath": .string("  ")])
        #expect(RecipeSourceValues.string(blank, "SoundFilePath", variable: "SoundFilePath", in: context()) == nil)
        let file = step("ImmediateFeedback", ["SoundFilePath": .string("~/click.aiff")])
        #expect(RecipeSourceValues.string(file, "SoundFilePath", variable: "SoundFilePath", in: context()) == "~/click.aiff")
    }

    @Test func screenCaptureModeAllTiers() {
        let none = step("Source", [:])
        #expect(RecipeSourceValues.screenCaptureMode(none, in: context(), setting: .auto) == .auto)
        let fixed = step("Source", ["ScreenCaptureMode": .string("Fixed")])
        #expect(RecipeSourceValues.screenCaptureMode(fixed, in: context(), setting: .auto) == .fixed)
        #expect(RecipeSourceValues.screenCaptureMode(fixed, in: context(["ScreenCaptureMode": .string("FullScreen")]), setting: .auto) == .fullScreen)
        #expect(RecipeSourceValues.screenCaptureMode(.string("1")) == .fullScreen)
        #expect(RecipeSourceValues.screenCaptureMode(.string("Other")) == nil)
    }

    @Test func regionsInBothShapes() {
        let text = RecipeSourceValues.region(.string("10, 20,300,200"))
        #expect(text == CGRect(x: 10, y: 20, width: 300, height: 200))
        let object = RecipeSourceValues.region(.object(["X": .number(-1440), "y": .number(0), "Width": .number(800), "height": .number(600)]))
        #expect(object == CGRect(x: -1440, y: 0, width: 800, height: 600))
        let leftTop = RecipeSourceValues.region(.object(["left": .number(5), "top": .number(6), "width": .number(7), "height": .number(8)]))
        #expect(leftTop == CGRect(x: 5, y: 6, width: 7, height: 8))
        #expect(RecipeSourceValues.region(.string("1,2,3")) == nil)
        #expect(RecipeSourceValues.region(.string("a,b,c,d")) == nil)
        #expect(RecipeSourceValues.region(.string("0,0,0,10")) == nil)
        #expect(RecipeSourceValues.region(nil) == nil)
        #expect(RecipeSourceValues.region(.null) == nil)
    }

    @Test func windowReferences() {
        #expect(RecipeSourceValues.windowReference(.string("4711")) == .id(4711))
        #expect(RecipeSourceValues.windowReference(.number(42)) == .id(42))
        #expect(RecipeSourceValues.windowReference(.string("0x1A")) == .id(26))
        #expect(RecipeSourceValues.windowReference(.string("w7")) == .other(.string("w7")))
        #expect(RecipeSourceValues.windowReference(.number(-3)) == .other(.number(-3)))
        #expect(RecipeSourceValues.windowReference(.string(" ")) == .none)
        #expect(RecipeSourceValues.windowReference(nil) == .none)
    }

    @Test func windowValueForExpressions() {
        let value = RecipeSourceValues.windowValue(id: 9, title: "Mail", app: "Mail", pid: 300, frame: CGRect(x: 1, y: 2, width: 3, height: 4))
        let object = value.objectValue
        #expect(object?.int("Id") == 9)
        #expect(object?.string("Title") == "Mail")
        #expect(object?.int("Pid") == 300)
        #expect(object?.int("Height") == 4)
    }

    @Test func delayIsAtMostAMinute() {
        #expect(RecipeSourceValues.clampedDelay(-5) == 0)
        #expect(RecipeSourceValues.clampedDelay(1500) == 1500)
        #expect(RecipeSourceValues.clampedDelay(600_000) == 60_000)
    }
}
