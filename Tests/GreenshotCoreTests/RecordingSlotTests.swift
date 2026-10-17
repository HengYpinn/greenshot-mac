// Greenshot for Mac (Community) - an unofficial macOS port of Greenshot
// Copyright (C) 2026 Greenshot for Mac (Community) contributors
// SPDX-License-Identifier: GPL-3.0-or-later

import Foundation
import Testing
@testable import GreenshotCore

/// A recording for the slot: what was done to it.
@MainActor
private final class FakeRecording {
    var actions: [RecordingSlot<FakeRecording>.PendingAction] = []
}

/// Makes recordings slowly, like the stream and the file being set up, and counts them.
@MainActor
private final class SlowFactory {
    var made = 0

    func make() async throws -> FakeRecording {
        try await Task.sleep(nanoseconds: 50_000_000)
        made += 1
        return FakeRecording()
    }

    func fail() async throws -> FakeRecording {
        try await Task.sleep(nanoseconds: 20_000_000)
        throw CocoaError(.fileWriteUnknown)
    }
}

/// The controller's way: the menu or hotkey claims the slot, then starts (`VideoRecordingController.start`/`begin`).
@MainActor
private func record(_ slot: RecordingSlot<FakeRecording>, _ factory: SlowFactory) async throws -> FakeRecording? {
    guard slot.claim() else { return nil }
    return try await slot.start { try await factory.make() }
}

/// Lets the started task run until it waits in the factory.
@MainActor
private func untilStarting(_ slot: RecordingSlot<FakeRecording>) async {
    for _ in 0..<1000 where slot.phase != .starting {
        await Task.yield()
    }
}

@MainActor
struct RecordingSlotTests {
    private func slot() -> RecordingSlot<FakeRecording> {
        let slot = RecordingSlot<FakeRecording>()
        slot.perform = { recording, action in recording.actions.append(action) }
        return slot
    }

    /// Record Screen twice and the hotkey while the first recording starts: one recording, stopped once it runs.
    @Test func oneRecordingWhileTheFirstStarts() async throws {
        let slot = slot()
        let factory = SlowFactory()
        let first = Task { try await record(slot, factory) }
        await untilStarting(slot)
        #expect(slot.phase == .starting)
        // The second Record Screen and a direct start (a recipe) are refused while the first starts.
        let second = try await record(slot, factory)
        #expect(second == nil)
        #expect(!slot.claim())
        // The hotkey (or a click on the indicator) while it starts: stop as soon as it runs.
        #expect(slot.whenStarted(.stop))
        let started = try #require(try await first.value)
        #expect(factory.made == 1)
        #expect(slot.recording === started)
        #expect(started.actions == [.stop])
        #expect(slot.pending == nil)
    }

    /// Quitting while the recording starts: the quit waits (`terminateLater`) and is answered when the slot is free.
    @Test func quittingWhileStartingWaitsForTheEnd() async throws {
        let slot = slot()
        let factory = SlowFactory()
        var freed = 0
        slot.onFree = { freed += 1 }
        let first = Task { try await record(slot, factory) }
        await untilStarting(slot)
        let waits = slot.whenStarted(.stop)
        #expect(waits)
        let started = try #require(try await first.value)
        #expect(started.actions == [.stop])
        #expect(freed == 0)
        // The stop finished the file.
        slot.finished(started)
        #expect(freed == 1)
        #expect(slot.phase == .idle)
        #expect(slot.claim())
    }

    @Test func aFailedStartFreesTheSlot() async {
        let slot = slot()
        let factory = SlowFactory()
        var freed = 0
        slot.onFree = { freed += 1 }
        #expect(slot.claim())
        await #expect(throws: CocoaError.self) {
            _ = try await slot.start { try await factory.fail() }
        }
        #expect(slot.phase == .idle)
        #expect(freed == 1)
        #expect(!slot.whenStarted(.stop))
    }

    @Test func discardWinsOverStop() async throws {
        let slot = slot()
        let factory = SlowFactory()
        let first = Task { try await record(slot, factory) }
        await untilStarting(slot)
        slot.whenStarted(.discard)
        slot.whenStarted(.stop)
        let started = try #require(try await first.value)
        #expect(started.actions == [.discard])
    }

    @Test func aCancelledPickOrCountdownGivesTheSlotBack() {
        let slot = slot()
        #expect(slot.claim())
        #expect(slot.phase == .preparing)
        #expect(!slot.whenStarted(.stop))
        slot.release()
        #expect(slot.phase == .idle)
        // Only the running recording ends it.
        #expect(slot.claim())
        slot.finished(FakeRecording())
        #expect(slot.phase == .preparing)
    }
}
