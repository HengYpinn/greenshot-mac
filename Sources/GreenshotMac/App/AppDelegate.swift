// Greenshot for Mac (Community) - an unofficial macOS port of Greenshot
// Copyright (C) 2026 Greenshot for Mac (Community) contributors
// SPDX-License-Identifier: GPL-3.0-or-later

import AppKit
import GreenshotCore

@MainActor
final class AppDelegate: NSObject, NSApplicationDelegate, NSMenuItemValidation {
    /// In the user defaults, or in the folder of `--settings-dir` (upstream `--ini-directory`).
    let settings = SettingsStore(fileURL: AppLaunchOptions.parse(arguments: CommandLine.arguments,
                                                                  environment: ProcessInfo.processInfo.environment).settingsFile)
    private(set) lazy var saver = ImageSaver(settings: settings)
    private(set) lazy var editors = EditorManager(settings: settings, saver: saver)
    private(set) lazy var output = OutputManager(settings: settings, saver: saver, editors: editors)
    private(set) lazy var capture = CaptureCoordinator(settings: settings, output: output)
    private let hotkeys = HotkeyManager()
    private var statusItem: StatusItemController?
    private lazy var settingsWindow = SettingsWindowController(settings: settings)
    private var updateTimer: Timer?
    private let log = Log("App")

    /// The last run of the app ended without quitting (a crash or a forced quit): the restore of open editors and the bug
    /// report use it. Package D fills it in.
    var previousRunEndedAbnormally: Bool { false }

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
        startLogging()
        NotificationService.install(app: self)
        applyTheme()
        settings.onChange(of: \.theme) { [weak self] _ in self?.applyTheme() }
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
        editors.restoreSavedEditors()
        showWelcomeOnFirstLaunch()
        scheduleUpdateChecks()
    }

    /// The log file in ~/Library/Logs, and its first entry (upstream `GreenshotMain.Main`: "Starting: " and the
    /// environment).
    private func startLogging() {
        LogCenter.startFile(at: AppInfo.logFile)
        let version = UpdateChecker.currentVersion
        log.info("Starting: \(AppInfo.name) \(version) (\(AppAboutCredits.versionDetail)), macOS \(ProcessInfo.processInfo.operatingSystemVersionString)")
    }

    /// Upstream `UpdateService`: the first check 20 s after the start, then every 30 minutes a look whether one is due
    /// (a menu bar app runs for weeks; a changed interval counts from then on).
    private func scheduleUpdateChecks() {
        DispatchQueue.main.asyncAfter(deadline: .now() + 20) { [weak self] in
            guard let self else { return }
            UpdateChecker.checkIfDue(settings: self.settings, saver: self.saver)
        }
        let timer = Timer(timeInterval: 30 * 60, repeats: true) { [weak self] _ in
            MainActor.assumeIsolated {
                guard let self else { return }
                UpdateChecker.checkIfDue(settings: self.settings, saver: self.saver)
            }
        }
        timer.tolerance = 60
        // Also while a menu is open or a modal window runs.
        RunLoop.main.add(timer, forMode: .common)
        updateTimer = timer
    }

    /// Upstream `Theme`: the app's windows as macOS, light or dark. The menu bar menu follows the menu bar.
    private func applyTheme() {
        switch settings.value.theme {
        case .system: NSApp.appearance = nil
        case .light: NSApp.appearance = NSAppearance(named: .aqua)
        case .dark: NSApp.appearance = NSAppearance(named: .darkAqua)
        }
    }

    func applicationShouldTerminateAfterLastWindowClosed(_ sender: NSApplication) -> Bool {
        false
    }

    func applicationWillTerminate(_ notification: Notification) {
        statusItem?.showIconForNextLaunch()
        log.info("Exiting")
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
        hotkeys.registerAll(settings.value.hotkeys, capture: capture, editors: editors)
    }

    // MARK: Menu actions

    @objc func showSettings(_ sender: Any?) {
        settingsWindow.show()
    }

    /// Settings on one tab (upstream `ShowSetting(pluginName, tabName)`), e.g. for `greenshot://settings?tab=`.
    func showSettings(pane: SettingsPane?) {
        settingsWindow.show(pane: pane)
    }

    @objc func showAbout(_ sender: Any?) {
        NSApp.activate()
        NSApp.orderFrontStandardAboutPanel(options: [.applicationName: AppInfo.name, .version: AppAboutCredits.versionDetail,
                                                     .credits: AppAboutCredits.make()])
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
        let region = settings.value.hotkeys.region.map { "Press \($0.displayString) to capture." }
        let detail: String
        if settings.value.hideMenuBarIcon {
            // Without the icon, opening the app again is the way to Settings.
            detail = [region, "Open the app again or click here for Settings."].compactMap { $0 }.joined(separator: " ")
        } else {
            detail = "\(region ?? "It's in the menu bar.") Click here for Settings."
        }
        saver.notify("\(AppInfo.name) is running", detail: detail) { [weak self] in
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
