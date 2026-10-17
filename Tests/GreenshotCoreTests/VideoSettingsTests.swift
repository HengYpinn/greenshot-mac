// Greenshot for Mac (Community) - an unofficial macOS port of Greenshot
// Copyright (C) 2026 Greenshot for Mac (Community) contributors
// SPDX-License-Identifier: GPL-3.0-or-later

import Foundation
import Testing
@testable import GreenshotCore

struct VideoSettingsTests {
    @Test func defaultsAreUpstreams() {
        let video = VideoSettings()
        #expect(video.format == .mp4H264)
        #expect(video.preset == .balanced)
        #expect(video.frameRate == 30)
        #expect(video.bitrate == 0)
        #expect(video.colorMode == .fullColor)
        #expect(video.captureCursor)
        #expect(video.windowResizeBehavior == .letterboxFixedCanvas)
        #expect(video.audioSource == AudioCaptureSource.none)
        #expect(video.preventSleep)
        #expect(video.autoPauseOnLock)
        #expect(video.stopWhenWindowCloses)
        #expect(video.outputFolder == "~/Movies/Greenshot")
        #expect(video.destinations == [.picker])
    }

    @Test func unknownOrMissingValuesFallBackOneByOne() throws {
        let json = #"{"format":"av1","preset":"smallSize","frameRate":"fast","destinations":["share","fax"],"maximumSize":{"width":1280,"height":720}}"#
        let video = try JSONDecoder().decode(VideoSettings.self, from: Data(json.utf8))
        #expect(video.format == .mp4H264)
        #expect(video.preset == .smallSize)
        #expect(video.frameRate == 30)
        #expect(video.destinations == [.picker])
        #expect(video.maximumSize == CaptureSize(width: 1280, height: 720))
    }

    @Test func roundTrip() throws {
        var video = VideoSettings()
        video.format = .mp4HEVC
        video.audioSource = .systemAudioAndMicrophone
        video.destinations = [.showInFinder, .copyPath]
        let decoded = try JSONDecoder().decode(VideoSettings.self, from: JSONEncoder().encode(video))
        #expect(decoded == video)
    }

    @Test func settingsWithoutVideoOrTheRecordHotkeyLoad() throws {
        let settings = try JSONDecoder().decode(AppSettings.self, from: Data(#"{"jpegQuality":70}"#.utf8))
        #expect(settings.video == VideoSettings())
        #expect(settings.hotkeys.recordVideo == nil)
        #expect(settings.jpegQuality == 70)
    }

    @Test func upstreamNames() {
        #expect(VideoFormat(upstreamName: "Mp4_HEVC") == .mp4HEVC)
        #expect(VideoFormat(upstreamName: "Mp4_Hevc") == .mp4HEVC)
        #expect(VideoFormat(upstreamName: "mp4_h264") == .mp4H264)
        #expect(VideoEncodingPreset(upstreamName: "HighFrameRateGaming") == .highFrameRateGaming)
        #expect(VideoColorMode(upstreamName: "Grayscale") == .grayscale)
        #expect(WindowResizeBehavior(upstreamName: "ScaleToFit") == .scaleToFit)
        // The recipe editor's options that aren't values of upstream's enum.
        #expect(WindowResizeBehavior(upstreamName: "CropToCanvas") == nil)
        #expect(WindowResizeBehavior(upstreamName: "ScaleContent") == nil)
        #expect(AudioCaptureSource(upstreamName: "SystemAudioLoopback") == .systemAudio)
        #expect(AudioCaptureSource(upstreamName: "SystemAudioAndMicrophone") == .systemAudioAndMicrophone)
        #expect(AudioCaptureSource(upstreamName: "") == nil)
    }

    @Test func askEveryTimeExcludesTheOthers() {
        var video = VideoSettings()
        video.setDestination(.showInFinder, on: true)
        #expect(video.destinations == [.showInFinder])
        video.setDestination(.copyPath, on: true)
        #expect(video.destinations == [.showInFinder, .copyPath])
        video.setDestination(.picker, on: true)
        #expect(video.destinations == [.picker])
        video.setDestination(.picker, on: false)
        #expect(video.destinations == [.picker])
    }
}
