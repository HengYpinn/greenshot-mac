// Greenshot for Mac (Community) - an unofficial macOS port of Greenshot
// Copyright (C) 2026 Greenshot for Mac (Community) contributors
// Based on Greenshot, Copyright (C) 2007-2026 Thomas Braun, Jens Klingen, Robin Krom
// SPDX-License-Identifier: GPL-3.0-or-later

import Foundation

private let log = Log("Video")

/// Which window a recipe means: upstream `Greenshot.Base/Core/WindowHelper.FindMatchingWindow` (used by the RecordVideo
/// step and the active-window source): a part of the title, or a regular expression for it, and the process.
public struct WindowMatchQuery: Equatable, Sendable {
    /// A part of the title; used when there is no `titlePattern`.
    public var title: String?
    /// A regular expression for the title; an invalid one is logged and left out.
    public var titlePattern: String?
    /// The app: its name, its executable or its bundle identifier, with or without an extension (".app", ".exe").
    public var processName: String?
    public var matchCase: Bool

    public init(title: String? = nil, titlePattern: String? = nil, processName: String? = nil, matchCase: Bool = false) {
        self.title = title
        self.titlePattern = titlePattern
        self.processName = processName
        self.matchCase = matchCase
    }

    /// Nothing to match: the caller takes the active window.
    public var isEmpty: Bool {
        (title ?? "").isEmpty && (titlePattern ?? "").isEmpty && (processName ?? "").isEmpty
    }

    /// The active window when it matches, else the first matching window in `windows` (front to back), else nil.
    /// `names` are the names of a window's app (`processName` matches any of them).
    public func firstMatch<Window>(in windows: [Window], active: Window?, title: (Window) -> String,
                                   names: (Window) -> [String]) -> Window? {
        let regex = compiledPattern()
        func matches(_ window: Window) -> Bool {
            matchesWindow(title: title(window), names: names(window), regex: regex)
        }
        if let active, matches(active) { return active }
        return windows.first(where: matches)
    }

    /// Whether a window with this title and these app names matches.
    public func matches(title: String, names: [String]) -> Bool {
        matchesWindow(title: title, names: names, regex: compiledPattern())
    }

    private func compiledPattern() -> NSRegularExpression? {
        guard let pattern = titlePattern, !pattern.isEmpty else { return nil }
        do {
            return try NSRegularExpression(pattern: pattern, options: matchCase ? [] : [.caseInsensitive])
        } catch {
            log.warn("Invalid window title pattern '\(pattern)'", error: error)
            return nil
        }
    }

    private func matchesWindow(title caption: String, names: [String], regex: NSRegularExpression?) -> Bool {
        let options: String.CompareOptions = matchCase ? [] : [.caseInsensitive]
        if let wanted = processName, !wanted.isEmpty {
            let bare = (wanted as NSString).deletingPathExtension
            let found = names.contains { name in
                name.compare(wanted, options: options) == .orderedSame || name.compare(bare, options: options) == .orderedSame
            }
            if !found { return false }
        }
        if let regex {
            let range = NSRange(caption.startIndex..., in: caption)
            return regex.firstMatch(in: caption, range: range) != nil
        }
        guard let title, !title.isEmpty else { return true }
        return caption.range(of: title, options: options) != nil
    }
}
