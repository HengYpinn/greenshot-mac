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
    private let settings: SettingsStore

    init(settings: SettingsStore) {
        self.settings = settings
        let hosting = NSHostingController(rootView: SettingsView(store: settings, status: SystemStatus(), navigation: navigation))
        hosting.sizingOptions = .preferredContentSize
        let window = NSWindow(contentViewController: hosting)
        window.title = String(localized: "\(AppInfo.name) Settings")
        window.styleMask = [.titled, .closable]
        window.isReleasedWhenClosed = false
        // Like the editors: come to the Space the user is on (also over a full screen app) and hide when another
        // app is clicked, rather than staying open on another Space where opening the app again can't be seen.
        window.collectionBehavior = [.moveToActiveSpace, .fullScreenAuxiliary]
        window.hidesOnDeactivate = true
        super.init(window: window)
        window.delegate = self
        window.center()
        // An administrator can turn Settings or its Expert tab off while it is open.
        settings.onChange(of: \.disableSettings) { [weak self] off in
            if off { self?.close() }
        }
        settings.onChange(of: \.hideExpertSettings) { [weak self] hidden in
            guard let self, hidden, self.navigation.tab == SettingsPane.expert.rawValue else { return }
            self.navigation.tab = SettingsPane.general.rawValue
        }
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

    /// Opens the window, on `pane` when given (upstream `SettingsWindow.SelectTab`), else on the tab shown last. With
    /// Settings turned off by an administrator (upstream `DisableSettings`) it says so instead: every way to Settings
    /// (⌘,, the editor's button, a link, opening the app again) ends here.
    func show(pane: SettingsPane? = nil) {
        settings.refreshManaged()
        guard !settings.value.disableSettings else {
            Self.sayTurnedOff()
            return
        }
        if let pane { navigation.tab = pane.rawValue }
        // Upstream `HideExpertSettings`: the Expert tab is gone.
        if settings.value.hideExpertSettings && navigation.tab == SettingsPane.expert.rawValue {
            navigation.tab = SettingsPane.general.rawValue
        }
        if !isOpen {
            isOpen = true
            onOpenChange?()
        }
        NSApp.activate()
        showWindow(nil)
        window?.makeKeyAndOrderFront(nil)
    }

    private static func sayTurnedOff() {
        let alert = NSAlert()
        alert.messageText = String(localized: "Settings are turned off")
        alert.informativeText = String(localized: "Your organisation manages \(AppInfo.name) on this Mac and turned off its settings.")
        NSApp.activate()
        alert.runModal()
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
        .frame(width: Self.width, height: 600)
        .padding(.vertical, 8)
        // The administrator's locks for `.managed(\.keyPath)` on every tab.
        .environment(\.managedPolicy, store.policy)
    }

    /// Ten tabs: their names need about 700 pt in English; a longer language gets a wider window, so no name is cut.
    static var width: CGFloat {
        let font = NSFont.systemFont(ofSize: NSFont.systemFontSize)
        let names = [String(localized: "General"), String(localized: "Capture"), String(localized: "Video"), String(localized: "Output"),
                     String(localized: "Destinations"), String(localized: "Editor"), String(localized: "Printer"),
                     String(localized: "Recipes"), String(localized: "AI Tools"), String(localized: "Expert")]
        let text = names.reduce(0) { $0 + ($1 as NSString).size(withAttributes: [.font: font]).width }
        return max(760, ceil(text + CGFloat(names.count) * 26 + 40))
    }

    @ViewBuilder private var tabs: some View {
        GeneralSettings(store: store, status: status).tabItem { Label("General", systemImage: "gearshape") }.tag(SettingsPane.general.rawValue)
        CaptureSettings(store: store).tabItem { Label("Capture", systemImage: "camera.viewfinder") }.tag(SettingsPane.capture.rawValue)
        VideoSettingsTab(store: store).tabItem { Label("Video", systemImage: "record.circle") }.tag(SettingsPane.video.rawValue)
        OutputSettings(store: store).tabItem { Label("Output", systemImage: "square.and.arrow.down") }.tag(SettingsPane.output.rawValue)
        DestinationsSettings(store: store).tabItem { Label("Destinations", systemImage: "paperplane") }.tag(SettingsPane.destinations.rawValue)
        EditorSettings(store: store).tabItem { Label("Editor", systemImage: "pencil.and.outline") }.tag(SettingsPane.editor.rawValue)
        PrinterSettings(store: store).tabItem { Label("Printer", systemImage: "printer") }.tag(SettingsPane.printer.rawValue)
        RecipesSettingsTab(store: store).tabItem { Label("Recipes", systemImage: "list.bullet.rectangle") }.tag(SettingsPane.recipes.rawValue)
        AIToolsSettingsTab(store: store).tabItem { Label("AI Tools", systemImage: "sparkles") }.tag(SettingsPane.aiTools.rawValue)
        if !store.value.hideExpertSettings {
            ExpertSettings(store: store).tabItem { Label("Expert", systemImage: "wrench.and.screwdriver") }.tag(SettingsPane.expert.rawValue)
        }
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
    /// Captures work: macOS's preflight, or a capture that worked in this run although it said no.
    @Published var canRecordScreen = Permissions.hasScreenCapture

    func setLaunchAtLogin(_ on: Bool) {
        let message = LaunchAtLogin.set(on)
        refresh()
        // Waiting for approval has its own hint and button; anything else is an error.
        loginError = loginNeedsApproval ? nil : message
    }

    func refresh() {
        canRecordScreen = Permissions.hasScreenCapture
        let state = LaunchAtLogin.state
        launchAtLogin = state != .off
        loginNeedsApproval = state == .needsApproval
    }
}
