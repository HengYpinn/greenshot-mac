// Greenshot for Mac (Community) - an unofficial macOS port of Greenshot
// Copyright (C) 2026 Greenshot for Mac (Community) contributors
// Based on Greenshot, Copyright (C) 2007-2026 Thomas Braun, Jens Klingen, Robin Krom
// SPDX-License-Identifier: GPL-3.0-or-later

import AppKit
import GreenshotCore
import SwiftUI

/// Settings › General (upstream's General tab): hotkeys (`HotkeysSection`), the app (appearance, startup, Dock), the
/// menu bar icon (upstream's ini-only `LeftClickAction`, `DoubleClickAction`, `HideTrayicon`), updates, permissions.
struct GeneralSettings: View {
    @ObservedObject var store: SettingsStore
    @ObservedObject var status: SystemStatus

    var body: some View {
        Form {
            HotkeysSection(store: store)
            Section("Application") {
                // Upstream "Colors": Same as Windows / Light / Dark.
                Picker("Appearance", selection: store.binding(\.theme)) {
                    ForEach(AppTheme.allCases, id: \.self) { Text($0.displayName).tag($0) }
                }
                Toggle("Launch at login", isOn: Binding(get: { status.launchAtLogin }, set: { status.setLaunchAtLogin($0) }))
                Toggle("Show in Dock while a window is open", isOn: store.binding(\.dockIconWhileWindowOpen))
                    .help("""
                        A Dock icon and a place in ⌘Tab while an editor or Settings is open; the menu bar icon is there \
                        either way, unless it is hidden below. Off: opening an editor from a full screen app stays on its Space instead of switching to \
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
            menuBarSection
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
            // The menu bar icon can be hidden (behind the notch, by macOS's menu bar settings or above), and it is the
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

    private var menuBarSection: some View {
        Section {
            Toggle("Show the menu bar icon", isOn: showIcon)
            Picker("Click", selection: store.binding(\.leftClickAction)) {
                ForEach(ClickAction.allCases, id: \.self) { Text($0.displayName).tag($0) }
            }
            Picker("Double-click", selection: store.binding(\.doubleClickAction)) {
                ForEach(ClickAction.allCases, id: \.self) { Text($0.displayName).tag($0) }
            }
            .disabled(MenuBarClick.clickShowsMenu(store.value.leftClickAction))
        } header: {
            Text("Menu bar icon")
        } footer: {
            Text(MenuBarClick.clickShowsMenu(store.value.leftClickAction)
                 ? "The menu opens on the first click, so a double-click does nothing more. Right-click or ⌃-click always shows the menu."
                 : "Right-click or ⌃-click shows the menu. With a double-click action, a click waits the double-click time first.")
                .font(.caption).foregroundStyle(.secondary)
        }
    }

    /// Hiding the icon asks first and says how to come back (upstream's `HideTrayicon` is for admins in the ini file).
    private var showIcon: Binding<Bool> {
        Binding(get: { !store.value.hideMenuBarIcon }, set: { show in
            if show {
                store.update { $0.hideMenuBarIcon = false }
            } else {
                // After SwiftUI finished the toggle; it shows "on" until the user confirms.
                DispatchQueue.main.async { confirmHidingIcon() }
            }
        })
    }

    private func confirmHidingIcon() {
        let alert = NSAlert()
        alert.messageText = "Hide the menu bar icon?"
        alert.informativeText = """
            The hotkeys keep working. To come back to Settings, open \(AppInfo.name) again from Spotlight, Launchpad or \
            the Applications folder.
            """
        alert.addButton(withTitle: "Hide Icon")
        alert.addButton(withTitle: "Cancel")
        let hide = { [store] in store.update { $0.hideMenuBarIcon = true } }
        if let window = NSApp.keyWindow {
            alert.beginSheetModal(for: window) { if $0 == .alertFirstButtonReturn { hide() } }
        } else if alert.runModal() == .alertFirstButtonReturn {
            hide()
        }
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
