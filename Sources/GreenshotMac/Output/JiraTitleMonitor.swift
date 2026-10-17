// Greenshot for Mac (Community) - an unofficial macOS port of Greenshot
// Copyright (C) 2026 Greenshot for Mac (Community) contributors
// Based on Greenshot, Copyright (C) 2007-2026 Thomas Braun, Jens Klingen, Robin Krom
// SPDX-License-Identifier: GPL-3.0-or-later

import AppKit
import GreenshotCore

/// Watches the window titles for Jira issue keys, so the destination picker and the upload window offer the issues the
/// user looked at recently (upstream `Greenshot.Plugin.Jira/Monitoring/JiraMonitor.cs`). Upstream listens to every title
/// change of every window; macOS tells an app about other apps' title changes only with the Accessibility permission, so
/// the monitor reads the titles of the windows on screen (`CGWindowListCopyWindowInfo`, which needs the Screen Recording
/// permission Greenshot asks for anyway) every two seconds and when another app comes to the front. `JiraRecentIssues`
/// keeps the keys; without the permission the titles are empty and nothing is found (nothing is asked).
///
/// It runs only while Jira is set up (`JiraRecentIssues.watches`). The titles are never logged or saved, and only the
/// keys stay, in memory; the server is asked for an issue's summary when the picker shows it, not here.
@MainActor
final class JiraTitleMonitor {
    static let shared = JiraTitleMonitor()

    /// The keys seen so far.
    private(set) var recent = JiraRecentIssues()
    /// How often the titles are read, seconds.
    static let interval: TimeInterval = 2

    private var timer: Timer?
    private var activation: NSObjectProtocol?
    private weak var settings: SettingsStore?
    private var started = false

    /// At launch; samples only while Jira is set up (its URL and user), follows changes of `jira`.
    func start(settings: SettingsStore) {
        guard !started else { return }
        started = true
        self.settings = settings
        settings.onChange(of: \.jira) { [weak self] _ in self?.update() }
        update()
    }

    /// The keys for the picker and the upload window: the ones seen in changed titles (newest first), then `onScreen`,
    /// then `uploadedTo`.
    func keys(onScreen: [String] = [], uploadedTo: [String], limit: Int = JiraRecentIssues.maxEntries) -> [String] {
        recent.merged(onScreen: onScreen, uploadedTo: uploadedTo, limit: limit)
    }

    /// A key the server doesn't know (a title with "UTF-8" in it): not offered again.
    func forget(_ key: String) {
        recent.forget(key)
    }

    /// Titles as if they had been read from the screen, for the snapshots.
    func observeForSnapshots(_ titles: [String]) {
        recent.observe(titles.enumerated().map { (id: UInt32($0.offset + 1), title: $0.element) }, at: Date())
    }

    private func update() {
        let watching = settings.map { JiraRecentIssues.watches($0.value.jira) } ?? false
        if watching, timer == nil {
            let timer = Timer(timeInterval: Self.interval, repeats: true) { _ in
                MainActor.assumeIsolated { JiraTitleMonitor.shared.sample() }
            }
            timer.tolerance = 1
            RunLoop.main.add(timer, forMode: .common)
            self.timer = timer
            activation = NSWorkspace.shared.notificationCenter.addObserver(
                forName: NSWorkspace.didActivateApplicationNotification, object: nil, queue: .main) { _ in
                    MainActor.assumeIsolated { JiraTitleMonitor.shared.sample() }
                }
            sample()
        } else if !watching, timer != nil {
            timer?.invalidate()
            timer = nil
            if let activation { NSWorkspace.shared.notificationCenter.removeObserver(activation) }
            activation = nil
            // Another Jira (or none): its issues go.
            recent = JiraRecentIssues()
        }
    }

    /// One reading of the titles of the normal windows on screen (not Greenshot's own).
    private func sample() {
        guard CGPreflightScreenCaptureAccess() else { return }
        let windows = ScreenCapturer.onScreenWindows().map { (id: UInt32($0.id), title: $0.title) }
        recent.observe(windows, at: Date())
    }
}
