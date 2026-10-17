// Greenshot for Mac (Community) - an unofficial macOS port of Greenshot
// Copyright (C) 2026 Greenshot for Mac (Community) contributors
// Based on Greenshot, Copyright (C) 2007-2026 Thomas Braun, Jens Klingen, Robin Krom
// SPDX-License-Identifier: GPL-3.0-or-later

import Foundation

/// The logic of upstream `Greenshot/Helpers/UpdateService.cs`, for this port's GitHub releases: when a check is
/// due, what the latest release says, and whether its version is newer.
public enum UpdateCheck {
    /// The newest stable release (GitHub leaves out drafts and pre-releases here).
    public static let latestReleaseURL = URL(string: "https://api.github.com/repos/HengYpinn/greenshot-mac/releases/latest")!
    /// The recent releases, pre-releases included, for "Check for unstable updates" (upstream `CheckForUnstable`).
    public static let releasesURL = URL(string: "https://api.github.com/repos/HengYpinn/greenshot-mac/releases?per_page=20")!

    public struct Release: Equatable, Sendable {
        public var version: String
        public var pageURL: URL
        /// A beta (GitHub "pre-release"), upstream's `LatestBetaVersion`.
        public var isPrerelease: Bool

        public init(version: String, pageURL: URL, isPrerelease: Bool = false) {
            self.version = version
            self.pageURL = pageURL
            self.isPrerelease = isPrerelease
        }
    }

    /// A check is due when the interval (days, 0 = never) has passed since the last one, or there was none.
    public static func isDue(lastCheck: Date?, intervalDays: Int, now: Date = Date()) -> Bool {
        guard intervalDays > 0 else { return false }
        guard let lastCheck else { return true }
        return now.timeIntervalSince(lastCheck) >= Double(intervalDays) * 24 * 60 * 60
    }

    /// The `tag_name` and `html_url` of GitHub's "latest release" answer; nil for anything else, a draft or a
    /// pre-release.
    public static func release(fromJSON data: Data) -> Release? {
        guard let object = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              let release = release(from: object), !release.isPrerelease else { return nil }
        return release
    }

    /// The newest release in GitHub's list of releases, by version; drafts never, pre-releases only when
    /// `includePrereleases`. Nil when there is none or the answer is no list.
    public static func newestRelease(fromListJSON data: Data, includePrereleases: Bool) -> Release? {
        guard let list = try? JSONSerialization.jsonObject(with: data) as? [[String: Any]] else { return nil }
        let releases = list.compactMap(release(from:)).filter { includePrereleases || !$0.isPrerelease }
        return releases.dropFirst().reduce(releases.first) { newest, release in
            guard let newest else { return release }
            return isNewer(release.version, than: newest.version) ? release : newest
        }
    }

    private static func release(from object: [String: Any]) -> Release? {
        guard let tag = object["tag_name"] as? String,
              let page = (object["html_url"] as? String).flatMap(URL.init(string:)),
              object["draft"] as? Bool != true else { return nil }
        return Release(version: normalized(tag), pageURL: page, isPrerelease: object["prerelease"] as? Bool == true)
    }

    /// "v1.2.3" → "1.2.3".
    public static func normalized(_ version: String) -> String {
        var text = version.trimmingCharacters(in: .whitespaces)
        if text.first == "v" || text.first == "V" { text.removeFirst() }
        return text
    }

    /// Compares dotted versions number by number ("1.10" is newer than "1.9", "1.2" equals "1.2.0"). With the same
    /// numbers a release is newer than its pre-releases ("1.5.0" > "1.5.0-beta.2" > "1.5.0-beta.1"), compared part by
    /// part like semantic versioning; build metadata after "+" is ignored.
    public static func isNewer(_ candidate: String, than current: String) -> Bool {
        let a = numbers(candidate)
        let b = numbers(current)
        for i in 0..<max(a.count, b.count) {
            let x = i < a.count ? a[i] : 0
            let y = i < b.count ? b[i] : 0
            if x != y { return x > y }
        }
        switch (prerelease(candidate), prerelease(current)) {
        case (nil, nil), (.some, nil): return false
        case (nil, .some): return true
        case let (.some(p), .some(q)): return isNewerPrerelease(p, than: q)
        }
    }

    static func numbers(_ version: String) -> [Int] {
        coreVersion(version).split(separator: ".").map { part in
            Int(part.prefix(while: { $0.isNumber })) ?? 0
        }
    }

    /// "1.2.0-beta.1+42" → "1.2.0".
    private static func coreVersion(_ version: String) -> Substring {
        let text = normalized(version)
        return text.prefix { $0 != "-" && $0 != "+" }
    }

    /// "1.2.0-beta.1+42" → ["beta", "1"]; nil without a pre-release part.
    private static func prerelease(_ version: String) -> [Substring]? {
        let text = normalized(version)
        guard let dash = text.firstIndex(of: "-") else { return nil }
        let rest = text[text.index(after: dash)...].prefix { $0 != "+" }
        return rest.isEmpty ? nil : rest.split(separator: ".", omittingEmptySubsequences: false)
    }

    /// Semantic versioning: numbers compare as numbers and before words, words alphabetically; more parts is newer
    /// when the shared ones are equal.
    private static func isNewerPrerelease(_ a: [Substring], than b: [Substring]) -> Bool {
        for (x, y) in zip(a, b) where x != y {
            switch (Int(x), Int(y)) {
            case let (.some(m), .some(n)): return m > n
            case (.some, nil): return false
            case (nil, .some): return true
            case (nil, nil): return x.lowercased() > y.lowercased()
            }
        }
        return a.count > b.count
    }
}
