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
///
/// All runs share one budget as well: at most `budget` seconds of work in any `window` seconds. A document of hundreds
/// of SVG elements that each take just under `timeout` would otherwise keep the app busy for minutes; with the budget
/// used up, runs fail at once until older work has left the window (the elements not drawn yet show nothing until a
/// later redraw).
final class SvgDeadline: @unchecked Sendable {
    /// How `run` ended.
    enum Outcome<Value> {
        case done(Value)
        /// The work didn't end within `timeout`: it takes too long.
        case timedOut
        /// Earlier work that didn't end in time is still going on: this work didn't run.
        case busy
        /// The budget was used up before the work ended, or before it began: it may be fine at another time.
        case outOfTime
    }

    /// The one every SVG goes through: 2.5 seconds per SVG, 2.5 seconds in any 10 seconds for all of them.
    static let shared = SvgDeadline(timeout: 2.5, budget: 2.5, window: 10)

    let timeout: TimeInterval
    let budget: TimeInterval
    let window: TimeInterval
    /// Seconds from any fixed point, for the budget (tests give a clock of their own).
    private let now: @Sendable () -> TimeInterval
    /// A queue of its own, not Swift's cooperative pool: the work blocks its thread for as long as it takes.
    private let queue = DispatchQueue(label: "io.github.greenshot-mac.svg", qos: .userInitiated)
    private let lock = NSLock()
    private var overdue = false
    /// When the work of the window ran; one that hasn't ended counts up to now.
    private var spans: [Span] = []

    init(timeout: TimeInterval, budget: TimeInterval? = nil, window: TimeInterval = 10,
         now: @escaping @Sendable () -> TimeInterval = { ProcessInfo.processInfo.systemUptime }) {
        self.timeout = timeout
        self.budget = budget ?? timeout
        self.window = window
        self.now = now
    }

    /// Whether work that didn't end in time is still going on.
    var isOverdue: Bool {
        lock.withLock { overdue }
    }

    /// The seconds of work the budget has left now.
    var budgetLeft: TimeInterval {
        lock.withLock { leftLocked(at: now()) }
    }

    func run<Value>(_ work: @escaping () -> Value) -> Outcome<Value> {
        let left: TimeInterval
        do {
            lock.lock()
            defer { lock.unlock() }
            if overdue { return .busy }
            left = leftLocked(at: now())
        }
        guard left > 0 else { return .outOfTime }
        let wait = min(timeout, left)
        let job = Job<Value>()
        queue.async { [self] in
            guard job.begin() else { return }
            let span = Span(start: now())
            lock.withLock { spans.append(span) }
            let value = work()
            let wasAbandoned = job.end(with: value)
            lock.withLock {
                span.end = now()
                if wasAbandoned { overdue = false }
            }
        }
        if job.done.wait(timeout: .now() + wait) == .success, let value = job.value { return .done(value) }
        return job.giveUp(marking: self, budgetEnded: wait < timeout)
    }

    fileprivate func markOverdue() {
        lock.withLock { overdue = true }
    }

    /// `budget` less the work in the `window` before `time`; old spans are dropped. The lock is held.
    private func leftLocked(at time: TimeInterval) -> TimeInterval {
        let from = time - window
        spans.removeAll { ($0.end ?? time) <= from }
        let used = spans.reduce(0) { $0 + min($1.end ?? time, time) - max($1.start, from) }
        return budget - used
    }

    /// When one run's work began and ended.
    private final class Span {
        let start: TimeInterval
        var end: TimeInterval?

        init(start: TimeInterval) {
            self.start = start
        }
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

        /// What the caller gets when its time is up: work that hadn't begun never will (busy); work still running makes
        /// the deadline overdue until it ends, and took too long unless the caller only waited for what was left of
        /// the budget (`budgetEnded`); work that ended just now still counts.
        func giveUp(marking deadline: SvgDeadline, budgetEnded: Bool) -> Outcome<Value> {
            lock.withLock {
                switch state {
                case .waiting:
                    // Behind other work all the time: not this work's fault.
                    state = .cancelled
                    return .busy
                case .running:
                    abandoned = true
                    deadline.markOverdue()
                    return budgetEnded ? .outOfTime : .timedOut
                case .ended:
                    return result.map { .done($0) } ?? .timedOut
                case .cancelled:
                    return .timedOut
                }
            }
        }
    }
}
