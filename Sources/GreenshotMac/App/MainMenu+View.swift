// Greenshot for Mac (Community) - an unofficial macOS port of Greenshot
// Copyright (C) 2026 Greenshot for Mac (Community) contributors
// Based on Greenshot, Copyright (C) 2007-2026 Thomas Braun, Jens Klingen, Robin Krom
// SPDX-License-Identifier: GPL-3.0-or-later

import AppKit
import GreenshotCore

/// The View menu: upstream's zoom menu (`ImageEditorForm` `zoomMenuStrip`), also behind the status bar's zoom button.
extension MainMenu {
    static func addViewMenu(to main: NSMenu) {
        let view = submenu(in: main, title: "View")
        zoomItems(target: nil, withKeys: true).forEach(view.addItem)
    }

    /// Zoom in and out, best fit, the presets below 100 %, 100 % (Actual Size), the presets above, in upstream's
    /// groups. `withKeys` gives them their shortcuts (the main menu); `target` nil goes to the front editor.
    static func zoomItems(target: AnyObject?, withKeys: Bool) -> [NSMenuItem] {
        var items: [NSMenuItem] = []
        func add(_ title: String, _ action: Selector, key: String = "", tag: Int = 0) -> NSMenuItem {
            let item = NSMenuItem(title: title, action: action, keyEquivalent: withKeys ? key : "")
            item.target = target
            item.tag = tag
            items.append(item)
            return item
        }
        _ = add("Zoom In", #selector(EditorWindowController.zoomIn(_:)), key: "=")
        if withKeys {
            // ⌘+ (Shift-=) zooms in too, without a second visible item.
            let zoomInPlus = add("Zoom In", #selector(EditorWindowController.zoomIn(_:)), key: "+")
            zoomInPlus.isHidden = true
            zoomInPlus.allowsKeyEquivalentWhenHidden = true
        }
        _ = add("Zoom Out", #selector(EditorWindowController.zoomOut(_:)), key: "-")
        items.append(.separator())
        _ = add("Zoom to Fit", #selector(EditorWindowController.zoomToFit(_:)), key: "9")
        for percent in EditorWindowController.zoomPresets {
            if percent == 25 || percent == 100 || percent == 200 { items.append(.separator()) }
            _ = add("\(percent) %", #selector(EditorWindowController.zoomPreset(_:)), key: percent == 100 ? "0" : "", tag: percent)
        }
        return items
    }
}
