// Greenshot for Mac (Community) - an unofficial macOS port of Greenshot
// Copyright (C) 2026 Greenshot for Mac (Community) contributors
// Based on Greenshot, Copyright (C) 2007-2026 Thomas Braun, Jens Klingen, Robin Krom
// SPDX-License-Identifier: GPL-3.0-or-later

import Foundation

/// The logic of upstream `Greenshot/Helpers/UpdateService.cs`, for this port's GitHub releases: when a check is
/// due, what the latest release says, and whether its version is newer.
public enum UpdateCheck {
    public static let latestReleaseURL = URL(string: "https://api.github.com/repos/HengYpinn/greenshot-mac/releases/latest")!

    public struct Release: Equatable, Sendable {
        public var version: String
        public var pageURL: URL

        public init(version: String, pageURL: URL) {
            self.version = version
            self.pageURL = pageURL
        }
    }

    /// A check is due when the interval (days, 0 = never) has passed since the last one, or there was none.
    public static func isDue(lastCheck: Date?, intervalDays: Int, now: Date = Date()) -> Bool {
        guard intervalDays > 0 else { return false }
        guard let lastCheck else { return true }
        return now.timeIntervalSince(lastCheck) >= Double(intervalDays) * 24 * 60 * 60
    }

    /// The `tag_name` and `html_url` of GitHub's "latest release" answer; nil for anything else.
    public static func release(fromJSON data: Data) -> Release? {
        guard let object = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              let tag = object["tag_name"] as? String,
              let page = (object["html_url"] as? String).flatMap(URL.init(string:)) else { return nil }
        if object["draft"] as? Bool == true || object["prerelease"] as? Bool == true { return nil }
        return Release(version: normalized(tag), pageURL: page)
    }

    /// "v1.2.3" → "1.2.3".
    public static func normalized(_ version: String) -> String {
        var text = version.trimmingCharacters(in: .whitespaces)
        if text.first == "v" || text.first == "V" { text.removeFirst() }
        return text
    }

    /// Compares dotted versions number by number ("1.10" is newer than "1.9", "1.2" equals "1.2.0"). Anything
    /// after the numbers (e.g. "-beta") is ignored.
    public static func isNewer(_ candidate: String, than current: String) -> Bool {
        let a = numbers(candidate)
        let b = numbers(current)
        for i in 0..<max(a.count, b.count) {
            let x = i < a.count ? a[i] : 0
            let y = i < b.count ? b[i] : 0
            if x != y { return x > y }
        }
        return false
    }

    static func numbers(_ version: String) -> [Int] {
        normalized(version).split(separator: ".").map { part in
            Int(part.prefix(while: { $0.isNumber })) ?? 0
        }
    }
}
