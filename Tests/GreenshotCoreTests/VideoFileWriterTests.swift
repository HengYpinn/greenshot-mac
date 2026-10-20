// Greenshot for Mac (Community) - an unofficial macOS port of Greenshot
// Copyright (C) 2026 Greenshot for Mac (Community) contributors
// SPDX-License-Identifier: GPL-3.0-or-later

import AVFoundation
import CoreImage
import CoreVideo
import Foundation
import Testing
@testable import GreenshotCore

/// A BGRA frame of one colour.
private func frame(width: Int, height: Int, red: UInt8, green: UInt8, blue: UInt8) -> CVPixelBuffer {
    var buffer: CVPixelBuffer?
    let attributes = [kCVPixelBufferIOSurfacePropertiesKey as String: [String: Any]()] as CFDictionary
    CVPixelBufferCreate(nil, width, height, kCVPixelFormatType_32BGRA, attributes, &buffer)
    let pixels = buffer!
    CVPixelBufferLockBaseAddress(pixels, [])
    let base = CVPixelBufferGetBaseAddress(pixels)!.assumingMemoryBound(to: UInt8.self)
    let rowBytes = CVPixelBufferGetBytesPerRow(pixels)
    for y in 0..<height {
        for x in 0..<width {
            let offset = y * rowBytes + x * 4
            base[offset] = blue
            base[offset + 1] = green
            base[offset + 2] = red
            base[offset + 3] = 255
        }
    }
    CVPixelBufferUnlockBaseAddress(pixels, [])
    return pixels
}

/// The BGRA pixel at x, y (from the top left) as (r, g, b).
private func pixel(_ buffer: CVPixelBuffer, x: Int, y: Int) -> (r: Int, g: Int, b: Int) {
    CVPixelBufferLockBaseAddress(buffer, .readOnly)
    defer { CVPixelBufferUnlockBaseAddress(buffer, .readOnly) }
    let base = CVPixelBufferGetBaseAddress(buffer)!.assumingMemoryBound(to: UInt8.self)
    let offset = y * CVPixelBufferGetBytesPerRow(buffer) + x * 4
    return (Int(base[offset + 2]), Int(base[offset + 1]), Int(base[offset]))
}

private func seconds(_ value: Double) -> CMTime { CMTime(seconds: value, preferredTimescale: 600) }

private func temporaryFile(_ name: String) -> URL {
    let folder = FileManager.default.temporaryDirectory.appendingPathComponent("greenshot-video-tests-\(UUID().uuidString)")
    return folder.appendingPathComponent(name)
}

/// The track of `type` and its codec as four letters.
private func track(_ url: URL, _ type: AVMediaType) async throws -> (codec: String, size: CGSize)? {
    let asset = AVURLAsset(url: url)
    guard let track = try await asset.loadTracks(withMediaType: type).first else { return nil }
    let descriptions = try await track.load(.formatDescriptions)
    let subtype = descriptions.first.map { CMFormatDescriptionGetMediaSubType($0) } ?? 0
    let bytes: [UInt8] = [24, 16, 8, 0].map { UInt8((subtype >> UInt32($0)) & 0xFF) }
    let size = try await track.load(.naturalSize)
    return (String(decoding: bytes, as: UTF8.self), size)
}

private func duration(_ url: URL) async throws -> Double {
    try await AVURLAsset(url: url).load(.duration).seconds
}

private func writer(_ url: URL, format: VideoFormat = .mp4H264, colorMode: VideoColorMode = .fullColor,
                    audio: Bool = false) throws -> VideoFileWriter {
    try VideoFileWriter(.init(url: url, format: format, width: 320, height: 240, frameRate: 30, bitrate: 1_000_000,
                              colorMode: colorMode, hasAudio: audio, realTime: false))
}

/// An empty frame in `format`.
private func blankFrame(width: Int, height: Int, format: OSType) -> CVPixelBuffer {
    var buffer: CVPixelBuffer?
    let attributes = [kCVPixelBufferIOSurfacePropertiesKey as String: [String: Any]()] as CFDictionary
    CVPixelBufferCreate(nil, width, height, format, attributes, &buffer)
    return buffer!
}

