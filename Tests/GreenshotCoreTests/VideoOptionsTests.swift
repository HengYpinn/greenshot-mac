// Greenshot for Mac (Community) - an unofficial macOS port of Greenshot
// Copyright (C) 2026 Greenshot for Mac (Community) contributors
// SPDX-License-Identifier: GPL-3.0-or-later

import AVFoundation
import Foundation
import Testing
@testable import GreenshotCore

struct VideoOptionsTests {
    private let file = URL(fileURLWithPath: "/tmp/test.mp4")

    /// Upstream `WindowsGraphicsCaptureVideoTests.VideoCaptureOptions_Presets_ConfigureExpectedValues`, with the sizes of
    /// the presets' documentation.
    @Test func presetsLikeUpstream() {
        var options = VideoCaptureOptions(target: .display(1), outputURL: file)
        options.apply(.smallSize)
        #expect(options.frameRate == 15)
        #expect(options.bitrate == 800_000)
        #expect(options.maximumSize == CaptureSize(width: 1280, height: 720))

        options.apply(.balanced)
        #expect(options.frameRate == 30)
        #expect(options.bitrate == 2_500_000)
        #expect(options.maximumSize == CaptureSize(width: 1920, height: 1080))

        options.apply(.highQuality)
        #expect(options.frameRate == 60)
        #expect(options.bitrate == 8_000_000)
        #expect(options.maximumSize == nil)

        options.apply(.highFrameRateGaming)
        #expect(options.frameRate == 144)
        #expect(options.bitrate == 25_000_000)

        options.apply(.custom)
        #expect(options.frameRate == 144)
    }

    @Test func customPresetTakesTheSettings() {
        var video = VideoSettings()
        video.preset = .custom
        video.frameRate = 500
        video.bitrate = -3
        video.scaleFactor = 0.5
        video.audioSource = .microphone
        video.maximumDurationSeconds = 90
        let options = video.captureOptions(target: .window(7), outputURL: file)
        #expect(options.frameRate == 240)
        #expect(options.bitrate == 0)
        #expect(options.scaleFactor == 0.5)
        #expect(options.maximumSize == nil)
        #expect(options.audioSource == .microphone)
        #expect(options.maximumDuration == 90)
        #expect(options.target == .window(7))
    }

    @Test func presetOverridesTheCustomValues() {
        var video = VideoSettings()
        video.frameRate = 12
        let options = video.captureOptions(target: .display(1), outputURL: file)
        #expect(options.frameRate == 30)
        #expect(options.bitrate == 2_500_000)
    }

    @Test func automaticBitrate() {
        #expect(VideoDimensions.automaticBitrate(width: 1280, height: 720, frameRate: 30) == 1_500_000)
        #expect(VideoDimensions.automaticBitrate(width: 2880, height: 1800, frameRate: 30) == 7_776_000)
        var options = VideoCaptureOptions(target: .display(1), outputURL: file)
        options.bitrate = 4_000_000
        #expect(VideoDimensions.bitrate(options, width: 2880, height: 1800) == 4_000_000)
    }

    @Test func dimensionsScaleAndStayEven() {
        let half = VideoDimensions.size(source: CGSize(width: 2880, height: 1800), maximumSize: nil, scaleFactor: 0.5, format: .mp4H264)
        #expect(half.width == 1440)
        #expect(half.height == 900)
        let odd = VideoDimensions.size(source: CGSize(width: 801, height: 601), maximumSize: nil, scaleFactor: nil, format: .mp4H264)
        #expect(odd.width == 800)
        #expect(odd.height == 600)
        let tiny = VideoDimensions.size(source: CGSize(width: 20, height: 10), maximumSize: nil, scaleFactor: nil, format: .mp4H264)
        #expect(tiny.width == 64)
        #expect(tiny.height == 64)
        let double = VideoDimensions.size(source: CGSize(width: 400, height: 300), maximumSize: nil, scaleFactor: 3, format: .mp4H264)
        #expect(double.width == 800)
    }

    @Test func maximumSizeFitsWithoutEnlarging() {
        let box = CaptureSize(width: 1920, height: 1080)
        let retina = VideoDimensions.size(source: CGSize(width: 2880, height: 1800), maximumSize: box, scaleFactor: 0.5, format: .mp4H264)
        #expect(retina.width == 1728)
        #expect(retina.height == 1080)
        let small = VideoDimensions.size(source: CGSize(width: 1000, height: 500), maximumSize: box, scaleFactor: nil, format: .mp4H264)
        #expect(small.width == 1000)
        #expect(small.height == 500)
    }

    @Test func h264StaysWithinItsLimits() {
        let fiveK = CGSize(width: 5120, height: 2880)
        let h264 = VideoDimensions.size(source: fiveK, maximumSize: nil, scaleFactor: nil, format: .mp4H264)
        #expect(h264.width == 4096)
        #expect(h264.height == 2304)
        let hevc = VideoDimensions.size(source: fiveK, maximumSize: nil, scaleFactor: nil, format: .mp4HEVC)
        #expect(hevc.width == 5120)
        #expect(hevc.height == 2880)
    }

    @Test func encoderSettings() throws {
        let settings = VideoEncoderSettings.video(format: .mp4HEVC, width: 640, height: 480, frameRate: 30, bitrate: 2_000_000)
        let codec = settings[AVVideoCodecKey] as? AVVideoCodecType
        #expect(codec == .hevc)
        let compression = try #require(settings[AVVideoCompressionPropertiesKey] as? [String: Any])
        let bitrate = compression[AVVideoAverageBitRateKey] as? Int
        #expect(bitrate == 2_000_000)
        let keyFrames = compression[AVVideoMaxKeyFrameIntervalKey] as? Int
        #expect(keyFrames == 60)
        #expect(VideoEncoderSettings.codec(.mp4H264) == .h264)
    }

    @Test func texts() {
        #expect(VideoEncodingPreset.balanced.summary == "30 fps, 2.5 Mbps, at most 1920 × 1080")
        #expect(VideoEncodingPreset.smallSize.summary == "15 fps, 800 kbps, at most 1280 × 720")
        #expect(VideoEncodingPreset.highQuality.summary == "60 fps, 8 Mbps")
        #expect(RecordingText.elapsed(5) == "0:05")
        #expect(RecordingText.elapsed(62.9) == "1:02")
        #expect(RecordingText.elapsed(3723) == "1:02:03")
        #expect(VideoCaptureTarget.region(CGRect(x: 10, y: 20, width: 300, height: 200)).description == "Region (300x200 at 10,20)")
    }

    @Test func statesMoveLikeUpstream() {
        #expect(RecordingState.unstarted.canMove(to: .recording))
        #expect(RecordingState.recording.canMove(to: .paused))
        #expect(RecordingState.paused.canMove(to: .recording))
        #expect(!RecordingState.unstarted.canMove(to: .paused))
        #expect(!RecordingState.stopped.canMove(to: .cancelled))
        #expect(!RecordingState.finalizing.canMove(to: .cancelled))
        #expect(RecordingState.finalizing.canMove(to: .stopped))
        #expect(RecordingState.paused.isActive)
        #expect(RecordingState.failed.isFinished)
    }
}
