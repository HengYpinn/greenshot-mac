// Greenshot for Mac (Community) - an unofficial macOS port of Greenshot
// Copyright (C) 2026 Greenshot for Mac (Community) contributors
// Based on Greenshot, Copyright (C) 2007-2026 Thomas Braun, Jens Klingen, Robin Krom
// SPDX-License-Identifier: GPL-3.0-or-later

import Foundation

/// The file a recording writes.
public enum RecordingOutputPath {
    /// Upstream records to `Videos\Greenshot` (`WindowsGraphicsCaptureVideoSession.EnsureOutputFilePath`).
    public static let defaultFolder = "~/Movies/Greenshot"
    public static let fileExtension = "mp4"

    /// Settings › Video: the folder (its pattern variables filled in, `~` expanded, empty = the default folder) and the
    /// filled file name pattern plus ".mp4". A file that exists gets " (2)", " (3)", …: a recording never overwrites one.
    public static func url(folder: String, pattern: String, context: FilenamePattern.Context,
                           exists: (URL) -> Bool = { FileManager.default.fileExists(atPath: $0.path) }) -> URL {
        let trimmed = folder.trimmingCharacters(in: .whitespaces)
        let folderURL = DestinationSupport.outputFolder(trimmed.isEmpty ? defaultFolder : trimmed, context: previewing(context))
        let name = FilenamePattern.fileName(pattern, context: context)
        let base = name.hasPrefix("/") ? URL(fileURLWithPath: name) : folderURL.appendingPathComponent(name)
        return DestinationSupport.uniqueURL(for: base.appendingPathExtension(fileExtension), exists: exists)
    }

    /// The context with `${NUM}` only previewed, for the folder: the file name counts it once.
    private static func previewing(_ context: FilenamePattern.Context) -> FilenamePattern.Context {
        var copy = context
        copy.nextNumber = { 0 }
        return copy
    }

    /// The file of a recipe's RecordVideo step (upstream `RecordVideoRecipeStep.BuildOptions` §11 and
    /// `EnsureOutputFilePath`): `outputFilePath`, else `outputDirectory` with `filenamePattern` (default
    /// `Greenshot_{yyyyMMdd_HHmmss}.mp4`), else `Greenshot_Recording_<time>.mp4` in the default folder. `%NAME%` is
    /// replaced by the environment variable (left as it is when not set, like .NET's `ExpandEnvironmentVariables`),
    /// `{yyyyMMdd_HHmmss}` by the time, a leading `~` by the home folder; a relative path is in the default folder.
    public static func recipeURL(outputFilePath: String?, outputDirectory: String?, filenamePattern: String?, date: Date,
                                 environment: [String: String], homeDirectory: URL,
                                 timeZone: TimeZone = .current) -> URL {
        let stamp = timestamp(date, timeZone: timeZone)
        let defaultFolderURL = homeDirectory.appendingPathComponent("Movies/Greenshot", isDirectory: true)
        var path = outputFilePath?.trimmingCharacters(in: .whitespaces) ?? ""
        let directory = outputDirectory?.trimmingCharacters(in: .whitespaces) ?? ""
        if path.isEmpty && !directory.isEmpty {
            let pattern = filenamePattern?.trimmingCharacters(in: .whitespaces) ?? ""
            let name = pattern.isEmpty ? "Greenshot_{yyyyMMdd_HHmmss}.mp4" : pattern
            path = (directory as NSString).appendingPathComponent(name)
        }
        guard !path.isEmpty else {
            return defaultFolderURL.appendingPathComponent("Greenshot_Recording_\(stamp).\(fileExtension)")
        }
        path = expandEnvironmentVariables(path, environment: environment)
        path = path.replacingOccurrences(of: "{yyyyMMdd_HHmmss}", with: stamp)
        if path == "~" || path.hasPrefix("~/") { path = homeDirectory.path + path.dropFirst() }
        guard path.hasPrefix("/") else { return defaultFolderURL.appendingPathComponent(path) }
        return URL(fileURLWithPath: path)
    }

    /// "20261017_143005" (upstream `DateTime.Now.ToString("yyyyMMdd_HHmmss")`).
    public static func timestamp(_ date: Date, timeZone: TimeZone = .current) -> String {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.calendar = Calendar(identifier: .gregorian)
        formatter.timeZone = timeZone
        formatter.dateFormat = "yyyyMMdd_HHmmss"
        return formatter.string(from: date)
    }

    /// .NET `Environment.ExpandEnvironmentVariables`: `%NAME%` (any case) becomes the variable's value; unknown names
    /// and lone `%` stay.
    public static func expandEnvironmentVariables(_ text: String, environment: [String: String]) -> String {
        var byName: [String: String] = [:]
        for (key, value) in environment { byName[key.lowercased()] = value }
        var result = ""
        var rest = Substring(text)
        while let open = rest.firstIndex(of: "%") {
            result += rest[..<open]
            let afterOpen = rest.index(after: open)
            guard let close = rest[afterOpen...].firstIndex(of: "%") else {
                rest = rest[open...]
                break
            }
            let name = String(rest[afterOpen..<close])
            if !name.isEmpty, let value = byName[name.lowercased()] {
                result += value
                rest = rest[rest.index(after: close)...]
            } else {
                // Not a variable: the first % stays, the second may open the next one.
                result += "%"
                rest = rest[afterOpen...]
            }
        }
        return result + rest
    }
}