/// Waits until the file being written plays (its first movie fragment is on the disk), at most 5 s.
private func waitUntilReadable(_ url: URL) async throws {
    for _ in 0..<50 {
        if let length = try? await duration(url), length > 0 { return }
        try await Task.sleep(nanoseconds: 100_000_000)
    }
}

/// The errors `VideoFileWriter.onFailure` got.
private final class Failures: @unchecked Sendable {
    private let lock = NSLock()
    private var errors: [Error] = []

    var count: Int {
        lock.lock()
        defer { lock.unlock() }
        return errors.count
    }

    func add(_ error: Error) {
        lock.lock()
        errors.append(error)
        lock.unlock()
    }
}

/// A second of frames, starting at `start` (host clock seconds).
private func appendSecond(_ writer: VideoFileWriter, start: Double, red: UInt8 = 200) {
    for index in 0..<30 {
        let buffer = frame(width: 320, height: 240, red: red, green: 40, blue: UInt8(index * 8))
        writer.appendVideo(buffer, at: seconds(start + Double(index) / 30))
    }
}

struct VideoFrameProcessorTests {
    @Test func aFrameThatNeedsNothingGoesThrough() {
        let processor = VideoFrameProcessor(width: 64, height: 48, colorMode: .fullColor, behavior: .letterboxFixedCanvas)
        let input = frame(width: 64, height: 48, red: 10, green: 20, blue: 30)
        let output = processor.process(input)
        #expect(output === input)
    }

    @Test func grayscaleHasNoColour() throws {
        let processor = VideoFrameProcessor(width: 64, height: 48, colorMode: .grayscale, behavior: .letterboxFixedCanvas)
        let output = try #require(processor.process(frame(width: 64, height: 48, red: 220, green: 30, blue: 90)))
        let value = pixel(output, x: 32, y: 24)
        #expect(abs(value.r - value.g) <= 1)
        #expect(abs(value.g - value.b) <= 1)
        #expect(value.r > 20)
    }

    @Test func aSmallerWindowIsCentredWithBlackBars() throws {
        let processor = VideoFrameProcessor(width: 100, height: 100, colorMode: .fullColor, behavior: .letterboxFixedCanvas)
        let output = try #require(processor.process(frame(width: 50, height: 50, red: 255, green: 255, blue: 255)))
        let corner = pixel(output, x: 5, y: 5)
        let middle = pixel(output, x: 50, y: 50)
        #expect(corner.r < 10)
        #expect(middle.r > 245)
        #expect(CVPixelBufferGetWidth(output) == 100)
    }

    @Test func onlyTheContentRectCounts() throws {
        let processor = VideoFrameProcessor(width: 100, height: 100, colorMode: .fullColor, behavior: .scaleToFit)
        // The picture is the top left quarter; scaled to fit it fills the video.
        let output = try #require(processor.process(frame(width: 100, height: 100, red: 0, green: 255, blue: 0),
                                                    contentRect: CGRect(x: 0, y: 0, width: 50, height: 50)))
        let corner = pixel(output, x: 2, y: 97)
        #expect(corner.g > 245)
    }
}

struct VideoFileWriterTests {
    @Test(.enabled(if: VideoEncoderSettings.canEncode(.mp4H264), "no H.264 encoder"))
    func h264File() async throws {
        let url = temporaryFile("h264.mp4")
        let video = try writer(url)
        appendSecond(video, start: 100)
        let result = try await video.finish(at: seconds(101))
        let info = try #require(try await track(url, .video))
        #expect(info.codec == "avc1")
        #expect(info.size == CGSize(width: 320, height: 240))
        let length = try await duration(url)
        #expect(abs(length - 1) < 0.05)
        #expect(result.width == 320)
        #expect(result.frameRate == 30)
        #expect(result.fileSize > 0)
        #expect(!result.hasAudio)
        #expect(abs(result.duration - 1) < 0.05)
    }

