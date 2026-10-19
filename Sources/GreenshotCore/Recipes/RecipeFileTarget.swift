// Greenshot for Mac (Community) - an unofficial macOS port of Greenshot
// Copyright (C) 2026 Greenshot for Mac (Community) contributors
// Based on Greenshot, Copyright (C) 2007-2026 Thomas Braun, Jens Klingen, Robin Krom
// SPDX-License-Identifier: GPL-3.0-or-later

import Foundation

/// Where a File destination step writes (security review): a recipe's `FilenamePattern` is evaluated before the step
/// sees it, so a value from the outside (a QR text, a page title, a flow variable) can start with "/" or "~". Only the
/// recipe author's own raw pattern may name an absolute path; text that came in through a `${...}` stays in the folder.
public enum RecipeFileTarget {
    /// The recipe author wrote an absolute ("/…" or "~…") pattern: the raw parameter of the node, not its evaluated text.
    public static func rawPatternIsAbsolute(_ step: RecipeStepInvocation) -> Bool {
        guard let raw = step.node.parameters.string("FilenamePattern") else { return false }
        return RecipeFileExportOptions.isAbsolutePattern(raw)
    }

    /// The file for the filled-in pattern `name`: where the author put it for an absolute raw pattern, else inside `folder`
    /// (a leading "/" of an incoming value is dropped, "~" is an ordinary name, and ".." can't climb out).
    public static func file(forName name: String, rawPatternIsAbsolute: Bool, in folder: URL, fileExtension: String) -> URL {
        let url: URL
        if rawPatternIsAbsolute {
            let trimmed = name.trimmingCharacters(in: .whitespaces)
            url = trimmed.hasPrefix("/") || trimmed.hasPrefix("~")
                ? URL(fileURLWithPath: (trimmed as NSString).expandingTildeInPath) : folder.appendingPathComponent(name)
        } else {
            var relative = Substring(name.trimmingCharacters(in: .whitespaces))
            while relative.hasPrefix("/") { relative = relative.dropFirst() }
            url = FilenamePattern.file(named: String(relative.isEmpty ? "Greenshot" : relative), in: folder)
        }
        return url.appendingPathExtension(fileExtension)
    }
}
