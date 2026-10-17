// Greenshot for Mac (Community) - an unofficial macOS port of Greenshot
// Copyright (C) 2026 Greenshot for Mac (Community) contributors
// Based on Greenshot, Copyright (C) 2007-2026 Thomas Braun, Jens Klingen, Robin Krom
// SPDX-License-Identifier: GPL-3.0-or-later

import Foundation

/// Where a recording is: upstream `Greenshot.Base/Interfaces/Video/RecordingState.cs`.
public enum RecordingState: String, Equatable, Sendable {
    /// Before the capture starts.
    case unstarted
    case recording
    /// Nothing is recorded and the video's time stands still.
    case paused
    /// The file is being finished (the MP4's index written).
    case finalizing
    /// The file is ready.
    case stopped
    /// Cancelled: the file is deleted.
    case cancelled
    /// An error ended the recording.
    case failed

    /// Recording or paused.
    public var isActive: Bool { self == .recording || self == .paused }

    /// Stopped, cancelled or failed: nothing comes after it.
    public var isFinished: Bool { self == .stopped || self == .cancelled || self == .failed }

    /// The changes a session makes (upstream `PauseAsync` only from Recording, `ResumeAsync` only from Paused,
    /// `StopAsync`/`CancelAsync` not after Stopped). A file being finished isn't cancelled any more.
    public func canMove(to next: RecordingState) -> Bool {
        switch (self, next) {
        case (.unstarted, .recording), (.unstarted, .cancelled), (.unstarted, .failed): return true
        case (.recording, .paused), (.paused, .recording): return true
        case (.recording, .finalizing), (.paused, .finalizing): return true
        case (.recording, .cancelled), (.paused, .cancelled): return true
        case (.recording, .failed), (.paused, .failed): return true
        case (.finalizing, .stopped), (.finalizing, .failed): return true
        default: return false
        }
    }
}

/// A finished recording: upstream `Greenshot.Base/Interfaces/Video/VideoRecordingResult.cs`. Wave 4's recipe step puts
/// it into the flow (`VideoRecordingResult`, `VideoFilePath`).
public struct VideoRecordingResult: Equatable, Sendable, CustomStringConvertible {
    public var fileURL: URL
    /// The recorded time without the pauses.
    public var duration: TimeInterval
    public var fileSize: Int64
    public var width: Int
    public var height: Int
    public var frameRate: Int
    public var format: VideoFormat
    /// The file has a sound track with sound in it.
    public var hasAudio: Bool

    public init(fileURL: URL, duration: TimeInterval, fileSize: Int64, width: Int, height: Int, frameRate: Int,
                format: VideoFormat, hasAudio: Bool) {
        self.fileURL = fileURL
        self.duration = duration
        self.fileSize = fileSize
        self.width = width
        self.height = height
        self.frameRate = frameRate
        self.format = format
        self.hasAudio = hasAudio
    }

    /// Upstream's `ToString`, for the log (the file name only).
    public var description: String {
        "VideoRecordingResult: \(width)x\(height) @ \(frameRate)fps, \(RecordingText.elapsed(duration)), "
            + "\(fileSize / 1024) KB, \(fileURL.lastPathComponent)"
    }
}

/// Texts of the recording indicator and the messages.
public enum RecordingText {
    /// "0:05", "1:02", "1:02:03".
    public static func elapsed(_ seconds: TimeInterval) -> String {
        let total = Int(max(seconds, 0).rounded(.down))
        let hours = total / 3600
        let minutes = (total % 3600) / 60
        let rest = total % 60
        let secondsText = rest < 10 ? "0\(rest)" : "\(rest)"
        guard hours > 0 else { return "\(minutes):\(secondsText)" }
        let minutesText = minutes < 10 ? "0\(minutes)" : "\(minutes)"
        return "\(hours):\(minutesText):\(secondsText)"
    }

    /// "12.3 MB".
    public static func fileSize(_ bytes: Int64) -> String {
        ByteCountFormatter.string(fromByteCount: bytes, countStyle: .file)
    }
}
