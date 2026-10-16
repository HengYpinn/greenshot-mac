// Greenshot for Mac (Community) - an unofficial macOS port of Greenshot
// Copyright (C) 2026 Greenshot for Mac (Community) contributors
// Based on Greenshot, Copyright (C) 2007-2026 Thomas Braun, Jens Klingen, Robin Krom
// SPDX-License-Identifier: GPL-3.0-or-later

import AppKit
import GreenshotCore

/// The View menu: zoom in and out, to fit, and upstream's zoom presets.
extension MainMenu {
    static func addViewMenu(to main: NSMenu) {
        let view = submenu(in: main, title: "View")
        view.addItem(withTitle: "Zoom In", action: #selector(EditorWindowController.zoomIn(_:)), keyEquivalent: "=")
        // ⌘+ (Shift-=) zooms in too, without a second visible item.
        let zoomInPlus = view.addItem(withTitle: "Zoom In", action: #selector(EditorWindowController.zoomIn(_:)), keyEquivalent: "+")
        zoomInPlus.isHidden = true
        zoomInPlus.allowsKeyEquivalentWhenHidden = true
        view.addItem(withTitle: "Zoom Out", action: #selector(EditorWindowController.zoomOut(_:)), keyEquivalent: "-")
        view.addItem(withTitle: "Zoom to Fit", action: #selector(EditorWindowController.zoomToFit(_:)), keyEquivalent: "9")
        view.addItem(.separator())
        // Upstream's zoom presets; 100 % is Actual Size (⌘0).
        for percent in EditorWindowController.zoomPresets {
            let item = view.addItem(withTitle: "\(percent) %", action: #selector(EditorWindowController.zoomPreset(_:)),
                                    keyEquivalent: percent == 100 ? "0" : "")
            item.tag = percent
        }

    }
}
