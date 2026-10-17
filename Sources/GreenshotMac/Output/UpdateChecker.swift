// Greenshot for Mac (Community) - an unofficial macOS port of Greenshot
// Copyright (C) 2026 Greenshot for Mac (Community) contributors
// Based on Greenshot, Copyright (C) 2007-2026 Thomas Braun, Jens Klingen, Robin Krom
// SPDX-License-Identifier: GPL-3.0-or-later

import AppKit
import GreenshotCore

/// Looks for a newer release on GitHub: port of upstream `Greenshot/Helpers/UpdateService.cs` (every
/// `updateCheckIntervalDays` days, 0 never). A newer version shows a message that opens the release page; no
/// release, an error or no network say nothing (unless the user asked) and count as checked. With "Check for unstable
/// updates" (upstream `CheckForUnstable`) pre-releases count too; upstream shows its beta whenever the feed has one,
/// here only with that setting.
@MainActor
enum UpdateChecker {
    static var currentVersion: String {
        Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? "0"
    }

    static func checkIfDue(settings: SettingsStore, saver: ImageSaver) {
        let s = settings.value
        guard UpdateCheck.isDue(lastCheck: s.lastUpdateCheck, intervalDays: s.updateCheckIntervalDays) else { return }
        check(settings: settings, saver: saver, userAsked: false)
    }

    /// `userAsked` (Settings › General › Check Now) also says when there is nothing new or the check failed.
    static func check(settings: SettingsStore, saver: ImageSaver, userAsked: Bool) {
        let unstable = settings.value.checkForUnstable
        var request = URLRequest(url: unstable ? UpdateCheck.releasesURL : UpdateCheck.latestReleaseURL, timeoutInterval: 20)
        request.setValue("application/vnd.github+json", forHTTPHeaderField: "Accept")
        let version = currentVersion
        URLSession.shared.dataTask(with: request) { data, response, error in
            let status = (response as? HTTPURLResponse)?.statusCode ?? 0
            let release = status == 200 ? data.flatMap { data in
                unstable ? UpdateCheck.newestRelease(fromListJSON: data, includePrereleases: true) : UpdateCheck.release(fromJSON: data)
            } : nil
            let failed = error != nil || (status != 200 && status != 404)
            DispatchQueue.main.async {
                MainActor.assumeIsolated {
                    settings.update { $0.lastUpdateCheck = Date() }
                    finish(release: release, failed: failed, current: version, saver: saver, userAsked: userAsked)
                }
            }
        }.resume()
    }

    private static func finish(release: UpdateCheck.Release?, failed: Bool, current: String, saver: ImageSaver, userAsked: Bool) {
        if let release, UpdateCheck.isNewer(release.version, than: current) {
            let page = release.pageURL
            // A warning, so "Show a message after saving or copying" doesn't hide it; the message level does
            // (after "Check Now" it counts as an error, shown at every level but None).
            let name = release.isPrerelease ? "Beta version" : "Version"
            saver.notify("\(name) \(release.version) is available – click to download", detail: "You have \(current).",
                         kind: userAsked ? .error : .warning) {
                NSWorkspace.shared.open(page)
            }
            return
        }
        guard userAsked else { return }
        if failed {
            saver.notify("Could not check for updates", detail: "GitHub could not be reached.", kind: .warning)
        } else {
            Toast.show("\(AppInfo.name) is up to date", detail: "Version \(current).")
        }
    }
}
