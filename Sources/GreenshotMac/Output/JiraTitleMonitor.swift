// Greenshot for Mac (Community) - an unofficial macOS port of Greenshot
// Copyright (C) 2026 Greenshot for Mac (Community) contributors
// Based on Greenshot, Copyright (C) 2007-2026 Thomas Braun, Jens Klingen, Robin Krom
// SPDX-License-Identifier: GPL-3.0-or-later

import AppKit
import GreenshotCore

private let log = Log("Jira")

/// Watches the window titles for Jira issue keys, so the destination picker and the upload window offer the issues the
/// user looked at recently (upstream `Greenshot.Plugin.Jira/Monitoring/JiraMonitor.cs`). Upstream listens to every title
/// change of every window; macOS tells an app about other apps' title changes only with the Accessibility permission, so
/// the monitor reads the titles of the windows on screen (`CGWindowListCopyWindowInfo`, which needs the Screen Recording
/// permission Greenshot asks for anyway) every two seconds and when another app comes to the front. `JiraRecentIssues`
/// keeps the keys; without the permission the titles are empty and nothing is found (nothing is asked).
///
/// It runs only while Jira is set up (`JiraRecentIssues.watches`), and not while the displays sleep, the screen is
/// locked or another user has the session. The titles are never logged or saved, and only the keys stay, in memory.
/// The projects of the Jira (`projects(for:)`, so only keys of its projects are looked up, like upstream) are read
/// once per site when the picker or the upload window first needs them; another Jira forgets them and the keys.
@MainActor
final class JiraTitleMonitor {
    static let shared = JiraTitleMonitor()

    /// The keys seen so far.
    private(set) var recent = JiraRecentIssues()
    /// How often the titles are read, seconds.
    static let interval: TimeInterval = 2

    /// Why the titles aren't read just now.
    private enum Pause: Hashable {
        case displaysAsleep, sessionInactive, screenLocked
    }

    private var timer: Timer?
    private var observers: [(center: NotificationCenter, token: NSObjectProtocol)] = []
    private var pauses: Set<Pause> = []
    private weak var settings: SettingsStore?
    private var started = false
    /// The Jira the keys belong to (its address), to forget them when another one is set up.
    private var watchedURL: String?
    /// Who signs in where: another account may see other projects.
    private var signIn: String?
    /// The projects of `projectsSite`, once read; the running request.
    private var projectsSite: String?
    private var projectsTask: Task<Set<String>?, Never>?

    /// At launch; samples only while Jira is set up (its URL and user), follows changes of `jira`.
    func start(settings: SettingsStore) {
        guard !started else { return }
        started = true
        self.settings = settings
        settings.onChange(of: \.jira) { [weak self] _ in self?.update() }
        observePauses()
        update()
    }

    /// The keys for the picker and the upload window: the ones seen in changed titles (newest first), then `onScreen`,
    /// then `uploadedTo`; only keys of the Jira's projects once they are known.
    func keys(onScreen: [String] = [], uploadedTo: [String], limit: Int = JiraRecentIssues.maxEntries) -> [String] {
        recent.merged(onScreen: onScreen, uploadedTo: uploadedTo, limit: limit)
    }

    /// A key the server doesn't know (a title with "UTF-8" in it): not offered again.
    func forget(_ key: String) {
        recent.forget(key)
    }

    /// The project keys of the Jira `client` talks to, read once per site and kept in memory (upstream reads them when it
    /// signs in); nil when they can't be read (offline, not allowed): then nothing is looked up.
    func projects(for client: JiraClient) async -> Set<String>? {
        let site = client.site.baseURL.absoluteString
        if projectsSite != site {
            projectsTask?.cancel()
            projectsSite = site
            projectsTask = Task {
                do {
                    return try await client.projectKeys()
                } catch {
                    log.warn("The projects of the Jira could not be read", error: error)
                    return nil
                }
            }
        }
        guard let task = projectsTask else { return nil }
        let projects = await task.value
        // Another Jira may have been set up while it was read.
        guard projectsSite == site else { return nil }
        if projects == nil {
            // Try again next time.
            projectsSite = nil
            projectsTask = nil
        } else if recent.projects != projects {
            recent.setProjects(projects)
        }
        return projects
    }

