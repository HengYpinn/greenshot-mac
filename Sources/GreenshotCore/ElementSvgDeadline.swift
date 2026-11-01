// Greenshot for Mac (Community) - an unofficial macOS port of Greenshot
// Copyright (C) 2026 Greenshot for Mac (Community) contributors
// Based on Greenshot, Copyright (C) 2007-2026 Thomas Braun, Jens Klingen, Robin Krom
// SPDX-License-Identifier: GPL-3.0-or-later

import Foundation

/// Runs what macOS does with an SVG (reading it, drawing it) on a thread of its own and waits for it for at most
/// `timeout`. How long drawing takes depends on how much area its shapes fill at the size it is drawn, which no count
/// of its elements tells: a few KB of full-size rectangles drawn at 8192 pixels took many seconds. Work that runs past
/// its time can't be stopped; it goes on in the background, and until it has ended every further run fails at once, so
/// there is never more than one.
final class SvgDeadline: @unchecked Sendable {
    /// How `run` ended.
    enum Outcome<Value> {
        case done(Value)
        /// The work didn't end within `timeout`.
        case timedOut
        /// Earlier work that didn't end in time is still going on: this work didn't run.
        case busy
    }

    /// The one every SVG goes through.
    static let shared = SvgDeadline(timeout: 2.5)

    let timeout: TimeInterval
    /// A queue of its own, not Swift's cooperative pool: the work blocks its thread for as long as it takes.
    private let queue = DispatchQueue(label: "io.github.greenshot-mac.svg", qos: .userInitiated)
    private let lock = NSLock()
    private var overdue = false

    init(timeout: TimeInterval) {
        self.timeout = timeout
    }

    /// Whether work that didn't end in time is still going on.
    var isOverdue: Bool {
        lock.withLock { overdue }
    }

    func run<Value>(_ work: @escaping () -> Value) -> Outcome<Value> {
        if isOverdue { return .busy }
        let job = Job<Value>()
        queue.async { [self] in
            guard job.begin() else { return }
            let value = work()
            if job.end(with: value) {
                lock.withLock { overdue = false }
            }
        }
        if job.done.wait(timeout: .now() + timeout) == .success, let value = job.value { return .done(value) }
        return job.giveUp(marking: self)
    }

    fileprivate func markOverdue() {
        lock.withLock { overdue = true }
    }

    /// One run: whether its work began, ended, or was given up by the caller.
    private final class Job<Value>: @unchecked Sendable {
        private enum State { case waiting, running, ended, cancelled }

        let done = DispatchSemaphore(value: 0)
        private let lock = NSLock()
        private var state = State.waiting
        private var abandoned = false
        private var result: Value?

        var value: Value? {
            lock.withLock { result }
        }

        /// False when the caller gave up before the work began: it doesn't run then.
        func begin() -> Bool {
            lock.withLock {
                guard state == .waiting else { return false }
                state = .running
                return true
            }
        }

        /// Keeps the work's value; true when the caller had given up on it (the deadline is no longer overdue).
        func end(with value: Value) -> Bool {
            let wasAbandoned = lock.withLock {
                state = .ended
                result = value
                return abandoned
            }
            done.signal()
            return wasAbandoned
        }

        /// What the caller gets when its time is up: work that hadn't begun never will (busy); work still running makes the
        /// deadline overdue until it ends; work that ended just now still counts.
        func giveUp(marking deadline: SvgDeadline) -> Outcome<Value> {
            lock.withLock {
                switch state {
                case .waiting:
                    // Behind other work all the time: not this work's fault.
                    state = .cancelled
                    return .busy
                case .running:
                    abandoned = true
                    deadline.markOverdue()
                    return .timedOut
                case .ended:
                    return result.map { .done($0) } ?? .timedOut
                case .cancelled:
                    return .timedOut
                }
            }
        }
    }
}
