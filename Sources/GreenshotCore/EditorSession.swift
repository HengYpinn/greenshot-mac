// Greenshot for Mac (Community) - an unofficial macOS port of Greenshot
// Copyright (C) 2026 Greenshot for Mac (Community) contributors
// Based on Greenshot, Copyright (C) 2007-2026 Thomas Braun, Jens Klingen, Robin Krom
// SPDX-License-Identifier: GPL-3.0-or-later

import Foundation

/// The unsaved editors kept for the next start of the app, one `.greenshot` file each (with `GreenshotFile.Session`),
/// named after the document's id like upstream's `Surface.ID + ".greenshot"` (`Greenshot/Helpers/RestartManagerHelper.cs`
/// keeps them in %TEMP%\Greenshot\RestartState). A file that is being restored is renamed to `.restoring` first, so a
/// file that makes the app crash while it opens is not opened again at every start.
public struct EditorSessionStore: Sendable {
    public static let folderName = "Unsaved Editors"
    static let restoringExtension = "restoring"

    public let folder: URL

    public init(folder: URL) {
        self.folder = folder
    }

    /// In the folder of `--settings-dir` when there is one (a portable setup keeps its screenshots with it), else in
    /// the app's folder in Application Support.
    public static func folder(settingsDirectory: URL?, applicationSupport: URL, bundleIdentifier: String) -> URL {
        let base = settingsDirectory ?? applicationSupport.appendingPathComponent(bundleIdentifier, isDirectory: true)
        return base.appendingPathComponent(folderName, isDirectory: true)
    }

    public func url(for id: UUID) -> URL {
        folder.appendingPathComponent(id.uuidString).appendingPathExtension(GreenshotFile.fileExtension)
    }

    /// Writes the file of the document `id`, readable by the user only (it is a screenshot).
    public func write(_ data: Data, for id: UUID) throws {
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true,
                                                attributes: [.posixPermissions: 0o700])
        let url = url(for: id)
        try data.write(to: url, options: .atomic)
        try FileManager.default.setAttributes([.posixPermissions: 0o600], ofItemAtPath: url.path)
    }

    public func remove(_ id: UUID) {
        try? FileManager.default.removeItem(at: url(for: id))
    }

    /// Removes the kept editors (and nothing else that may be in the folder).
    public func removeAll() {
        for url in files(withExtension: GreenshotFile.fileExtension) + files(withExtension: Self.restoringExtension) {
            try? FileManager.default.removeItem(at: url)
        }
    }

    /// The kept editors, the oldest first (they open in that order, so the newest ends up in front).
    public func saved() -> [URL] {
        files(withExtension: GreenshotFile.fileExtension)
    }

    /// Files whose restore did not finish: the app ended while one of them opened.
    public func unfinishedRestores() -> [URL] {
        files(withExtension: Self.restoringExtension)
    }

    /// Marks a kept editor as being restored (renamed to `.restoring`); the new name, nil when that failed.
    public func claim(_ url: URL) -> URL? {
        let claimed = url.deletingPathExtension().appendingPathExtension(Self.restoringExtension)
        do {
            try FileManager.default.moveItem(at: url, to: claimed)
            return claimed
        } catch {
            return nil
        }
    }

    /// A restored editor keeps its file as the one of its new document `id` until it is saved, closed or written again.
    @discardableResult
    public func adopt(_ claimed: URL, as id: UUID) -> Bool {
        (try? FileManager.default.moveItem(at: claimed, to: url(for: id))) != nil
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
