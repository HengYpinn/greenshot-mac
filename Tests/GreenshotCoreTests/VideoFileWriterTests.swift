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

/// Waits until the file being written plays (its first movie fragment is on the disk), at most 10 s; false when it
/// never did.
private func waitUntilReadable(_ url: URL) async throws -> Bool {
    for _ in 0..<100 {
        if let length = try? await duration(url), length > 0 { return true }
        try await Task.sleep(nanoseconds: 100_000_000)
    }
    return false
}

/// Makes the file at `url` take no more writes, like a full disk or a drive that went away: each descriptor of it
/// open in this process now refers to /dev/null opened for reading, so the writer's next write fails (EBADF). False
/// when this process holds no descriptor of it (the writer writes it some other way).
private func stopWrites(to url: URL) -> Bool {
    guard let resolved = realpath(url.path, nil) else { return false }
    let path = String(cString: resolved)
    free(resolved)
    let readOnly = open("/dev/null", O_RDONLY)
    guard readOnly >= 0 else { return false }
    defer { close(readOnly) }
    var stopped = false
    var buffer = [CChar](repeating: 0, count: Int(MAXPATHLEN))
    for descriptor in 0..<min(getdtablesize(), 65_536) where descriptor != readOnly {
        guard fcntl(descriptor, F_GETPATH, &buffer) != -1 else { continue }
        let openPath = buffer.withUnsafeBufferPointer { String(cString: $0.baseAddress!) }
        if openPath == path, dup2(readOnly, descriptor) != -1 { stopped = true }
    }
    return stopped
}

/// The way a test makes the writer fail did not work on this macOS: there is nothing to check, which is recorded as a
/// known issue (neither a failure nor a pass that proved nothing).
private func failureNotTriggered(_ reason: String) {
    withKnownIssue("The writer could not be made to fail on this macOS") {
        Issue.record("\(reason)")
    }
}

/// Interleaved stereo samples of a 440 Hz tone at 48 kHz.
private func tone(seconds: Double) -> [Float] {
    let frames = Int(seconds * 48_000)
    var samples = [Float](repeating: 0, count: frames * 2)
    for index in 0..<frames {
        let phase = Float(index) * 2 * Float.pi * 440 / 48_000
        samples[index * 2] = sin(phase) * 0.3
        samples[index * 2 + 1] = samples[index * 2]
    }
    return samples
}

/// Where the sound track ends in the video (seconds), nil without one.
private func audioEnd(_ url: URL) async throws -> Double? {
    guard let track = try await AVURLAsset(url: url).loadTracks(withMediaType: .audio).first else { return nil }
    return try await track.load(.timeRange).end.seconds
}

/// A file holding `text` in a new temporary folder.
private func existingFile(_ name: String, holding text: String) throws -> URL {
    let url = temporaryFile(name)
    try FileManager.default.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
    try Data(text.utf8).write(to: url)
    return url
}

/// The hidden files in the folder of `url` (where a replaced file waits).
private func hiddenFiles(next url: URL) throws -> [String] {
    try FileManager.default.contentsOfDirectory(atPath: url.deletingLastPathComponent().path).filter { $0.hasPrefix(".") }
}

