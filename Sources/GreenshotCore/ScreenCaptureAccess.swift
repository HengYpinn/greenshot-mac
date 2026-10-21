// Greenshot for Mac (Community) - an unofficial macOS port of Greenshot
// Copyright (C) 2026 Greenshot for Mac (Community) contributors
// SPDX-License-Identifier: GPL-3.0-or-later

import Foundation

/// Whether a capture may start when macOS's preflight for the Screen Recording permission says no (Windows, and so
/// upstream, has no such permission). The preflight can stay "no" after the user turned the permission on until the
/// app is reopened, so one real try of ScreenCaptureKit decides; the try also puts the app into the list in System
/// Settings on recent macOS versions.
public enum ScreenCaptureAccess {
    /// What one real try of ScreenCaptureKit gave.
    public enum Probe: Equatable, Sendable {
        /// It works: the permission is there.
        case works
        /// macOS refused it (the user declined, or the permission is off).
        case refused
        /// Another error.
        case failed
        /// No answer in time.
        case timedOut
    }

    public enum Decision: Equatable, Sendable {
        /// Capture.
        case granted
        /// Don't capture; macOS may be asking the user right now, so no dialog on top of its prompt: a short note.
        case note
        /// Don't capture; macOS asks nothing: explain where to turn the permission on.
        case explain
    }

    /// The longest a capture waits for the try, in seconds.
    public static let probeTimeout: Double = 3

    /// What a capture does after the preflight said no and macOS was asked for the permission
    /// (`CGRequestScreenCaptureAccess`), from the `probe`. macOS shows its own prompt only the first time it is asked
    /// for the app; `askedBefore` says it was asked on an earlier press (in this run or an earlier one), so no prompt
    /// can be showing now. Whether a first request showed one can't be known, so the first refusal is a note, not a
    /// second dialog; a probe that doesn't answer may be waiting for the user, so it is a note too.
    public static func decision(probe: Probe, askedBefore: Bool) -> Decision {
        switch probe {
        case .works: return .granted
        case .timedOut: return .note
        case .refused, .failed: return askedBefore ? .explain : .note
        }
    }

    /// The answer of `operation`, or `.timedOut` when it takes longer than `seconds`: the caller doesn't wait any
    /// longer (the operation ends in the background, its answer unused), so a hung ScreenCaptureKit can't hold up a
    /// capture.
    public static func probe(within seconds: Double, _ operation: @escaping @Sendable () async -> Probe) async -> Probe {
        await withCheckedContinuation { continuation in
            let answer = FirstAnswer(continuation)
            let timer = Task {
                try? await Task.sleep(nanoseconds: UInt64(max(seconds, 0) * 1_000_000_000))
                answer.give(.timedOut)
            }
            Task {
                answer.give(await operation())
                timer.cancel()
            }
        }
    }
}

/// Resumes a continuation with the first answer given; later ones are dropped.
private final class FirstAnswer: @unchecked Sendable {
    private let lock = NSLock()
    private var continuation: CheckedContinuation<ScreenCaptureAccess.Probe, Never>?

    init(_ continuation: CheckedContinuation<ScreenCaptureAccess.Probe, Never>) {
        self.continuation = continuation
    }

    func give(_ probe: ScreenCaptureAccess.Probe) {
        lock.lock()
        let waiting = continuation
        continuation = nil
        lock.unlock()
        waiting?.resume(returning: probe)
    }
}
