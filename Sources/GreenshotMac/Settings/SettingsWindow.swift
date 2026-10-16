// Greenshot for Mac (Community) - an unofficial macOS port of Greenshot
// Copyright (C) 2026 Greenshot for Mac (Community) contributors
// Based on Greenshot, Copyright (C) 2007-2026 Thomas Braun, Jens Klingen, Robin Krom
// SPDX-License-Identifier: GPL-3.0-or-later

import AppKit
import GreenshotCore
import SwiftUI

@MainActor
final class SettingsWindowController: NSWindowController, NSWindowDelegate {
    init(settings: SettingsStore) {
        let hosting = NSHostingController(rootView: SettingsView(store: settings, status: SystemStatus()))
        hosting.sizingOptions = .preferredContentSize
        let window = NSWindow(contentViewController: hosting)
        window.title = "\(AppInfo.name) Settings"
        window.styleMask = [.titled, .closable]
        window.isReleasedWhenClosed = false
        // Like the editors: come to the Space the user is on (also over a full screen app) and hide when another
        // app is clicked, rather than staying open on another Space where opening the app again can't be seen.
        window.collectionBehavior = [.moveToActiveSpace, .fullScreenAuxiliary]
        window.hidesOnDeactivate = true
        super.init(window: window)
        window.delegate = self
        window.center()
    }

    /// A backstop for the shortcut recorder: whatever happened, the hotkeys are on again once Settings closes.
    func windowWillClose(_ notification: Notification) {
        NotificationCenter.default.post(name: ShortcutRecorderButton.recordingDidEnd, object: self)
        isOpen = false
        onOpenChange?()
    }

    required init?(coder: NSCoder) {
        fatalError("not used")
    }

    /// Open from show() until the window is closed (also while it is hidden because another app is active).
    private(set) var isOpen = false
    var onOpenChange: (() -> Void)?

    func show() {
        if !isOpen {
            isOpen = true
            onOpenChange?()
        }
        NSApp.activate()
        showWindow(nil)
        window?.makeKeyAndOrderFront(nil)
    }
}

struct SettingsView: View {
    @ObservedObject var store: SettingsStore
    /// Owned by the window controller, so it lives as long as the window.
    @ObservedObject var status: SystemStatus
    /// Shows one fixed tab (for `--snapshot`); nil lets the user switch tabs.
    var initialTab: Int?

    var body: some View {
        Group {
            if let initialTab {
                TabView(selection: .constant(initialTab)) { tabs }
            } else {
                TabView { tabs }
            }
        }
        .frame(width: 580, height: 600)
        .padding(.vertical, 8)
    }

    @ViewBuilder private var tabs: some View {
        GeneralSettings(store: store, status: status).tabItem { Label("General", systemImage: "gearshape") }.tag(0)
        CaptureSettings(store: store).tabItem { Label("Capture", systemImage: "camera.viewfinder") }.tag(1)
        OutputSettings(store: store).tabItem { Label("Output", systemImage: "square.and.arrow.down") }.tag(2)
        DestinationsSettings(store: store).tabItem { Label("Destinations", systemImage: "paperplane") }.tag(3)
        PrinterSettings(store: store).tabItem { Label("Printer", systemImage: "printer") }.tag(4)
    }
}

/// What the General tab shows about the system. (An ObservableObject rather than `@State`: SwiftUI's `@State`
/// is a macro whose plugin only ships with Xcode, and the app builds with the Command Line Tools alone.)
@MainActor
final class SystemStatus: ObservableObject {
    @Published var launchAtLogin = LaunchAtLogin.state != .off
    @Published var loginNeedsApproval = LaunchAtLogin.state == .needsApproval
    @Published var loginError: String?
    @Published var canRecordScreen = CGPreflightScreenCaptureAccess()

    func setLaunchAtLogin(_ on: Bool) {
        let message = LaunchAtLogin.set(on)
        refresh()
        // Waiting for approval has its own hint and button; anything else is an error.
        loginError = loginNeedsApproval ? nil : message
    }

    func refresh() {
        canRecordScreen = CGPreflightScreenCaptureAccess()
        let state = LaunchAtLogin.state
        launchAtLogin = state != .off
        loginNeedsApproval = state == .needsApproval
    }
}
