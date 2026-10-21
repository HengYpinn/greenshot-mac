// Greenshot for Mac (Community) - an unofficial macOS port of Greenshot
// Copyright (C) 2026 Greenshot for Mac (Community) contributors
// Based on Greenshot, Copyright (C) 2007-2026 Thomas Braun, Jens Klingen, Robin Krom
// SPDX-License-Identifier: GPL-3.0-or-later

import AVFoundation
import CoreGraphics
import Foundation
import VideoToolbox

/// What a recording records: upstream `Greenshot.Base/Interfaces/Video/VideoCaptureTarget.cs`.
public enum VideoCaptureTarget: Equatable, Sendable, CustomStringConvertible {
    /// A whole display (upstream `FromMonitor`).
    case display(CGDirectDisplayID)
    /// One window, followed when it moves (upstream `FromWindow`).
    case window(CGWindowID)
    /// A fixed area in Quartz global points (upstream `FromRegion`, in virtual screen coordinates).
    case region(CGRect)

    public var isWindow: Bool {
        if case .window = self { return true }
        return false
    }

    public var description: String {
        switch self {
        case .display(let id): return "Display \(id)"
        case .window(let id): return "Window \(id)"
        case .region(let rect):
            return "Region (\(Int(rect.width))x\(Int(rect.height)) at \(Int(rect.minX)),\(Int(rect.minY)))"
        }
    }
}

/// The frame rate, bit rate and largest size of a preset (upstream `VideoCaptureOptions.ApplyPreset`).
public struct VideoPresetValues: Equatable, Sendable {
    public var frameRate: Int
    /// Bits per second.
    public var bitrate: Int
    /// The video fits into this size; nil keeps the recorded size.
    public var maximumSize: CaptureSize?
}

extension VideoEncodingPreset {
    /// The values of the preset; nil for `.custom`. The frame rates and bit rates are upstream's `ApplyPreset`. The
    /// sizes follow the preset's documentation in `VideoEncodingPreset.cs` ("720p maximum resolution", "1080p maximum
    /// resolution", "native resolution"): upstream's code sets 1280 × 720 for SmallSize without scaling to it, and no
    /// size for Balanced.
    public var values: VideoPresetValues? {
        switch self {
        case .smallSize: return VideoPresetValues(frameRate: 15, bitrate: 800_000, maximumSize: CaptureSize(width: 1280, height: 720))
        case .balanced: return VideoPresetValues(frameRate: 30, bitrate: 2_500_000, maximumSize: CaptureSize(width: 1920, height: 1080))
        case .highQuality: return VideoPresetValues(frameRate: 60, bitrate: 8_000_000, maximumSize: nil)
        case .highFrameRateGaming: return VideoPresetValues(frameRate: 144, bitrate: 25_000_000, maximumSize: nil)
        case .custom: return nil
        }
    }

    /// "30 fps, 2.5 Mbps, at most 1920 × 1080" for Settings › Video; empty for `.custom`.
    public var summary: String {
        guard let values else { return "" }
        var parts = [String(localized: "\(values.frameRate) fps"), VideoBitrateText.text(values.bitrate)]
        if let size = values.maximumSize {
            // Pixel sizes as strings: an Int in a localized text gets the locale's grouping ("1,920")
            let width = String(size.width), height = String(size.height)
            parts.append(String(localized: "at most \(width) × \(height)"))
        }
        return parts.joined(separator: ", ")
    }
}

/// "2.5 Mbps", "800 kbps".
public enum VideoBitrateText {
    public static func text(_ bitsPerSecond: Int) -> String {
        if bitsPerSecond < 1_000_000 { return String(localized: "\(bitsPerSecond / 1000) kbps") }
        let megabits = Double(bitsPerSecond) / 1_000_000
        let rounded = (megabits * 10).rounded() / 10
        // Formatted here on purpose ("2.5", "8"): a Double in the localized text would be "%lf" ("2.500000")
        let number = rounded == rounded.rounded() ? "\(Int(rounded))" : "\(rounded)"
        return String(localized: "\(number) Mbps")
    }
}

