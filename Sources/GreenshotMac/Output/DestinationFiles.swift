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
    static func write(_ capture: Capture, settings: SettingsStore, format: ImageFormat = .png) throws -> URL {
        let context = settings.patternContext(title: capture.title, date: capture.date, consumeNumber: false)
        var name = (FilenamePattern.fileName(settings.value.filenamePattern, context: context) as NSString).lastPathComponent
        if name.trimmingCharacters(in: .whitespaces).isEmpty { name = "Screenshot" }
        let folder = FileManager.default.temporaryDirectory
            .appendingPathComponent("Greenshot", isDirectory: true)
            .appendingPathComponent(UUID().uuidString, isDirectory: true)
        let url = folder.appendingPathComponent(name).appendingPathExtension(format.fileExtension)
        try ImageExporter.write(capture.image, to: url, format: format, quality: settings.value.jpegQuality, scale: capture.scale)
        return url
    }
}