    @Test(.enabled(if: VideoEncoderSettings.canEncode(.mp4HEVC), "no HEVC encoder"))
    func hevcFile() async throws {
        let url = temporaryFile("hevc.mp4")
        let video = try writer(url, format: .mp4HEVC)
        appendSecond(video, start: 0)
        _ = try await video.finish(at: seconds(1))
        let info = try #require(try await track(url, .video))
        #expect(info.codec == "hvc1")
    }

    @Test(.enabled(if: VideoEncoderSettings.canEncode(.mp4H264), "no H.264 encoder"))
    func soundTrack() async throws {
        let url = temporaryFile("sound.mp4")
        let video = try writer(url, audio: true)
        appendSecond(video, start: 50)
        for chunk in 0..<10 {
            var samples = [Float](repeating: 0, count: 4800 * 2)
            for index in 0..<4800 {
                let phase = Float(chunk * 4800 + index) * 2 * Float.pi * 440 / 48_000
                samples[index * 2] = sin(phase) * 0.3
                samples[index * 2 + 1] = samples[index * 2]
            }
            video.appendAudio(samples: samples, channels: 2, sampleRate: 48_000, at: seconds(50 + Double(chunk) / 10))
        }
        let result = try await video.finish(at: seconds(51))
        #expect(result.hasAudio)
        let info = try #require(try await track(url, .audio))
        #expect(info.codec == "aac ")
    }

    /// Sound was asked for but none came (nothing played): the video is still written, without sound.
    @Test(.enabled(if: VideoEncoderSettings.canEncode(.mp4H264), "no H.264 encoder"))
    func silenceStillGivesAVideo() async throws {
        let url = temporaryFile("silent.mp4")
        let video = try writer(url, audio: true)
        appendSecond(video, start: 5)
        let result = try await video.finish(at: seconds(6))
        #expect(!result.hasAudio)
        #expect(FileManager.default.fileExists(atPath: url.path))
    }

    @Test(.enabled(if: VideoEncoderSettings.canEncode(.mp4H264), "no H.264 encoder"))
    func pausesAreCutOut() async throws {
        let url = temporaryFile("pause.mp4")
        let video = try writer(url)
        appendSecond(video, start: 10)
        video.pause(at: seconds(11))
        // Frames while paused are left out.
        appendSecond(video, start: 11)
        video.resume(at: seconds(14))
        appendSecond(video, start: 14)
        let result = try await video.finish(at: seconds(15))
        let length = try await duration(url)
        #expect(abs(length - 2) < 0.05)
        #expect(abs(result.duration - 2) < 0.05)
    }

    @Test(.enabled(if: VideoEncoderSettings.canEncode(.mp4H264), "no H.264 encoder"))
    func aStillScreenLastsUntilTheStop() async throws {
        let url = temporaryFile("still.mp4")
        let video = try writer(url)
        video.appendVideo(frame(width: 320, height: 240, red: 1, green: 2, blue: 3), at: seconds(20))
        let result = try await video.finish(at: seconds(22))
        let length = try await duration(url)
        #expect(abs(length - 2) < 0.05)
        #expect(abs(result.duration - 2) < 0.05)
    }

    @Test(.enabled(if: VideoEncoderSettings.canEncode(.mp4H264), "no H.264 encoder"))
    func grayscaleFile() async throws {
        let url = temporaryFile("gray.mp4")
        let video = try writer(url, colorMode: .grayscale)
        appendSecond(video, start: 0)
        _ = try await video.finish(at: seconds(1))
        let generator = AVAssetImageGenerator(asset: AVURLAsset(url: url))
        generator.requestedTimeToleranceBefore = .zero
        generator.requestedTimeToleranceAfter = .zero
        let image = try await generator.image(at: seconds(0.5)).image
        let data = try #require(image.dataProvider?.data as Data?)
        let bytesPerPixel = image.bitsPerPixel / 8
        let middle = (image.height / 2) * image.bytesPerRow + (image.width / 2) * bytesPerPixel
        let first = Int(data[middle])
        let second = Int(data[middle + 1])
        let third = Int(data[middle + 2])
        #expect(abs(first - second) <= 3)
        #expect(abs(second - third) <= 3)
    }