    /// Titles as if they had been read from the screen, for the snapshots.
    func observeForSnapshots(_ titles: [String]) {
        recent.observe(titles.enumerated().map { (id: UInt32($0.offset + 1), title: $0.element) }, at: Date())
    }

    // MARK: Running

    private func update() {
        let jira = settings?.value.jira
        let watching = jira.map(JiraRecentIssues.watches) ?? false
        let url = watching ? jira?.url.trimmingCharacters(in: .whitespaces) : nil
        let account = jira.map { "\($0.url)\n\($0.login.rawValue)\n\($0.email)" }
        if url != watchedURL {
            // Another Jira (or none): its keys go (the same keys may mean other issues there).
            recent = JiraRecentIssues()
            watchedURL = url
        }
        if account != signIn {
            // Another site or account: its projects are read again.
            projectsTask?.cancel()
            projectsTask = nil
            projectsSite = nil
            recent.setProjects(nil)
            signIn = account
        }
        schedule()
    }

    /// The timer runs while Jira is set up and nothing pauses it.
    private func schedule() {
        let runs = watchedURL != nil && pauses.isEmpty
        if runs, timer == nil {
            let timer = Timer(timeInterval: Self.interval, repeats: true) { _ in
                MainActor.assumeIsolated { JiraTitleMonitor.shared.sample() }
            }
            timer.tolerance = 1
            RunLoop.main.add(timer, forMode: .common)
            self.timer = timer
            sample()
        } else if !runs, let timer {
            timer.invalidate()
            self.timer = nil
        }
    }

    /// Another app in front: a reading at once. Displays asleep, the session switched away (fast user switching) or the
    /// screen locked: no readings until they are back.
    private func observePauses() {
        let workspace = NSWorkspace.shared.notificationCenter
        observe(workspace, NSWorkspace.didActivateApplicationNotification) { $0.sampleIfRunning() }
        observe(workspace, NSWorkspace.screensDidSleepNotification) { $0.pause(.displaysAsleep, true) }
        observe(workspace, NSWorkspace.screensDidWakeNotification) { $0.pause(.displaysAsleep, false) }
        observe(workspace, NSWorkspace.sessionDidResignActiveNotification) { $0.pause(.sessionInactive, true) }
        observe(workspace, NSWorkspace.sessionDidBecomeActiveNotification) { $0.pause(.sessionInactive, false) }
        let distributed = DistributedNotificationCenter.default()
        observe(distributed, Notification.Name("com.apple.screenIsLocked")) { $0.pause(.screenLocked, true) }
        observe(distributed, Notification.Name("com.apple.screenIsUnlocked")) { $0.pause(.screenLocked, false) }
    }

    private func observe(_ center: NotificationCenter, _ name: Notification.Name, _ action: @escaping (JiraTitleMonitor) -> Void) {
        let token = center.addObserver(forName: name, object: nil, queue: .main) { _ in
            MainActor.assumeIsolated { action(JiraTitleMonitor.shared) }
        }
        observers.append((center, token))
    }

    private func pause(_ reason: Pause, _ on: Bool) {
        if on { pauses.insert(reason) } else { pauses.remove(reason) }
        schedule()
    }

    private func sampleIfRunning() {
        if timer != nil { sample() }
    }

    /// One reading of the titles of the normal windows on screen (not Greenshot's own).
    private func sample() {
        guard CGPreflightScreenCaptureAccess() else { return }
        let windows = ScreenCapturer.onScreenWindows().map { (id: UInt32($0.id), title: $0.title) }
        recent.observe(windows, at: Date())
    }
}
