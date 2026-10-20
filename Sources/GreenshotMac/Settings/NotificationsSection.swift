// Greenshot for Mac (Community) - an unofficial macOS port of Greenshot
// Copyright (C) 2026 Greenshot for Mac (Community) contributors
// Based on Greenshot, Copyright (C) 2007-2026 Thomas Braun, Jens Klingen, Robin Krom
// SPDX-License-Identifier: GPL-3.0-or-later

import AppKit
import GreenshotCore
import SwiftUI

/// Settings › Capture › Notifications: upstream's notification options on the Capture tab
/// (`Greenshot/Settings/ViewModels/SettingsViewModel.Notifications.cs`): which notifications are shown, the thumbnail,
/// and whether macOS lets the app notify.
struct NotificationSettings: View {
    @ObservedObject var store: SettingsStore
    @StateObject private var status: NotificationStatus

    /// `state` fixes what macOS says, for the snapshots.
    init(store: SettingsStore, state: NotificationState? = nil) {
        self.store = store
        _status = StateObject(wrappedValue: NotificationStatus(fixed: state))
    }

    var body: some View {
        Section {
            Picker("Show notifications", selection: level) {
                ForEach(NotificationLevel.allCases, id: \.self) { Text($0.displayName).tag($0) }
            }
            .managed(\.notificationLevel, \.showNotifications)
            // Only notifications that can show the capture offer the thumbnail (upstream `CanShowNotificationThumbnail`).
            if status.state == .allowed || status.state == .notAsked {
                Toggle("Show a thumbnail of the capture in the notification", isOn: store.binding(\.showNotificationThumbnail))
                    .disabled(level.wrappedValue == .none)
                    .managed(\.showNotificationThumbnail)
            }
            LabeledContent("macOS notifications") {
                HStack {
                    Text(stateText).foregroundStyle(.secondary).multilineTextAlignment(.trailing)
                    stateButton
                }
            }
        } header: {
            Text("Notifications")
        } footer: {
            Text(footer).font(.caption).foregroundStyle(.secondary)
                .multilineTextAlignment(.leading).frame(maxWidth: .infinity, alignment: .leading)
        }
        .onAppear { status.refresh() }
    }

    /// Upstream `SelectedNotificationLevel`: None also turns off `showNotifications` (`setNotificationsShown`, like
    /// Quick Settings › Show Notifications).
    private var level: Binding<NotificationLevel> {
        Binding(get: { store.value.notificationsShown ? store.value.notificationLevel : .none },
                set: { newValue in
                    store.update { values in
                        if newValue != .none { values.notificationLevel = newValue }
                        values.setNotificationsShown(newValue != .none)
                    }
                })
    }

    private var stateText: String {
        switch status.state {
        case .inApp: return String(localized: "Not available, messages appear in the corner")
        case .refused: return String(localized: "Refused for this build, messages appear in the corner")
        case .notAsked: return String(localized: "Asked with the first notification")
        case .allowed: return String(localized: "Allowed", comment: "macOS allows the app's notifications")
        case .off: return String(localized: "Off for this app: no notifications")
        }
    }

    @ViewBuilder private var stateButton: some View {
        switch status.state {
        case .inApp:
            EmptyView()
        case .notAsked:
            Button("Allow…") { status.ask() }
        case .allowed, .off, .refused:
            Button("Notification Settings…") { NotificationStatus.openSystemSettings() }
        }
    }

    private var footer: String {
        switch status.state {
        case .inApp:
            return String(localized: "macOS notifications need the app bundle (scripts/build-app.sh); without it messages appear in the top right corner.")
        case .allowed, .notAsked:
            return String(localized: """
                After a capture one notification lists where it went. Click it within an hour to send the capture somewhere \
                else, also after a restart. Focus and Do Not Disturb hold notifications back like those of other apps.
                """)
        case .off:
            return String(localized: "Turn on Allow Notifications for \(AppInfo.name) in System Settings › Notifications to see them again.")
        case .refused:
            return String(localized: "macOS didn't let this build post notifications. A build signed with a stable identity usually can (see the README).")
        }
    }
}

/// What macOS says about the app's notifications, kept up to date for the settings.
@MainActor
final class NotificationStatus: ObservableObject {
    @Published private(set) var state: NotificationState
    private let fixed: Bool
    private var observer: NSObjectProtocol?

    init(fixed: NotificationState? = nil) {
        state = fixed ?? NotificationService.shared.state
        self.fixed = fixed != nil
        guard !self.fixed else { return }
        observer = NotificationCenter.default.addObserver(forName: NotificationService.stateDidChange, object: nil, queue: .main) { [weak self] _ in
            MainActor.assumeIsolated { self?.state = NotificationService.shared.state }
        }
    }

    deinit {
        if let observer { NotificationCenter.default.removeObserver(observer) }
    }

    func refresh() {
        guard !fixed, let native = NotificationService.shared.native else { return }
        native.refreshStatus { [weak self] in self?.state = NotificationService.shared.state }
    }

    func ask() {
        guard !fixed, let native = NotificationService.shared.native else { return }
        native.requestPermission { [weak self] _ in self?.state = NotificationService.shared.state }
    }

    /// System Settings › Notifications, on the app's page when macOS knows it.
    static func openSystemSettings() {
        let id = Bundle.main.bundleIdentifier.map { "?id=\($0)" } ?? ""
        if let url = URL(string: "x-apple.systempreferences:com.apple.Notifications-Settings.extension" + id) {
            NSWorkspace.shared.open(url)
        }
    }
}
