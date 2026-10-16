// Greenshot for Mac (Community) - an unofficial macOS port of Greenshot
// Copyright (C) 2026 Greenshot for Mac (Community) contributors
// SPDX-License-Identifier: GPL-3.0-or-later

import AppKit
import GreenshotCore

@MainActor
final class AppDelegate: NSObject, NSApplicationDelegate, NSMenuItemValidation {
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
        Printing.settings = settings
        Clipboard.formats = { [settings] in settings.value.clipboardFormats }
        editors.onWindowsChange = { [weak self] in self?.updateDockIcon() }
        settingsWindow.onOpenChange = { [weak self] in self?.updateDockIcon() }
        updateDockIcon()
        NSApp.mainMenu = MainMenu.make()
        statusItem = StatusItemController(app: self)
        settings.onHotkeysChange = { [weak self] in self?.registerHotkeys() }
        settings.onDockChange = { [weak self] in self?.updateDockIcon() }
        NotificationCenter.default.addObserver(forName: ShortcutRecorderButton.recordingDidBegin, object: nil, queue: .main) { [weak self] _ in
            MainActor.assumeIsolated { self?.hotkeys.unregisterAll() }
        }
        NotificationCenter.default.addObserver(forName: ShortcutRecorderButton.recordingDidEnd, object: nil, queue: .main) { [weak self] _ in
            MainActor.assumeIsolated { self?.registerHotkeys() }
        }
        registerHotkeys()
        showWelcomeOnFirstLaunch()
        // After the welcome (which is modal), and a little later so a message doesn't cover "is running".
        DispatchQueue.main.asyncAfter(deadline: .now() + 5) { [weak self] in
            guard let self else { return }
            UpdateChecker.checkIfDue(settings: self.settings, saver: self.saver)
        }
    }

    func applicationShouldTerminateAfterLastWindowClosed(_ sender: NSApplication) -> Bool {
        false
    }

    /// Quitting doesn't close the editor windows one by one, so ask about unsaved screenshots here.
    func applicationShouldTerminate(_ sender: NSApplication) -> NSApplication.TerminateReply {
        editors.confirmQuit() ? .terminateNow : .terminateCancel
    }

    /// Opening the app again while it runs brings back the editors (they hide when another app is clicked), or
    /// shows the settings when there are none.
    func applicationShouldHandleReopen(_ sender: NSApplication, hasVisibleWindows flag: Bool) -> Bool {
        // Also when a window is "visible": it may be on another Space, where the user doesn't see it.
        if !editors.showEditors() { showSettings(nil) }
        return true
    }

    /// Images dropped on the app or opened with it go to the editor.
    func application(_ application: NSApplication, open urls: [URL]) {
        urls.forEach(editors.open(fileURL:))
    }

    /// A Dock icon (with the menu bar and a place in ⌘Tab) while an editor or Settings is open, if the setting is on;
    /// otherwise only the menu bar icon, which is there whenever the app runs. Hidden editors count as open: a click
    /// on the Dock icon brings them back.
    private func updateDockIcon() {
        let windowOpen = editors.hasEditors || settingsWindow.isOpen
        NSApp.setActivationPolicy(settings.value.dockIconWhileWindowOpen && windowOpen ? .regular : .accessory)
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

    /// The screenshot of the editor window in front, with the window, for the File menu's destinations.
    var frontEditor: (capture: Capture, window: NSWindow)? {
        guard let window = NSApp.keyWindow ?? NSApp.mainWindow,
              let editor = window.windowController as? EditorWindowController else { return nil }
        let document = editor.editorDocument
        let capture = Capture(image: document.flattened(), scale: document.scale, title: document.title, date: document.captureDate)
        return (capture, window)
    }

    /// File menu entries of the destinations: the item's `representedObject` is a `DestinationTargetBox`.
    @objc func sendToDestination(_ sender: NSMenuItem) {
        guard let box = sender.representedObject as? DestinationTargetBox, let front = frontEditor else { return }
        output.perform(box.target, with: front.capture, window: front.window)
    }

    func validateMenuItem(_ menuItem: NSMenuItem) -> Bool {
        if menuItem.action == #selector(sendToDestination(_:)) {
            let window = NSApp.keyWindow ?? NSApp.mainWindow
            return window?.windowController is EditorWindowController
        }
        if menuItem.action == #selector(openClipboard(_:)) {
            return NSImage.canInit(with: .general)
        }
        return true
    }

    @objc func openHelp(_ sender: Any?) {
        NSWorkspace.shared.open(AppInfo.helpURL)
    }

    @objc func reportIssue(_ sender: Any?) {
        NSWorkspace.shared.open(AppInfo.issuesURL)
    }

    @objc func openUpstreamWebsite(_ sender: Any?) {
        NSWorkspace.shared.open(AppInfo.upstreamURL)
    }

    private static let didShowWelcomeKey = "didShowWelcome"
    private static let didOfferLaunchAtLoginKey = "didOfferLaunchAtLogin"

    /// The welcome on the first launch; users who saw it before this option existed are asked about opening at
    /// login once, separately.
    private func showWelcomeOnFirstLaunch() {
        let defaults = UserDefaults.standard
        if !defaults.bool(forKey: Self.didShowWelcomeKey) {
            defaults.set(true, forKey: Self.didShowWelcomeKey)
            defaults.set(true, forKey: Self.didOfferLaunchAtLoginKey)
            showWelcome()
        } else if !defaults.bool(forKey: Self.didOfferLaunchAtLoginKey) {
            defaults.set(true, forKey: Self.didOfferLaunchAtLoginKey)
            offerLaunchAtLogin()
        } else {
            showRunningMessage()
        }
    }

    /// A menu bar app opens no window, and macOS can hide its icon (behind the notch), so starting it would look
    /// like nothing happened. Say that it runs; a click opens Settings.
    private func showRunningMessage() {
        let region = settings.value.hotkeys.region.map { "Press \($0.displayString) to capture." } ?? "It's in the menu bar."
        saver.notify("\(AppInfo.name) is running", detail: "\(region) Click here for Settings.") { [weak self] in
            self?.showSettings(nil)
        }
    }

    private func showWelcome() {
        let region = settings.value.hotkeys.region?.displayString ?? "the menu bar icon"
        let alert = NSAlert()
        alert.messageText = "\(AppInfo.name) is in your menu bar"
        alert.informativeText = """
            Press \(region) to capture a region, or use the camera icon in the menu bar. \
            The hotkeys can be changed in Settings.

            macOS will ask you to allow screen recording the first time you take a screenshot.
            """ + LaunchAtLogin.moveToApplicationsTip
        // Checked by default, like the "start with Windows" option of Greenshot's installer.
        let openAtLogin = NSButton(checkboxWithTitle: "Open \(AppInfo.name) at login", target: nil, action: nil)
        openAtLogin.state = .on
        alert.accessoryView = openAtLogin
        alert.addButton(withTitle: "OK")
        alert.addButton(withTitle: "Open Settings")
        NSApp.activate()
        let response = alert.runModal()
        if openAtLogin.state == .on { turnOnLaunchAtLogin() }
        if response == .alertSecondButtonReturn { showSettings(nil) }
    }

    private func offerLaunchAtLogin() {
        guard LaunchAtLogin.state == .off else { return }
        let alert = NSAlert()
        alert.messageText = "Open \(AppInfo.name) when you log in?"
        alert.informativeText = """
            Then the hotkeys work right after a restart, like Greenshot on Windows. \
            You can change this any time in Settings › General.
            """ + LaunchAtLogin.moveToApplicationsTip
        alert.addButton(withTitle: "Open at Login")
        alert.addButton(withTitle: "Not Now")
        NSApp.activate()
        if alert.runModal() == .alertFirstButtonReturn { turnOnLaunchAtLogin() }
    }

    private func turnOnLaunchAtLogin() {
        guard let problem = LaunchAtLogin.set(true) else { return }
        ErrorPresenter.show(message: "\(AppInfo.name) doesn't open at login yet", detail: problem)
    }
}
