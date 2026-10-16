// Greenshot for Mac (Community) - an unofficial macOS port of Greenshot
// Copyright (C) 2026 Greenshot for Mac (Community) contributors
// Based on Greenshot, Copyright (C) 2007-2026 Thomas Braun, Jens Klingen, Robin Krom
// SPDX-License-Identifier: GPL-3.0-or-later

import AppKit
import GreenshotCore

/// The menu bar icon and its menu: upstream's tray icon menu.
@MainActor
final class StatusItemController: NSObject, NSMenuDelegate {
    private let statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.squareLength)
    private unowned let app: AppDelegate

    init(app: AppDelegate) {
        self.app = app
        super.init()
        if let button = statusItem.button {
            let image = NSImage(systemSymbolName: "camera.viewfinder", accessibilityDescription: AppInfo.name)
            image?.isTemplate = true
            button.image = image
            button.toolTip = AppInfo.name
        }
        let menu = NSMenu()
        menu.delegate = self
        statusItem.menu = menu
        // macOS keeps the icon where the user ⌘-dragged it.
        statusItem.autosaveName = "GreenshotStatusItem"
    }

    func menuNeedsUpdate(_ menu: NSMenu) {
        menu.removeAllItems()
        let hotkeys = app.settings.value.hotkeys
        let capture = app.capture

        // Editors hide when another app is clicked; this brings them back.
        if app.editors.hasEditors {
            menu.addItem(ClosureMenuItem(title: "Show Open Screenshots") { [unowned app] in app.editors.showEditors() })
            menu.addItem(.separator())
        }

        menu.addItem(item("Capture Region", hotkeys.region) { capture.captureRegion() })
        menu.addItem(item("Capture Last Region", hotkeys.lastRegion) { capture.captureLastRegion() })
        menu.addItem(item("Capture Window", hotkeys.window) { capture.captureWindowInteractively() })

        let screens = NSScreen.screens
        if screens.count > 1 {
            let fullScreen = NSMenuItem(title: "Capture Full Screen", action: nil, keyEquivalent: "")
            let submenu = NSMenu()
            submenu.addItem(item("All Screens", hotkeys.fullScreen) { capture.captureFullScreen() })
            submenu.addItem(.separator())
            for screen in screens {
                let id = screen.displayID
                submenu.addItem(ClosureMenuItem(title: screen.localizedName) { capture.captureFullScreen(displayID: id) })
            }
            fullScreen.submenu = submenu
            menu.addItem(fullScreen)
        } else {
            menu.addItem(item("Capture Full Screen", hotkeys.fullScreen) { capture.captureFullScreen() })
        }

        let fromList = NSMenuItem(title: "Capture Window from List", action: nil, keyEquivalent: "")
        let windowMenu = NSMenu()
        let windows = ScreenCapturer.onScreenWindows()
        if windows.isEmpty {
            let none = NSMenuItem(title: "No windows", action: nil, keyEquivalent: "")
            none.isEnabled = false
            windowMenu.addItem(none)
        }
        for window in windows.prefix(40) {
            let entry = ClosureMenuItem(title: window.menuTitle) { capture.capture(window: window) }
            if let icon = NSRunningApplication(processIdentifier: window.pid)?.icon {
                icon.size = NSSize(width: 16, height: 16)
                entry.image = icon
            }
            windowMenu.addItem(entry)
        }
        fromList.submenu = windowMenu
        menu.addItem(fromList)

        menu.addItem(.separator())
        menu.addItem(item("Open Image from Clipboard", hotkeys.clipboard) { [unowned app] in app.editors.openClipboard() })
        menu.addItem(ClosureMenuItem(title: "Open Image from File…") { [unowned app] in app.editors.chooseAndOpenFile() })
        menu.addItem(.separator())
        menu.addItem(ClosureMenuItem(title: "Settings…", keyEquivalent: ",") { [unowned app] in app.showSettings(nil) })
        menu.addItem(ClosureMenuItem(title: "About \(AppInfo.name)") { [unowned app] in app.showAbout(nil) })
        menu.addItem(.separator())
        menu.addItem(ClosureMenuItem(title: "Quit", keyEquivalent: "q") { NSApp.terminate(nil) })
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
