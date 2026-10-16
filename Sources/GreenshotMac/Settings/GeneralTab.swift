// Greenshot for Mac (Community) - an unofficial macOS port of Greenshot
// Copyright (C) 2026 Greenshot for Mac (Community) contributors
// Based on Greenshot, Copyright (C) 2007-2026 Thomas Braun, Jens Klingen, Robin Krom
// SPDX-License-Identifier: GPL-3.0-or-later

import AppKit
import GreenshotCore
import SwiftUI

/// Settings › General (upstream's General tab): hotkeys, startup, permissions.
struct GeneralSettings: View {
    @ObservedObject var store: SettingsStore
    @ObservedObject var status: SystemStatus

    var body: some View {
        Form {
            Section {
                LabeledContent("Capture region") { ShortcutRecorder(combo: store.binding(\.hotkeys.region)) }
                LabeledContent("Capture window") { ShortcutRecorder(combo: store.binding(\.hotkeys.window)) }
                LabeledContent("Capture full screen") { ShortcutRecorder(combo: store.binding(\.hotkeys.fullScreen)) }
                LabeledContent("Capture last region") { ShortcutRecorder(combo: store.binding(\.hotkeys.lastRegion)) }
                LabeledContent("Open image from clipboard") { ShortcutRecorder(combo: store.binding(\.hotkeys.clipboard)) }
            } header: {
                Text("Hotkeys")
            } footer: {
                Text("Click a shortcut, then type the new one. ⌫ clears it, ⎋ cancels. Keyboards with an F13 key can use it like Print Screen.")
                    .font(.caption).foregroundStyle(.secondary)
            }
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
}
