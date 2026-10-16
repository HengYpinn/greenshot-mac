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
        // Items are enabled or disabled here, not by the responder chain.
        menu.autoenablesItems = false
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
        let clipboard = item("Open Image from Clipboard", hotkeys.clipboard) { [unowned app] in app.editors.openClipboard() }
        clipboard.isEnabled = NSImage.canInit(with: .general)
        menu.addItem(clipboard)
        menu.addItem(ClosureMenuItem(title: "Open Image from File…") { [unowned app] in app.editors.chooseAndOpenFile() })
        menu.addItem(recentCaptureItem())
        menu.addItem(.separator())
        menu.addItem(quickSettingsItem())
        menu.addItem(ClosureMenuItem(title: "Settings…", keyEquivalent: ",") { [unowned app] in app.showSettings(nil) })
        menu.addItem(ClosureMenuItem(title: "About \(AppInfo.name)") { [unowned app] in app.showAbout(nil) })
        menu.addItem(.separator())
        menu.addItem(ClosureMenuItem(title: "Quit", keyEquivalent: "q") { NSApp.terminate(nil) })
    }

    /// Upstream's "Open last capture in explorer": shows the last saved file in Finder.
    private func recentCaptureItem() -> NSMenuItem {
        let path = app.settings.value.lastSavedFile
        let url = path.map { URL(fileURLWithPath: $0) }
        let entry = ClosureMenuItem(title: "Open Recent Capture") {
            if let url { NSWorkspace.shared.activateFileViewerSelecting([url]) }
        }
        if let url {
            entry.toolTip = (url.path as NSString).abbreviatingWithTildeInPath
        }
        entry.isEnabled = url.map { FileManager.default.fileExists(atPath: $0.path) } ?? false
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
