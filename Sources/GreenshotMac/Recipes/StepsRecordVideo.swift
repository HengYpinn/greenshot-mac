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
/// from the step (`RecipeRecordVideoPlan`; `ShowCaptureBorder` frames what is recorded, `RecordingBorder`). It ends
/// after `DurationSeconds`, when the window closes, or when it is stopped from the menu bar (upstream stops a recording
/// without either right away). `VideoFilePath` and `VideoRecordingResult` go into the flow; the capture is the video's
/// first frame when there was none.
struct RecipeRecordVideoExecutor: RecipeStepExecutor {
    let runtime: RecipeRuntime

    func execute(_ step: RecipeStepInvocation, in context: RecipeFlowContext) async throws {
        // A run of greenshot-cli asks before it records (SM-M1; RUN_RECIPE asked already when it saw the step).
        if let consent = context.object(forKey: RecipeCaptureConsent.objectKey) as? RecipeCaptureConsent,
           !(await consent.allows("a screen recording")) {
            context.abort("The screen recording wasn't allowed.")
            return
        }
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
        case .other(let reference):
            // Like the Source step: a window the flow named that is gone is an error, not the active window or the screen.
            guard let id = resolver?.windowID(for: reference) else {
                throw RecipeStepError("The window to record (\(reference.interpolationText)) doesn't exist (anymore).",
                                      errorType: "InvalidOperationException")
            }
            windowID = id
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
        guard await Permissions.ensureScreenCapture() else {
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
            // The primary display (with the menu bar), not `NSScreen.main` (the focused window's).
            let displays = Self.displayIDs()
            let primary = displays.firstIndex(of: CGMainDisplayID()) ?? 0
            guard let index = RecipeRecordVideoPlan.monitorIndex(step, displays: displays.count, primary: primary) else {
                throw RecipeStepError("There is no display to record.", errorType: "InvalidOperationException")
            }
            let id = displays[index]
            target = .display(id)
            area = CGDisplayBounds(id)
            title = NSScreen.screens.first { $0.displayID == id }?.localizedName ?? title
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
            if let window {
                target = .window(window.id)
                area = window.frame
                title = window.displayTitle
            } else if windowID == nil {
                // The active app has no window on the screen (the desktop clicked): the screen when the user started it,
                // like the Source step and "Capture active window" (upstream records the window in front, the desktop
                // then); a video shows one display, the primary one, as MonitorIndex does by default. An AI tool, a link
                // or another program's start fails (`ActiveWindowChoice.fallback`); greenshot-cli's run was asked for
                // "a screen recording", which this is.
                let consent = context.object(forKey: RecipeCaptureConsent.objectKey) as? RecipeCaptureConsent
                let marked = context.object(forKey: OverlayInputArming.automationMarkKey) is AutomationStartMark
                switch ActiveWindowChoice.fallback(triggerType: context.trigger?.triggerType, markedByAutomation: marked,
                                                   hasConsent: consent != nil) {
                case .none:
                    throw CaptureError.windowNotFound
                case .askForScreen:
                    guard let consent, await consent.allows("a screen recording") else {
                        throw RecipeStepError("The screen recording wasn't allowed.", errorType: "UnauthorizedAccessException")
                    }
                case .screen:
                    break
                }
                let id = CGMainDisplayID()
                target = .display(id)
                area = CGDisplayBounds(id)
                title = "Screen"
                context.log("The active app has no window on the screen: recording the screen.")
            } else {
                throw CaptureError.windowNotFound
            }
        }
        let url = RecordingOutputPath.recipeURL(outputFilePath: step.string("OutputFilePath"),
                                                rawOutputFilePath: step.node.parameters.string("OutputFilePath"), outputDirectory: step.string("OutputDirectory"),
                                                filenamePattern: step.string("FilenamePattern"), date: Date(),
                                                environment: ProcessInfo.processInfo.environment,
                                                homeDirectory: FileManager.default.homeDirectoryForCurrentUser)
        var options = RecipeRecordVideoPlan.options(step, target: target, outputURL: url)
        if options.audioSource.includesMicrophone, !(await MicrophoneCapture.authorize()) {
            // A recipe doesn't ask: without the permission it records without the microphone.
            log.warn("Recording without the microphone: Greenshot may not use it.")
            options.audioSource = options.audioSource == .systemAudioAndMicrophone ? .systemAudio : .none
        }
        log.info("Recipe '\(context.recipe.id)' records \(title)")
        return try await runtime.app.video.record(options, countdown: 0, area: area, deliver: false)
    }

    /// The displays in the order of `list_windows`' `index` (`AIToolsWindows.displays`), so that an AI tool's
    /// `MonitorIndex` names the display it saw (upstream counts both in `DisplayInfo.AllDisplayInfos`): the active
    /// ones, while they sleep the connected ones.
    private static func displayIDs() -> [CGDirectDisplayID] {
        typealias DisplayList = (UInt32, UnsafeMutablePointer<CGDirectDisplayID>?, UnsafeMutablePointer<UInt32>?) -> CGError
        let lists: [DisplayList] = [CGGetActiveDisplayList, CGGetOnlineDisplayList]
        for list in lists {
            var count: UInt32 = 0
            guard list(0, nil, &count) == .success, count > 0 else { continue }
            var ids = [CGDirectDisplayID](repeating: 0, count: Int(count))
            guard list(count, &ids, &count) == .success else { continue }
            return Array(ids.prefix(Int(count)))
        }
        return []
    }

    /// The first frame of the video, for a flow that had no capture.
    private static func firstFrame(of url: URL) async -> CGImage? {
        let generator = AVAssetImageGenerator(asset: AVURLAsset(url: url))
        generator.appliesPreferredTrackTransform = true
        return try? await generator.image(at: .zero).image
    }
}
