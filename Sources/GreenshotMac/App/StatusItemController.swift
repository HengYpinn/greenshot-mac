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
            let image = NSImage(systemSymbolName: "camera.viewfinder", accessibilityDescription: AppInfo.name)
            image?.isTemplate = true
            button.image = image
            button.toolTip = AppInfo.name
            button.target = self
            button.action = #selector(iconClicked(_:))
            button.sendAction(on: [.leftMouseUp, .rightMouseUp])
        }
        applySettings()
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
        let settings = app.settings.value
        let hotkeys = settings.hotkeys
        let capture = app.capture

        // Editors hide when another app is clicked; this brings them back.
        if app.editors.hasEditors {
            menu.addItem(ClosureMenuItem(title: "Show Open Screenshots") { [unowned app] in app.editors.showEditors() })
            menu.addItem(.separator())
        }

        menu.addItem(item("Capture Region", hotkeys.region) { capture.captureRegion() })
        let lastRegion = item("Capture Last Region", hotkeys.lastRegion) { capture.captureLastRegion() }
        // Upstream greys it out until a region was captured (TrayMenu.cs).
        lastRegion.isEnabled = settings.lastCapturedRegion != nil
        menu.addItem(lastRegion)
        menu.addItem(item("Capture Window", hotkeys.window) { capture.captureWindowInteractively() })
        menu.addItem(item("Capture Text", hotkeys.text) { capture.captureText() })
        menu.addItem(fullScreenItem(hotkey: hotkeys.fullScreen))
        menu.addItem(windowList.makeItem())

        menu.addItem(.separator())
        let clipboard = item("Open Image from Clipboard", hotkeys.clipboard) { [unowned app] in app.editors.openClipboard() }
        clipboard.isEnabled = NSImage.canInit(with: .general)
        menu.addItem(clipboard)
        menu.addItem(ClosureMenuItem(title: "Open Image from File…") { [unowned app] in MenuBarActions.openFilesToDestinations(app: app) })
        menu.addItem(recentCaptureItem())
        menu.addItem(.separator())
        menu.addItem(quickSettingsItem())
        menu.addItem(ClosureMenuItem(title: "Settings…", keyEquivalent: ",") { [unowned app] in app.showSettings(nil) })
        menu.addItem(.separator())
        menu.addItem(ClosureMenuItem(title: "Help") { NSWorkspace.shared.open(AppInfo.helpURL) })
        menu.addItem(ClosureMenuItem(title: "About \(AppInfo.name)") { [unowned app] in app.showAbout(nil) })
        menu.addItem(.separator())
        menu.addItem(ClosureMenuItem(title: "Quit", keyEquivalent: "q") { NSApp.terminate(nil) })
    }

    /// "Capture Full Screen"; with several displays a submenu with all of them and each one, named with upstream's
    /// position words (TrayMenu.cs `CreateFullscreenItem`).
    private func fullScreenItem(hotkey: KeyCombo?) -> NSMenuItem {
        let capture = app.capture
        let screens = NSScreen.screens
        guard screens.count > 1 else {
            return item("Capture Full Screen", hotkey) { capture.captureFullScreen() }
        }
        let fullScreen = NSMenuItem(title: "Capture Full Screen", action: nil, keyEquivalent: "")
        let submenu = NSMenu()
        submenu.addItem(item("All Screens", hotkey) { capture.captureFullScreen() })
        submenu.addItem(.separator())
        let frames = screens.map { CGDisplayBounds($0.displayID) }
        for (screen, frame) in zip(screens, frames) {
            let id = screen.displayID
            let title = ScreenPosition.label(name: screen.localizedName, frame: frame, among: frames)
            submenu.addItem(ClosureMenuItem(title: title) { capture.captureFullScreen(displayID: id) })
        }
        fullScreen.submenu = submenu
        return fullScreen
    }

    /// Upstream's "Open last capture location": the last saved file in Finder, else its folder or the output folder.
    private func recentCaptureItem() -> NSMenuItem {
        let settings = app.settings
        let entry = ClosureMenuItem(title: "Open Last Capture Location") { MenuBarActions.openLastCaptureLocation(settings: settings) }
        if let path = settings.value.lastSavedFile {
            entry.toolTip = (path as NSString).abbreviatingWithTildeInPath
        }
        return entry
    }

    /// Upstream's quick settings in the tray menu (`TrayMenu.cs`): the most used options as check items.
    private func quickSettingsItem() -> NSMenuItem {
        let store = app.settings
        let s = store.value
        let menu = NSMenu(title: "Quick Settings")
        menu.autoenablesItems = false
        menu.addItem(toggle("Capture Mouse Pointer", s.captureMousePointer) { store.update { $0.captureMousePointer.toggle() } })

        let destinations = NSMenu(title: "Destinations")
        destinations.autoenablesItems = false
        for destination in CaptureDestination.allCases {
            let on = s.destinations.contains(destination)
            destinations.addItem(toggle(destination.displayName, on) { store.update { $0.setDestination(destination, on: !on) } })
            if destination == .picker { destinations.addItem(.separator()) }
        }
        let destinationsItem = NSMenuItem(title: "After a Capture", action: nil, keyEquivalent: "")
        destinationsItem.submenu = destinations
        menu.addItem(destinationsItem)

        let printing = NSMenu(title: "Print Options")
        printing.autoenablesItems = false
        let p = s.printing
        let printToggles: [(String, WritableKeyPath<PrintSettings, Bool>)] = [
            ("Ask Every Time", \.promptOptions), ("Shrink to Fit", \.allowShrink), ("Enlarge to Fit", \.allowEnlarge),
            ("Rotate to Page", \.allowRotate), ("Center on Page", \.center), ("Footer with Date and Title", \.footer),
            ("Inverted Colours", \.inverted), ("Grayscale", \.grayscale), ("Black and White", \.monochrome),
        ]
        for (title, keyPath) in printToggles {
            printing.addItem(toggle(title, p[keyPath: keyPath]) {
                store.update { settings in
                    settings.printing[keyPath: keyPath].toggle()
                    // Grayscale and black and white exclude each other, like the radio buttons.
                    if keyPath == \PrintSettings.grayscale, settings.printing.grayscale { settings.printing.monochrome = false }
                    if keyPath == \PrintSettings.monochrome, settings.printing.monochrome { settings.printing.grayscale = false }
                }
            })
            if keyPath == \PrintSettings.promptOptions || keyPath == \PrintSettings.footer { printing.addItem(.separator()) }
        }
        let printingItem = NSMenuItem(title: "Print Options", action: nil, keyEquivalent: "")
        printingItem.submenu = printing
        menu.addItem(printingItem)

        menu.addItem(.separator())
        menu.addItem(toggle("Play Camera Sound", s.playCameraSound) { store.update { $0.playCameraSound.toggle() } })
        menu.addItem(toggle("Show Notifications", s.showNotifications) { store.update { $0.showNotifications.toggle() } })

        let item = NSMenuItem(title: "Quick Settings", action: nil, keyEquivalent: "")
        item.submenu = menu
        return item
    }

    private func toggle(_ title: String, _ on: Bool, action: @escaping () -> Void) -> NSMenuItem {
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
