// Greenshot for Mac (Community) - an unofficial macOS port of Greenshot
// Copyright (C) 2026 Greenshot for Mac (Community) contributors
// Based on Greenshot, Copyright (C) 2007-2026 Thomas Braun, Jens Klingen, Robin Krom
// SPDX-License-Identifier: GPL-3.0-or-later

import Foundation

/// How important a message after a capture is, for the `notificationLevel` setting (upstream `NotificationKind`).
public enum MessageKind: Sendable {
    case info, warning, error
}

extension NotificationLevel {
    /// Whether a message of `kind` is shown at this level (upstream `NotificationLevel` in `ICoreConfiguration.cs`).
    public func shows(_ kind: MessageKind) -> Bool {
        switch self {
        case .all: return true
        case .warnings: return kind != .info
        case .errors: return kind == .error
        case .none: return false
        }
    }
}

/// Helpers the destinations share.
public enum DestinationSupport {
    /// `url`, or with " (2)", " (3)", … before the extension when a file is there already (upstream with
    /// `OutputFileAllowOverwrite` off).
    public static func uniqueURL(for url: URL, exists: (URL) -> Bool = { FileManager.default.fileExists(atPath: $0.path) }) -> URL {
        guard exists(url) else { return url }
        let folder = url.deletingLastPathComponent()
        let ext = url.pathExtension
        let base = url.deletingPathExtension().lastPathComponent
        var number = 2
        while true {
            let name = "\(base) (\(number))"
            let candidate = ext.isEmpty ? folder.appendingPathComponent(name) : folder.appendingPathComponent(name).appendingPathExtension(ext)
            if !exists(candidate) { return candidate }
            number += 1
        }
    }

    /// The HTML clipboard format: the PNG embedded in an `<img>` (upstream `ClipboardHelper` "HTML DATAURL").
    public static func htmlSnippet(png: Data, width: Int, height: Int) -> String {
        "<img src=\"data:image/png;base64,\(png.base64EncodedString())\" width=\"\(width)\" height=\"\(height)\">"
    }

    /// Splits a recipient list ("a@b.c, d@e.f; g@h.i") into addresses.
    public static func recipients(_ text: String) -> [String] {
        text.components(separatedBy: CharacterSet(charactersIn: ",;"))
            .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter { !$0.isEmpty }
    }

    /// A `mailto:` URL with recipients and subject (no attachment: mailto can't carry one).
    public static func mailtoURL(to: [String], cc: [String], bcc: [String], subject: String) -> URL? {
        var components = URLComponents()
        components.scheme = "mailto"
        components.path = to.joined(separator: ",")
        var query: [URLQueryItem] = []
        if !cc.isEmpty { query.append(URLQueryItem(name: "cc", value: cc.joined(separator: ","))) }
        if !bcc.isEmpty { query.append(URLQueryItem(name: "bcc", value: bcc.joined(separator: ","))) }
        if !subject.isEmpty { query.append(URLQueryItem(name: "subject", value: subject)) }
        components.queryItems = query.isEmpty ? nil : query
        return components.url
    }

    // MARK: Folders

    /// The output folder with the pattern variables filled in and `~` expanded (upstream `FileDestination`
    /// `FillVariables(OutputFilePath, false)`). `context` should not count `${NUM}` up (`consumeNumber: false`), so the
    /// file name's `${NUM}` counts once. An empty folder is the Desktop.
    public static func outputFolder(_ folder: String, context: FilenamePattern.Context) -> URL {
        let trimmed = folder.trimmingCharacters(in: .whitespaces)
        guard !trimmed.isEmpty else { return context.homeDirectory.appendingPathComponent("Desktop", isDirectory: true) }
        // Captured values (a window title) are cleaned: one gives at most one folder level, never "..", "~" or "/".
        let filled = FilenamePattern.fill(trimmed, context: context, filenameSafe: false, cleanCapturedValues: true)
        let path = trimmed.hasPrefix("~") ? context.homeDirectory.path + filled.dropFirst() : filled
        return URL(fileURLWithPath: path, isDirectory: true)
    }

