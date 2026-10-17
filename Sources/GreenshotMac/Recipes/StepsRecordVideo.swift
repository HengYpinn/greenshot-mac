// Greenshot for Mac (Community) - an unofficial macOS port of Greenshot
// Copyright (C) 2026 Greenshot for Mac (Community) contributors
// Based on Greenshot, Copyright (C) 2007-2026 Thomas Braun, Jens Klingen, Robin Krom
// SPDX-License-Identifier: GPL-3.0-or-later

import AVFoundation
import AppKit
import GreenshotCore

private let log = Log("Recipes")

/// Upstream `RecordVideoRecipeStep` (Greenshot/Recipes/Steps/RecordVideoRecipeStep.cs) on the Mac's recorder
/// (`VideoRecordingController.record`, the menu bar indicator with its Stop): the active window (the one in front when
/// the flow started), a window by `WindowHandle` or by title/process, a region, or a display; the recording's options
/// from the step (`RecipeRecordVideoPlan`). It ends after `DurationSeconds`, when the window closes, or when it is
/// stopped from the menu bar (upstream stops a recording without either right away). `VideoFilePath` and
/// `VideoRecordingResult` go into the flow; the capture is the video's first frame when there was none.
struct RecipeRecordVideoExecutor: RecipeStepExecutor {
    let runtime: RecipeRuntime

    func execute(_ step: RecipeStepInvocation, in context: RecipeFlowContext) async throws {
        let delay = RecipeSourceValues.clampedDelay(step.int("DelayMs") ?? 0)
        if delay > 0 { try await Task.sleep(nanoseconds: UInt64(delay) * 1_000_000) }
        let source = RecipeRecordVideoPlan.source(step, in: context)
        let region = RecipeRecordVideoPlan.region(step, in: context)
        let query = RecipeRecordVideoPlan.windowQuery(step)
        let handle = RecipeSourceValues.windowReference(context[variable: "WindowHandle"])
        let resolver = await MainActor.run { runtime.windowResolver }
        var windowID: CGWindowID?
        switch handle {
        case .id(let id): windowID = id
        case .other(let reference): windowID = resolver?.windowID(for: reference)
        case .none: break
        }
        let recorder = try await Self.start(step, source: source, region: region, query: query, windowID: windowID, context: context,
                                            runtime: runtime)
        let options = await MainActor.run { recorder.options }
        context.log("Recording \(options.target) until \(Self.text(RecipeRecordVideoPlan.ending(of: options))).")
        let result = await withTaskCancellationHandler {
            await recorder.waitUntilFinished()
        } onCancel: {
            Task { @MainActor in await recorder.cancel() }
        }
        try Task.checkCancellation()
        guard let result else {
            throw RecipeStepError("The recording failed or was discarded.", errorType: "InvalidOperationException")
        }
        context[variable: "VideoFilePath"] = .string(result.fileURL.path)
        context[variable: "VideoRecordingResult"] = RecipeRecordVideoPlan.resultValue(result)
        var payload = context.payload
        if payload == nil, let frame = await Self.firstFrame(of: result.fileURL) {
            var made = RecipePayload(image: frame, scale: 1, title: result.fileURL.deletingPathExtension().lastPathComponent)
            made.fileURL = result.fileURL
            made.metadata["source"] = .string("Video")
            payload = made
        }
        if var payload {
            payload.metadata["VideoFilePath"] = .string(result.fileURL.path)
            payload.metadata["VideoRecordingResult"] = RecipeRecordVideoPlan.resultValue(result)
            context.payload = payload
        }
        context.log("Video recording completed: \(result)")
    }

    private static func text(_ ending: RecipeRecordVideoPlan.Ending) -> String {
        switch ending {
        case .after(let seconds): return "\(seconds) s have passed"
        case .whenWindowCloses: return "the window closes"
        case .whenStopped: return "it is stopped from the menu bar"
        }
    }

    @MainActor
    private static func start(_ step: RecipeStepInvocation, source: RecipeRecordVideoPlan.Source, region: CGRect, query: WindowMatchQuery,
                              windowID: CGWindowID?, context: RecipeFlowContext, runtime: RecipeRuntime) async throws -> VideoRecorder {
        guard Permissions.ensureScreenCapture() else {
            throw RecipeStepError("Greenshot may not record the screen.", errorType: "UnauthorizedAccessException")
        }
        let target: VideoCaptureTarget
        let area: CGRect
        var title = "Recording"
        switch source {
        case .region:
            target = .region(region)
            area = region
        case .monitor:
            let screens = NSScreen.screens
            let index = step.int("MonitorIndex") ?? -1
            let screen = screens.indices.contains(index) ? screens[index] : (NSScreen.main ?? screens.first)
            guard let screen else { throw RecipeStepError("There is no display to record.", errorType: "InvalidOperationException") }
            target = .display(screen.displayID)
            area = CGDisplayBounds(screen.displayID)
            title = screen.localizedName
        case .window, .activeWindow:
            let windows = ScreenCapturer.onScreenWindows().filter { $0.level == 0 }
            var window = windowID.flatMap { id in windows.first { $0.id == id } }
            if window == nil, !query.isEmpty {
                let active = windows.first { $0.pid == context.trigger?.frontmostProcessID }
                window = query.firstMatch(in: windows, active: active, title: \.title, names: { [$0.appName] })
                if window == nil { log.warn("No window matches the recipe's window; recording the active one.") }
            }
            if window == nil {
                window = windows.first { $0.pid == context.trigger?.frontmostProcessID } ?? ScreenCapturer.frontWindow(in: windows)
            }
            guard let window else { throw CaptureError.windowNotFound }
            target = .window(window.id)
            area = window.frame
            title = window.displayTitle
        }
        let url = RecordingOutputPath.recipeURL(outputFilePath: step.string("OutputFilePath"), outputDirectory: step.string("OutputDirectory"),
                                                filenamePattern: step.string("FilenamePattern"), date: Date(),
                                                environment: ProcessInfo.processInfo.environment,
                                                homeDirectory: FileManager.default.homeDirectoryForCurrentUser)
        var options = RecipeRecordVideoPlan.options(step, target: target, outputURL: url)
        if options.audioSource.includesMicrophone, !(await MicrophoneCapture.authorize()) {
            // A recipe doesn't ask: without the permission it records without the microphone.
            log.warn("Recording without the microphone: Greenshot may not use it.")
            options.audioSource = options.audioSource == .systemAudioAndMicrophone ? .systemAudio : .none
        }
        if step.bool("ShowCaptureBorder") == true { context.log("ShowCaptureBorder: the Mac shows the recording in the menu bar instead.") }
        log.info("Recipe '\(context.recipe.id)' records \(title)")
        return try await runtime.app.video.record(options, countdown: 0, area: area, deliver: false)
    }

    /// The first frame of the video, for a flow that had no capture.
    private static func firstFrame(of url: URL) async -> CGImage? {
        let generator = AVAssetImageGenerator(asset: AVURLAsset(url: url))
        generator.appliesPreferredTrackTransform = true
        return try? await generator.image(at: .zero).image
    }
}
