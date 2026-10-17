// Greenshot for Mac (Community) - an unofficial macOS port of Greenshot
// Copyright (C) 2026 Greenshot for Mac (Community) contributors
// Based on Greenshot, Copyright (C) 2007-2026 Thomas Braun, Jens Klingen, Robin Krom
// SPDX-License-Identifier: GPL-3.0-or-later

import Foundation

// Settings of the screen recordings. Upstream has video only as the recipe step "Record Video"
// (`Greenshot/Recipes/Steps/RecordVideoRecipeStep.cs`) with the options of
// `Greenshot.Base/Interfaces/Video/VideoCaptureOptions.cs`; on the Mac these are the defaults of the menu's
// Record Screen / Window / Region and of Settings › Video. Every type is flat and Codable with upstream's defaults, and
// `VideoSettings` decodes every value on its own, so settings written by another version still load.

/// Container and codec: upstream `VideoFormat.cs`.
public enum VideoFormat: String, Codable, CaseIterable, Sendable {
    /// MP4 with H.264 (AVC) video and AAC audio (upstream `Mp4_H264`, the default).
    case mp4H264
    /// MP4 with H.265 (HEVC) video and AAC audio (upstream `Mp4_HEVC`).
    case mp4HEVC

    /// Upstream's names in recipes, any case: "Mp4_H264", "Mp4_HEVC" (the schema writes "Mp4_Hevc").
    public init?(upstreamName: String) {
        guard let value = Self.upstreamCase(named: upstreamName) else { return nil }
        self = value
    }
}

/// Quality presets: upstream `VideoEncodingPreset.cs`, applied by `VideoCaptureOptions.ApplyPreset`.
public enum VideoEncodingPreset: String, Codable, CaseIterable, Sendable {
    /// 15 fps, 0.8 Mbps, at most 1280 × 720.
    case smallSize
    /// 30 fps, 2.5 Mbps (the default of `docs/recipe.schema.json` "Preset").
    case balanced
    /// 60 fps, 8 Mbps, the recorded size.
    case highQuality
    /// 144 fps (as many as the display shows), 25 Mbps, the recorded size.
    case highFrameRateGaming
    /// The frame rate, bit rate and size of `VideoSettings`.
    case custom

    /// Upstream's names in recipes, any case ("SmallSize", "HighFrameRateGaming", …).
    public init?(upstreamName: String) {
        guard let value = Self.upstreamCase(named: upstreamName) else { return nil }
        self = value
    }
}

/// Upstream `VideoColorMode.cs`.
public enum VideoColorMode: String, Codable, CaseIterable, Sendable {
    case fullColor
    case grayscale

    public init?(upstreamName: String) {
        guard let value = Self.upstreamCase(named: upstreamName) else { return nil }
        self = value
    }
}

/// A recorded window that changes its size: upstream `WindowResizeBehavior.cs`. A video keeps one size, the window's
/// size when the recording started.
public enum WindowResizeBehavior: String, Codable, CaseIterable, Sendable {
    /// The window at its own size, centred, with black bars around it; scaled down only when it got larger (upstream
    /// `LetterboxFixedCanvas`, the default).
    case letterboxFixedCanvas
    /// The window scaled to fill the video, keeping its proportions (upstream `ScaleToFit`).
    case scaleToFit

    /// Only upstream's two real names: the recipe editor's "CropToCanvas" and "ScaleContent" are not values of the enum
    /// and upstream keeps the default for them, so does this.
    public init?(upstreamName: String) {
        guard let value = Self.upstreamCase(named: upstreamName) else { return nil }
        self = value
    }
}

/// The sound recorded with the video: upstream `AudioCaptureSource.cs`.
public enum AudioCaptureSource: String, Codable, CaseIterable, Sendable {
    /// No sound (the default).
    case none
    /// What the Mac plays (upstream's speaker loopback).
    case systemAudio
    /// The microphone (macOS asks for the permission the first time).
    case microphone
    /// Both, mixed into one sound track.
    case systemAudioAndMicrophone

    /// Upstream's names, any case; also "SystemAudioLoopback" of the schema and the recipe editor, which upstream itself
    /// doesn't read (it records no sound then).
    public init?(upstreamName: String) {
        if upstreamName.trimmingCharacters(in: .whitespaces).caseInsensitiveCompare("SystemAudioLoopback") == .orderedSame {
            self = .systemAudio
            return
        }
        guard let value = Self.upstreamCase(named: upstreamName) else { return nil }
        self = value
    }

    public var includesSystemAudio: Bool { self == .systemAudio || self == .systemAudioAndMicrophone }
    public var includesMicrophone: Bool { self == .microphone || self == .systemAudioAndMicrophone }
}

/// What the "Start or stop recording" hotkey records when no recording runs (a Mac addition; upstream has no video
/// hotkey).
public enum RecordingHotkeyTarget: String, Codable, CaseIterable, Sendable {
    /// The capture screen in region mode; Space switches to window mode.
    case region
    /// The capture screen in window mode.
    case window
    /// The display with the mouse pointer.
    case screen
}

/// Where a finished recording goes besides its file in the video folder. The image destinations (editor, clipboard,
/// printer, …) take pictures; these take a file (upstream passes the file on in the recipe, `VideoFilePath`).
public enum VideoDestination: String, Codable, CaseIterable, Sendable {
    /// A menu with the others after every recording, like the screenshots' "Ask every time".
    case picker
    case showInFinder
    /// The default app for MP4 files (QuickTime Player).
    case open
    /// The macOS share menu.
    case share
    /// The file's path to the clipboard.
    case copyPath
}

