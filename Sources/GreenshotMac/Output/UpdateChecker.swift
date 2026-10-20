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
    private static let log = Log("Update")

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
        let version = currentVersion
        Task { @MainActor in
            let (release, failed) = await fetch(unstable: unstable)
            settings.update { $0.lastUpdateCheck = Date() }
            finish(release: release, failed: failed, current: version, saver: saver, userAsked: userAsked)
        }
    }

    /// The newest release without a message, for the setup checks and the bug report (upstream
    /// `CheckForUpdatesAsync(showNotification: false)`). Doesn't count as the regular check.
    static func fetchLatest(unstable: Bool) async -> UpdateCheck.Outcome {
        let (release, failed) = await fetch(unstable: unstable)
        return UpdateCheck.outcome(release: release, failed: failed, current: currentVersion)
    }

    private static func fetch(unstable: Bool) async -> (release: UpdateCheck.Release?, failed: Bool) {
        var request = URLRequest(url: unstable ? UpdateCheck.releasesURL : UpdateCheck.latestReleaseURL, timeoutInterval: 20)
        request.setValue("application/vnd.github+json", forHTTPHeaderField: "Accept")
        do {
            let (data, response) = try await URLSession.shared.data(for: request)
            let status = (response as? HTTPURLResponse)?.statusCode ?? 0
            let release = status == 200
                ? (unstable ? UpdateCheck.newestRelease(fromListJSON: data, includePrereleases: true) : UpdateCheck.release(fromJSON: data))
                : nil
            // 404: no release yet.
            let failed = status != 200 && status != 404
            if failed {
                log.warn("The update check got HTTP \(status)")
            } else {
                log.info("Update check: newest release \(release?.version ?? "none"), this is \(currentVersion)")
            }
            return (release, failed)
        } catch {
            log.warn("The update check failed", error: error)
            return (nil, true)
        }
    }

    private static func finish(release: UpdateCheck.Release?, failed: Bool, current: String, saver: ImageSaver, userAsked: Bool) {
        let outcome = UpdateCheck.outcome(release: release, failed: failed, current: current)
        switch UpdateCheck.notice(for: outcome, userAsked: userAsked) {
        case .newer(let release):
            let page = release.pageURL
            // A warning, so "Show a message after saving or copying" doesn't hide it; the message level does
            // (after "Check Now" it counts as an error, shown at every level but None).
            let version = release.version
            let title = release.isPrerelease ? String(localized: "Beta version \(version) is available – click to download")
                : String(localized: "Version \(version) is available – click to download")
            saver.notify(title, detail: String(localized: "You have \(current).", comment: "The version of the app the user has"),
                         kind: userAsked ? .error : .warning) {
                NSWorkspace.shared.open(page)
            }
        case .failed:
            saver.notify(String(localized: "Could not check for updates"), detail: String(localized: "GitHub could not be reached."), kind: .warning)
        case .upToDate:
            Toast.show(String(localized: "\(AppInfo.name) is up to date"), detail: String(localized: "Version \(current).", comment: "The version of the app"))
        case .noRelease:
            Toast.show(String(localized: "No release has been published yet."),
                       detail: String(localized: "Version \(current).", comment: "The version of the app"))
        case nil:
            break
        }
    }
}
