// Greenshot for Mac (Community) - an unofficial macOS port of Greenshot
// Copyright (C) 2026 Greenshot for Mac (Community) contributors
// Based on Greenshot, Copyright (C) 2007-2026 Thomas Braun, Jens Klingen, Robin Krom
// SPDX-License-Identifier: GPL-3.0-or-later

import Foundation

public enum RecordingSlotError: LocalizedError, Equatable {
    case busy

    public var errorDescription: String? { String(localized: "A recording is already running.") }
}

/// The one recording at a time, from the moment it is asked for until its file is finished: picking what to record
/// and the countdown (`preparing`), setting up the stream and the file (`starting`, which takes a moment), recording
/// and saving (`running`). Nothing else can start meanwhile, and a stop or discard asked for while the recording starts
/// is done as soon as it runs, so no recording is ever left without a way to stop it.
@MainActor
public final class RecordingSlot<Recording: AnyObject> {
    public enum Phase: Equatable, Sendable {
        case idle
        /// Picking what to record, or counting down.
        case preparing
        /// The recording is being started.
        case starting
        /// It records, or its file is being finished.
        case running
    }

    /// What was asked for while the recording started.
    public enum PendingAction: Equatable, Sendable {
        case stop
        case discard
    }

    public private(set) var phase: Phase = .idle
    /// The recording once it runs.
    public private(set) var recording: Recording?
    public private(set) var pending: PendingAction?
    /// Does what was asked for while the recording started, right after it started.
    public var perform: (Recording, PendingAction) -> Void = { _, _ in }
    /// Called each time the slot is free again.
    public var onFree: () -> Void = {}

    public init() {}

    /// Takes the slot for a new recording; false while another one is prepared, starts or runs.
    public func claim() -> Bool {
        guard phase == .idle else { return false }
        phase = .preparing
        return true
    }

    /// Gives a claimed slot back: picking or the countdown was cancelled, or the preparation failed.
    public func release() {
        guard phase == .preparing else { return }
        free()
    }

    /// Starts the recording of a claimed slot with `make`. A failed start frees the slot.
    public func start(_ make: () async throws -> Recording) async throws -> Recording {
        guard phase == .preparing else { throw RecordingSlotError.busy }
        phase = .starting
        let made: Recording
        do {
            made = try await make()
        } catch {
            free()
            throw error
        }
        recording = made
        phase = .running
        if let action = pending {
            pending = nil
            perform(made, action)
        }
        return made
    }

    /// Asks the recording that starts to stop or be discarded once it runs; false when none is starting. A discard
    /// wins over a stop.
    @discardableResult
    public func whenStarted(_ action: PendingAction) -> Bool {
        guard phase == .starting else { return false }
        if pending != .discard { pending = action }
        return true
    }

    /// The recording ended (saved, discarded or failed): the slot is free.
    public func finished(_ ended: Recording) {
        guard phase == .running, recording === ended else { return }
        free()
    }

    private func free() {
        phase = .idle
        recording = nil
        pending = nil
        onFree()
    }
}
