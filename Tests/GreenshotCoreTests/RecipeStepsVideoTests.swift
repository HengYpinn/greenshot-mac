// Greenshot for Mac (Community) - an unofficial macOS port of Greenshot
// Copyright (C) 2026 Greenshot for Mac (Community) contributors
// Based on Greenshot, Copyright (C) 2007-2026 Thomas Braun, Jens Klingen, Robin Krom
// SPDX-License-Identifier: GPL-3.0-or-later

import CoreGraphics
import Foundation
import Testing
@testable import GreenshotCore

/// Upstream `RecordVideoRecipeStep.BuildOptions`: the step's parameters as a recording.
@Suite struct RecipeStepsVideoTests {
    let url = URL(fileURLWithPath: "/tmp/recipe-video.mp4")

    func step(_ parameters: JSONObject = [:]) -> RecipeStepInvocation {
        RecipeStepInvocation(node: RecipeNode(id: "record", stepType: WellKnownStepType.recordVideo, parameters: parameters),
                             parameters: parameters, contract: StepContractCatalog.builtIn.contract(for: WellKnownStepType.recordVideo))
    }

    func context(_ variables: [String: JSONValue] = [:]) -> RecipeFlowContext {
        let context = RecipeFlowContext(recipe: CaptureRecipe(id: "video_test", name: "Video Test"), environment: FixedRecipeEnvironment())
        for (name, value) in variables { context[variable: name] = value }
        return context
    }

    @Test func sourceFromParameterThenVariable() {
        #expect(RecipeRecordVideoPlan.source(step(), in: context()) == .activeWindow)
        #expect(RecipeRecordVideoPlan.source(step(), in: context(["SourceType": .string("Region")])) == .region)
        #expect(RecipeRecordVideoPlan.source(step(["SourceType": .string("Monitor")]), in: context(["SourceType": .string("Region")])) == .monitor)
        #expect(RecipeRecordVideoPlan.source(step(["SourceType": .string("window")]), in: context()) == .window)
    }

    @Test func regionFromTheCallerOrTheParameters() {
        #expect(RecipeRecordVideoPlan.region(step(), in: context()) == CGRect(x: 0, y: 0, width: 800, height: 600))
        let given = step(["RegionX": .number(10), "RegionY": .number(20), "RegionWidth": .number(300), "RegionHeight": .number(200)])
        #expect(RecipeRecordVideoPlan.region(given, in: context()) == CGRect(x: 10, y: 20, width: 300, height: 200))
        #expect(RecipeRecordVideoPlan.region(given, in: context(["CaptureRegion": .string("1,2,3,4")])) == CGRect(x: 1, y: 2, width: 3, height: 4))
    }

    @Test func defaultsAreTheRecordingsOwn() {
        let options = RecipeRecordVideoPlan.options(step(), target: .display(1), outputURL: url)
        #expect(options.frameRate == 30)
        #expect(options.bitrate == 0)
        #expect(options.format == .mp4H264)
        #expect(options.captureCursor)
        #expect(options.audioSource == .none)
        #expect(options.preventSleep)
        #expect(options.autoPauseOnLock)
        #expect(options.maximumDuration == 0)
        #expect(!options.stopWhenWindowCloses)
        #expect(RecipeRecordVideoPlan.ending(of: options) == .whenStopped)
    }

    @Test func presetThenSingleValues() {
        let options = RecipeRecordVideoPlan.options(step(["Preset": .string("HighFrameRateGaming"), "FrameRate": .number(24),
                                                          "Format": .string("Mp4_Hevc"), "Bitrate": .number(4_000_000),
                                                          "TargetWidth": .number(1280), "TargetHeight": .number(720),
                                                          "ColorMode": .string("Grayscale"), "AudioSource": .string("SystemAudioLoopback"),
                                                          "CaptureMouseCursor": .bool(false), "ScaleFactor": .number(3)]),
                                                    target: .display(1), outputURL: url)
        #expect(options.frameRate == 24)
        #expect(options.format == .mp4HEVC)
        #expect(options.bitrate == 4_000_000)
        #expect(options.maximumSize == CaptureSize(width: 1280, height: 720))
        #expect(options.colorMode == .grayscale)
        #expect(options.audioSource == .systemAudio)
        #expect(!options.captureCursor)
        // Out of 0 < s <= 2: not taken.
        #expect(options.scaleFactor == nil)
        let scaled = RecipeRecordVideoPlan.options(step(["ScaleFactor": .number(0.5)]), target: .display(1), outputURL: url)
        #expect(scaled.scaleFactor == 0.5)
    }

    @Test func endings() {
        let timed = RecipeRecordVideoPlan.options(step(["DurationSeconds": .number(15)]), target: .window(7), outputURL: url)
        #expect(RecipeRecordVideoPlan.ending(of: timed) == .after(seconds: 15))
        #expect(!timed.stopWhenWindowCloses)
        let window = RecipeRecordVideoPlan.options(step(), target: .window(7), outputURL: url)
        #expect(window.stopWhenWindowCloses)
        #expect(RecipeRecordVideoPlan.ending(of: window) == .whenWindowCloses)
        let kept = RecipeRecordVideoPlan.options(step(["UntilWindowCloses": .bool(false)]), target: .window(7), outputURL: url)
        #expect(RecipeRecordVideoPlan.ending(of: kept) == .whenStopped)
    }

    @Test func windowQuery() {
        let query = RecipeRecordVideoPlan.windowQuery(step(["WindowTitlePattern": .string("^Untitled"), "ProcessName": .string(" TextEdit "),
                                                            "MatchCase": .bool(true)]))
        #expect(query.titlePattern == "^Untitled")
        #expect(query.processName == "TextEdit")
        #expect(query.title == nil)
        #expect(query.matchCase)
        #expect(RecipeRecordVideoPlan.windowQuery(step()).isEmpty)
    }

    @Test func resultForExpressions() {
        let result = VideoRecordingResult(fileURL: url, duration: 12.5, fileSize: 2048, width: 1920, height: 1080, frameRate: 30,
                                          format: .mp4H264, hasAudio: true)
        let value = RecipeRecordVideoPlan.resultValue(result).objectValue
        #expect(value?.string("FilePath") == "/tmp/recipe-video.mp4")
        #expect(value?.double("Duration") == 12.5)
        #expect(value?.int("FileSizeBytes") == 2048)
        #expect(value?.int("Width") == 1920)
        #expect(value?.bool("HasAudio") == true)
    }
}
