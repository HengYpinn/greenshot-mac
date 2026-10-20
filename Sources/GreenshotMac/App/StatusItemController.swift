// Greenshot for Mac (Community) - an unofficial macOS port of Greenshot
// Copyright (C) 2026 Greenshot for Mac (Community) contributors
// Based on Greenshot, Copyright (C) 2007-2026 Thomas Braun, Jens Klingen, Robin Krom
// SPDX-License-Identifier: GPL-3.0-or-later

import AppKit
import GreenshotCore

/// The menu bar icon and its menu: upstream's tray icon (`Greenshot/Shell/TrayIcon.cs`) and menu (`TrayMenu.cs`).
///
/// A click runs `leftClickAction`. When that shows the menu (the default), the menu belongs to the icon and opens on
/// mouse-down like every Mac menu bar item. Otherwise the icon is a button: a click runs the action, a right-click or
/// ⌃-click pops the menu up under it, and with a `doubleClickAction` a click waits the double-click time for a second
/// one.
@MainActor
final class StatusItemController: NSObject, NSMenuDelegate {
    private let statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.squareLength)
    private unowned let app: AppDelegate
    private let menu = NSMenu()
    private lazy var windowList = MenuBarWindowList(app: app)
    /// A first click waiting for its second one (upstream `_doubleClickTimer`).
    private var singleClickTimer: Timer?

    init(app: AppDelegate) {
        self.app = app
        super.init()
        // Items are enabled or disabled here, not by the responder chain.
        menu.autoenablesItems = false
        menu.delegate = self
        // macOS keeps the icon where the user ⌘-dragged it.
        statusItem.autosaveName = "GreenshotStatusItem"
        if let button = statusItem.button {
            button.image = MenuBarIcon.make()
            button.toolTip = AppInfo.name
            button.target = self
            button.action = #selector(iconClicked(_:))
            button.sendAction(on: [.leftMouseUp, .rightMouseUp])
        }
        applySettings()
        // The app's log file is open now: say what an administrator set.
        app.settings.logManagedPolicy()
        app.settings.onChange(of: \.leftClickAction) { [weak self] _ in self?.applySettings() }
        app.settings.onChange(of: \.hideMenuBarIcon) { [weak self] _ in self?.applySettings() }
    }

    /// The icon's menu while a click shows it, and whether the icon is there (upstream `HideTrayicon`). Set at every
    /// launch: macOS remembers the visibility under the autosave name and must not win over the setting.
    private func applySettings() {
        let s = app.settings.value
        cancelSingleClick()
        statusItem.menu = MenuBarClick.clickShowsMenu(s.leftClickAction) ? menu : nil
        statusItem.isVisible = !s.hideMenuBarIcon
    }

    /// Before quitting, the icon is made visible again: macOS stores its visibility under the autosave name, and an
    /// older build of the app (without the setting) would otherwise start without an icon and no way to get it back.
    /// This build applies the setting again at launch.
    func showIconForNextLaunch() {
        statusItem.isVisible = true
    }

    /// Whether the icon can be seen: false when it is switched off, or when the menu bar is shown but the icon's window
    /// isn't (macOS hides icons behind the notch, and macOS 26 can hide them in its menu bar settings). Nil when the
    /// menu bar itself is hidden (a full screen app, or "hide the menu bar automatically"), then nothing is known.
    var isIconOnScreen: Bool? {
        guard statusItem.isVisible else { return false }
        guard NSMenu.menuBarVisible(), let window = statusItem.button?.window else { return nil }
        return window.occlusionState.contains(.visible) && window.screen != nil
    }

    // MARK: Clicks

    @objc private func iconClicked(_ sender: Any?) {
        let event = NSApp.currentEvent
        let mouseUp = event?.type == .leftMouseUp || event?.type == .rightMouseUp
        // A press without the mouse (VoiceOver, keyboard) gets the menu too: it is the way to everything else.
        let menuGesture = !mouseUp || event?.type == .rightMouseUp || event?.modifierFlags.contains(.control) == true
        let s = app.settings.value
        switch MenuBarClick.decide(menuGesture: menuGesture, waiting: singleClickTimer != nil,
                                   click: s.leftClickAction, doubleClick: s.doubleClickAction) {
        case .showMenu:
            cancelSingleClick()
            showMenu()
        case .run(let action):
            run(action)
        case .waitForSecondClick:
            let timer = Timer(timeInterval: NSEvent.doubleClickInterval, repeats: false) { [weak self] _ in
                MainActor.assumeIsolated {
                    guard let self else { return }
                    self.singleClickTimer = nil
                    self.run(self.app.settings.value.leftClickAction)
                }
            }
            // Also while a menu or a modal window runs its own loop.
            RunLoop.main.add(timer, forMode: .common)
            singleClickTimer = timer
        case .runDoubleClick(let action):
            cancelSingleClick()
            run(action)
        }
    }

    private func cancelSingleClick() {
        singleClickTimer?.invalidate()
        singleClickTimer = nil
    }

    /// Runs a click action once the click is handled (upstream `RunLater`).
    private func run(_ action: ClickAction) {
        DispatchQueue.main.async { [weak self] in
            MainActor.assumeIsolated {
                guard let self else { return }
                MenuBarActions.perform(action, app: self.app) { self.showMenu() }
            }
        }
    }

    /// Opens the menu under the icon while it isn't the icon's menu. Popped up by hand, with the icon highlighted
    /// meanwhile: giving the icon the menu and calling `performClick` from inside the icon's own action could run that
    /// action again instead.
    private func showMenu() {
        guard let button = statusItem.button, statusItem.isVisible else { return }
        button.highlight(true)
        let below = NSPoint(x: 0, y: button.isFlipped ? button.bounds.maxY + 5 : -5)
        menu.popUp(positioning: nil, at: below, in: button)
        button.highlight(false)
    }

    // MARK: The menu

    func menuNeedsUpdate(_ menu: NSMenu) {
        guard menu === self.menu else { return }
        menu.removeAllItems()
        // A profile installed or removed while the app runs.
        app.settings.refreshManaged()
        let settings = app.settings.value
        let hotkeys = settings.hotkeys
        let capture = app.capture

        // Editors hide when another app is clicked; this brings them back.
        if app.editors.hasEditors {
            menu.addItem(ClosureMenuItem(title: String(localized: "Show Open Screenshots")) { [unowned app] in app.editors.showEditors() })
            menu.addItem(.separator())
        }

        menu.addItem(item(String(localized: "Capture Region"), hotkeys.region) { capture.captureRegion(byAutomation: false) })
        let lastRegion = item(String(localized: "Capture Last Region"), hotkeys.lastRegion) { capture.captureLastRegion(byAutomation: false) }
        // Upstream greys it out until a region was captured (TrayMenu.cs).
        lastRegion.isEnabled = settings.lastCapturedRegion != nil
        menu.addItem(lastRegion)
        menu.addItem(item(String(localized: "Capture Window"), hotkeys.window) { capture.captureWindowInteractively(byAutomation: false) })
        menu.addItem(item(String(localized: "Capture Text"), hotkeys.text) { capture.captureText(byAutomation: false) })
        menu.addItem(fullScreenItem(hotkey: hotkeys.fullScreen))
        menu.addItem(windowList.makeItem())
        app.video.addMenuItems(to: menu)

        menu.addItem(.separator())
        // Upstream TrayMenu.cs: the Recipes submenu (RUI) after the window list, before the clipboard; none with recipes off.
        if let recipes = RecipeMenus.statusMenuItem(app: app) { menu.addItem(recipes) }
        let clipboard = item(String(localized: "Open Image from Clipboard"), hotkeys.clipboard) { [unowned app] in app.editors.openClipboard() }
        clipboard.isEnabled = NSImage.canInit(with: .general)
        menu.addItem(clipboard)
        menu.addItem(ClosureMenuItem(title: String(localized: "Open Image from File…")) { [unowned app] in MenuBarActions.openFilesToDestinations(app: app) })
        menu.addItem(recentCaptureItem())
        menu.addItem(.separator())
        let settingsItems = Self.settingsItems(store: app.settings) { [unowned app] in app.showSettings(nil) }
        settingsItems.forEach(menu.addItem)
        if !settingsItems.isEmpty { menu.addItem(.separator()) }
        menu.addItem(ClosureMenuItem(title: String(localized: "Help")) { HelpOpener.open() })
        menu.addItem(ClosureMenuItem(title: String(localized: "About \(AppInfo.name)")) { [unowned app] in app.showAbout(nil) })
        menu.addItem(.separator())
        menu.addItem(ClosureMenuItem(title: String(localized: "Quit"), keyEquivalent: "q") { NSApp.terminate(nil) })
    }

    /// "Capture Full Screen"; with several displays a submenu with all of them and each one, named with upstream's
    /// position words (TrayMenu.cs `CreateFullscreenItem`).
    private func fullScreenItem(hotkey: KeyCombo?) -> NSMenuItem {
        let capture = app.capture
        let screens = NSScreen.screens
        guard screens.count > 1 else {
            return item(String(localized: "Capture Full Screen"), hotkey) { capture.captureFullScreen(byAutomation: false) }
        }
        let fullScreen = NSMenuItem(title: String(localized: "Capture Full Screen"), action: nil, keyEquivalent: "")
        let submenu = NSMenu()
        submenu.addItem(item(String(localized: "All Screens"), hotkey) { capture.captureFullScreen(byAutomation: false) })
        submenu.addItem(.separator())
        let frames = screens.map { CGDisplayBounds($0.displayID) }
        for (screen, frame) in zip(screens, frames) {
            let id = screen.displayID
            let title = ScreenPosition.label(name: screen.localizedName, frame: frame, among: frames)
            submenu.addItem(ClosureMenuItem(title: title) { capture.captureFullScreen(displayID: id, byAutomation: false) })
        }
        fullScreen.submenu = submenu
        return fullScreen
    }

    /// Upstream's "Open last capture location": the last saved file in Finder, else its folder or the output folder.
    private func recentCaptureItem() -> NSMenuItem {
        let settings = app.settings
        let entry = ClosureMenuItem(title: String(localized: "Open Last Capture Location")) { MenuBarActions.openLastCaptureLocation(settings: settings) }
        if let path = settings.value.lastSavedFile {
            entry.toolTip = (path as NSString).abbreviatingWithTildeInPath
        }
        return entry
    }

    /// Quick Settings and Settings…, unless an administrator turned them off (upstream `TrayMenu.cs`: `DisableQuickSettings`,
    /// `DisableSettings`).
    static func settingsItems(store: SettingsStore, openSettings: @escaping () -> Void) -> [NSMenuItem] {
        var items: [NSMenuItem] = []
        if let quickSettings = quickSettingsItem(store: store) { items.append(quickSettings) }
        if !store.value.disableSettings {
            items.append(ClosureMenuItem(title: String(localized: "Settings…"), keyEquivalent: ",", handler: openSettings))
        }
        return items
    }

    /// Upstream's quick settings in the tray menu (`TrayMenu.cs`): the most used options as check items. Like upstream
    /// (`AddBoolMenuItem`, `IsConstant("Destinations")`) a setting an administrator locked is left out, and so are the
    /// destinations they turned off; nil when nothing is left or Quick Settings are turned off.
    static func quickSettingsItem(store: SettingsStore) -> NSMenuItem? {
        let s = store.value
        guard !s.disableQuickSettings else { return nil }
        let menu = NSMenu(title: String(localized: "Quick Settings"))
        menu.autoenablesItems = false
        if !store.isLocked(\.captureMousePointer) {
            menu.addItem(toggle(String(localized: "Capture Mouse Pointer"), s.captureMousePointer) { store.update { $0.captureMousePointer.toggle() } })
        }

        if !store.isLocked(\.destinations) {
            let destinations = NSMenu(title: String(localized: "Destinations"))
            destinations.autoenablesItems = false
            for destination in CaptureDestination.allCases where !s.isDestinationExcluded(destination) {
                let on = s.destinations.contains(destination)
                destinations.addItem(toggle(destination.displayName, on) { store.update { $0.setDestination(destination, on: !on) } })
                if destination == .picker { destinations.addItem(.separator()) }
            }
            let destinationsItem = NSMenuItem(title: String(localized: "After a Capture"), action: nil, keyEquivalent: "")
            destinationsItem.submenu = destinations
            menu.addItem(destinationsItem)
        }

        let printing = NSMenu(title: String(localized: "Print Options"))
        printing.autoenablesItems = false
        let p = s.printing
        let printToggles: [(String, WritableKeyPath<PrintSettings, Bool>)] = [
            (String(localized: "Ask Every Time"), \.promptOptions), (String(localized: "Shrink to Fit"), \.allowShrink),
            (String(localized: "Enlarge to Fit"), \.allowEnlarge), (String(localized: "Rotate to Page"), \.allowRotate),
            (String(localized: "Center on Page"), \.center), (String(localized: "Footer with Date and Title"), \.footer),
            (String(localized: "Inverted Colours"), \.inverted), (String(localized: "Grayscale"), \.grayscale),
            (String(localized: "Black and White"), \.monochrome),
        ]
        for (title, keyPath) in printToggles {
            let setting: AnyKeyPath = (\AppSettings.printing).appending(path: keyPath)
            if !store.policy.isLocked(setting) {
                printing.addItem(toggle(title, p[keyPath: keyPath]) {
                    store.update { settings in
                        settings.printing[keyPath: keyPath].toggle()
                        // Grayscale and black and white exclude each other, like the radio buttons.
                        if keyPath == \PrintSettings.grayscale, settings.printing.grayscale { settings.printing.monochrome = false }
                        if keyPath == \PrintSettings.monochrome, settings.printing.monochrome { settings.printing.grayscale = false }
                    }
                })
            }
            if keyPath == \PrintSettings.promptOptions || keyPath == \PrintSettings.footer { printing.addItem(.separator()) }
        }
        trimSeparators(printing)
        if !printing.items.isEmpty {
            let printingItem = NSMenuItem(title: String(localized: "Print Options"), action: nil, keyEquivalent: "")
            printingItem.submenu = printing
            menu.addItem(printingItem)
        }

        menu.addItem(.separator())
        if !store.isLocked(\.playCameraSound) {
            menu.addItem(toggle(String(localized: "Play Camera Sound"), s.playCameraSound) { store.update { $0.playCameraSound.toggle() } })
        }
        if !store.isLocked(\.showNotifications) && !store.isLocked(\.notificationLevel) {
            menu.addItem(toggle(String(localized: "Show Notifications"), s.showNotifications) { store.update { $0.showNotifications.toggle() } })
        }
        // Upstream `AddRecipeQuickSettings`: the automatic steps' switches come last (RMANAGER).
        RecipeQuickSettingsMenu.append(to: menu, store: store)
        trimSeparators(menu)
        guard !menu.items.isEmpty else { return nil }

        let item = NSMenuItem(title: String(localized: "Quick Settings"), action: nil, keyEquivalent: "")
        item.submenu = menu
        return item
    }

    /// Removes separators at the ends and doubled ones, left by the entries that were left out.
    private static func trimSeparators(_ menu: NSMenu) {
        var previousWasSeparator = true
        for item in menu.items {
            if item.isSeparatorItem && previousWasSeparator { menu.removeItem(item) } else { previousWasSeparator = item.isSeparatorItem }
        }
        if let last = menu.items.last, last.isSeparatorItem { menu.removeItem(last) }
    }

    private static func toggle(_ title: String, _ on: Bool, action: @escaping () -> Void) -> NSMenuItem {
        let entry = ClosureMenuItem(title: title, handler: action)
        entry.state = on ? .on : .off
        return entry
    }

    /// A menu entry showing its global hotkey.
    private func item(_ title: String, _ combo: KeyCombo?, action: @escaping () -> Void) -> NSMenuItem {
        let entry = ClosureMenuItem(title: title, handler: action)
        if let combo, let key = combo.menuKeyEquivalent {
            entry.keyEquivalent = key
            entry.keyEquivalentModifierMask = combo.modifierFlags
        }
        return entry
    }
}