    /// A crash or power loss while recording: the file as it is on the disk then plays up to the last movie fragment.
    @Test(.enabled(if: VideoEncoderSettings.canEncode(.mp4H264), "no H.264 encoder"))
    func anAbandonedFileStaysReadable() async throws {
        let url = temporaryFile("crash.mp4")
        let video = try VideoFileWriter(.init(url: url, format: .mp4H264, width: 320, height: 240, frameRate: 30,
                                              bitrate: 1_000_000, realTime: false, fragmentInterval: 0.5))
        for second in 0..<3 { appendSecond(video, start: Double(second)) }
        // What the disk holds at the "crash", once the encoder caught up; the writer never finishes it.
        let copy = url.deletingLastPathComponent().appendingPathComponent("copy.mp4")
        var length: Double = 0
        for _ in 0..<50 where length <= 0 {
            try await Task.sleep(nanoseconds: 100_000_000)
            try? FileManager.default.removeItem(at: copy)
            try FileManager.default.copyItem(at: url, to: copy)
            length = (try? await duration(copy)) ?? 0
        }
        video.cancel()
        #expect(length > 0.4)
        let info = try #require(try await track(copy, .video))
        #expect(info.codec == "avc1")
    }

    /// With fragments written on the way, a finished recording is still a complete video.
    @Test(.enabled(if: VideoEncoderSettings.canEncode(.mp4H264), "no H.264 encoder"))
    func aFragmentedFileFinishesNormally() async throws {
        let url = temporaryFile("fragments.mp4")
        let video = try VideoFileWriter(.init(url: url, format: .mp4H264, width: 320, height: 240, frameRate: 30,
                                              bitrate: 1_000_000, realTime: false, fragmentInterval: 0.5))
        for second in 0..<3 { appendSecond(video, start: Double(second)) }
        let result = try await video.finish(at: seconds(3))
        let length = try await duration(url)
        #expect(abs(length - 3) < 0.05)
        #expect(abs(result.duration - 3) < 0.05)
    }

    /// The disk fills up or the encoder fails while recording: the file keeps what was written until then.
    @Test(.enabled(if: VideoEncoderSettings.canEncode(.mp4H264), "no H.264 encoder"))
    func aWriterThatFailsKeepsWhatItWrote() async throws {
        let url = temporaryFile("failed.mp4")
        let video = try VideoFileWriter(.init(url: url, format: .mp4H264, width: 320, height: 240, frameRate: 30,
                                              bitrate: 1_000_000, realTime: false, fragmentInterval: 0.5))
        for second in 0..<3 { appendSecond(video, start: Double(second)) }
        try await waitUntilReadable(url)
        // The H.264 encoder can't take a depth map: the writer fails a few frames later.
        video.appendVideo(blankFrame(width: 320, height: 240, format: kCVPixelFormatType_DepthFloat32), at: seconds(3))
        var failedAt: Int?
        for index in 1..<120 where failedAt == nil {
            let buffer = frame(width: 320, height: 240, red: 10, green: 200, blue: 10)
            if !video.appendVideo(buffer, at: seconds(3 + Double(index) / 30)) { failedAt = index }
        }
        #expect(failedAt != nil)
        do {
            _ = try await video.finish(at: seconds(8))
            Issue.record("A failed writer finished")
        } catch let error as VideoWriterError {
            guard case .incomplete(_, let kept) = error else {
                Issue.record("Not kept: \(error)")
                return
            }
            #expect(kept == url)
        }
        #expect(FileManager.default.fileExists(atPath: url.path))
        let length = try await duration(url)
        #expect(length > 0.4)
        let info = try #require(try await track(url, .video))
        #expect(info.codec == "avc1")
    }

