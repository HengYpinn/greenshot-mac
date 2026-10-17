// Greenshot for Mac (Community) - an unofficial macOS port of Greenshot
// Copyright (C) 2026 Greenshot for Mac (Community) contributors
// Based on Greenshot, Copyright (C) 2007-2026 Thomas Braun, Jens Klingen, Robin Krom
// SPDX-License-Identifier: GPL-3.0-or-later

import AVFoundation
import CoreMedia
import CoreVideo
import Foundation

private let log = Log("Video")

public enum VideoWriterError: LocalizedError, Equatable {
    case cannotAddInput
    case cannotStart(String)
    /// The recording ended before the screen sent a picture.
    case noFrames
    case failed(String)

    public var errorDescription: String? {
        switch self {
        case .cannotAddInput: return "The video file could not be set up."
        case .cannotStart(let reason): return "The video file could not be written: \(reason)"
        case .noFrames: return "The recording ended before anything was recorded."
        case .failed(let reason): return "The video file could not be finished: \(reason)"
        }
    }
}

/// Writes a recording's MP4: the frames (through `VideoFrameProcessor`) and the sound, with pauses taken out
/// (`RecordingTimeline`). The port of upstream `WindowsGraphicsCaptureVideoSession`'s transcoder part, with
/// AVAssetWriter in place of Media Foundation. Thread-safe; the screen and the sound may come on different queues.
public final class VideoFileWriter: @unchecked Sendable {
    public struct Configuration: Sendable {
        public var url: URL
        public var format: VideoFormat
        public var width: Int
        public var height: Int
        public var frameRate: Int
        /// Bits per second.
        public var bitrate: Int
        public var colorMode: VideoColorMode
        public var resizeBehavior: WindowResizeBehavior
        /// The file gets a sound track (AAC).
        public var hasAudio: Bool
        /// Live recording: a frame the encoder has no room for is dropped. Off (tests, files): appending waits.
        public var realTime: Bool

        public init(url: URL, format: VideoFormat, width: Int, height: Int, frameRate: Int, bitrate: Int,
                    colorMode: VideoColorMode = .fullColor, resizeBehavior: WindowResizeBehavior = .letterboxFixedCanvas,
                    hasAudio: Bool = false, realTime: Bool = true) {
            self.url = url
            self.format = format
            self.width = width
            self.height = height
            self.frameRate = frameRate
            self.bitrate = bitrate
            self.colorMode = colorMode
            self.resizeBehavior = resizeBehavior
            self.hasAudio = hasAudio
            self.realTime = realTime
        }
    }

    public let configuration: Configuration
    private let lock = NSLock()
    private let writer: AVAssetWriter
    private let videoInput: AVAssetWriterInput
    private let adaptor: AVAssetWriterInputPixelBufferAdaptor
    private let audioInput: AVAssetWriterInput?
    private let processor: VideoFrameProcessor
    private var timeline = RecordingTimeline()
    private var lastVideoTime: CMTime?
    private var lastAudioTime: CMTime?
    private var lastFrame: CVPixelBuffer?
    private var audioWritten = false
    private var done = false
    /// Frames the encoder had no room for.
    public private(set) var droppedFrames = 0

    public init(_ configuration: Configuration) throws {
        self.configuration = configuration
        let folder = configuration.url.deletingLastPathComponent()
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        writer = try AVAssetWriter(outputURL: configuration.url, fileType: .mp4)
        let settings = VideoEncoderSettings.video(format: configuration.format, width: configuration.width,
                                                  height: configuration.height, frameRate: configuration.frameRate,
                                                  bitrate: configuration.bitrate)
        videoInput = AVAssetWriterInput(mediaType: .video, outputSettings: settings)
        videoInput.expectsMediaDataInRealTime = configuration.realTime
        let attributes: [String: Any] = [
            kCVPixelBufferPixelFormatTypeKey as String: kCVPixelFormatType_32BGRA,
            kCVPixelBufferWidthKey as String: configuration.width,
            kCVPixelBufferHeightKey as String: configuration.height,
        ]
        adaptor = AVAssetWriterInputPixelBufferAdaptor(assetWriterInput: videoInput, sourcePixelBufferAttributes: attributes)
        guard writer.canAdd(videoInput) else { throw VideoWriterError.cannotAddInput }
        writer.add(videoInput)
        if configuration.hasAudio {
            let input = AVAssetWriterInput(mediaType: .audio, outputSettings: VideoEncoderSettings.audio)
            input.expectsMediaDataInRealTime = configuration.realTime
            guard writer.canAdd(input) else { throw VideoWriterError.cannotAddInput }
            writer.add(input)
            audioInput = input
        } else {
            audioInput = nil
        }
        processor = VideoFrameProcessor(width: configuration.width, height: configuration.height,
                                        colorMode: configuration.colorMode, behavior: configuration.resizeBehavior)
        guard writer.startWriting() else {
            throw VideoWriterError.cannotStart(writer.error?.localizedDescription ?? "unknown")
        }
    }

