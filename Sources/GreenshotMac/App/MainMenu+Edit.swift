// Greenshot for Mac (Community) - an unofficial macOS port of Greenshot
// Copyright (C) 2026 Greenshot for Mac (Community) contributors
// Based on Greenshot, Copyright (C) 2007-2026 Thomas Braun, Jens Klingen, Robin Krom
// SPDX-License-Identifier: GPL-3.0-or-later

import AppKit
import GreenshotCore

/// The Edit (and later Object) menus of the editor.
extension MainMenu {
    static func addEditMenus(to main: NSMenu) {
        let edit = submenu(in: main, title: "Edit")
        edit.addItem(withTitle: "Undo", action: Selector(("undo:")), keyEquivalent: "z")
        let redo = edit.addItem(withTitle: "Redo", action: Selector(("redo:")), keyEquivalent: "z")
        redo.keyEquivalentModifierMask = [.command, .shift]
        edit.addItem(.separator())
        edit.addItem(withTitle: "Cut", action: #selector(NSText.cut(_:)), keyEquivalent: "x")
        edit.addItem(withTitle: "Copy", action: #selector(NSText.copy(_:)), keyEquivalent: "c")
        edit.addItem(withTitle: "Paste", action: #selector(NSText.paste(_:)), keyEquivalent: "v")
        edit.addItem(withTitle: "Duplicate", action: #selector(CanvasView.duplicate(_:)), keyEquivalent: "d")
        edit.addItem(withTitle: "Delete", action: #selector(NSText.delete(_:)), keyEquivalent: "")
        edit.addItem(withTitle: "Select All", action: #selector(NSText.selectAll(_:)), keyEquivalent: "a")
        edit.addItem(.separator())
        // Upstream Edit › Insert window; the list is made when the menu opens.
        let windows = NSMenu(title: "Insert Window")
        windows.delegate = WindowInsertMenu.shared
        edit.addItem(withTitle: "Insert Window", action: nil, keyEquivalent: "").submenu = windows
        // Upstream Plugins › Insert QR / Barcode... (ZxingEditorPlugin).
        edit.addItem(withTitle: "Insert QR / Barcode…", action: #selector(EditorWindowController.insertBarcode(_:)), keyEquivalent: "")

        addObjectMenu(to: main)
    }

    /// Upstream's Object menu: the drawing tools with their one-letter shortcuts, and arranging the elements.
    private static func addObjectMenu(to main: NSMenu) {
        let object = submenu(in: main, title: "Object")
        for (index, tool) in EditorTool.allCases.enumerated() where tool != .select {
            let item = object.addItem(withTitle: tool.menuTitle, action: #selector(CanvasView.selectTool(_:)),
                                      keyEquivalent: String(tool.shortcut))
            // A letter without modifiers, like upstream; CanvasView only enables these while it has the keyboard.
            item.keyEquivalentModifierMask = []
            item.tag = index
        }
        object.addItem(.separator())
        object.addItem(withTitle: "Select All", action: #selector(NSText.selectAll(_:)), keyEquivalent: "")
        object.addItem(withTitle: "Delete", action: #selector(NSText.delete(_:)), keyEquivalent: "")
        object.addItem(.separator())
        let arrange = NSMenu(title: "Arrange")
        object.addItem(withTitle: "Arrange", action: nil, keyEquivalent: "").submenu = arrange
        func add(_ title: String, _ action: Selector, _ key: String, _ modifiers: NSEvent.ModifierFlags) {
            arrange.addItem(withTitle: title, action: action, keyEquivalent: key).keyEquivalentModifierMask = modifiers
        }
        add("Bring to Front", #selector(CanvasView.bringToFront(_:)), "f", [.command, .shift])
        add("Bring Forward", #selector(CanvasView.bringForward(_:)), "f", [.command, .option, .shift])
        add("Send Backward", #selector(CanvasView.sendBackward(_:)), "b", [.command, .option, .shift])
        add("Send to Back", #selector(CanvasView.sendToBack(_:)), "b", [.command, .shift])
        object.addItem(.separator())
        object.addItem(withTitle: "Save Elements…", action: #selector(EditorWindowController.saveElements(_:)), keyEquivalent: "")
        object.addItem(withTitle: "Load Elements…", action: #selector(EditorWindowController.loadElements(_:)), keyEquivalent: "")
    }
}
