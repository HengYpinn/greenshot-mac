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