    /// A frame arrived (or the first one did).
    public var hasFrames: Bool {
        lock.lock()
        defer { lock.unlock() }
        return lastVideoTime != nil
    }

    // MARK: Samples

    /// Adds a frame of the screen taken at `time` (the host clock). `contentRect` as in `VideoFrameProcessor.process`.
    /// False when it isn't in the video (before the start, paused, the encoder full).
    @discardableResult
    public func appendVideo(_ buffer: CVPixelBuffer, contentRect: CGRect? = nil, at time: CMTime) -> Bool {
        lock.lock()
        defer { lock.unlock() }
        guard !done, writer.status == .writing else { return false }
        if timeline.start == nil {
            guard !timeline.isPaused else { return false }
            timeline.begin(at: time)
            writer.startSession(atSourceTime: .zero)
        }
        guard let output = timeline.outputTime(for: time) else { return false }
        if let last = lastVideoTime, CMTimeCompare(output, last) <= 0 { return false }
        guard let frame = processor.process(buffer, contentRect: contentRect, pool: adaptor.pixelBufferPool) else {
            return false
        }
        guard ready(videoInput) else {
            droppedFrames += 1
            return false
        }
        guard adaptor.append(frame, withPresentationTime: output) else {
            log.warn("A frame could not be added to the video", error: writer.error)
            return false
        }
        lastVideoTime = output
        lastFrame = frame
        return true
    }

    /// Adds sound taken at its presentation time (the host clock); sound before the first frame is left out.
    @discardableResult
    public func appendAudio(_ sampleBuffer: CMSampleBuffer) -> Bool {
        lock.lock()
        defer { lock.unlock() }
        guard !done, let audioInput, writer.status == .writing, timeline.start != nil else { return false }
        let time = CMSampleBufferGetPresentationTimeStamp(sampleBuffer)
        guard let output = timeline.outputTime(for: time) else { return false }
        if let last = lastAudioTime, CMTimeCompare(output, last) <= 0 { return false }
        guard let moved = Self.retimed(sampleBuffer, to: output), ready(audioInput) else { return false }
        guard audioInput.append(moved) else {
            log.warn("Sound could not be added to the video", error: writer.error)
            return false
        }
        lastAudioTime = output
        audioWritten = true
        return true
    }

    /// Adds interleaved float samples taken at `time` (the mixed sound of `RecordingAudioMixer`).
    @discardableResult
    public func appendAudio(samples: [Float], channels: Int, sampleRate: Double, at time: CMTime) -> Bool {
        guard let buffer = Self.audioBuffer(samples: samples, channels: channels, sampleRate: sampleRate, at: time) else {
            return false
        }
        return appendAudio(buffer)
    }

    // MARK: Pause, stop

    /// Leaves out what comes from `time` on, until `resume` (host clock).
    public func pause(at time: CMTime) {
        lock.lock()
        timeline.pause(at: time)
        lock.unlock()
    }

    public func resume(at time: CMTime) {
        lock.lock()
        timeline.resume(at: time)
        lock.unlock()
    }

    /// The recorded time at `now` (host clock), without the pauses.
    public func duration(at now: CMTime) -> TimeInterval {
        lock.lock()
        defer { lock.unlock() }
        return timeline.duration(at: now).seconds
    }

    /// Finishes the file with the recording ending at `end` (host clock). The last frame is shown until then: the screen
    /// sends frames only when something changes, and a still screen would otherwise end the video early.
    public func finish(at end: CMTime) async throws -> VideoRecordingResult {
        let endTime = try endSession(at: end)
        await writer.finishWriting()
        guard writer.status == .completed else {
            throw VideoWriterError.failed(writer.error?.localizedDescription ?? "unknown")
        }
        let attributes = try? FileManager.default.attributesOfItem(atPath: configuration.url.path)
        let size = (attributes?[.size] as? NSNumber)?.int64Value ?? 0
        return VideoRecordingResult(fileURL: configuration.url, duration: endTime.seconds, fileSize: size,
                                    width: configuration.width, height: configuration.height,
                                    frameRate: configuration.frameRate, format: configuration.format,
                                    hasAudio: audioWritten)
    }

    /// Marks the inputs finished and ends the session; the time the video ends.
    private func endSession(at end: CMTime) throws -> CMTime {
        lock.lock()
        defer { lock.unlock() }
        guard !done else { throw VideoWriterError.failed("The recording was already finished.") }
        done = true
        guard let lastVideoTime, writer.status == .writing else {
            let failed = writer.status == .failed
            let reason = writer.error?.localizedDescription ?? "unknown"
            writer.cancelWriting()
            try? FileManager.default.removeItem(at: configuration.url)
            if failed { throw VideoWriterError.failed(reason) }
            throw VideoWriterError.noFrames
        }
        let frameDuration = CMTime(value: 1, timescale: CMTimeScale(max(configuration.frameRate, 1)))
        var finalTime = CMTimeMaximum(timeline.duration(at: end), CMTimeAdd(lastVideoTime, frameDuration))
        if let lastAudioTime { finalTime = CMTimeMaximum(finalTime, lastAudioTime) }
        let repeatTime = CMTimeSubtract(finalTime, frameDuration)
        if let lastFrame, CMTimeCompare(repeatTime, lastVideoTime) > 0, ready(videoInput) {
            adaptor.append(lastFrame, withPresentationTime: repeatTime)
        }
        videoInput.markAsFinished()
        audioInput?.markAsFinished()
        writer.endSession(atSourceTime: finalTime)
        return finalTime
    }

