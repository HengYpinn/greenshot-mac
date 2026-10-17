// Greenshot for Mac (Community) - an unofficial macOS port of Greenshot
// Copyright (C) 2026 Greenshot for Mac (Community) contributors
// Based on Greenshot, Copyright (C) 2007-2026 Thomas Braun, Jens Klingen, Robin Krom
// SPDX-License-Identifier: GPL-3.0-or-later

import AppKit
import GreenshotCore

private let log = Log("Notifications")

/// The captures the notifications offer again: port of upstream `Greenshot/Notifications/NotificationCaptures.cs`.
/// A capture is written after its notification was posted, read back for a click (also after a restart) and removed
/// then, when the notification is dismissed, or after an hour.
@MainActor
final class NotificationCaptures {
    let store: NotificationCaptureStore
    private let queue = DispatchQueue(label: "Greenshot.NotificationCaptures", qos: .utility)

    init(store: NotificationCaptureStore) {
        self.store = store
    }

    /// Writes the capture off the main thread (PNG with its scale as resolution), then calls `done` on the main thread.
    func keep(_ capture: Capture, id: String, done: @escaping () -> Void) {
        guard let url = store.captureURL(id) else { return }
        let image = capture.image
        let scale = capture.scale
        queue.async {
            do {
                try ImageExporter.write(image, to: url, format: .png, scale: scale)
            } catch {
                // The notification then only shows the capture; a click does nothing.
                log.warn("Couldn't keep the capture for the notification.", error: error)
            }
            DispatchQueue.main.async {
                MainActor.assumeIsolated { done() }
            }
        }
    }

    /// Reads the kept capture of a notification and removes it (its notification is gone with the click). Nil when there
    /// is none: the id is no UUID, or the hour is over.
    func take(_ payload: NotificationPayload) -> Capture? {
        guard let url = store.captureURL(payload.captureId ?? ""), FileManager.default.fileExists(atPath: url.path) else { return nil }
        defer { discard(payload.captureId) }
        guard let loaded = ImageFileLoader.load(url) else {
            log.warn("Couldn't read the capture of the notification.")
            return nil
        }
        return Capture(image: loaded.image, scale: loaded.scale, title: payload.title ?? "", date: payload.date ?? Date())
    }

    /// Removes the kept capture (upstream `Discard`).
    func discard(_ id: String?) {
        guard let id, let capture = store.captureURL(id) else { return }
        for url in [capture, store.attachmentURL(id)].compactMap({ $0 }) where FileManager.default.fileExists(atPath: url.path) {
            do {
                try FileManager.default.removeItem(at: url)
            } catch {
                log.warn("Couldn't remove \(url.lastPathComponent).", error: error)
            }
        }
    }

    /// Removes the files older than an hour.
    func removeExpiredFiles() {
        let folder = store.folder
        queue.async {
            let keys: [URLResourceKey] = [.contentModificationDateKey, .isRegularFileKey]
            guard let urls = try? FileManager.default.contentsOfDirectory(at: folder, includingPropertiesForKeys: keys) else { return }
            var files: [(name: String, modified: Date)] = []
            for url in urls {
                guard let values = try? url.resourceValues(forKeys: Set(keys)), values.isRegularFile == true,
                      let modified = values.contentModificationDate else { continue }
                files.append((url.lastPathComponent, modified))
            }
            for name in NotificationCaptureStore.expiredFiles(files) {
                do {
                    try FileManager.default.removeItem(at: folder.appendingPathComponent(name))
                } catch {
                    log.warn("Couldn't remove \(name).", error: error)
                }
            }
        }
    }
}
