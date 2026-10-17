// Greenshot for Mac (Community) - an unofficial macOS port of Greenshot
// Copyright (C) 2026 Greenshot for Mac (Community) contributors
// SPDX-License-Identifier: GPL-3.0-or-later

import AppKit
import GreenshotCore

/// The menu bar shown while an editor window is open. Its items go through the responder chain to the editor
/// window, the canvas or the app delegate.
@MainActor
enum MainMenu {
    static func make() -> NSMenu {
        let main = NSMenu()

        let app = submenu(in: main, title: AppInfo.name)
        app.addItem(withTitle: String(localized: "About \(AppInfo.name)"), action: #selector(AppDelegate.showAbout(_:)), keyEquivalent: "")
        app.addItem(.separator())
        app.addItem(withTitle: String(localized: "Settings…"), action: #selector(AppDelegate.showSettings(_:)), keyEquivalent: ",")
        app.addItem(.separator())
        app.addItem(withTitle: String(localized: "Hide \(AppInfo.name)"), action: #selector(NSApplication.hide(_:)), keyEquivalent: "h")
        let hideOthers = app.addItem(withTitle: String(localized: "Hide Others"), action: #selector(NSApplication.hideOtherApplications(_:)), keyEquivalent: "h")
        hideOthers.keyEquivalentModifierMask = [.command, .option]
        app.addItem(withTitle: String(localized: "Show All"), action: #selector(NSApplication.unhideAllApplications(_:)), keyEquivalent: "")
        app.addItem(.separator())
        app.addItem(withTitle: String(localized: "Quit \(AppInfo.name)"), action: #selector(NSApplication.terminate(_:)), keyEquivalent: "q")

        addFileMenu(to: main)

        addEditMenus(to: main)

        addImageMenu(to: main)

        // The editor's Recipes menu (RUI), upstream's order File, Edit, Object, Recipes.
        RecipeMenus.addEditorMenu(to: main)

        addViewMenu(to: main)

        let window = submenu(in: main, title: String(localized: "Window"))
        window.addItem(withTitle: String(localized: "Minimize"), action: #selector(NSWindow.performMiniaturize(_:)), keyEquivalent: "m")
        let zoom = String(localized: "menu.window.zoom", defaultValue: "Zoom",
                          comment: "Window menu: makes the window as large as it fits (macOS's Zoom), not the image zoom")
        window.addItem(withTitle: zoom, action: #selector(NSWindow.performZoom(_:)), keyEquivalent: "")
        window.addItem(.separator())
        window.addItem(withTitle: String(localized: "Bring All to Front"), action: #selector(NSApplication.arrangeInFront(_:)), keyEquivalent: "")
        NSApp.windowsMenu = window

        let help = submenu(in: main, title: String(localized: "Help"))
        help.addItem(withTitle: String(localized: "Greenshot Help"), action: #selector(AppDelegate.openHelp(_:)), keyEquivalent: "?")
        help.addItem(withTitle: String(localized: "Greenshot Website"), action: #selector(AppDelegate.openUpstreamWebsite(_:)), keyEquivalent: "")
        help.addItem(withTitle: String(localized: "Welcome Guide…"), action: #selector(AppDelegate.showWelcomeGuide(_:)), keyEquivalent: "")
        help.addItem(.separator())
        help.addItem(withTitle: String(localized: "Self-Service…"), action: #selector(AppDelegate.showSelfService(_:)), keyEquivalent: "")
        help.addItem(withTitle: String(localized: "Log Viewer…"), action: #selector(AppDelegate.showLogViewer(_:)), keyEquivalent: "")
        help.addItem(.separator())
        help.addItem(withTitle: String(localized: "Report an Issue…"), action: #selector(AppDelegate.reportIssue(_:)), keyEquivalent: "")
        NSApp.helpMenu = help

        return main
    }

    static func submenu(in main: NSMenu, title: String) -> NSMenu {
        let item = main.addItem(withTitle: title, action: nil, keyEquivalent: "")
        let menu = NSMenu(title: title)
        item.submenu = menu
        return menu
    }
}