/// Everything one recording needs: upstream `VideoCaptureOptions.cs`, with the values resolved.
public struct VideoCaptureOptions: Equatable, Sendable {
    public var target: VideoCaptureTarget
    /// The MP4 file to write; an existing file is not overwritten (the recording fails) unless `replacesExistingFile`.
    public var outputURL: URL
    /// An existing file at `outputURL` is replaced by the recording (a recipe's, upstream's `FileMode.Create`); it is put
    /// back when the recording ends before its first frame. Menu recordings get a free name instead
    /// (`RecordingOutputPath.url`).
    public var replacesExistingFile = false
    public var format: VideoFormat = .mp4H264
    /// Upstream `FrameRate`, 30. The display's refresh rate is the most a screen gives.
    public var frameRate = 30
    /// Bits per second; 0 picks one from the size and frame rate (upstream `Bitrate` null).
    public var bitrate = 0
    /// The video fits into this size, keeping its proportions and never getting larger (upstream `TargetSize`).
    public var maximumSize: CaptureSize?
    /// 0.1–2 times the recorded pixels, used without a `maximumSize` (upstream `ScaleFactor`).
    public var scaleFactor: Double?
    public var colorMode: VideoColorMode = .fullColor
    public var captureCursor = true
    /// Greenshot draws a frame around what is recorded, kept out of the video (upstream recipe `ShowCaptureBorder`, the
    /// Windows capture border, default off).
    public var showCaptureBorder = false
    public var windowResizeBehavior: WindowResizeBehavior = .letterboxFixedCanvas
    public var audioSource: AudioCaptureSource = .none
    public var preventSleep = true
    public var autoPauseOnLock = true
    /// A window recording ends when the window closes (upstream `UntilWindowCloses`).
    public var stopWhenWindowCloses = true
    /// Seconds after which the recording ends by itself; 0 never (upstream `DurationSeconds`).
    public var maximumDuration: TimeInterval = 0

    public init(target: VideoCaptureTarget, outputURL: URL) {
        self.target = target
        self.outputURL = outputURL
    }

    /// Upstream `ApplyPreset`: the preset's frame rate, bit rate and size; `.custom` changes nothing.
    public mutating func apply(_ preset: VideoEncodingPreset) {
        guard let values = preset.values else { return }
        frameRate = values.frameRate
        bitrate = values.bitrate
        maximumSize = values.maximumSize
        scaleFactor = nil
    }
}

extension VideoSettings {
    /// The options of a recording of `target` to `outputURL` with these settings.
    public func captureOptions(target: VideoCaptureTarget, outputURL: URL) -> VideoCaptureOptions {
        var options = VideoCaptureOptions(target: target, outputURL: outputURL)
        options.format = format
        if preset == .custom {
            options.frameRate = min(max(frameRate, 1), 240)
            options.bitrate = max(bitrate, 0)
            options.maximumSize = maximumSize.flatMap { $0.width > 0 && $0.height > 0 ? $0 : nil }
            options.scaleFactor = scaleFactor == 1 ? nil : min(max(scaleFactor, 0.1), 2)
        } else {
            options.apply(preset)
        }
        options.colorMode = colorMode
        options.captureCursor = captureCursor
        options.windowResizeBehavior = windowResizeBehavior
        options.audioSource = audioSource
        options.preventSleep = preventSleep
        options.autoPauseOnLock = autoPauseOnLock
        options.stopWhenWindowCloses = stopWhenWindowCloses
        options.maximumDuration = TimeInterval(max(maximumDurationSeconds, 0))
        return options
    }
}

/// The size of the video and its bit rate: upstream `WindowsGraphicsCaptureVideoSession.ComputeFinalDimensions` and
/// `InitializeTranscoderAsync`.
public enum VideoDimensions {
    /// The largest frame VideoToolbox's H.264 encoders take (level 5.2: 4096 × 2304); HEVC goes to 8K.
    static func limits(for format: VideoFormat) -> (side: Double, pixels: Double) {
        switch format {
        case .mp4H264: return (4096, 4096 * 2304)
        case .mp4HEVC: return (8192, 8192 * 4320)
        }
    }

