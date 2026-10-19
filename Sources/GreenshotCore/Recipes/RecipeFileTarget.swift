// Greenshot for Mac (Community) - an unofficial macOS port of Greenshot
// Copyright (C) 2026 Greenshot for Mac (Community) contributors
// Based on Greenshot, Copyright (C) 2007-2026 Thomas Braun, Jens Klingen, Robin Krom
// SPDX-License-Identifier: GPL-3.0-or-later

import Foundation

/// Where a File destination step writes (security review): a recipe's `FilenamePattern` is evaluated before the step
/// sees it, so a value from the outside (a QR text, a page title, a flow variable) can start with "/" or "~". Only the
/// recipe author's own raw pattern may name an absolute path; text that came in through a `${...}` stays in the folder.
public enum RecipeFileTarget {
    /// The raw `FilenamePattern` parameter of the node, as the recipe author wrote it (not its evaluated text).
    public static func rawPattern(_ step: RecipeStepInvocation) -> String? {
        step.node.parameters.string("FilenamePattern")
    }

    /// The recipe author wrote an absolute ("/…" or "~…") pattern: the raw parameter of the node, not its evaluated text.
    public static func rawPatternIsAbsolute(_ step: RecipeStepInvocation) -> Bool {
        rawPattern(step).map(RecipeFileExportOptions.isAbsolutePattern) ?? false
    }

    /// The file for the filled-in pattern `name` of the raw pattern `rawPattern`. An absolute raw pattern goes where the
    /// author put it, but values can't climb out of its fixed start (`/Volumes/Shots/${title}` with "../../x" stays in
    /// /Volumes/Shots). Else the file is inside `folder` (a leading "/" of an incoming value is dropped, "~" is an
    /// ordinary name, and ".." can't climb out).
    public static func file(forName name: String, rawPattern: String?, in folder: URL, fileExtension: String,
                            home: URL = FileManager.default.homeDirectoryForCurrentUser) -> URL {
        let url: URL
        if let rawPattern, RecipeFileExportOptions.isAbsolutePattern(rawPattern) {
            let trimmed = name.trimmingCharacters(in: .whitespaces)
            let target = trimmed.hasPrefix("/") || trimmed.hasPrefix("~")
                ? URL(fileURLWithPath: (trimmed as NSString).expandingTildeInPath) : folder.appendingPathComponent(name)
            url = contained(target, byRawPattern: rawPattern, home: home)
        } else {
            var relative = Substring(name.trimmingCharacters(in: .whitespaces))
            while relative.hasPrefix("/") { relative = relative.dropFirst() }
            url = FilenamePattern.file(named: String(relative.isEmpty ? "Greenshot" : relative), in: folder)
        }
        return url.appendingPathExtension(fileExtension)
    }

    /// `url` when it is inside the fixed start of the absolute raw pattern (its text before the first `${` or `%`, up
    /// to the last "/"), else a file of the same last name in that folder. A raw pattern without a fixed start
    /// (`~`, `/${x}`) has nothing to stay in.
    public static func contained(_ url: URL, byRawPattern rawPattern: String, home: URL,
                                 environment: [String: String] = [:]) -> URL {
        let expanded = RecordingOutputPath.expandEnvironmentVariables(rawPattern, environment: environment)
        guard let root = FilenamePattern.literalRoot(ofFolderPattern: expanded, home: home), root.path != "/" else { return url }
        if FilenamePattern.isInside(url, folder: root), url.standardizedFileURL.path != root.standardizedFileURL.path { return url }
        return FilenamePattern.file(named: (url.path as NSString).lastPathComponent, in: root)
    }
}
