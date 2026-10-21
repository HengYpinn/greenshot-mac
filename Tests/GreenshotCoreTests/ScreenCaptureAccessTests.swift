// Greenshot for Mac (Community) - an unofficial macOS port of Greenshot
// Copyright (C) 2026 Greenshot for Mac (Community) contributors
// SPDX-License-Identifier: GPL-3.0-or-later

import Foundation
import Testing
@testable import GreenshotCore

struct ScreenCaptureAccessTests {
    @Test func aWorkingProbeGrantsAlthoughThePreflightSaysNo() {
        // The permission was turned on while the app runs: the preflight may say no until a relaunch.
        #expect(ScreenCaptureAccess.decision(probe: .works, askedBefore: true) == .granted)
        #expect(ScreenCaptureAccess.decision(probe: .works, askedBefore: false) == .granted)
    }

    @Test func aRefusalIsExplainedWhenMacOSAsksNothing() {
        // macOS showed its prompt the first time it was asked; now it shows nothing, so the app explains.
        #expect(ScreenCaptureAccess.decision(probe: .refused, askedBefore: true) == .explain)
        #expect(ScreenCaptureAccess.decision(probe: .failed, askedBefore: true) == .explain)
    }

    @Test func theFirstRefusalIsANoteBesideMacOSsPrompt() {
        // Asked for the first time: macOS may show its own prompt now, so no dialog on top, but not silence either.
        #expect(ScreenCaptureAccess.decision(probe: .refused, askedBefore: false) == .note)
        #expect(ScreenCaptureAccess.decision(probe: .failed, askedBefore: false) == .note)
    }

    @Test func aProbeThatDoesntAnswerIsANote() {
        // Something may be waiting for the user (a prompt of macOS): no dialog on top of it.
        #expect(ScreenCaptureAccess.decision(probe: .timedOut, askedBefore: true) == .note)
        #expect(ScreenCaptureAccess.decision(probe: .timedOut, askedBefore: false) == .note)
    }

    @Test func aQuickProbeGivesItsAnswer() async {
        #expect(await ScreenCaptureAccess.probe(within: 5) { .works } == .works)
        #expect(await ScreenCaptureAccess.probe(within: 5) { .refused } == .refused)
    }

    @Test(.timeLimit(.minutes(1)))
    func aProbeThatHangsIsNotWaitedFor() async {
        // The try can't answer before the test opens the gate. A probe that awaits its try in the caller's task fails
        // at the time limit (its cancellation opens the gate, the try answers `.works`); a probe whose timer never fires
        // would hang the run instead, because the try runs in a task of its own that the cancellation doesn't reach.
        let gate = Gate()
        let result = await ScreenCaptureAccess.probe(within: 0.05) {
            await gate.wait()
            return .works
        }
        #expect(result == .timedOut)
        gate.open()
    }
}

/// Holds back an operation until `open`, or until its task is cancelled.
private final class Gate: @unchecked Sendable {
    private let lock = NSLock()
    private var isOpen = false
    private var waiting: CheckedContinuation<Void, Never>?

    func wait() async {
        await withTaskCancellationHandler {
            await withCheckedContinuation { (continuation: CheckedContinuation<Void, Never>) in
                lock.lock()
                if isOpen {
                    lock.unlock()
                    continuation.resume()
                    return
                }
                waiting = continuation
                lock.unlock()
            }
        } onCancel: {
            open()
        }
    }

    func open() {
        lock.lock()
        isOpen = true
        let resumed = waiting
        waiting = nil
        lock.unlock()
        resumed?.resume()
    }
}
