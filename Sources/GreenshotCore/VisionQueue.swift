// Greenshot for Mac (Community) - an unofficial macOS port of Greenshot
// Copyright (C) 2026 Greenshot for Mac (Community) contributors
// SPDX-License-Identifier: GPL-3.0-or-later

import Foundation

/// Where the async text recognition and barcode detection run. `VNImageRequestHandler.perform` blocks its thread
/// while Vision's text recognition waits for work that needs a thread of Swift's cooperative pool. Run on that pool,
/// as many requests at once as it has threads (3 on a small Mac or a CI runner) leave no thread for that work, and none
/// of them ever finishes. Here each request blocks a thread of its own while the awaiting task gives its pool thread
/// back.
enum VisionQueue {
    /// At most one request per core runs at once; more wait in the queue, not on a thread.
    private static let queue: OperationQueue = {
        let queue = OperationQueue()
        queue.name = "Vision requests"
        queue.maxConcurrentOperationCount = max(2, ProcessInfo.processInfo.activeProcessorCount)
        return queue
    }()

    /// Runs `work` (synchronous Vision calls) on the queue, at the priority of the calling task, and waits for it
    /// without blocking the task's thread.
    static func run<T: Sendable>(_ work: @escaping @Sendable () throws -> T) async throws -> T {
        let quality = qualityOfService(for: Task.currentPriority)
        return try await withCheckedThrowingContinuation { (continuation: CheckedContinuation<T, Error>) in
            let operation = BlockOperation { continuation.resume(with: Result { try work() }) }
            operation.qualityOfService = quality
            queue.addOperation(operation)
        }
    }

    static func qualityOfService(for priority: TaskPriority) -> QualityOfService {
        if priority >= .high { return .userInitiated }
        if priority >= .medium { return .default }
        if priority >= .low { return .utility }
        return .background
    }
}
