// Greenshot for Mac (Community) - an unofficial macOS port of Greenshot
// Copyright (C) 2026 Greenshot for Mac (Community) contributors
// Based on Greenshot, Copyright (C) 2007-2026 Thomas Braun, Jens Klingen, Robin Krom
// SPDX-License-Identifier: GPL-3.0-or-later

import AppKit
import GreenshotCore

/// The Image menu: upstream's Effects split button and the image operations (resize, rotate, canvas).
extension MainMenu {
    static func addImageMenu(to main: NSMenu) {
        let image = submenu(in: main, title: "Image")

        // Upstream's Effects menu.
        for (index, effect) in ImageEffect.allCases.enumerated() {
            let item = image.addItem(withTitle: effect.menuTitle, action: #selector(EditorWindowController.applyEffect(_:)),
                                     keyEquivalent: effect.keyEquivalent)
            item.keyEquivalentModifierMask = [.control, .command]
            item.tag = index
        }

        image.addItem(.separator())
        // Upstream's Resize button (key Z there; single letters choose the tools in the canvas, so ⌥⌘R here).
        image.addItem(withTitle: "Resize…", action: #selector(EditorWindowController.resizeImage(_:)), keyEquivalent: "r")
            .keyEquivalentModifierMask = [.option, .command]
        // Upstream Ctrl+. and Ctrl+,; ⌘, opens the Settings on a Mac, so the arrows with ⌥⌘.
        image.addItem(withTitle: "Rotate Clockwise", action: #selector(EditorWindowController.rotateClockwise(_:)),
                      keyEquivalent: arrow(NSRightArrowFunctionKey)).keyEquivalentModifierMask = [.option, .command]
        image.addItem(withTitle: "Rotate Counter-Clockwise", action: #selector(EditorWindowController.rotateCounterClockwise(_:)),
                      keyEquivalent: arrow(NSLeftArrowFunctionKey)).keyEquivalentModifierMask = [.option, .command]
    }

    private static func arrow(_ key: Int) -> String {
        String(utf16CodeUnits: [UInt16(key)], count: 1)
    }
}
