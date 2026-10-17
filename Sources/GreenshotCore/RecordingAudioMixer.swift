// Greenshot for Mac (Community) - an unofficial macOS port of Greenshot
// Copyright (C) 2026 Greenshot for Mac (Community) contributors
// Based on Greenshot, Copyright (C) 2007-2026 Thomas Braun, Jens Klingen, Robin Krom
// SPDX-License-Identifier: GPL-3.0-or-later

import AVFoundation
import CoreMedia
import Foundation

/// Mixes what the Mac plays and the microphone into one sound track (upstream `AudioCaptureSource.SystemAudioAndMicrophone`:
/// "both mixed together"). Each source sends chunks of interleaved float samples at the time they were taken; the
/// chunks are placed by that time, and the mix goes out as far as both sources have sent. A source that falls more than
/// `maximumLag` behind (a silent or stopped microphone) counts as silence from there on.
public struct RecordingAudioMixer: Sendable {
    public let sampleRate: Double
    public let channels: Int
    /// Seconds one source may be behind the other before its part is silence.
    public var maximumLag: Double = 0.5

    /// The time of frame 0, from the first chunk of any source.
    public private(set) var origin: Double?
    /// The next frame to go out.
    private var emitted: Int64 = 0
    private var sources: [Source]

    private struct Source: Sendable {
        /// The frame `samples` starts at.
        var start: Int64 = 0
        var samples: [Float] = []
        var hasData = false

        func end(channels: Int) -> Int64 { start + Int64(samples.count / channels) }
    }

    public init(sources count: Int = 2, sampleRate: Double = 48_000, channels: Int = 2) {
        self.sampleRate = sampleRate
        self.channels = channels
        sources = Array(repeating: Source(), count: count)
    }

    /// Adds `samples` of source `index` taken at `time` (seconds, the same clock for all sources). Small jitter is
    /// ignored (the chunk follows the source's last one); a gap of more than 10 ms is silence.
    public mutating func add(_ samples: [Float], source index: Int, at time: Double) {
        guard sources.indices.contains(index), !samples.isEmpty else { return }
        let first = origin ?? time
        origin = first
        let frame = Int64(((time - first) * sampleRate).rounded())
        var source = sources[index]
        if source.hasData {
            let end = source.end(channels: channels)
            let tolerance = Int64(sampleRate / 100)
            if frame > end + tolerance {
                source.samples += [Float](repeating: 0, count: Int(frame - end) * channels)
            }
        } else {
            source.hasData = true
            source.start = frame
        }
        source.samples += samples
        // What is before the part that already went out is too late.
        if source.start < emitted {
            let late = min(Int(emitted - source.start), source.samples.count / channels)
            source.samples.removeFirst(late * channels)
            source.start += Int64(late)
        }
        sources[index] = source
    }

    /// The mix that is ready: interleaved samples and the time of its first frame; nil when nothing is ready.
    /// `flush` sends everything (at the end of a recording).
    public mutating func mix(flush: Bool = false) -> (samples: [Float], time: Double)? {
        guard let origin else { return nil }
        let ends = sources.map { $0.hasData ? $0.end(channels: channels) : emitted }
        guard let latest = ends.max(), let earliest = ends.min() else { return nil }
        var ready = earliest
        let lagFrames = Int64(maximumLag * sampleRate)
        if flush {
            ready = latest
        } else if latest - earliest > lagFrames {
            ready = latest - lagFrames
        }
        guard ready > emitted else { return nil }
        let count = Int(ready - emitted)
        var output = [Float](repeating: 0, count: count * channels)
        for index in sources.indices {
            var source = sources[index]
            guard source.hasData else { continue }
            let offset = Int(emitted - source.start)
            let available = source.samples.count / channels
            for frame in 0..<count {
                let position = offset + frame
                guard position >= 0, position < available else { continue }
                for channel in 0..<channels {
                    output[frame * channels + channel] += source.samples[position * channels + channel]
                }
            }
            // Drop what went out.
            let consumed = min(max(Int(ready - source.start), 0), available)
            if consumed > 0 {
                source.samples.removeFirst(consumed * channels)
                source.start += Int64(consumed)
            }
            sources[index] = source
        }
        for index in output.indices { output[index] = min(1, max(-1, output[index])) }
        let time = origin + Double(emitted) / sampleRate
        emitted = ready
        return (output, time)
    }
}

