// Greenshot for Mac (Community) - an unofficial macOS port of Greenshot
// Copyright (C) 2026 Greenshot for Mac (Community) contributors
// Based on Greenshot, Copyright (C) 2007-2026 Thomas Braun, Jens Klingen, Robin Krom
// SPDX-License-Identifier: GPL-3.0-or-later

import AppKit
import GreenshotCore

/// The temporary image files that mail, share, external commands and "Open with" hand to other apps: port of
/// `ExportFiles.SaveNamedTmpFileAsync` in upstream `Greenshot.Base`. Each file gets its own folder in the temporary
/// directory, so it can have the name of the filename pattern (that is what the other app shows) without clashes.
@MainActor
enum TemporaryCaptureFile {
    static var root: URL {
        FileManager.default.temporaryDirectory.appendingPathComponent("Greenshot", isDirectory: true)
    }

    static func write(_ capture: Capture, settings: SettingsStore, format: ImageFormat = .png) throws -> URL {
        removeOldFiles()
        let context = settings.patternContext(title: capture.title, date: capture.date, consumeNumber: false)
        var name = (FilenamePattern.fileName(settings.value.filenamePattern, context: context) as NSString).lastPathComponent
        if name.trimmingCharacters(in: .whitespaces).isEmpty { name = "Screenshot" }
        let folder = root.appendingPathComponent(UUID().uuidString, isDirectory: true)
        let url = folder.appendingPathComponent(name).appendingPathExtension(format.fileExtension)
        try ImageExporter.write(capture.image, to: url,
                                options: ImageOutputOptions(settings: settings.value, format: format, scale: capture.scale,
                                                            title: capture.title))
        return url
    }

    /// Deletes the files of earlier exports that are older than a day (upstream `SharingFiles.CleanupOldShareFiles`
    /// deletes the previous share files before each share; here another app may still use a recent one).
    static func removeOldFiles(now: Date = Date()) {
        let manager = FileManager.default
        guard let folders = try? manager.contentsOfDirectory(at: root, includingPropertiesForKeys: [.contentModificationDateKey],
                                                             options: [.skipsHiddenFiles]) else { return }
        let dated = folders.compactMap { folder -> (url: URL, modified: Date)? in
            guard let date = try? folder.resourceValues(forKeys: [.contentModificationDateKey]).contentModificationDate else { return nil }
            return (folder, date)
        }
        for folder in DestinationSupport.staleTemporaryFolders(dated, now: now) {
            try? manager.removeItem(at: folder)
        }
    }
}
