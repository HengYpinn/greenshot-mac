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
    /// filled file name pattern plus ".mp4". A file that exists, or that another recording has reserved and not yet
    /// written, gets " (2)", " (3)", …: a recording never overwrites one. The path is reserved until `release`.
    public static func url(folder: String, pattern: String, context: FilenamePattern.Context,
                           exists: (URL) -> Bool = { FileManager.default.fileExists(atPath: $0.path) }) -> URL {
        let trimmed = folder.trimmingCharacters(in: .whitespaces)
        let folderPattern = trimmed.isEmpty ? defaultFolder : trimmed
        var folderURL = DestinationSupport.outputFolder(folderPattern, context: previewing(context))
        // A window title is chosen by any app: whatever the pattern's variables bring in must not move the folder out
        // of the pattern's fixed start (e.g. `~/Movies/${title}`).
        if let root = FilenamePattern.literalRoot(ofFolderPattern: folderPattern, home: context.homeDirectory),
           !FilenamePattern.isInside(folderURL, folder: root) {
            folderURL = root
        }
        let name = FilenamePattern.fileName(pattern, context: context)
        let base = name.hasPrefix("/") ? URL(fileURLWithPath: name) : folderURL.appendingPathComponent(name)
        return reserved.reserve { taken in
            DestinationSupport.uniqueURL(for: base.appendingPathExtension(fileExtension),
                                         exists: { taken.contains($0.standardizedFileURL.path) || exists($0) })
        }
    }

    /// The recording of `url` ended (or never started): another one may take the path.
    public static func release(_ url: URL) {
        reserved.release(url)
    }

    /// The paths `url` gave out whose recordings haven't ended.
    private static let reserved = ReservedPaths()

    private final class ReservedPaths: @unchecked Sendable {
        private let lock = NSLock()
        private var paths: Set<String> = []

        /// `choose` picks a path that is not in the set it gets; it is added in the same step.
        func reserve(_ choose: (Set<String>) -> URL) -> URL {
            lock.lock()
            defer { lock.unlock() }
            let url = choose(paths)
            paths.insert(url.standardizedFileURL.path)
            return url
        }

        func release(_ url: URL) {
            lock.lock()
            paths.remove(url.standardizedFileURL.path)
            lock.unlock()
        }
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
    /// `rawOutputFilePath` is the node's parameter as the author wrote it (default: `outputFilePath`): `outputFilePath` is
    /// evaluated, so a value from outside (a QR text, a page title) can bring in "/", "~" or "..". Only an absolute raw
    /// path goes where it says, and values stay inside its fixed start; else the file stays in the default folder.
    /// The file always ends in a video extension: a value can't make the recording overwrite a file of another kind
    /// (a `.zshrc`, a LaunchAgent's `.plist`) inside the folder the path names.
    public static func recipeURL(outputFilePath: String?, rawOutputFilePath: String? = nil, outputDirectory: String?,
                                 filenamePattern: String?, date: Date,
                                 environment: [String: String], homeDirectory: URL,
                                 timeZone: TimeZone = .current) -> URL {
        let url = uncheckedRecipeURL(outputFilePath: outputFilePath, rawOutputFilePath: rawOutputFilePath,
                                     outputDirectory: outputDirectory, filenamePattern: filenamePattern, date: date,
                                     environment: environment, homeDirectory: homeDirectory, timeZone: timeZone)
        return videoExtensions.contains(url.pathExtension.lowercased()) ? url : url.appendingPathExtension(fileExtension)
    }

    /// What a recording may be called: what the recorder writes, and QuickTime's own names for it.
    static let videoExtensions: Set<String> = ["mp4", "m4v", "mov"]

    private static func uncheckedRecipeURL(outputFilePath: String?, rawOutputFilePath: String?, outputDirectory: String?,
                                           filenamePattern: String?, date: Date,
                                           environment: [String: String], homeDirectory: URL,
                                           timeZone: TimeZone) -> URL {
        let stamp = timestamp(date, timeZone: timeZone)
        let defaultFolderURL = homeDirectory.appendingPathComponent("Movies/Greenshot", isDirectory: true)
        var path = outputFilePath?.trimmingCharacters(in: .whitespaces) ?? ""
        let directory = outputDirectory?.trimmingCharacters(in: .whitespaces) ?? ""
        func expanded(_ text: String) -> String {
            expandEnvironmentVariables(text, environment: environment).replacingOccurrences(of: "{yyyyMMdd_HHmmss}", with: stamp)
        }
        if path.isEmpty, !directory.isEmpty {
            // The pattern comes from the recipe, the folder was approved: "../" or a "/" start in the pattern can't leave it.
            var folder = expanded(directory)
            if folder == "~" || folder.hasPrefix("~/") { folder = homeDirectory.path + folder.dropFirst() }
            let pattern = filenamePattern?.trimmingCharacters(in: .whitespaces) ?? ""
            var name = expanded(pattern.isEmpty ? "Greenshot_{yyyyMMdd_HHmmss}.mp4" : pattern)
            while name.hasPrefix("/") { name.removeFirst() }
            let folderURL = folder.hasPrefix("/") ? URL(fileURLWithPath: folder, isDirectory: true)
                                                  : defaultFolderURL.appendingPathComponent(folder, isDirectory: true)
            return FilenamePattern.file(named: name, in: folderURL)
        }
        guard !path.isEmpty else {
            return defaultFolderURL.appendingPathComponent("Greenshot_Recording_\(stamp).\(fileExtension)")
        }
        // Environment variables are the user's own, so they count as written by the author.
        let raw = expanded((rawOutputFilePath ?? outputFilePath)?.trimmingCharacters(in: .whitespaces) ?? "")
        path = expanded(path)
        guard RecipeFileExportOptions.isAbsolutePattern(raw) else {
            var relative = path
            while relative.hasPrefix("/") { relative.removeFirst() }
            return FilenamePattern.file(named: relative.isEmpty ? "Greenshot_Recording_\(stamp).\(fileExtension)" : relative, in: defaultFolderURL)
        }
        if path == "~" || path.hasPrefix("~/") { path = homeDirectory.path + path.dropFirst() }
        // An absolute raw path whose value no longer starts at "/" (raw "~${X}" with X = "../../tmp/x"): the default
        // folder, contained like a relative path.
        guard path.hasPrefix("/") else { return FilenamePattern.file(named: path, in: defaultFolderURL) }
        return RecipeFileTarget.contained(URL(fileURLWithPath: path), byRawPattern: raw, home: homeDirectory)
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
