// Greenshot for Mac (Community) - an unofficial macOS port of Greenshot
// Copyright (C) 2026 Greenshot for Mac (Community) contributors
// SPDX-License-Identifier: GPL-3.0-or-later

import AppKit
import GreenshotCore

@MainActor
final class AppDelegate: NSObject, NSApplicationDelegate {
    let settings = SettingsStore()
    private(set) lazy var saver = ImageSaver(settings: settings)
    private(set) lazy var editors = EditorManager(settings: settings, saver: saver)
    private(set) lazy var output = OutputManager(settings: settings, saver: saver, editors: editors)
    private(set) lazy var capture = CaptureCoordinator(settings: settings, output: output)
    private let hotkeys = HotkeyManager()
    private var statusItem: StatusItemController?
    private lazy var settingsWindow = SettingsWindowController(settings: settings)

    func applicationDidFinishLaunching(_ notification: Notification) {
        if let folder = Snapshots.requestedFolder {
            do {
                try Snapshots.render(to: folder)
                exit(0)
            } catch {
                FileHandle.standardError.write(Data("Snapshot failed: \(error)\n".utf8))
                exit(1)
            }
        }
        NSApp.setActivationPolicy(.accessory)
        NSApp.mainMenu = MainMenu.make()
        statusItem = StatusItemController(app: self)
        settings.onHotkeysChange = { [weak self] in self?.registerHotkeys() }
        NotificationCenter.default.addObserver(forName: ShortcutRecorderButton.recordingDidBegin, object: nil, queue: .main) { [weak self] _ in
            MainActor.assumeIsolated { self?.hotkeys.unregisterAll() }
        }
        NotificationCenter.default.addObserver(forName: ShortcutRecorderButton.recordingDidEnd, object: nil, queue: .main) { [weak self] _ in
            MainActor.assumeIsolated { self?.registerHotkeys() }
        }
        registerHotkeys()
        showWelcomeOnFirstLaunch()
    }

    func applicationShouldTerminateAfterLastWindowClosed(_ sender: NSApplication) -> Bool {
        false
    }

    /// Quitting doesn't close the editor windows one by one, so ask about unsaved screenshots here.
    func applicationShouldTerminate(_ sender: NSApplication) -> NSApplication.TerminateReply {
        editors.confirmQuit() ? .terminateNow : .terminateCancel
    }

    /// Opening the app again while it runs (it has no window) shows the settings.
    func applicationShouldHandleReopen(_ sender: NSApplication, hasVisibleWindows flag: Bool) -> Bool {
        if !flag { showSettings(nil) }
        return true
    }

    /// Images dropped on the app or opened with it go to the editor.
    func application(_ application: NSApplication, open urls: [URL]) {
        urls.forEach(editors.open(fileURL:))
    }

    // MARK: Hotkeys

    private func registerHotkeys() {
        hotkeys.unregisterAll()
        let h = settings.value.hotkeys
        var failed: [String] = []
        func bind(_ combo: KeyCombo?, _ name: String, _ action: @escaping () -> Void) {
            guard let combo else { return }
            if !hotkeys.register(combo, action: action) { failed.append("\(name): \(combo.displayString)") }
        }
        bind(h.region, "Capture region") { [weak self] in self?.capture.captureRegion() }
        bind(h.window, "Capture window") { [weak self] in self?.capture.captureWindowFromHotkey() }
        bind(h.fullScreen, "Capture full screen") { [weak self] in self?.capture.captureFullScreen() }
        bind(h.lastRegion, "Capture last region") { [weak self] in self?.capture.captureLastRegion() }
        bind(h.clipboard, "Open clipboard") { [weak self] in self?.editors.openClipboard() }
        if !failed.isEmpty {
            ErrorPresenter.show(message: "Some hotkeys could not be registered",
                                detail: failed.joined(separator: "\n") + "\n\nAnother app may use them. Choose others in Settings › General.")
        }
    }

    // MARK: Menu actions

    @objc func showSettings(_ sender: Any?) {
        settingsWindow.show()
    }

    @objc func showAbout(_ sender: Any?) {
        let credits = NSMutableAttributedString(string: """
            An unofficial, community-made macOS port of Greenshot, the free and open source screenshot tool for Windows. \
            It is not affiliated with the Greenshot team or the official Greenshot app in the Mac App Store.

            Based on Greenshot, Copyright © 2007-2026 Thomas Braun, Jens Klingen, Robin Krom.
            Licensed under the GNU General Public License version 3 or later.
            """, attributes: [.font: NSFont.systemFont(ofSize: 11), .foregroundColor: NSColor.labelColor])
        NSApp.activate()
        NSApp.orderFrontStandardAboutPanel(options: [.applicationName: AppInfo.name, .credits: credits])
    }

    @objc func captureRegion(_ sender: Any?) {
        capture.captureRegion()
    }

    @objc func openImageFile(_ sender: Any?) {
        editors.chooseAndOpenFile()
    }

    @objc func openClipboard(_ sender: Any?) {
        editors.openClipboard()
    }

    @objc func openUpstreamWebsite(_ sender: Any?) {
        NSWorkspace.shared.open(AppInfo.upstreamURL)
    }

    private func showWelcomeOnFirstLaunch() {
        let key = "didShowWelcome"
        guard !UserDefaults.standard.bool(forKey: key) else { return }
        UserDefaults.standard.set(true, forKey: key)
        let region = settings.value.hotkeys.region?.displayString ?? "the menu bar icon"
        let alert = NSAlert()
        alert.messageText = "\(AppInfo.name) is in your menu bar"
        alert.informativeText = """
            Press \(region) to capture a region, or use the camera icon in the menu bar. \
            The hotkeys can be changed in Settings.

            macOS will ask you to allow screen recording the first time you take a screenshot.
            """
        alert.addButton(withTitle: "OK")
        alert.addButton(withTitle: "Open Settings")
        NSApp.activate()
        if alert.runModal() == .alertSecondButtonReturn { showSettings(nil) }
    }
}