/// Turns sound of any format into the interleaved 48 kHz stereo floats the mixer and the writer take (mono goes to
/// both sides). One converter per source: it keeps the state of the sample rate conversion.
public final class RecordingAudioConverter: @unchecked Sendable {
    public let sampleRate: Double
    public let channels: Int
    private var converter: AVAudioConverter?
    private var inputFormat: AVAudioFormat?
    private let outputFormat: AVAudioFormat
    private var streamStart: Double?
    private var sentFrames: Int64 = 0

    public init(sampleRate: Double = VideoEncoderSettings.audioSampleRate, channels: Int = VideoEncoderSettings.audioChannels) {
        self.sampleRate = sampleRate
        self.channels = channels
        outputFormat = AVAudioFormat(commonFormat: .pcmFormatFloat32, sampleRate: sampleRate,
                                     channels: AVAudioChannelCount(channels), interleaved: true)!
    }

    /// The samples of `buffer` and the time of its first one (seconds); nil when it can't be read. `time` replaces the
    /// buffer's own time (the microphone's, moved to the host clock).
    public func convert(_ buffer: CMSampleBuffer, time: Double? = nil) -> (samples: [Float], time: Double)? {
        guard let description = CMSampleBufferGetFormatDescription(buffer),
              let format = Optional(AVAudioFormat(cmAudioFormatDescription: description)) else { return nil }
        let frames = AVAudioFrameCount(CMSampleBufferGetNumSamples(buffer))
        guard frames > 0, let input = AVAudioPCMBuffer(pcmFormat: format, frameCapacity: frames) else { return nil }
        input.frameLength = frames
        guard CMSampleBufferCopyPCMDataIntoAudioBufferList(buffer, at: 0, frameCount: Int32(frames),
                                                           into: input.mutableAudioBufferList) == noErr else { return nil }
        let time = time ?? CMSampleBufferGetPresentationTimeStamp(buffer).seconds
        guard let samples = convert(input) else { return nil }
        // The converter holds a few frames back, so the time of its output follows from the frames sent so far; a gap
        // in the input (sound that stopped and came back) starts counting again.
        let expected = (streamStart ?? time) + Double(sentFrames) / sampleRate
        if streamStart == nil || abs(time - expected) > 0.1 {
            streamStart = time
            sentFrames = 0
        }
        let start = (streamStart ?? time) + Double(sentFrames) / sampleRate
        sentFrames += Int64(samples.count / channels)
        return (samples, start)
    }

    /// The samples of a PCM buffer in the output format.
    public func convert(_ input: AVAudioPCMBuffer) -> [Float]? {
        if converter == nil || inputFormat != input.format {
            guard let made = AVAudioConverter(from: input.format, to: outputFormat) else { return nil }
            if input.format.channelCount == 1 && channels == 2 { made.channelMap = [0, 0] }
            converter = made
            inputFormat = input.format
        }
        guard let converter else { return nil }
        let ratio = sampleRate / input.format.sampleRate
        let capacity = AVAudioFrameCount((Double(input.frameLength) * ratio).rounded(.up)) + 32
        guard let output = AVAudioPCMBuffer(pcmFormat: outputFormat, frameCapacity: capacity) else { return nil }
        var supplied = false
        var error: NSError?
        let status = converter.convert(to: output, error: &error) { _, inputStatus in
            if supplied {
                inputStatus.pointee = .noDataNow
                return nil
            }
            supplied = true
            inputStatus.pointee = .haveData
            return input
        }
        guard status != .error, let data = output.floatChannelData else { return nil }
        let count = Int(output.frameLength) * channels
        return Array(UnsafeBufferPointer(start: data[0], count: count))
    }
}
