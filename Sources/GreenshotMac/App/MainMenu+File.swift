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
        file.addItem(destinationItem("Save as PDF…", .pdfAs, key: "p", modifiers: [.command, .option]))
        let copyImage = file.addItem(withTitle: "Copy Image to Clipboard", action: #selector(EditorWindowController.copyImage(_:)), keyEquivalent: "c")
        copyImage.keyEquivalentModifierMask = [.command, .shift]
        file.addItem(withTitle: "Print…", action: #selector(EditorWindowController.printImage(_:)), keyEquivalent: "p")
        file.addItem(destinationItem("Copy Text (OCR)", .destination(.ocr), key: "t", modifiers: [.command, .option]))
        file.addItem(.separator())
        file.addItem(destinationItem("Email…", .destination(.email), key: "e"))
        file.addItem(destinationItem("Share…", .destination(.share)))
        let external = file.addItem(withTitle: "External Command", action: nil, keyEquivalent: "")
        external.submenu = NSMenu(title: "External Command")
        external.submenu?.delegate = DynamicFileMenus.shared
        DynamicFileMenus.shared.externalCommands = external.submenu
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

/// The File menu's submenus whose entries come from the settings, filled each time they open.
@MainActor
final class DynamicFileMenus: NSObject, NSMenuDelegate {
    static let shared = DynamicFileMenus()
    weak var externalCommands: NSMenu?

    func menuNeedsUpdate(_ menu: NSMenu) {
        guard let app = NSApp.delegate as? AppDelegate else { return }
        menu.removeAllItems()
        if menu === externalCommands {
            for command in app.settings.value.externalCommands {
                menu.addItem(MainMenu.destinationItem(command.name, .externalCommand(command)))
            }
            if menu.items.isEmpty {
                menu.addItem(NSMenuItem(title: "None set up", action: nil, keyEquivalent: ""))
            }
            menu.addItem(.separator())
            menu.addItem(withTitle: "Set Up Commands…", action: #selector(AppDelegate.showSettings(_:)), keyEquivalent: "")
        }
    }
}
