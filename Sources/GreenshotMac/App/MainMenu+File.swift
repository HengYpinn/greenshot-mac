// Greenshot for Mac (Community) - an unofficial macOS port of Greenshot
// Copyright (C) 2026 Greenshot for Mac (Community) contributors
// Based on Greenshot, Copyright (C) 2007-2026 Thomas Braun, Jens Klingen, Robin Krom
// SPDX-License-Identifier: GPL-3.0-or-later

import AppKit
import GreenshotCore

/// The File menu: open, close, and the destinations with their shortcuts (upstream `DestinationMenuBuilder`).
extension MainMenu {
    static func addFileMenu(to main: NSMenu) {
        let file = submenu(in: main, title: "File")
        file.addItem(withTitle: "Capture Region", action: #selector(AppDelegate.captureRegion(_:)), keyEquivalent: "")
        file.addItem(withTitle: "Open…", action: #selector(AppDelegate.openImageFile(_:)), keyEquivalent: "o")
        file.addItem(withTitle: "Open Image from Clipboard", action: #selector(AppDelegate.openClipboard(_:)), keyEquivalent: "")
        file.addItem(.separator())
        file.addItem(withTitle: "Close", action: #selector(NSWindow.performClose(_:)), keyEquivalent: "w")
        file.addItem(withTitle: "Save", action: #selector(EditorWindowController.saveImage(_:)), keyEquivalent: "s")
        let saveAs = file.addItem(withTitle: "Save As…", action: #selector(EditorWindowController.saveImageAs(_:)), keyEquivalent: "s")
        saveAs.keyEquivalentModifierMask = [.command, .shift]
        let copyImage = file.addItem(withTitle: "Copy Image to Clipboard", action: #selector(EditorWindowController.copyImage(_:)), keyEquivalent: "c")
        copyImage.keyEquivalentModifierMask = [.command, .shift]
        file.addItem(withTitle: "Print…", action: #selector(EditorWindowController.printImage(_:)), keyEquivalent: "p")
        file.addItem(.separator())
        file.addItem(destinationItem("Email…", .destination(.email), key: "e"))
    }

    /// A File menu entry that sends the front editor's screenshot to a destination (see `AppDelegate.sendToDestination`).
    static func destinationItem(_ title: String, _ target: DestinationTarget, key: String = "",
                                modifiers: NSEvent.ModifierFlags = .command) -> NSMenuItem {
        let item = NSMenuItem(title: title, action: #selector(AppDelegate.sendToDestination(_:)), keyEquivalent: key)
        item.keyEquivalentModifierMask = modifiers
        item.representedObject = DestinationTargetBox(target)
        return item
    }
}
