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
    /// The file could not be written any more while recording (the disk is full, the volume went away); what was
    /// written until then is kept in the file.
    case incomplete(String, URL)

    /// The reason when macOS gives none.
    static var unknownReason: String { String(localized: "unknown", comment: "The reason of a video file error when macOS gives none") }

    public var errorDescription: String? {
        switch self {
        case .cannotAddInput: return String(localized: "The video file could not be set up.")
        case .cannotStart(let reason): return String(localized: "The video file could not be written: \(reason)")
        case .noFrames: return String(localized: "The recording ended before anything was recorded.")
        case .failed(let reason): return String(localized: "The video file could not be finished: \(reason)")
        case .incomplete(let reason, let url):
            let path = (url.path as NSString).abbreviatingWithTildeInPath
            return String(localized: "The recording stopped because its file could not be written: \(reason). What was recorded until then is in \(path).")
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
        /// Seconds between the parts written so far being made readable (movie fragments): after a crash, a force quit
        /// or a power loss the file plays up to the last part. `finish` still writes a normal MP4. 0: none.
        public var fragmentInterval: TimeInterval
        /// A file at `url` is replaced (a recipe's path): moved aside when the writer starts, deleted with the first
        /// frame, put back when the recording ends before that. Else the writer can't start.
        public var replacesExistingFile: Bool
        /// Where a replaced file that a crash left behind goes (`discardLeftOverReplacedFiles`): the Trash. Tests give
        /// a folder of their own.
        var discardLeftOver: @Sendable (URL) throws -> Void = {
            try FileManager.default.trashItem(at: $0, resultingItemURL: nil)
        }

        public init(url: URL, format: VideoFormat, width: Int, height: Int, frameRate: Int, bitrate: Int,
                    colorMode: VideoColorMode = .fullColor, resizeBehavior: WindowResizeBehavior = .letterboxFixedCanvas,
                    hasAudio: Bool = false, realTime: Bool = true, fragmentInterval: TimeInterval = 10,
                    replacesExistingFile: Bool = false) {
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
            self.fragmentInterval = fragmentInterval
            self.replacesExistingFile = replacesExistingFile
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
    private var failureHandler: (@Sendable (Error) -> Void)?
    private var failureReported = false
    /// The file that was at `url` (`replacesExistingFile`), under a hidden name next to it until the first frame.
    private var replacedFile: URL?
    /// Why that file could not be put back, until `takePutBackFailure`.
    private var putBackFailure: Error?
    /// Frames the encoder had no room for.
    public private(set) var droppedFrames = 0

    /// Called once when the file can't be written any more (the disk is full, the volume went away, the encoder
    /// failed), on the queue of the sample or the `checkForFailure` that found it out. `finish` then keeps what was
    /// written until then.
    public var onFailure: (@Sendable (Error) -> Void)? {
        get {
            lock.lock()
            defer { lock.unlock() }
            return failureHandler
        }
        set {
            lock.lock()
            failureHandler = newValue
            lock.unlock()
        }
    }

    public init(_ configuration: Configuration) throws {
        self.configuration = configuration
        let folder = configuration.url.deletingLastPathComponent()
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        writer = try AVAssetWriter(outputURL: configuration.url, fileType: .mp4)
        if configuration.fragmentInterval > 0 {
            writer.movieFragmentInterval = CMTime(seconds: configuration.fragmentInterval, preferredTimescale: 600)
        }
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
        // Only now, when nothing else can stop the start: AVAssetWriter writes no file over an existing one.
        if configuration.replacesExistingFile { replacedFile = try Self.moveAside(configuration.url) }
        let discard = configuration.discardLeftOver
        DispatchQueue.global(qos: .utility).async { Self.discardLeftOverReplacedFiles(in: folder, discard: discard) }
        guard writer.startWriting() else {
            let reason = writer.error?.localizedDescription ?? VideoWriterError.unknownReason
            // Only what the writer may have made where the moved file was; a file or folder that was there stays.
            if replacedFile != nil {
                try? FileManager.default.removeItem(at: configuration.url)
                putBackReplacedFile()
            }
            throw VideoWriterError.cannotStart(reason)
        }
    }

    /// Never left without `cancel` or `finish` by the recorder; should it be, a file it was to replace goes back.
    deinit {
        guard replacedFile != nil else { return }
        writer.cancelWriting()
        try? FileManager.default.removeItem(at: configuration.url)
        putBackReplacedFile()
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
        lockedNoticingFailure { lockedAppendVideo(buffer, contentRect: contentRect, at: time) }
    }

    private func lockedAppendVideo(_ buffer: CVPixelBuffer, contentRect: CGRect?, at time: CMTime) -> Bool {
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
        if lastVideoTime == nil { deleteReplacedFile() }
        lastVideoTime = output
        lastFrame = frame
        return true
    }

    /// Adds sound taken at its presentation time (the host clock); sound before the first frame or in a pause is left
    /// out, also the part of a chunk before the first frame or the resume.
    @discardableResult
    public func appendAudio(_ sampleBuffer: CMSampleBuffer) -> Bool {
        lockedNoticingFailure { lockedAppendAudio(sampleBuffer) }
    }

    private func lockedAppendAudio(_ sampleBuffer: CMSampleBuffer) -> Bool {
        guard !done, let audioInput, writer.status == .writing, timeline.start != nil else { return false }
        let time = CMSampleBufferGetPresentationTimeStamp(sampleBuffer)
        var sound = sampleBuffer
        var output = timeline.outputTime(for: time)
        if output == nil, let part = recordedPart(of: sampleBuffer, at: time) {
            sound = part.buffer
            output = part.output
        }
        guard let output else { return false }
        if let last = lastAudioTime, CMTimeCompare(output, last) <= 0 { return false }
        guard let moved = Self.retimed(sound, to: output), ready(audioInput) else { return false }
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

    /// Tells `onFailure` when the file can't be written any more, also while no samples come (a still screen).
    public func checkForFailure() {
        lockedNoticingFailure {}
    }

    /// Finishes the file with the recording ending at `end` (host clock). The last frame is shown until then: the screen
    /// sends frames only when something changes, and a still screen would otherwise end the video early.
    public func finish(at end: CMTime) async throws -> VideoRecordingResult {
        let endTime: CMTime
        switch try endSession(at: end) {
        case .finishing(let time): endTime = time
        case .broken(let reason): throw await keepWhatWasWritten(reason)
        }
        await writer.finishWriting()
        guard writer.status == .completed else {
            throw VideoWriterError.failed(writer.error?.localizedDescription ?? VideoWriterError.unknownReason)
        }
        let attributes = try? FileManager.default.attributesOfItem(atPath: configuration.url.path)
        let size = (attributes?[.size] as? NSNumber)?.int64Value ?? 0
        return VideoRecordingResult(fileURL: configuration.url, duration: endTime.seconds, fileSize: size,
                                    width: configuration.width, height: configuration.height,
                                    frameRate: configuration.frameRate, format: configuration.format,
                                    hasAudio: audioWritten)
    }

    /// How `endSession` left the file.
    private enum Ending {
        /// The video ends at this time; the file is to be finished.
        case finishing(CMTime)
        /// The writer failed after frames were written: the movie fragments written until then may play.
        case broken(String)
    }

    /// Marks the inputs finished and ends the session.
    private func endSession(at end: CMTime) throws -> Ending {
        lock.lock()
        defer { lock.unlock() }
        guard !done else { throw VideoWriterError.failed(String(localized: "The recording was already finished.")) }
        done = true
        guard let lastVideoTime, writer.status == .writing else {
            let failed = writer.status == .failed
            let reason = writer.error?.localizedDescription ?? VideoWriterError.unknownReason
            // Not deleted yet: `finish` keeps the file if what was written until the failure plays.
            if failed, lastVideoTime != nil, configuration.fragmentInterval > 0 { return .broken(reason) }
            writer.cancelWriting()
            try? FileManager.default.removeItem(at: configuration.url)
            putBackReplacedFile()
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
        return .finishing(finalTime)
    }

    /// The writer failed after frames: the file stays when the movie fragments written until then play (the error says
    /// where it is). Else (no fragment on the disk yet) it is deleted, like a file without frames.
    private func keepWhatWasWritten(_ reason: String) async -> VideoWriterError {
        let url = configuration.url
        let length = (try? await AVURLAsset(url: url).load(.duration).seconds) ?? 0
        guard length > 0 else {
            try? FileManager.default.removeItem(at: url)
            return .failed(reason)
        }
        log.warn("The video file could not be written any more; kept what plays (\(Int(length)) s)")
        return .incomplete(reason, url)
    }

    /// Stops and deletes the file (upstream `CancelAsync`); a file it was to replace goes back when no frame was
    /// written yet (the recording didn't start).
    public func cancel() {
        lock.lock()
        defer { lock.unlock() }
        guard !done else { return }
        done = true
        writer.cancelWriting()
        try? FileManager.default.removeItem(at: configuration.url)
        putBackReplacedFile()
    }

    // MARK: The file a recording replaces

    /// Moves the file at `url` (never a folder: the start then fails as before) to a hidden name next to it, so that a
    /// recording that doesn't start can put it back; nil when there is none.
    private static func moveAside(_ url: URL) throws -> URL? {
        var isFolder: ObjCBool = false
        guard FileManager.default.fileExists(atPath: url.path, isDirectory: &isFolder), !isFolder.boolValue else {
            return nil
        }
        let aside = url.deletingLastPathComponent().appendingPathComponent(replacedFileName(at: Date()))
        do {
            try FileManager.default.moveItem(at: url, to: aside)
        } catch {
            throw VideoWriterError.cannotStart(error.localizedDescription)
        }
        return aside
    }

    private static let replacedPrefix = ".greenshot-replaced-"
    private static let replacedSuffix = ".previous"

    /// The hidden name a replaced file waits under: `.greenshot-replaced-<seconds since 1970>-<UUID>.previous`, 76
    /// bytes whatever the video's name (a name near the 255-byte limit still has room), unique, and with the time it
    /// was moved, so that one left behind can be told from any other file (`discardLeftOverReplacedFiles`).
    static func replacedFileName(at date: Date) -> String {
        "\(replacedPrefix)\(Int(date.timeIntervalSince1970))-\(UUID().uuidString)\(replacedSuffix)"
    }

    /// The time in a name `replacedFileName` made; nil for any other name.
    static func replacedFileDate(_ name: String) -> Date? {
        guard name.hasPrefix(replacedPrefix), name.hasSuffix(replacedSuffix) else { return nil }
        let middle = name.dropFirst(replacedPrefix.count).dropLast(replacedSuffix.count)
        guard let dash = middle.firstIndex(of: "-"), let seconds = Int(middle[..<dash]),
              UUID(uuidString: String(middle[middle.index(after: dash)...])) != nil else { return nil }
        return Date(timeIntervalSince1970: TimeInterval(seconds))
    }

    /// Moves to the Trash (`discard`) the files in `folder` that a recording moved aside more than a day ago and that
    /// were never put back or deleted: the app crashed or was force quit before the first frame, or putting one back
    /// failed (then it is the only copy of that video). Only plain files with such a name; never deleted for good: one
    /// that can't go to the Trash stays.
    static func discardLeftOverReplacedFiles(in folder: URL, now: Date = Date(), discard: (URL) throws -> Void) {
        let names = (try? FileManager.default.contentsOfDirectory(atPath: folder.path)) ?? []
        for name in names {
            guard let moved = replacedFileDate(name), now.timeIntervalSince(moved) > 24 * 60 * 60 else { continue }
            let url = folder.appendingPathComponent(name)
            guard (try? url.resourceValues(forKeys: [.isRegularFileKey]))?.isRegularFile == true else { continue }
            do {
                try discard(url)
                log.info("Moved \(name), a video a recording was to replace and didn't, to the Trash")
            } catch {
                log.warn("\(name), a video a recording was to replace and didn't, could not go to the Trash; it stays",
                         error: error)
            }
        }
    }

    /// Why the file this recording was to replace could not be put back when it ended before its first frame (`cancel`,
    /// `finish`), once; nil when it was or there was none. The file then waits under its hidden name next to the video
    /// (Finder doesn't show it) until a recording a day later moves it to the Trash.
    public func takePutBackFailure() -> Error? {
        lock.lock()
        defer { lock.unlock() }
        let failure = putBackFailure
        putBackFailure = nil
        return failure
    }

    /// The recording ended before its first frame (its own file is deleted): the file it was to replace goes back.
    private func putBackReplacedFile() {
        guard let aside = replacedFile else { return }
        replacedFile = nil
        do {
            try FileManager.default.moveItem(at: aside, to: configuration.url)
        } catch {
            log.error("The file the recording was to replace could not be put back: it is \(aside.lastPathComponent) "
                      + "next to \(configuration.url.lastPathComponent)", error: error)
            putBackFailure = error
        }
    }

    /// The first frame is written: the recording replaces the file for good (upstream `FileMode.Create`). Deleted off
    /// the screen's queue: a large file may take a moment.
    private func deleteReplacedFile() {
        guard let aside = replacedFile else { return }
        replacedFile = nil
        DispatchQueue.global(qos: .utility).async {
            try? FileManager.default.removeItem(at: aside)
        }
    }

    // MARK: Helpers

    /// Runs `body` under the lock, then tells `onFailure` (outside the lock, once) when the writer has failed.
    private func lockedNoticingFailure<T>(_ body: () -> T) -> T {
        lock.lock()
        let result = body()
        var handler: (@Sendable (Error) -> Void)?
        var error: Error?
        if !done, !failureReported, writer.status == .failed {
            failureReported = true
            handler = failureHandler
            error = writer.error ?? VideoWriterError.failed(VideoWriterError.unknownReason)
        }
        lock.unlock()
        if let handler, let error { handler(error) }
        return result
    }

    /// The part of sound taken at `time` from the first frame or the end of a pause on (the chunk starts before it and
    /// goes on after it), and its time in the video; nil when none of it is in the video.
    private func recordedPart(of buffer: CMSampleBuffer, at time: CMTime) -> (buffer: CMSampleBuffer, output: CMTime)? {
        guard let from = timeline.recordedTime(from: time),
              let description = CMSampleBufferGetFormatDescription(buffer),
              let sampleRate = CMAudioFormatDescriptionGetStreamBasicDescription(description)?.pointee.mSampleRate,
              sampleRate > 0 else { return nil }
        let count = CMSampleBufferGetNumSamples(buffer)
        let skip = Int((CMTimeSubtract(from, time).seconds * sampleRate).rounded(.up))
        guard skip > 0, skip < count else { return nil }
        var part: CMSampleBuffer?
        guard CMSampleBufferCopySampleBufferForRange(allocator: nil, sampleBuffer: buffer,
                                                     sampleRange: CFRange(location: skip, length: count - skip),
                                                     sampleBufferOut: &part) == noErr, let part,
              let output = timeline.outputTime(for: CMSampleBufferGetPresentationTimeStamp(part)) else { return nil }
        return (part, output)
    }

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
