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
        app.addItem(withTitle: "About \(AppInfo.name)", action: #selector(AppDelegate.showAbout(_:)), keyEquivalent: "")
        app.addItem(.separator())
        app.addItem(withTitle: "Settings…", action: #selector(AppDelegate.showSettings(_:)), keyEquivalent: ",")
        app.addItem(.separator())
        app.addItem(withTitle: "Hide \(AppInfo.name)", action: #selector(NSApplication.hide(_:)), keyEquivalent: "h")
        let hideOthers = app.addItem(withTitle: "Hide Others", action: #selector(NSApplication.hideOtherApplications(_:)), keyEquivalent: "h")
        hideOthers.keyEquivalentModifierMask = [.command, .option]
        app.addItem(withTitle: "Show All", action: #selector(NSApplication.unhideAllApplications(_:)), keyEquivalent: "")
        app.addItem(.separator())
        app.addItem(withTitle: "Quit \(AppInfo.name)", action: #selector(NSApplication.terminate(_:)), keyEquivalent: "q")

        addFileMenu(to: main)

        addEditMenus(to: main)

        addImageMenu(to: main)

        addViewMenu(to: main)

        let window = submenu(in: main, title: "Window")
        window.addItem(withTitle: "Minimize", action: #selector(NSWindow.performMiniaturize(_:)), keyEquivalent: "m")
        window.addItem(withTitle: "Zoom", action: #selector(NSWindow.performZoom(_:)), keyEquivalent: "")
        window.addItem(.separator())
        window.addItem(withTitle: "Bring All to Front", action: #selector(NSApplication.arrangeInFront(_:)), keyEquivalent: "")
        NSApp.windowsMenu = window

        let help = submenu(in: main, title: "Help")
        help.addItem(withTitle: "Greenshot Help", action: #selector(AppDelegate.openHelp(_:)), keyEquivalent: "?")
        help.addItem(withTitle: "Greenshot Website", action: #selector(AppDelegate.openUpstreamWebsite(_:)), keyEquivalent: "")
        help.addItem(.separator())
        help.addItem(withTitle: "Report an Issue…", action: #selector(AppDelegate.reportIssue(_:)), keyEquivalent: "")
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
