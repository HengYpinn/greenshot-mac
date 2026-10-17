// Greenshot for Mac (Community) - an unofficial macOS port of Greenshot
// Copyright (C) 2026 Greenshot for Mac (Community) contributors
// Based on Greenshot, Copyright (C) 2007-2026 Thomas Braun, Jens Klingen, Robin Krom
// SPDX-License-Identifier: GPL-3.0-or-later

import Foundation

/// The unsaved editors kept for the next start of the app, one `.greenshot` file each (with `GreenshotFile.Session`),
/// named after the document's id like upstream's `Surface.ID + ".greenshot"` (`Greenshot/Helpers/RestartManagerHelper.cs`
/// keeps them in %TEMP%\Greenshot\RestartState). A file that is being restored is renamed to `.restoring` first and
/// stays so until the app has run for a while with it open (`settle`): a file that makes the app crash while it opens
/// or is first drawn is not opened again at every start.
///
/// The names also carry the process that wrote the file (`<document id>.<process id>.greenshot`): when two copies of the
/// app run (e.g. two builds), neither restores nor removes the files of the other one while it runs.
public struct EditorSessionStore: Sendable {
    public static let folderName = "Unsaved Editors"
    static let restoringExtension = "restoring"

    public let folder: URL
    /// The process this store writes for.
    public let process: Int32

    public init(folder: URL, process: Int32 = ProcessInfo.processInfo.processIdentifier) {
        self.folder = folder
        self.process = process
    }

    /// In the folder of `--settings-dir` when there is one (a portable setup keeps its screenshots with it), else in
    /// the app's folder in Application Support.
    public static func folder(settingsDirectory: URL?, applicationSupport: URL, bundleIdentifier: String) -> URL {
        let base = settingsDirectory ?? applicationSupport.appendingPathComponent(bundleIdentifier, isDirectory: true)
        return base.appendingPathComponent(folderName, isDirectory: true)
    }

    public func url(for id: UUID) -> URL {
        folder.appendingPathComponent("\(id.uuidString).\(process)").appendingPathExtension(GreenshotFile.fileExtension)
    }

    /// The file of the document `id` while it is restored and not settled yet.
    func restoringURL(for id: UUID) -> URL {
        folder.appendingPathComponent("\(id.uuidString).\(process)").appendingPathExtension(Self.restoringExtension)
    }

    /// The process that wrote a file of the store, from its name; nil for a name without one.
    public static func owner(of url: URL) -> Int32? {
        let parts = url.deletingPathExtension().lastPathComponent.split(separator: ".")
        guard parts.count == 2 else { return nil }
        return Int32(parts[1])
    }

    /// Whether the file belongs to another copy of the app that is running now (`isRunning` tells for a process id).
    func ownedByAnotherRunningCopy(_ url: URL, isRunning: (Int32) -> Bool) -> Bool {
        guard let owner = Self.owner(of: url), owner != process else { return false }
        return isRunning(owner)
    }

    /// Writes the file of the document `id`, readable by the user only (it is a screenshot).
    public func write(_ data: Data, for id: UUID) throws {
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true,
                                                attributes: [.posixPermissions: 0o700])
        let url = url(for: id)
        try data.write(to: url, options: .atomic)
        try FileManager.default.setAttributes([.posixPermissions: 0o600], ofItemAtPath: url.path)
        // Written again after it was restored: this file is its state now.
        try? FileManager.default.removeItem(at: restoringURL(for: id))
    }

    public func remove(_ id: UUID) {
        try? FileManager.default.removeItem(at: url(for: id))
        try? FileManager.default.removeItem(at: restoringURL(for: id))
    }

    /// Removes the files of these documents (of this process; another copy's files stay).
    public func remove(_ ids: Set<UUID>) {
        for id in ids { remove(id) }
    }

    /// The kept editors, the oldest first (they open in that order, so the newest ends up in front); without those of
    /// another copy of the app that is running (`isRunning` tells for a process id).
    public func saved(isRunning: (Int32) -> Bool = { _ in false }) -> [URL] {
        files(withExtension: GreenshotFile.fileExtension).filter { !ownedByAnotherRunningCopy($0, isRunning: isRunning) }
    }

    /// Files whose restore did not finish: the app ended while one of them opened or soon after. Not those another
    /// running copy is restoring.
    public func unfinishedRestores(isRunning: (Int32) -> Bool = { _ in false }) -> [URL] {
        files(withExtension: Self.restoringExtension).filter { !ownedByAnotherRunningCopy($0, isRunning: isRunning) }
    }

    /// Marks a kept editor as being restored by this process (renamed to `.restoring`); the new name, nil when that
    /// failed (e.g. another copy claimed it first).
    public func claim(_ url: URL) -> URL? {
        let stem = url.deletingPathExtension().lastPathComponent.split(separator: ".").first.map(String.init) ?? "restore"
        let claimed = folder.appendingPathComponent("\(stem).\(process)").appendingPathExtension(Self.restoringExtension)
        do {
            try FileManager.default.moveItem(at: url, to: claimed)
            return claimed
        } catch {
            return nil
        }
    }

    /// A restored editor keeps its file as the one of its new document `id` until it is saved, closed or written again.
    /// It stays `.restoring` until `settle(_:)`.
    @discardableResult
    public func adopt(_ claimed: URL, as id: UUID) -> Bool {
        (try? FileManager.default.moveItem(at: claimed, to: restoringURL(for: id))) != nil
    }

    /// The app ran for a while with the restored document `id` open: its file is a kept editor again, restored at the
    /// next start if the app ends without quitting.
    public func settle(_ id: UUID) {
        let restoring = restoringURL(for: id)
        guard FileManager.default.fileExists(atPath: restoring.path) else { return }
        if FileManager.default.fileExists(atPath: url(for: id).path) {
            try? FileManager.default.removeItem(at: restoring)
        } else {
            try? FileManager.default.moveItem(at: restoring, to: url(for: id))
        }
    }

    private func files(withExtension fileExtension: String) -> [URL] {
        let keys: [URLResourceKey] = [.contentModificationDateKey]
        guard let urls = try? FileManager.default.contentsOfDirectory(at: folder, includingPropertiesForKeys: keys) else { return [] }
        // Named from `folder` (the listing may spell the folder differently, e.g. /private/var for /var).
        let matching = urls.filter { $0.pathExtension == fileExtension }.map { folder.appendingPathComponent($0.lastPathComponent) }
        let dated: [(url: URL, date: Date)] = matching.map { url in
            let values = try? url.resourceValues(forKeys: [.contentModificationDateKey])
            return (url, values?.contentModificationDate ?? .distantPast)
        }
        let sorted = dated.sorted { (a: (url: URL, date: Date), b: (url: URL, date: Date)) -> Bool in
            if a.date != b.date { return a.date < b.date }
            return a.url.lastPathComponent < b.url.lastPathComponent
        }
        return sorted.map(\.url)
    }
}

