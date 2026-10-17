// Greenshot for Mac (Community) - an unofficial macOS port of Greenshot
// Copyright (C) 2026 Greenshot for Mac (Community) contributors
// Based on Greenshot, Copyright (C) 2007-2026 Thomas Braun, Jens Klingen, Robin Krom
// SPDX-License-Identifier: GPL-3.0-or-later

import CoreMedia
import Foundation

/// The time line of a recording with pauses (upstream `WindowsGraphicsCaptureVideoSession.PauseAsync`/`ResumeAsync`:
/// while paused nothing is encoded and the time stands still). Samples carry the time of the clock they were taken on
/// (the host clock for the screen and the sound); the video starts at 0 with the first frame, and everything after a
/// pause moves back by the time paused.
public struct RecordingTimeline: Sendable {
    /// The source time of the video's 0: the first frame.
    public private(set) var start: CMTime?
    /// Pauses that ended, in source time.
    private var pauses: [(from: CMTime, to: CMTime)] = []
    /// The source time the running pause began.
    public private(set) var pausedSince: CMTime?

    public init() {}

    public var isPaused: Bool { pausedSince != nil }

    /// The first frame arrived at `time`.
    public mutating func begin(at time: CMTime) {
        guard start == nil else { return }
        start = time
    }

    public mutating func pause(at time: CMTime) {
        guard pausedSince == nil else { return }
        pausedSince = time
    }

    public mutating func resume(at time: CMTime) {
        guard let since = pausedSince else { return }
        pausedSince = nil
        // A pause before the first frame changes nothing: the video starts at its first frame anyway.
        guard let start, CMTimeCompare(time, start) > 0 else { return }
        let from = CMTimeMaximum(since, start)
        if CMTimeCompare(time, from) > 0 { pauses.append((from, time)) }
    }

    /// The time in the video of a sample taken at `time`; nil before the first frame or during a pause.
    public func outputTime(for time: CMTime) -> CMTime? {
        guard let start, time.isNumeric, CMTimeCompare(time, start) >= 0 else { return nil }
        if let since = pausedSince, CMTimeCompare(time, since) >= 0 { return nil }
        var paused = CMTime.zero
        for pause in pauses {
            if CMTimeCompare(time, pause.from) >= 0 && CMTimeCompare(time, pause.to) < 0 { return nil }
            if CMTimeCompare(time, pause.to) >= 0 { paused = CMTimeAdd(paused, CMTimeSubtract(pause.to, pause.from)) }
        }
        return CMTimeSubtract(CMTimeSubtract(time, start), paused)
    }

    /// The recorded time at `now`, without the pauses (upstream `Duration`); 0 before the first frame.
    public func duration(at now: CMTime) -> CMTime {
        guard let start, CMTimeCompare(now, start) > 0 else { return .zero }
        let end = pausedSince.map { CMTimeMinimum($0, now) } ?? now
        var paused = CMTime.zero
        for pause in pauses where CMTimeCompare(pause.from, end) < 0 {
            paused = CMTimeAdd(paused, CMTimeSubtract(CMTimeMinimum(pause.to, end), pause.from))
        }
        let total = CMTimeSubtract(CMTimeSubtract(end, start), paused)
        return CMTimeCompare(total, .zero) > 0 ? total : .zero
    }
}
