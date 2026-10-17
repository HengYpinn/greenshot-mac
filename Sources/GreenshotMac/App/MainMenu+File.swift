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
        // Upstream opens an empty editor of `DefaultEditorSize` (500 × 500).
        let newImage = file.addItem(withTitle: "New Image", action: #selector(EditorMenuActions.newImage(_:)), keyEquivalent: "n")
        newImage.target = EditorMenuActions.shared
        file.addItem(withTitle: "Open…", action: #selector(AppDelegate.openImageFile(_:)), keyEquivalent: "o")
        file.addItem(withTitle: "Open Image from Clipboard", action: #selector(AppDelegate.openClipboard(_:)), keyEquivalent: "")
        file.addItem(.separator())
        file.addItem(withTitle: "Close", action: #selector(NSWindow.performClose(_:)), keyEquivalent: "w")
        let closeAll = file.addItem(withTitle: "Close All", action: #selector(EditorWindowController.closeAllWindows(_:)), keyEquivalent: "w")
        closeAll.keyEquivalentModifierMask = [.command, .option]
        file.addItem(withTitle: "Save", action: #selector(EditorWindowController.saveImage(_:)), keyEquivalent: "s")
        let saveAs = file.addItem(withTitle: "Save As…", action: #selector(EditorWindowController.saveImageAs(_:)), keyEquivalent: "s")
        saveAs.keyEquivalentModifierMask = [.command, .shift]
        // Upstream's "Greenshot Editor" format (.greenshot): the image with elements that stay editable.
        file.addItem(withTitle: "Save as Greenshot File…", action: #selector(EditorWindowController.saveAsGreenshotFile(_:)),
                     keyEquivalent: "")
        // The saved file (upstream's status bar menu after a save: copy the path, open the folder).
        file.addItem(withTitle: "Show in Finder", action: #selector(EditorWindowController.showInFinder(_:)), keyEquivalent: "")
        file.addItem(withTitle: "Copy Path", action: #selector(EditorWindowController.copyFilePath(_:)), keyEquivalent: "")
        file.addItem(destinationItem("Save as PDF…", .pdfAs, key: "p", modifiers: [.command, .option]))
        let copyImage = file.addItem(withTitle: "Copy Image to Clipboard", action: #selector(EditorWindowController.copyImage(_:)), keyEquivalent: "c")
        copyImage.keyEquivalentModifierMask = [.command, .shift]
        file.addItem(withTitle: "Print…", action: #selector(EditorWindowController.printImage(_:)), keyEquivalent: "p")
        file.addItem(destinationItem("Copy Text (OCR)", .destination(.ocr), key: "t", modifiers: [.command, .option]))
        file.addItem(.separator())
        file.addItem(destinationItem("Email…", .destination(.email), key: "e"))
        file.addItem(destinationItem("Share…", .destination(.share)))
        for upload in [CaptureDestination.jira, .confluence, .box, .dropbox] {
            file.addItem(destinationItem(upload.displayName, .destination(upload)))
        }
        OfficeMenus.fileMenuItems().forEach(file.addItem)
        let openWith = file.addItem(withTitle: "Open With", action: nil, keyEquivalent: "")
        openWith.submenu = NSMenu(title: "Open With")
        openWith.submenu?.delegate = DynamicFileMenus.openWith
        file.addItem(destinationItem("QR Code Actions…", .destination(.qrCode)))
        let external = file.addItem(withTitle: "External Command", action: nil, keyEquivalent: "")
        external.submenu = NSMenu(title: "External Command")
        external.submenu?.delegate = DynamicFileMenus.externalCommands
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

/// The menus whose entries come from the settings, filled each time they open: the File menu's Open With and External
/// Command submenus, and the drop-downs of the editor's toolbar.
@MainActor
final class DynamicFileMenus: NSObject, NSMenuDelegate {
    enum Kind {
        case openWith, externalCommands
    }

    static let openWith = DynamicFileMenus(.openWith)
    static let externalCommands = DynamicFileMenus(.externalCommands)

    let kind: Kind
    /// A pull-down button's menu: its first item is the button itself and stays.
    let keepsTitleItem: Bool

    init(_ kind: Kind, keepsTitleItem: Bool = false) {
        self.kind = kind
        self.keepsTitleItem = keepsTitleItem
    }

    func menuNeedsUpdate(_ menu: NSMenu) {
        guard let app = NSApp.delegate as? AppDelegate else { return }
        let titleItem = keepsTitleItem ? menu.items.first : nil
        menu.removeAllItems()
        if let titleItem { menu.addItem(titleItem) }
        switch kind {
        case .externalCommands:
            let commands = app.settings.value.externalCommands
            for command in commands {
                menu.addItem(MainMenu.destinationItem(command.name, .externalCommand(command)))
            }
            if commands.isEmpty {
                menu.addItem(NSMenuItem(title: "None set up", action: nil, keyEquivalent: ""))
            }
            menu.addItem(.separator())
            menu.addItem(withTitle: "Set Up Commands…", action: #selector(AppDelegate.showSettings(_:)), keyEquivalent: "")
        case .openWith:
            let format = app.settings.value.outputFormat
            for application in OpenWithDestination.applications(for: format).prefix(30) {
                let item = MainMenu.destinationItem(OpenWithDestination.name(of: application), .application(application))
                let icon = NSWorkspace.shared.icon(forFile: application.path)
                icon.size = NSSize(width: 16, height: 16)
                item.image = icon
                menu.addItem(item)
            }
            menu.addItem(.separator())
            menu.addItem(MainMenu.destinationItem("Other…", .application(nil)))
        }
    }
}

/// Main menu actions that also work without an editor window.
@MainActor
final class EditorMenuActions: NSObject {
    static let shared = EditorMenuActions()

    /// File › New Image.
    @objc func newImage(_ sender: Any?) {
        (NSApp.delegate as? AppDelegate)?.editors.openEmptyEditor()
    }
}