    /// The folder part of a filled file name pattern ("2026-10-17/000001 - Safari" → "2026-10-17"), nil without one.
    public static func subfolder(ofFileName name: String) -> String? {
        guard let slash = name.lastIndex(of: "/"), !name.hasPrefix("/") else { return nil }
        let folder = String(name[..<slash]).trimmingCharacters(in: CharacterSet(charactersIn: "/"))
        return folder.isEmpty ? nil : folder
    }

    /// Where the Save As dialog starts (upstream `SaveImageFileDialog.Init` and `ApplySuggestedValues`): the folder of
    /// the file the editor shows, else the pattern's sub folder of the output folder, else the folder of the last saved
    /// file when it still exists, else the output folder.
    public static func saveAsFolder(editorFile: URL?, patternSubfolder: URL?, lastSavedFile: String?, outputFolder: URL,
                                    folderExists: (URL) -> Bool) -> URL {
        if let editorFile { return editorFile.deletingLastPathComponent() }
        if let patternSubfolder { return patternSubfolder }
        if let lastSavedFile, !lastSavedFile.isEmpty {
            let folder = URL(fileURLWithPath: lastSavedFile).deletingLastPathComponent()
            if folderExists(folder) { return folder }
        }
        return outputFolder
    }

    /// Whether a folder created for the Save As dialog can go again: nothing was saved in it (upstream
    /// `SaveImageFileDialog.CleanUp`). Finder's `.DS_Store` doesn't count.
    public static func isUnused(folderContents: [String]) -> Bool {
        folderContents.allSatisfy { $0 == ".DS_Store" }
    }

    // MARK: Temporary files

    /// How long the temporary files of mail, share, external commands and "Open with" are kept.
    public static let temporaryFileLifetime: TimeInterval = 24 * 60 * 60

    /// The temporary capture folders to delete: those last changed longer than `maxAge` ago (upstream
    /// `SharingFiles.CleanupOldShareFiles` deletes the previous share files; another app may still have a recent one open).
    public static func staleTemporaryFolders(_ folders: [(url: URL, modified: Date)], now: Date,
                                             maxAge: TimeInterval = temporaryFileLifetime) -> [URL] {
        folders.filter { now.timeIntervalSince($0.modified) > maxAge }.map(\.url)
    }

    // MARK: Printers

    /// The printers for the picker: the default printer first, then by name (upstream `PrinterDestination`).
    public static func sortedPrinters(_ names: [String], defaultPrinter: String?) -> [String] {
        var unique: [String] = []
        for name in names where !unique.contains(name) { unique.append(name) }
        return unique.sorted { a, b in
            if a == defaultPrinter { return true }
            if b == defaultPrinter { return false }
            return a.unicodeScalars.lexicographicallyPrecedes(b.unicodeScalars)
        }
    }

    // MARK: Quality dialog

    /// Whether the quality slider of the quality dialog matters for `format` (upstream enables it for JPEG only; WebP is
    /// written lossless here, so the quality doesn't change it).
    public static func usesQuality(_ format: ImageFormat) -> Bool {
        format.usesQuality
    }

    /// Whether "Reduce colours" changes a file of `format`: every format whose colours `ImageExporter` reduces, all but
    /// JPEG, PDF and `.greenshot` (upstream enables the box for every format).
    public static func reducesColors(_ format: ImageFormat) -> Bool {
        format.reducesColors
    }

    /// Whether the quality dialog has anything to ask for `format`: the JPEG quality or the colour reduction.
    public static func asksQuality(_ format: ImageFormat) -> Bool {
        usesQuality(format) || reducesColors(format)
    }
}

extension AppSettings {
    /// "Save as default quality and do not ask again" in the quality dialog (upstream `QualityWindow.Apply`): the
    /// choices become the settings and the dialog stops asking.
    public mutating func rememberQualityChoice(jpegQuality: Int, reduceColors: Bool) {
        self.jpegQuality = min(max(jpegQuality, 1), 100)
        self.reduceColors = reduceColors
        promptJpegQuality = false
    }
}
