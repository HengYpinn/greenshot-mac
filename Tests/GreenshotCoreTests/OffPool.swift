// Greenshot for Mac (Community) - an unofficial macOS port of Greenshot
// Copyright (C) 2026 Greenshot for Mac (Community) contributors
// SPDX-License-Identifier: GPL-3.0-or-later

import Foundation

/// Runs blocking work (a socket read, a synchronous Vision request) on a thread of its own and waits for it without
/// blocking the test's thread. Tests run on Swift's cooperative pool, which has as many threads as cores (3 on CI):
/// blocking one while the work needs the pool (an IPC handler, Vision's text recognition) hangs once every pool thread
/// waits. `body` only returns what it saw; the assertions stay in the test, where swift-testing records them.
func offPool<T>(_ body: @escaping () throws -> T) async throws -> T {
    try await withCheckedThrowingContinuation { (continuation: CheckedContinuation<T, Error>) in
        let thread = Thread { continuation.resume(with: Result { try body() }) }
        thread.name = "Test blocking work"
        thread.start()
    }
}

/// Writes bytes to a socket one at a time from a thread of its own, pausing between them. `stop()` ends the writes and
/// waits until the thread has finished, so the test can close the descriptor afterwards: a writer that outlives its test
/// would write into whatever socket the next test gets under the same descriptor number.
final class TrickleWriter: @unchecked Sendable {
    private let lock = NSLock()
    private var stopped = false
    private let ended = DispatchSemaphore(value: 0)
    private let fd: Int32
    private let bytes: [UInt8]
    private let pause: useconds_t

    init(fd: Int32, bytes: [UInt8], pause: useconds_t) {
        self.fd = fd
        self.bytes = bytes
        self.pause = pause
    }

    private var isStopped: Bool {
        lock.lock()
        defer { lock.unlock() }
        return stopped
    }

    func start() {
        let thread = Thread { [self] in
            defer { ended.signal() }
            for byte in bytes {
                if isStopped { return }
                var value = byte
                if Darwin.write(fd, &value, 1) != 1 { return }
                usleep(pause)
            }
        }
        thread.name = "Test trickle writer"
        thread.start()
    }

    /// Ends the writes and waits for the thread. Blocks for at most one pause: call it from a thread of its own
    /// (`offPool`) in async tests.
    func stop() {
        lock.lock()
        stopped = true
        lock.unlock()
        ended.wait()
    }
}
