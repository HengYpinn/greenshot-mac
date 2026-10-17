// Greenshot for Mac (Community) - an unofficial macOS port of Greenshot
// Copyright (C) 2026 Greenshot for Mac (Community) contributors
// Based on Greenshot, Copyright (C) 2007-2026 Thomas Braun, Jens Klingen, Robin Krom
// SPDX-License-Identifier: GPL-3.0-or-later

import AppKit
import GreenshotCore
import SwiftUI

@MainActor
final class SettingsWindowController: NSWindowController, NSWindowDelegate {
    /// The tab shown; `show(pane:)` switches it.
    private let navigation = SettingsNavigation()

    init(settings: SettingsStore) {
        let hosting = NSHostingController(rootView: SettingsView(store: settings, status: SystemStatus(), navigation: navigation))
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

    /// Opens the window, on `pane` when given (upstream `SettingsWindow.SelectTab`), else on the tab shown last.
    func show(pane: SettingsPane? = nil) {
        if let pane { navigation.tab = pane.rawValue }
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
    /// The tab shown when `initialTab` is nil.
    @ObservedObject var navigation = SettingsNavigation()

    var body: some View {
        Group {
            if let initialTab {
                TabView(selection: .constant(initialTab)) { tabs }
            } else {
                TabView(selection: $navigation.tab) { tabs }
            }
        }
        .frame(width: 620, height: 600)
        .padding(.vertical, 8)
    }

    @ViewBuilder private var tabs: some View {
        GeneralSettings(store: store, status: status).tabItem { Label("General", systemImage: "gearshape") }.tag(SettingsPane.general.rawValue)
        CaptureSettings(store: store).tabItem { Label("Capture", systemImage: "camera.viewfinder") }.tag(SettingsPane.capture.rawValue)
        OutputSettings(store: store).tabItem { Label("Output", systemImage: "square.and.arrow.down") }.tag(SettingsPane.output.rawValue)
        DestinationsSettings(store: store).tabItem { Label("Destinations", systemImage: "paperplane") }.tag(SettingsPane.destinations.rawValue)
        EditorSettings(store: store).tabItem { Label("Editor", systemImage: "pencil.and.outline") }.tag(SettingsPane.editor.rawValue)
        PrinterSettings(store: store).tabItem { Label("Printer", systemImage: "printer") }.tag(SettingsPane.printer.rawValue)
        ExpertSettings(store: store).tabItem { Label("Expert", systemImage: "wrench.and.screwdriver") }.tag(SettingsPane.expert.rawValue)
    }
}

/// The selected tab of the settings window: the tag of a tab, `SettingsPane.rawValue`. (An ObservableObject for the same
/// reason as `SystemStatus`.)
@MainActor
final class SettingsNavigation: ObservableObject {
    @Published var tab = SettingsPane.general.rawValue
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
