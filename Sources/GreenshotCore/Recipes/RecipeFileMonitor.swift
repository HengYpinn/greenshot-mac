// Greenshot for Mac (Community) - an unofficial macOS port of Greenshot
// Copyright (C) 2026 Greenshot for Mac (Community) contributors
// Based on Greenshot, Copyright (C) 2007-2026 Thomas Braun, Jens Klingen, Robin Krom
// SPDX-License-Identifier: GPL-3.0-or-later

import CoreGraphics
import Foundation

/// Watches the folders of recipe files for changes to `*.gsrecipe.json` (upstream `FileSystemWatcher`) and reports a
/// changed file once it has been quiet for `debounce` seconds (upstream 1.5 s).
public final class RecipeFileMonitor: @unchecked Sendable {
    private let debounce: TimeInterval
    private let onChange: @Sendable (URL) -> Void
    private let queue = DispatchQueue(label: "greenshot.recipes.filemonitor")
    /// Everything below is only touched on `queue`.
    private var files: [String: WatchedFile] = [:]
    private var folders: [String: DispatchSourceFileSystemObject] = [:]
    private var pending: [String: DispatchWorkItem] = [:]

    private struct Snapshot: Equatable {
        var inode: UInt64
        var size: UInt64
        var modified: Date
    }

    private struct WatchedFile {
        var url: URL
        var snapshot: Snapshot?
        var source: DispatchSourceFileSystemObject?
    }

    public init(debounce: TimeInterval = 1.5, onChange: @escaping @Sendable (URL) -> Void) {
        self.debounce = debounce
        self.onChange = onChange
    }

    deinit {
        for file in files.values { file.source?.cancel() }
        for folder in folders.values { folder.cancel() }
    }

    public func watch(_ fileURL: URL) {
        let url = fileURL.standardizedFileURL
        queue.async { [self] in
            let key = url.path.lowercased()
            guard files[key] == nil else { return }
            files[key] = WatchedFile(url: url, snapshot: Self.snapshot(of: url), source: nil)
            openFileSource(key)
            let folder = url.deletingLastPathComponent().path
            if folders[folder.lowercased()] == nil, let source = makeSource(folder, events: .write, handler: { [weak self] in
                self?.folderChanged(folder)
            }) {
                folders[folder.lowercased()] = source
            }
        }
    }

    public func stopAll() {
        queue.sync {
            for file in files.values { file.source?.cancel() }
            for folder in folders.values { folder.cancel() }
            for item in pending.values { item.cancel() }
            files = [:]
            folders = [:]
            pending = [:]
        }
    }

    // MARK: On the queue

    private func makeSource(_ path: String, events: DispatchSource.FileSystemEvent,
                            handler: @escaping () -> Void) -> DispatchSourceFileSystemObject? {
        let descriptor = open(path, O_EVTONLY)
        guard descriptor >= 0 else { return nil }
        let source = DispatchSource.makeFileSystemObjectSource(fileDescriptor: descriptor, eventMask: events, queue: queue)
        source.setEventHandler(handler: handler)
        source.setCancelHandler { close(descriptor) }
        source.resume()
        return source
    }

    private func openFileSource(_ key: String) {
        guard let url = files[key]?.url else { return }
        files[key]?.source?.cancel()
        files[key]?.source = makeSource(url.path, events: [.write, .extend, .delete, .rename, .attrib]) { [weak self] in
            self?.fileEvent(key)
        }
    }

    private func fileEvent(_ key: String) {
        guard let file = files[key] else { return }
        // A file that was replaced (saved by renaming a new one over it) is a new file: watch that one.
        if let source = file.source, !source.data.intersection([.delete, .rename]).isEmpty {
            openFileSource(key)
        }
        check(key)
    }

    private func folderChanged(_ folder: String) {
        for (key, file) in files where file.url.deletingLastPathComponent().path == folder {
            if file.source == nil || Self.snapshot(of: file.url)?.inode != file.snapshot?.inode {
                openFileSource(key)
            }
            check(key)
        }
    }

    private func check(_ key: String) {
        guard let file = files[key] else { return }
        let now = Self.snapshot(of: file.url)
        guard now != file.snapshot else { return }
        files[key]?.snapshot = now
        pending[key]?.cancel()
        let url = file.url
        let item = DispatchWorkItem { [weak self] in
            guard let self else { return }
            self.pending[key] = nil
            log.info("Recipe file '\(url.path)' changed on disk.")
            self.onChange(url)
        }
        pending[key] = item
        queue.asyncAfter(deadline: .now() + debounce, execute: item)
    }

    private static func snapshot(of url: URL) -> Snapshot? {
        guard let attributes = try? FileManager.default.attributesOfItem(atPath: url.path) else { return nil }
        return Snapshot(inode: (attributes[.systemFileNumber] as? NSNumber)?.uint64Value ?? 0,
                        size: (attributes[.size] as? NSNumber)?.uint64Value ?? 0,
                        modified: attributes[.modificationDate] as? Date ?? .distantPast)
    }
}

private let log = Log("Recipes")