    /// The video's pixel size for `source` pixels: fitted into `maximumSize` (never larger), else times `scaleFactor`
    /// (at most 2), kept within the codec's limits, even (H.264 and HEVC need it) and at least 64 like upstream.
    public static func size(source: CGSize, maximumSize: CaptureSize?, scaleFactor: Double?,
                            format: VideoFormat) -> (width: Int, height: Int) {
        let sourceWidth = Double(max(source.width, 1))
        let sourceHeight = Double(max(source.height, 1))
        var factor: Double = 1
        if let box = maximumSize, box.width > 0, box.height > 0 {
            let horizontal = Double(box.width) / sourceWidth
            let vertical = Double(box.height) / sourceHeight
            factor = min(1, min(horizontal, vertical))
        } else if let scale = scaleFactor, scale > 0 {
            factor = min(scale, 2)
        }
        let limit = limits(for: format)
        let sideFactor = limit.side / (max(sourceWidth, sourceHeight) * factor)
        let pixelFactor = (limit.pixels / (sourceWidth * sourceHeight * factor * factor)).squareRoot()
        factor *= min(1, min(sideFactor, pixelFactor))
        // A hair over, so 1920 × (1080 / 1800) isn't 1079.9999 → 1078.
        let width = Int((sourceWidth * factor + 0.000_001).rounded(.down))
        let height = Int((sourceHeight * factor + 0.000_001).rounded(.down))
        return (max(64, width & ~1), max(64, height & ~1))
    }

    /// Upstream's bit rate without a `Bitrate`: at least 1.5 Mbps, else width × height × fps / 20.
    public static func automaticBitrate(width: Int, height: Int, frameRate: Int) -> Int {
        let pixels = Int64(width) * Int64(height)
        let perSecond: Int64 = pixels * Int64(max(frameRate, 1)) / 20
        let floor: Int64 = 1_500_000
        return Int(max(floor, perSecond))
    }

    /// The bit rate of `options` for a video of this size.
    public static func bitrate(_ options: VideoCaptureOptions, width: Int, height: Int) -> Int {
        options.bitrate > 0 ? options.bitrate : automaticBitrate(width: width, height: height, frameRate: options.frameRate)
    }
}

/// The AVAssetWriter settings of a recording.
public enum VideoEncoderSettings {
    public static func codec(_ format: VideoFormat) -> AVVideoCodecType {
        format == .mp4HEVC ? .hevc : .h264
    }

    /// H.264 High or HEVC Main, the bit rate, the frame rate and a key frame every 2 seconds, tagged as Rec. 709 like the
    /// sRGB frames the stream delivers.
    public static func video(format: VideoFormat, width: Int, height: Int, frameRate: Int, bitrate: Int) -> [String: Any] {
        var compression: [String: Any] = [
            AVVideoAverageBitRateKey: bitrate,
            AVVideoExpectedSourceFrameRateKey: frameRate,
            AVVideoMaxKeyFrameIntervalKey: max(frameRate * 2, 1),
            AVVideoMaxKeyFrameIntervalDurationKey: 2,
            AVVideoAllowFrameReorderingKey: false,
        ]
        compression[AVVideoProfileLevelKey] = format == .mp4HEVC
            ? kVTProfileLevel_HEVC_Main_AutoLevel as String
            : AVVideoProfileLevelH264HighAutoLevel
        return [
            AVVideoCodecKey: codec(format),
            AVVideoWidthKey: width,
            AVVideoHeightKey: height,
            AVVideoCompressionPropertiesKey: compression,
            AVVideoColorPropertiesKey: [
                AVVideoColorPrimariesKey: AVVideoColorPrimaries_ITU_R_709_2,
                AVVideoTransferFunctionKey: AVVideoTransferFunction_ITU_R_709_2,
                AVVideoYCbCrMatrixKey: AVVideoYCbCrMatrix_ITU_R_709_2,
            ],
        ]
    }

    /// The sound: AAC, 48 kHz stereo, 192 kbps (upstream `AudioEncodingProperties.CreateAac(..., 192000)`).
    public static let audioSampleRate: Double = 48_000
    public static let audioChannels = 2

    public static var audio: [String: Any] {
        [AVFormatIDKey: kAudioFormatMPEG4AAC, AVSampleRateKey: audioSampleRate, AVNumberOfChannelsKey: audioChannels,
         AVEncoderBitRateKey: 192_000]
    }

    /// Whether this Mac has an encoder for the format (hardware or software).
    public static func canEncode(_ format: VideoFormat) -> Bool {
        var list: CFArray?
        guard VTCopyVideoEncoderList(nil, &list) == noErr, let encoders = list as? [[String: Any]] else { return false }
        let wanted: CMVideoCodecType = format == .mp4HEVC ? kCMVideoCodecType_HEVC : kCMVideoCodecType_H264
        return encoders.contains { encoder in
            (encoder[kVTVideoEncoderList_CodecType as String] as? NSNumber)?.uint32Value == wanted
        }
    }
}