/// When quitting keeps the unsaved editors for the next start instead of asking about each (upstream's Restart Manager
/// integration saves the editors when Windows ends the session, `RestartManagerHelper.OnSessionEnding`).
public enum EditorSessionPolicy {
    /// A four character Apple Event code as its number ("logo" → 0x6C6F676F).
    public static func code(_ text: String) -> UInt32 {
        text.utf8.prefix(4).reduce(UInt32(0)) { (value: UInt32, byte: UInt8) -> UInt32 in value << 8 | UInt32(byte) }
    }

    /// The `kAEQuitReason` of the quit Apple Event when macOS logs out, restarts or shuts down (AERegistry.h:
    /// kAELogOut, kAEReallyLogOut, kAEShowRestartDialog, kAEShowShutdownDialog, kAERestart, kAEShutDown, kAEQuitAll).
    public static let sessionEndReasons: Set<UInt32> = Set(["logo", "rlgo", "rrst", "rsdn", "rest", "shut", "quia"].map(code))

    /// How long after `NSWorkspace.willPowerOffNotification` a quit counts as the end of the session: a logout that
    /// another app cancelled must not make the next ⌘Q keep the editors without asking.
    public static let powerOffWindow: TimeInterval = 60

    /// - Parameters:
    ///   - quitReason: the quit Apple Event's reason, nil when it has none (⌘Q, the menu bar menu's Quit).
    ///   - poweringOffSince: when macOS said it powers off or logs out, nil when it didn't.
    ///   - keepsWindows: macOS's "Close windows when quitting an application" is off (`NSQuitAlwaysKeepsWindows`).
    public static func keepsEditors(quitReason: UInt32?, poweringOffSince: Date?, now: Date, keepsWindows: Bool) -> Bool {
        if let quitReason, sessionEndReasons.contains(quitReason) { return true }
        if let poweringOffSince, now.timeIntervalSince(poweringOffSince) >= 0,
           now.timeIntervalSince(poweringOffSince) <= powerOffWindow { return true }
        return keepsWindows
    }
}

/// What the user answered about one editor with unsaved changes when the app quits.
public enum QuitAnswer: Sendable {
    /// Saved, or nothing to ask: it may go.
    case proceed
    /// "Don't Save".
    case discard
    /// "Cancel" (or saving failed): the app keeps running.
    case cancel
}

/// The questions before quitting: each editor is asked in turn, and "Don't Save" only counts once every editor agreed
/// to quit. Discarding at once would lose the changes of an editor that was answered "Don't Save" before another one
/// was cancelled.
public enum QuitReview {
    /// Asks about each editor in order and stops at the first Cancel. The editors whose changes go are returned when
    /// nobody cancelled; nil when the quit is cancelled.
    public static func run<Editor>(_ editors: [Editor], ask: (Editor) -> QuitAnswer) -> [Editor]? {
        var discarded: [Editor] = []
        for editor in editors {
            switch ask(editor) {
            case .proceed: continue
            case .discard: discarded.append(editor)
            case .cancel: return nil
            }
        }
        return discarded
    }
}
