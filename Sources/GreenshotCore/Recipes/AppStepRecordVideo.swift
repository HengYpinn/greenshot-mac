// Greenshot for Mac (Community) - an unofficial macOS port of Greenshot
// Copyright (C) 2026 Greenshot for Mac (Community) contributors
// Based on Greenshot, Copyright (C) 2007-2026 Thomas Braun, Jens Klingen, Robin Krom
// SPDX-License-Identifier: GPL-3.0-or-later

import CoreGraphics
import Foundation

/// The RecordVideo step's parameters as a recording (upstream `RecordVideoRecipeStep.BuildOptions`,
/// RecordVideoRecipeStep.cs:212-380). Like upstream, a recipe doesn't read Settings › Video: unset values are the
/// recording's own defaults (30 fps, H.264, the bit rate from the size, the pointer recorded, no sound).
public enum RecipeRecordVideoPlan {
    /// What to record (upstream `SourceType` of the step).
    public enum Source: Equatable, Sendable {
        case activeWindow, window, region, monitor
    }

    /// The parameter, else the variable `SourceType`, else ActiveWindow; Monitor also for FullScreen and Screen.
    public static func source(_ step: RecipeStepInvocation, in context: RecipeFlowContext) -> Source {
        let given = step.isSet("SourceType") ? step.string("SourceType") : context[variable: "SourceType"]?.asString
        switch given?.trimmingCharacters(in: .whitespaces).lowercased() ?? "activewindow" {
        case "window": return .window
        case "region": return .region
        case "monitor", "fullscreen", "screen": return .monitor
        default: return .activeWindow
        }
    }

    /// The region: the variable `CaptureRegion` ("x,y,w,h" or an object), else RegionX/Y/Width/Height (0, 0, 800, 600).
    public static func region(_ step: RecipeStepInvocation, in context: RecipeFlowContext) -> CGRect {
        if let given = RecipeSourceValues.region(context[variable: "CaptureRegion"]) { return given }
        let x = Double(step.int("RegionX") ?? 0)
        let y = Double(step.int("RegionY") ?? 0)
        let width = Double(max(step.int("RegionWidth") ?? 800, 1))
        let height = Double(max(step.int("RegionHeight") ?? 600, 1))
        return CGRect(x: x, y: y, width: width, height: height)
    }

    /// The display to record (Monitor) among `count` displays: `MonitorIndex` when it names one, else the primary
    /// display at `primary` (upstream: `allMonitors[monitorIndex]`, else the one that `IsPrimary`); nil without displays.
    public static func monitorIndex(_ step: RecipeStepInvocation, displays count: Int, primary: Int) -> Int? {
        guard count > 0 else { return nil }
        let index = step.int("MonitorIndex") ?? -1
        if (0..<count).contains(index) { return index }
        return (0..<count).contains(primary) ? primary : 0
    }

    /// The window to look for (Window, ActiveWindow).
    public static func windowQuery(_ step: RecipeStepInvocation) -> WindowMatchQuery {
        func text(_ name: String) -> String? {
            guard let value = step.string(name)?.trimmingCharacters(in: .whitespaces), !value.isEmpty else { return nil }
            return value
        }
        return WindowMatchQuery(title: text("WindowTitle"), titlePattern: text("WindowTitlePattern"),
                                processName: text("ProcessName"), matchCase: step.bool("MatchCase") ?? false)
    }

    /// The options: the preset first, then the single values over it (upstream's order).
    public static func options(_ step: RecipeStepInvocation, target: VideoCaptureTarget, outputURL: URL) -> VideoCaptureOptions {
        var options = VideoCaptureOptions(target: target, outputURL: outputURL)
        // The step names its file (OutputFilePath, OutputDirectory with FilenamePattern, a time stamp): like upstream's
        // `FileMode.Create` (WindowsGraphicsCaptureVideoSession.InitializeTranscoderAsync) a recording replaces a video
        // already there, once it has its first frame (`VideoFileWriter` puts the old one back when it gets none).
        options.replacesExistingFile = true
        if let name = step.string("Preset"), let preset = VideoEncodingPreset(upstreamName: name) { options.apply(preset) }
        if let name = step.string("Format"), let format = VideoFormat(upstreamName: name) { options.format = format }
        if let frameRate = step.int("FrameRate"), frameRate > 0 { options.frameRate = min(frameRate, 240) }
        if let bitrate = step.int("Bitrate"), bitrate > 0 { options.bitrate = bitrate }
        let width = step.int("TargetWidth") ?? 0
        let height = step.int("TargetHeight") ?? 0
        if width > 0, height > 0 { options.maximumSize = CaptureSize(width: width, height: height) }
        if let scale = step.double("ScaleFactor"), scale > 0, scale <= 2 { options.scaleFactor = max(scale, 0.1) }
        if let name = step.string("ColorMode"), let mode = VideoColorMode(upstreamName: name) { options.colorMode = mode }
        options.captureCursor = step.bool("CaptureMouseCursor") ?? true
        // Upstream's Windows capture border; the Mac draws its own frame, left out of the video.
        options.showCaptureBorder = step.bool("ShowCaptureBorder") ?? false
        if let name = step.string("WindowResizeBehavior"), let behavior = WindowResizeBehavior(upstreamName: name) {
            options.windowResizeBehavior = behavior
        }
        if let name = step.string("AudioSource"), let audio = AudioCaptureSource(upstreamName: name) { options.audioSource = audio }
        options.preventSleep = step.bool("PreventSleepWhileRecording") ?? true
        options.autoPauseOnLock = step.bool("AutoPauseOnSessionLock") ?? true
        let duration = max(step.int("DurationSeconds") ?? 0, 0)
        options.maximumDuration = TimeInterval(duration)
        // Upstream: until the window closes by default for a window without a duration.
        options.stopWhenWindowCloses = step.bool("UntilWindowCloses") ?? (target.isWindow && duration == 0)
        return options
    }

    /// How the recording ends: after `DurationSeconds`, when the window closes, or (neither) when it is stopped from the
    /// menu bar. Upstream stops a recording without either at once; the Mac records until it is stopped.
    public enum Ending: Equatable, Sendable {
        case after(seconds: Int)
        case whenWindowCloses
        case whenStopped
    }

    public static func ending(of options: VideoCaptureOptions) -> Ending {
        if options.maximumDuration > 0 { return .after(seconds: Int(options.maximumDuration)) }
        if options.target.isWindow, options.stopWhenWindowCloses { return .whenWindowCloses }
        return .whenStopped
    }

    /// `VideoRecordingResult` for expressions (upstream's property names).
    public static func resultValue(_ result: VideoRecordingResult) -> JSONValue {
        .object(["FilePath": .string(result.fileURL.path), "Duration": .number(result.duration),
                 "FileSizeBytes": .number(Double(result.fileSize)), "Width": .number(Double(result.width)),
                 "Height": .number(Double(result.height)), "FrameRate": .number(Double(result.frameRate)),
                 "Format": .string(result.format.rawValue), "HasAudio": .bool(result.hasAudio)])
    }
}
