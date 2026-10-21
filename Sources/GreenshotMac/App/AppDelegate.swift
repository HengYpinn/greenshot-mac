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
    private(set) lazy var video = VideoRecordingController(settings: settings, saver: saver)
    /// The recipes: library, step executors, runner, trigger hub, approvals (RSTEPS). Started at launch; code that must
    /// also work without it (windows, `--snapshot`, hooks) asks `RecipeRuntime.shared`, nil until started.
    private(set) lazy var recipes = RecipeRuntime(app: self)
    private let hotkeys = HotkeyManager()
    private var statusItem: StatusItemController?
    private lazy var settingsWindow = SettingsWindowController(settings: settings)
    private var updateTimer: Timer?
    /// greenshot-cli, `greenshotmac:` links, files from Finder, AppleScript, Services and Shortcuts.
    let automation = AutomationCenter()
    private lazy var services = ServicesProvider(app: self)
    private let log = Log("App")

    /// The last run of the app ended without quitting (a crash or a forced quit): the restore of open editors and the bug
    /// report use it. Read from the marker of the running app at launch (`CrashReporting`).
    private(set) var previousRunEndedAbnormally = false

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
        // A --language of this start is kept in the settings (L10N).
        LanguageStartup.saveCommandLineChoice(into: settings)
        CrashReporting.install()
        let previousRun = CrashReporting.checkPreviousRun()
        previousRunEndedAbnormally = previousRun.endedAbnormally
        #if DEBUG
        CrashReporting.runDebugTest(previousRun: previousRun)
        #endif
        NotificationService.install(app: self)
        applyTheme()
        settings.onChange(of: \.theme) { [weak self] _ in self?.applyTheme() }
        Printing.settings = settings
        // Recent Jira issues from the window titles (PARTIALS-DST, DST-088).
        JiraTitleMonitor.shared.start(settings: settings)
        Clipboard.formats = { [settings] in settings.value.clipboardFormats }
        editors.onWindowsChange = { [weak self] in self?.updateDockIcon() }
        settingsWindow.onOpenChange = { [weak self] in self?.updateDockIcon() }
        AuxiliaryWindows.onChange = { [weak self] in self?.updateDockIcon() }
        updateDockIcon()
        NSApp.mainMenu = MainMenu.make()
        // Before the menu bar icon, the hotkeys and the automation, which use the recipes. The approval sheet and the
        // automatic steps are wired before the recipe files load (that waits until this method returns).
        recipes.start()
        RecipeAppUI.start(app: self)
        RecipeAutomaticSteps.install(on: recipes)
        statusItem = StatusItemController(app: self)
        settings.onHotkeysChange = { [weak self] in self?.registerHotkeys() }
        settings.onDockChange = { [weak self] in self?.updateDockIcon() }
        NotificationCenter.default.addObserver(forName: ShortcutRecorderButton.recordingDidBegin, object: nil, queue: .main) { [weak self] _ in
            MainActor.assumeIsolated { self?.hotkeys.unregisterAll() }
        }
        NotificationCenter.default.addObserver(forName: ShortcutRecorderButton.recordingDidEnd, object: nil, queue: .main) { [weak self] note in
            // Settings closing (not a recorder) turns them on whatever a recorder says.
            let settingsClosed = !(note.object is ShortcutRecorderButton)
            MainActor.assumeIsolated { self?.registerHotkeys(evenWhileRecording: settingsClosed) }
        }
        // Hotkeys named by the keyboard layout; after the snapshots, which stay in US names.
        KeyboardLayoutNames.follow()
        registerHotkeys()
        editors.restoreSavedEditors()
        switch previousRun {
        case .crashed(_, let details):
            // The report says enough; no welcome or "is running" message on top of it.
            BugReportWindowController.show(details)
        case .endedAbnormally(let marker):
            CrashReporting.lookAgain(for: marker, after: 10) { BugReportWindowController.show($0) }
            showWelcomeOnFirstLaunch()
        case .clean:
            showWelcomeOnFirstLaunch()
        }
        scheduleUpdateChecks()
        NSApp.servicesProvider = services
        NSUpdateDynamicServices()
        automation.start(app: self)
    }

    /// The log file in ~/Library/Logs, and its first entry (upstream `GreenshotMain.Main`: "Starting: " and the
    /// environment).
    private func startLogging() {
        LogCenter.startFile(at: AppInfo.logFile)
        log.info("Starting: " + DiagnosticReport.environmentText(SystemInfo.snapshot(), newline: false))
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
        recipes.shutdown()
        automation.shutdown()
        statusItem?.showIconForNextLaunch()
        log.info("Exiting")
        CrashReporting.removeMarker()
    }

    /// Quitting doesn't close the editor windows one by one, so ask about unsaved screenshots here.
    func applicationShouldTerminate(_ sender: NSApplication) -> NSApplication.TerminateReply {
        guard editors.confirmQuit() else { return .terminateCancel }
        guard RecipeEditorService.reviewUnsavedBeforeQuit() else { return .terminateCancel }
        // A recipe that waits at a prompt or the destination flyout holds the only copy of its capture (RSTEPS, R-F9).
        guard recipes.confirmQuit() else { return .terminateCancel }
        return video.terminateReply()
    }

    /// Opening the app again while it runs brings back the editors (they hide when another app is clicked), or
    /// shows the settings when there are none.
    func applicationShouldHandleReopen(_ sender: NSApplication, hasVisibleWindows flag: Bool) -> Bool {
        // Also when a window is "visible": it may be on another Space, where the user doesn't see it.
        if !editors.showEditors() { showSettings(nil) }
        return true
    }

    /// Images dropped on the app or opened with it go to the editor (checked like greenshot-cli's files), and
    /// `greenshotmac:` links run their command (upstream `greenshot:` URL protocol).
    func application(_ application: NSApplication, open urls: [URL]) {
        automation.open(urls)
    }

    /// A Dock icon (with the menu bar and a place in ⌘Tab) while an editor or Settings is open, if the setting is on;
    /// otherwise only the menu bar icon, which is there whenever the app runs. Hidden editors count as open: a click
    /// on the Dock icon brings them back.
    private func updateDockIcon() {
        let windowOpen = editors.hasEditors || settingsWindow.isOpen || AuxiliaryWindows.anyOpen
        NSApp.setActivationPolicy(settings.value.dockIconWhileWindowOpen && windowOpen ? .regular : .accessory)
    }

    // MARK: Hotkeys

    private func registerHotkeys(evenWhileRecording: Bool = false) {
        // A shortcut recorder has them off; the end of the last one registers them (switching from one recorder to
        // another begins the second before the first ends).
        guard evenWhileRecording || !ShortcutRecorderButton.isAnyRecording else { return }
        hotkeys.registerAll(settings.value.hotkeys, capture: capture, editors: editors, video: video)
        guard let registration = HotkeyDiagnostics.lastRegistration else { return }
        let refused = registration.refused.filter(registration.combos.indices.contains)
            .map { "\(registration.names[$0]) (\(registration.combos[$0].displayString))" }
        if refused.isEmpty {
            log.info("Registered \(registration.combos.count) hotkeys")
        } else {
            log.warn("Registered \(registration.combos.count - refused.count) of \(registration.combos.count) hotkeys; macOS refused \(refused.joined(separator: ", "))")
        }
    }

    /// "Register Again" of Self-Service › Hotkeys and the setup checks (upstream `ReRegisterHotkeys`).
    func reregisterHotkeys() {
        log.info("Registering the hotkeys again")
        registerHotkeys()
    }

    /// Whether the menu bar icon is on a screen, for the setup checks; nil when unknown.
    var statusItemOnScreen: Bool? {
        statusItem?.isIconOnScreen
    }

    // MARK: Menu actions

    @objc func showSettings(_ sender: Any?) {
        settingsWindow.show()
    }

    /// Settings on one tab (upstream `ShowSetting(pluginName, tabName)`), e.g. for `greenshot://settings?tab=`.
    func showSettings(pane: SettingsPane?) {
        settingsWindow.show(pane: pane)
    }

    /// The log viewer on the app's log; a search text (at most 200 characters, trimmed, escaped) shows only the
    /// entries with it and never changes the level. For `greenshotmac://log?search=` (upstream `LogViewerWindow.ShowForLink`).
    func showLogViewer(search: String?) {
        LogViewerWindowController.show(search: search.map(LogSearch.linkSearchText))
    }

    @objc func showLogViewer(_ sender: Any?) {
        showLogViewer(search: nil)
    }

    /// The Self-Service window, on `section` when given (upstream `SelfServiceWindow.ShowSelfService`), for
    /// `greenshotmac://self-service?section=`.
    func showSelfService(section: SelfServiceSection?) {
        SelfServiceWindowController.show(section: section, app: self)
    }

    @objc func showSelfService(_ sender: Any?) {
        showSelfService(section: nil)
    }

    /// The About window with its Self-Service button (upstream `AboutWindow`).
    @objc func showAbout(_ sender: Any?) {
        AboutWindowController.show(app: self)
    }

    @objc func captureRegion(_ sender: Any?) {
        capture.captureRegion(byAutomation: false)
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
        return (editor.currentCapture, window)
    }

    /// File menu entries of the destinations: the item's `representedObject` is a `DestinationTargetBox`.
    @objc func sendToDestination(_ sender: NSMenuItem) {
        guard let box = sender.representedObject as? DestinationTargetBox, let front = frontEditor else { return }
        output.perform(box.target, with: front.capture, window: front.window)
    }

    func validateMenuItem(_ menuItem: NSMenuItem) -> Bool {
        if let verdict = ManagedHooks.validate(menuItem, settings: settings.value) { return verdict }
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
        HelpOpener.open()
    }

    @objc func reportIssue(_ sender: Any?) {
        NSWorkspace.shared.open(AppInfo.issuesURL)
    }

    @objc func openUpstreamWebsite(_ sender: Any?) {
        NSWorkspace.shared.open(AppInfo.upstreamURL)
    }

    /// The welcome window on the first start (upstream `WelcomeShown`, `GreenshotShell`), else the "is running" message.
    /// Users of a version with the earlier welcome alert see the window once too, like upstream's updaters.
    private func showWelcomeOnFirstLaunch() {
        // The alert of earlier versions and its separate offer to open at login: the welcome window has both now.
        UserDefaults.standard.removeObject(forKey: "didShowWelcome")
        UserDefaults.standard.removeObject(forKey: "didOfferLaunchAtLogin")
        if settings.value.welcomeShown {
            // Started by greenshot-cli or a script (`--background`): nobody needs to be told
            if !AutomationStartup.options.background { showRunningMessage() }
        } else {
            settings.update { $0.welcomeShown = true }
            WelcomeWindowController.show(app: self, firstLaunch: true)
        }
    }

    /// The welcome window again (upstream's pipe command `FIRST_LAUNCH`), for Help › Welcome Guide and
    /// `greenshotmac://` links.
    func showWelcome() {
        WelcomeWindowController.show(app: self, firstLaunch: false)
    }

    @objc func showWelcomeGuide(_ sender: Any?) {
        showWelcome()
    }

    /// A menu bar app opens no window, and macOS can hide its icon (behind the notch), so starting it would look
    /// like nothing happened. Say that it runs; a click opens Settings.
    private func showRunningMessage() {
        let region = settings.value.hotkeys.region.map { String(localized: "Press \(BidiText.isolatedLTR($0.displayString)) to capture.") }
        let detail: String
        if settings.value.hideMenuBarIcon {
            // Without the icon, opening the app again is the way to Settings.
            detail = [region, String(localized: "Open the app again or click here for Settings.")].compactMap { $0 }.joined(separator: " ")
        } else {
            detail = [region ?? String(localized: "It's in the menu bar."), String(localized: "Click here for Settings.")].joined(separator: " ")
        }
        saver.notify(String(localized: "\(AppInfo.name) is running"), detail: detail) { [weak self] in
            self?.showSettings(nil)
        }
    }
}