    /// Stops and deletes the file (upstream `CancelAsync`).
    public func cancel() {
        lock.lock()
        defer { lock.unlock() }
        guard !done else { return }
        done = true
        writer.cancelWriting()
        try? FileManager.default.removeItem(at: configuration.url)
    }

    // MARK: Helpers

    /// Live: whether the input takes more now. Otherwise waits for it (at most 10 s).
    private func ready(_ input: AVAssetWriterInput) -> Bool {
        if configuration.realTime || input.isReadyForMoreMediaData { return input.isReadyForMoreMediaData }
        let deadline = Date().addingTimeInterval(10)
        while !input.isReadyForMoreMediaData && writer.status == .writing && Date() < deadline {
            Thread.sleep(forTimeInterval: 0.002)
        }
        return input.isReadyForMoreMediaData
    }

    /// The same sound at another time.
    static func retimed(_ buffer: CMSampleBuffer, to time: CMTime) -> CMSampleBuffer? {
        var count: CMItemCount = 0
        CMSampleBufferGetSampleTimingInfoArray(buffer, entryCount: 0, arrayToFill: nil, entriesNeededOut: &count)
        var timing = [CMSampleTimingInfo](repeating: CMSampleTimingInfo(), count: max(count, 1))
        if count > 0 {
            CMSampleBufferGetSampleTimingInfoArray(buffer, entryCount: count, arrayToFill: &timing, entriesNeededOut: &count)
        }
        let original = CMSampleBufferGetPresentationTimeStamp(buffer)
        for index in timing.indices {
            let offset = timing[index].presentationTimeStamp.isNumeric
                ? CMTimeSubtract(timing[index].presentationTimeStamp, original) : .zero
            timing[index].presentationTimeStamp = CMTimeAdd(time, offset)
            timing[index].decodeTimeStamp = .invalid
        }
        var moved: CMSampleBuffer?
        let status = CMSampleBufferCreateCopyWithNewTiming(allocator: nil, sampleBuffer: buffer, sampleTimingEntryCount: timing.count,
                                                           sampleTimingArray: &timing, sampleBufferOut: &moved)
        return status == noErr ? moved : nil
    }

    /// Interleaved 32-bit float samples as a sample buffer at `time`.
    public static func audioBuffer(samples: [Float], channels: Int, sampleRate: Double, at time: CMTime) -> CMSampleBuffer? {
        guard channels > 0, !samples.isEmpty else { return nil }
        let frames = samples.count / channels
        guard frames > 0 else { return nil }
        let bytesPerFrame = UInt32(channels * MemoryLayout<Float>.size)
        var description = AudioStreamBasicDescription(
            mSampleRate: sampleRate, mFormatID: kAudioFormatLinearPCM,
            mFormatFlags: kAudioFormatFlagIsFloat | kAudioFormatFlagIsPacked,
            mBytesPerPacket: bytesPerFrame, mFramesPerPacket: 1, mBytesPerFrame: bytesPerFrame,
            mChannelsPerFrame: UInt32(channels), mBitsPerChannel: 32, mReserved: 0)
        var format: CMAudioFormatDescription?
        guard CMAudioFormatDescriptionCreate(allocator: nil, asbd: &description, layoutSize: 0, layout: nil,
                                             magicCookieSize: 0, magicCookie: nil, extensions: nil,
                                             formatDescriptionOut: &format) == noErr, let format else { return nil }
        let byteCount = frames * channels * MemoryLayout<Float>.size
        var block: CMBlockBuffer?
        guard CMBlockBufferCreateWithMemoryBlock(allocator: nil, memoryBlock: nil, blockLength: byteCount,
                                                 blockAllocator: nil, customBlockSource: nil, offsetToData: 0,
                                                 dataLength: byteCount, flags: kCMBlockBufferAssureMemoryNowFlag,
                                                 blockBufferOut: &block) == noErr, let block else { return nil }
        let copied = samples.withUnsafeBytes { bytes -> OSStatus in
            guard let base = bytes.baseAddress else { return -1 }
            return CMBlockBufferReplaceDataBytes(with: base, blockBuffer: block, offsetIntoDestination: 0, dataLength: byteCount)
        }
        guard copied == noErr else { return nil }
        var buffer: CMSampleBuffer?
        let status = CMAudioSampleBufferCreateReadyWithPacketDescriptions(
            allocator: nil, dataBuffer: block, formatDescription: format, sampleCount: frames,
            presentationTimeStamp: time, packetDescriptions: nil, sampleBufferOut: &buffer)
        return status == noErr ? buffer : nil
    }
}
