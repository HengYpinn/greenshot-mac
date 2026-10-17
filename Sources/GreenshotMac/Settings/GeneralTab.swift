// Greenshot for Mac (Community) - an unofficial macOS port of Greenshot
// Copyright (C) 2026 Greenshot for Mac (Community) contributors
// Based on Greenshot, Copyright (C) 2007-2026 Thomas Braun, Jens Klingen, Robin Krom
// SPDX-License-Identifier: GPL-3.0-or-later

import AppKit
import GreenshotCore
import SwiftUI

/// Settings › General (upstream's General tab): hotkeys (`HotkeysSection`), startup, updates, permissions.
struct GeneralSettings: View {
    @ObservedObject var store: SettingsStore
    @ObservedObject var status: SystemStatus

    var body: some View {
        Form {
            HotkeysSection(store: store)
            Section("Startup") {
                Toggle("Launch at login", isOn: Binding(get: { status.launchAtLogin }, set: { status.setLaunchAtLogin($0) }))
                Toggle("Show in Dock while a window is open", isOn: store.binding(\.dockIconWhileWindowOpen))
                    .help("""
                        A Dock icon and a place in ⌘Tab while an editor or Settings is open; the menu bar icon is always \
                        there. Off: opening an editor from a full screen app stays on its Space instead of switching to \
                        the desktop.
                        """)
                if status.loginNeedsApproval {
                    HStack {
                        Text(LaunchAtLogin.approvalHint).font(.caption).foregroundStyle(.orange)
                        Button("Open Login Items") { LaunchAtLogin.openSystemSettings() }
                    }
                }
                if let loginError = status.loginError {
                    Text(loginError).font(.caption).foregroundStyle(.red)
                }
            }
            Section("Updates") {
                Stepper(value: store.binding(\.updateCheckIntervalDays), in: 0...365) {
                    Text(store.value.updateCheckIntervalDays == 0
                         ? "Never check for updates"
                         : "Check for updates every \(store.value.updateCheckIntervalDays) days")
                }
                HStack {
                    Text(lastCheck).font(.caption).foregroundStyle(.secondary)
                    Spacer()
                    Button("Check Now") { checkNow() }
                }
            }
            Section("Permissions") {
                LabeledContent("Screen recording") {
                    HStack {
                        Text(status.canRecordScreen ? "Allowed" : "Not allowed yet")
                            .foregroundStyle(status.canRecordScreen ? Color.secondary : Color.orange)
                        if !status.canRecordScreen {
                            Button("Open System Settings") { NSWorkspace.shared.open(Permissions.screenCaptureSettingsURL) }
                        }
                    }
                }
            }
            // The menu bar icon can be hidden (behind the notch, or by macOS's menu bar settings), and it is the
            // only other way to quit; opening the app again from Spotlight or Finder shows this window.
            Section {
                HStack {
                    Text("The menu bar icon hidden? Quit from here.").font(.caption).foregroundStyle(.secondary)
                    Spacer()
                    Button("Quit \(AppInfo.name)") { NSApp.terminate(nil) }
                }
            }
        }
        .formStyle(.grouped)
        .onAppear { status.refresh() }
    }

    private var lastCheck: String {
        guard let date = store.value.lastUpdateCheck else { return "Not checked yet. You have version \(UpdateChecker.currentVersion)." }
        let when = date.formatted(date: .abbreviated, time: .shortened)
        return "Last checked \(when). You have version \(UpdateChecker.currentVersion)."
    }

    private func checkNow() {
        guard let app = NSApp.delegate as? AppDelegate else { return }
        UpdateChecker.check(settings: store, saver: app.saver, userAsked: true)
    }
}