/// A folder standing in for the Trash, next to `folder`, so that tests never put anything into the user's Trash.
private func testTrash(next folder: URL) throws -> (folder: URL, discard: @Sendable (URL) throws -> Void) {
    let trash = folder.deletingLastPathComponent().appendingPathComponent(folder.lastPathComponent + "-trash")
    try FileManager.default.createDirectory(at: trash, withIntermediateDirectories: true)
    return (trash, { try FileManager.default.moveItem(at: $0, to: trash.appendingPathComponent($0.lastPathComponent)) })
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

    /// Sound that starts a moment before the first frame: the part from the first frame on is in the video.
    @Test(.enabled(if: VideoEncoderSettings.canEncode(.mp4H264), "no H.264 encoder"))
    func soundFromJustBeforeTheStartIsTrimmed() async throws {
        let url = temporaryFile("early-sound.mp4")
        let video = try writer(url, audio: true)
        appendSecond(video, start: 50)
        // 0.5 s from 49.8: 0.3 s of it after the first frame.
        #expect(video.appendAudio(samples: tone(seconds: 0.5), channels: 2, sampleRate: 48_000, at: seconds(49.8)))
        let result = try await video.finish(at: seconds(51))
        #expect(result.hasAudio)
        let soundEnd = try #require(try await audioEnd(url))
        // AAC adds 2112 frames of priming and pads the last 1024-frame packet; a file whose edit list doesn't hide them
        // ends up to that much later (here it ends at 0.3). Placed whole, not cut, the sound would end at 0.5 or later.
        let aacSlack = Double(2112 + 1024) / 48_000
        #expect(soundEnd > 0.29)
        #expect(soundEnd < 0.31 + aacSlack)
    }

    /// Sound that starts in a pause and goes on after it: the part after the resume is in the video.
    @Test(.enabled(if: VideoEncoderSettings.canEncode(.mp4H264), "no H.264 encoder"))
    func soundFromAPauseIsTrimmed() async throws {
        let url = temporaryFile("pause-sound.mp4")
        let video = try writer(url, audio: true)
        appendSecond(video, start: 10)
        video.pause(at: seconds(11))
        video.resume(at: seconds(12))
        // 0.5 s from 11.7: the part after the resume goes on from 1 s in the video.
        #expect(video.appendAudio(samples: tone(seconds: 0.5), channels: 2, sampleRate: 48_000, at: seconds(11.7)))
        for index in 0..<3 {
            video.appendVideo(frame(width: 320, height: 240, red: 9, green: 9, blue: 9), at: seconds(12 + Double(index) / 30))
        }
        let result = try await video.finish(at: seconds(12.1))
        #expect(result.hasAudio)
        let soundEnd = try #require(try await audioEnd(url))
        #expect(soundEnd > 1.05)
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

    /// The disk fills up or the drive goes away while recording: the failure is told at the next frame, and the file
    /// keeps what was written until then.
    @Test(.enabled(if: VideoEncoderSettings.canEncode(.mp4H264), "no H.264 encoder"))
    func aWriterThatFailsKeepsWhatItWrote() async throws {
        let url = temporaryFile("failed.mp4")
        let video = try VideoFileWriter(.init(url: url, format: .mp4H264, width: 320, height: 240, frameRate: 30,
                                              bitrate: 1_000_000, realTime: false, fragmentInterval: 0.5))
        let failures = Failures()
        video.onFailure = { failures.add($0) }
        for second in 0..<3 { appendSecond(video, start: Double(second)) }
        guard try await waitUntilReadable(url) else {
            video.cancel()
            return failureNotTriggered("no movie fragment was on the disk after 10 s")
        }
        guard stopWrites(to: url) else {
            video.cancel()
            return failureNotTriggered("the writer holds no descriptor of its file in this process")
        }
        var failedAt: Int?
        for index in 0..<300 where failedAt == nil {
            let buffer = frame(width: 320, height: 240, red: 10, green: 200, blue: 10)
            if !video.appendVideo(buffer, at: seconds(3 + Double(index) / 30)) { failedAt = index }
        }
        guard failedAt != nil else {
            video.cancel()
            return failureNotTriggered("the writer wrote nothing in 10 s of frames")
        }
        #expect(failures.count == 1)
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
        let video = try writer(url)
        let failures = Failures()
        video.onFailure = { failures.add($0) }
        // Before anything is on the disk: the writer fails at its first write, with frames but nothing that plays.
        guard stopWrites(to: url) else {
            video.cancel()
            return failureNotTriggered("the writer holds no descriptor of its file in this process")
        }
        var failedAt: Int?
        for index in 0..<300 where failedAt == nil {
            if !video.appendVideo(frame(width: 320, height: 240, red: 1, green: 2, blue: 3), at: seconds(Double(index) / 30)) {
                failedAt = index
            }
        }
        guard let failedAt else {
            video.cancel()
            return failureNotTriggered("the writer wrote nothing in 10 s of frames")
        }
        // This test needs frames in the file and nothing that plays.
        guard failedAt > 0 else {
            video.cancel()
            return failureNotTriggered("the writer failed before its first frame was in")
        }
        #expect(failures.count == 1)
        #expect(!video.appendVideo(frame(width: 320, height: 240, red: 1, green: 2, blue: 3), at: seconds(20)))
        video.checkForFailure()
        #expect(failures.count == 1)
        do {
            _ = try await video.finish(at: seconds(21))
            Issue.record("A failed writer finished")
        } catch let error as VideoWriterError {
            guard case .failed = error else {
                Issue.record("Not deleted: \(error)")
                return
            }
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
        var left = try hiddenFiles(next: url)
        for _ in 0..<50 where !left.isEmpty {
            try await Task.sleep(nanoseconds: 50_000_000)
            left = try hiddenFiles(next: url)
        }
        #expect(left.isEmpty)
    }

    /// The recording to replace a file doesn't start (the screen stream fails, `VideoRecorder.begin` cancels the
    /// writer): the old file is back, nothing is left next to it.
    @Test(.enabled(if: VideoEncoderSettings.canEncode(.mp4H264), "no H.264 encoder"))
    func aRecordingThatDoesNotStartPutsTheOldFileBack() throws {
        let url = try existingFile("back.mp4", holding: "the last recording")
        let video = try VideoFileWriter(.init(url: url, format: .mp4H264, width: 320, height: 240, frameRate: 30,
                                              bitrate: 1_000_000, realTime: false, replacesExistingFile: true))
        video.cancel()
        #expect(try Data(contentsOf: url) == Data("the last recording".utf8))
        #expect(try hiddenFiles(next: url).isEmpty)
    }

    /// A file whose name is near the 255-byte limit can be replaced, and put back: the hidden name it waits under
    /// doesn't grow with it.
    @Test(.enabled(if: VideoEncoderSettings.canEncode(.mp4H264), "no H.264 encoder"))
    func aFileWithALongNameIsReplaced() async throws {
        let name = String(repeating: "a", count: 246) + ".mp4"
        #expect(name.utf8.count == 250)
        let url = try existingFile(name, holding: "the last recording")
        let first = try VideoFileWriter(.init(url: url, format: .mp4H264, width: 320, height: 240, frameRate: 30,
                                              bitrate: 1_000_000, realTime: false, replacesExistingFile: true))
        first.cancel()
        #expect(try Data(contentsOf: url) == Data("the last recording".utf8))
        let second = try VideoFileWriter(.init(url: url, format: .mp4H264, width: 320, height: 240, frameRate: 30,
                                               bitrate: 1_000_000, realTime: false, replacesExistingFile: true))
        appendSecond(second, start: 0)
        _ = try await second.finish(at: seconds(1))
        let info = try #require(try await track(url, .video))
        #expect(info.codec == "avc1")
    }

    /// What a crash before the first frame left behind goes to the Trash a day later (here a folder of the test's own);
    /// nothing else is touched.
    @Test func leftOversOfACrashGoToTheTrash() throws {
        let folder = temporaryFile("left-overs")
        let trash = try testTrash(next: folder)
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        let now = Date()
        let old = VideoFileWriter.replacedFileName(at: now.addingTimeInterval(-2 * 24 * 60 * 60))
        let recent = VideoFileWriter.replacedFileName(at: now.addingTimeInterval(-60 * 60))
        let lookAlike = ".greenshot-replaced-notes.previous"
        let oldFolder = VideoFileWriter.replacedFileName(at: now.addingTimeInterval(-3 * 24 * 60 * 60))
        for name in [old, recent, lookAlike, "video.mp4"] {
            try Data("kept?".utf8).write(to: folder.appendingPathComponent(name))
        }
        try FileManager.default.createDirectory(at: folder.appendingPathComponent(oldFolder), withIntermediateDirectories: true)
        let oldLink = VideoFileWriter.replacedFileName(at: now.addingTimeInterval(-4 * 24 * 60 * 60))
        try FileManager.default.createSymbolicLink(at: folder.appendingPathComponent(oldLink),
                                                   withDestinationURL: folder.appendingPathComponent("video.mp4"))
        VideoFileWriter.discardLeftOverReplacedFiles(in: folder, now: now, discard: trash.discard)
        let left = try Set(FileManager.default.contentsOfDirectory(atPath: folder.path))
        #expect(left == [recent, lookAlike, "video.mp4", oldFolder, oldLink])
        let trashed = try FileManager.default.contentsOfDirectory(atPath: trash.folder.path)
        #expect(trashed == [old])
    }

    /// A left-over that can't go to the Trash stays where it is: it is never deleted.
    @Test func aLeftOverThatCantBeTrashedStays() throws {
        let folder = temporaryFile("left-over-stays")
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        let old = VideoFileWriter.replacedFileName(at: Date().addingTimeInterval(-2 * 24 * 60 * 60))
        try Data("the only copy".utf8).write(to: folder.appendingPathComponent(old))
        VideoFileWriter.discardLeftOverReplacedFiles(in: folder, discard: { _ in throw CocoaError(.featureUnsupported) })
        #expect(try Data(contentsOf: folder.appendingPathComponent(old)) == Data("the only copy".utf8))
    }

    /// A writer starting in a folder sweeps it.
    @Test(.enabled(if: VideoEncoderSettings.canEncode(.mp4H264), "no H.264 encoder"))
    func aWriterTrashesLeftOversWhereItWrites() async throws {
        let url = temporaryFile("sweep.mp4")
        let trash = try testTrash(next: url.deletingLastPathComponent())
        try FileManager.default.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
        let name = VideoFileWriter.replacedFileName(at: Date().addingTimeInterval(-2 * 24 * 60 * 60))
        let old = url.deletingLastPathComponent().appendingPathComponent(name)
        try Data("left over".utf8).write(to: old)
        var configuration = VideoFileWriter.Configuration(url: url, format: .mp4H264, width: 320, height: 240,
                                                          frameRate: 30, bitrate: 1_000_000, realTime: false)
        configuration.discardLeftOver = trash.discard
        let video = try VideoFileWriter(configuration)
        var trashed = false
        for _ in 0..<50 where !trashed {
            try await Task.sleep(nanoseconds: 50_000_000)
            trashed = FileManager.default.fileExists(atPath: trash.folder.appendingPathComponent(name).path)
        }
        video.cancel()
        #expect(trashed)
        #expect(!FileManager.default.fileExists(atPath: old.path))
    }

    /// The old file can't be put back (here the folder became read-only): the recorder is told, and the file waits
    /// under its hidden name, not lost.
    @Test(.enabled(if: VideoEncoderSettings.canEncode(.mp4H264) && getuid() != 0, "no H.264 encoder, or root"))
    func aFailedPutBackIsTold() throws {
        let url = try existingFile("stuck.mp4", holding: "the last recording")
        let folder = url.deletingLastPathComponent()
        let video = try VideoFileWriter(.init(url: url, format: .mp4H264, width: 320, height: 240, frameRate: 30,
                                              bitrate: 1_000_000, realTime: false, replacesExistingFile: true))
        try FileManager.default.setAttributes([.posixPermissions: 0o555], ofItemAtPath: folder.path)
        defer { try? FileManager.default.setAttributes([.posixPermissions: 0o755], ofItemAtPath: folder.path) }
        video.cancel()
        #expect(video.takePutBackFailure() != nil)
        #expect(video.takePutBackFailure() == nil)
        let hidden = try hiddenFiles(next: url)
        #expect(hidden.count == 1)
        if let name = hidden.first {
            #expect(try Data(contentsOf: folder.appendingPathComponent(name)) == Data("the last recording".utf8))
        }
    }

    /// A writer let go without `cancel` or `finish` (no caller does): the old file is back.
    @Test(.enabled(if: VideoEncoderSettings.canEncode(.mp4H264), "no H.264 encoder"))
    func aWriterLetGoPutsTheOldFileBack() throws {
        let url = try existingFile("let-go.mp4", holding: "the last recording")
        _ = try VideoFileWriter(.init(url: url, format: .mp4H264, width: 320, height: 240, frameRate: 30,
                                      bitrate: 1_000_000, realTime: false, replacesExistingFile: true))
        #expect(try Data(contentsOf: url) == Data("the last recording".utf8))
        #expect(try hiddenFiles(next: url).isEmpty)
    }

    /// The recording ends before its first frame: the old file is back.
    @Test(.enabled(if: VideoEncoderSettings.canEncode(.mp4H264), "no H.264 encoder"))
    func aRecordingWithoutFramesPutsTheOldFileBack() async throws {
        let url = try existingFile("no-frames.mp4", holding: "the last recording")
        let video = try VideoFileWriter(.init(url: url, format: .mp4H264, width: 320, height: 240, frameRate: 30,
                                              bitrate: 1_000_000, realTime: false, replacesExistingFile: true))
        await #expect(throws: VideoWriterError.noFrames) {
            _ = try await video.finish(at: seconds(1))
        }
        #expect(try Data(contentsOf: url) == Data("the last recording".utf8))
        #expect(try hiddenFiles(next: url).isEmpty)
    }

    /// With its first frame the recording has started: the old file is gone for good (upstream `FileMode.Create`), also
    /// when the recording is then discarded.
    @Test(.enabled(if: VideoEncoderSettings.canEncode(.mp4H264), "no H.264 encoder"))
    func theOldFileGoesWithTheFirstFrame() async throws {
        let url = try existingFile("started.mp4", holding: "the last recording")
        let video = try VideoFileWriter(.init(url: url, format: .mp4H264, width: 320, height: 240, frameRate: 30,
                                              bitrate: 1_000_000, realTime: false, replacesExistingFile: true))
        video.appendVideo(frame(width: 320, height: 240, red: 1, green: 2, blue: 3), at: seconds(0))
        var left = try hiddenFiles(next: url)
        for _ in 0..<50 where !left.isEmpty {
            try await Task.sleep(nanoseconds: 50_000_000)
            left = try hiddenFiles(next: url)
        }
        #expect(left.isEmpty)
        video.cancel()
        #expect(!FileManager.default.fileExists(atPath: url.path))
    }

    /// A folder with the video's name is not removed: the recording can't start.
    @Test(.enabled(if: VideoEncoderSettings.canEncode(.mp4H264), "no H.264 encoder"))
    func aFolderIsNeverReplaced() throws {
        let url = temporaryFile("folder.mp4")
        let inside = url.appendingPathComponent("keep.txt")
        try FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)
        try Data("kept".utf8).write(to: inside)
        #expect(throws: VideoWriterError.self) {
            _ = try VideoFileWriter(.init(url: url, format: .mp4H264, width: 320, height: 240, frameRate: 30,
                                          bitrate: 1_000_000, realTime: false, replacesExistingFile: true))
        }
        #expect(FileManager.default.fileExists(atPath: inside.path))
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