/// Settings › Video, with upstream's defaults (`VideoCaptureOptions.cs`, `RecordVideoRecipeStep.cs`,
/// `WindowsGraphicsCaptureVideoSession.EnsureOutputFilePath`).
public struct VideoSettings: Codable, Equatable, Sendable {
    /// Upstream `Format`, MP4 with H.264.
    public var format: VideoFormat = .mp4H264
    /// Upstream recipe `Preset`; the schema's default is Balanced.
    public var preset: VideoEncodingPreset = .balanced
    /// Frames per second with the custom preset (upstream `FrameRate`, 30).
    public var frameRate = 30
    /// Bits per second with the custom preset; 0 picks one from the size and frame rate like upstream without a
    /// `Bitrate`: at least 1.5 Mbps, width × height × fps / 20.
    public var bitrate = 0
    /// The size of the video with the custom preset, 0.1–2 times the recorded pixels (upstream `ScaleFactor`).
    public var scaleFactor: Double = 1
    /// With the custom preset: the video fits into this size, keeping its proportions (upstream `TargetSize`); nil keeps
    /// the size from `scaleFactor`.
    public var maximumSize: CaptureSize?
    /// Upstream `ColorMode`, full colour.
    public var colorMode: VideoColorMode = .fullColor
    /// Record the mouse pointer (upstream `CaptureCursor`, true).
    public var captureCursor = true
    /// Upstream `WindowResizeBehavior`, letterbox.
    public var windowResizeBehavior: WindowResizeBehavior = .letterboxFixedCanvas
    /// A window recording ends when the window closes (upstream `UntilWindowCloses`, true for windows).
    public var stopWhenWindowCloses = true
    /// A recording ends by itself after this many seconds; 0 never (upstream `DurationSeconds`, 0).
    public var maximumDurationSeconds = 0
    /// Upstream `AudioSource`, none.
    public var audioSource: AudioCaptureSource = .none
    /// Keep the Mac from going to sleep while recording (upstream `PreventSleepWhileRecording`, true).
    public var preventSleep = true
    /// Pause while the screen is locked and go on after it is unlocked (upstream `AutoPauseOnSessionLock`, true).
    public var autoPauseOnLock = true
    /// Seconds counted down on the screen before the recording starts; 0 starts at once (upstream's recipe has
    /// `DelayMs`, 0, without a countdown).
    public var countdownSeconds = 3
    /// What the "Start or stop recording" hotkey records.
    public var hotkeyTarget: RecordingHotkeyTarget = .region
    /// Upstream records to `Videos\Greenshot`.
    public var outputFolder = "~/Movies/Greenshot"
    /// The file name without ".mp4", with the variables of the file name pattern (upstream
    /// `Greenshot_Recording_{yyyyMMdd_HHmmss}.mp4`).
    public var filenamePattern = "Greenshot_Recording_${capturetime:d\"yyyyMMdd_HHmmss\"}"
    /// Where a finished recording goes besides the folder.
    public var destinations: [VideoDestination] = [.picker]

    public init() {}

    enum CodingKeys: String, CodingKey {
        case format, preset, frameRate, bitrate, scaleFactor, maximumSize, colorMode, captureCursor, windowResizeBehavior
        case stopWhenWindowCloses, maximumDurationSeconds, audioSource, preventSleep, autoPauseOnLock, countdownSeconds
        case hotkeyTarget, outputFolder, filenamePattern, destinations
    }

    /// Every value falls back to its default, so settings written by another version (or an unknown value) still load.
    public init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        let d = VideoSettings()
        func value<T: Decodable>(_ key: CodingKeys, _ fallback: T) -> T {
            (try? c.decodeIfPresent(T.self, forKey: key)) ?? fallback
        }
        format = value(.format, d.format)
        preset = value(.preset, d.preset)
        frameRate = value(.frameRate, d.frameRate)
        bitrate = value(.bitrate, d.bitrate)
        scaleFactor = value(.scaleFactor, d.scaleFactor)
        maximumSize = value(.maximumSize, d.maximumSize)
        colorMode = value(.colorMode, d.colorMode)
        captureCursor = value(.captureCursor, d.captureCursor)
        windowResizeBehavior = value(.windowResizeBehavior, d.windowResizeBehavior)
        stopWhenWindowCloses = value(.stopWhenWindowCloses, d.stopWhenWindowCloses)
        maximumDurationSeconds = value(.maximumDurationSeconds, d.maximumDurationSeconds)
        audioSource = value(.audioSource, d.audioSource)
        preventSleep = value(.preventSleep, d.preventSleep)
        autoPauseOnLock = value(.autoPauseOnLock, d.autoPauseOnLock)
        countdownSeconds = value(.countdownSeconds, d.countdownSeconds)
        hotkeyTarget = value(.hotkeyTarget, d.hotkeyTarget)
        outputFolder = value(.outputFolder, d.outputFolder)
        filenamePattern = value(.filenamePattern, d.filenamePattern)
        destinations = value(.destinations, d.destinations)
    }
}

private extension CaseIterable where Self: RawRepresentable, Self.RawValue == String {
    /// The case whose name is `name` without its underscores, any case: upstream's C# names ("Mp4_HEVC", "FullColor")
    /// are the Swift names with a capital and sometimes "_".
    static func upstreamCase(named name: String) -> Self? {
        let key = name.trimmingCharacters(in: .whitespaces).replacingOccurrences(of: "_", with: "").lowercased()
        guard !key.isEmpty else { return nil }
        return allCases.first { $0.rawValue.lowercased() == key }
    }
}