    /// The failure is told once, when a sample finds it; a file with nothing that plays yet is deleted.
    @Test(.enabled(if: VideoEncoderSettings.canEncode(.mp4H264), "no H.264 encoder"))
    func aFailureIsToldOnce() async throws {
        let url = temporaryFile("failed-early.mp4")
        let video = try writer(url, audio: true)
        let failures = Failures()
        video.onFailure = { failures.add($0) }
        appendSecond(video, start: 0)
        #expect(failures.count == 0)
        // The AAC encoder can't take sound at 1 Hz: the writer fails at once.
        let sound = [Float](repeating: 0, count: 200)
        #expect(!video.appendAudio(samples: sound, channels: 2, sampleRate: 1, at: seconds(0.5)))
        #expect(failures.count == 1)
        #expect(!video.appendVideo(frame(width: 320, height: 240, red: 1, green: 2, blue: 3), at: seconds(1.5)))
        video.checkForFailure()
        #expect(failures.count == 1)
        await #expect(throws: VideoWriterError.self) {
            _ = try await video.finish(at: seconds(2))
        }
        #expect(!FileManager.default.fileExists(atPath: url.path))
    }

    /// A recipe's fixed path records again over the last recording (upstream `FileMode.Create`).
    @Test(.enabled(if: VideoEncoderSettings.canEncode(.mp4H264), "no H.264 encoder"))
    func aRecipeRecordsOverItsLastFile() async throws {
        let url = temporaryFile("again.mp4")
        try FileManager.default.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
        try Data("the last recording".utf8).write(to: url)
        let video = try VideoFileWriter(.init(url: url, format: .mp4H264, width: 320, height: 240, frameRate: 30,
                                              bitrate: 1_000_000, realTime: false, replacesExistingFile: true))
        appendSecond(video, start: 0)
        _ = try await video.finish(at: seconds(1))
        let info = try #require(try await track(url, .video))
        #expect(info.codec == "avc1")
    }

    /// Without it (a menu recording, which picks a free name) an existing file is never touched.
    @Test(.enabled(if: VideoEncoderSettings.canEncode(.mp4H264), "no H.264 encoder"))
    func anExistingFileIsKeptOtherwise() throws {
        let url = temporaryFile("taken.mp4")
        try FileManager.default.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
        try Data("someone's file".utf8).write(to: url)
        #expect(throws: VideoWriterError.self) {
            _ = try writer(url)
        }
        #expect(try Data(contentsOf: url) == Data("someone's file".utf8))
    }

    @Test(.enabled(if: VideoEncoderSettings.canEncode(.mp4H264), "no H.264 encoder"))
    func cancelDeletesTheFile() throws {
        let url = temporaryFile("cancel.mp4")
        let video = try writer(url)
        appendSecond(video, start: 0)
        video.cancel()
        #expect(!FileManager.default.fileExists(atPath: url.path))
    }

    @Test(.enabled(if: VideoEncoderSettings.canEncode(.mp4H264), "no H.264 encoder"))
    func noFramesNoFile() async throws {
        let url = temporaryFile("empty.mp4")
        let video = try writer(url)
        await #expect(throws: VideoWriterError.noFrames) {
            _ = try await video.finish(at: seconds(1))
        }
        #expect(!FileManager.default.fileExists(atPath: url.path))
    }
}

struct RecordingAudioConverterTests {
    @Test func monoBecomesStereoAt48kHz() throws {
        let converter = RecordingAudioConverter()
        let format = try #require(AVAudioFormat(commonFormat: .pcmFormatFloat32, sampleRate: 44_100, channels: 1, interleaved: false))
        let input = try #require(AVAudioPCMBuffer(pcmFormat: format, frameCapacity: 4410))
        input.frameLength = 4410
        let channel = try #require(input.floatChannelData?[0])
        for index in 0..<4410 { channel[index] = 0.5 }
        let output = try #require(converter.convert(input))
        // The converter holds a few frames back for the next chunk.
        let frames = output.count / 2
        #expect(frames > 4000)
        #expect(frames <= 4800)
        let left = output[2000]
        let right = output[2001]
        #expect(abs(left - right) < 0.0001)
        #expect(abs(left - 0.5) < 0.05)
    }
}
