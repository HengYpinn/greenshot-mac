// Greenshot for Mac (Community) - an unofficial macOS port of Greenshot
// Copyright (C) 2026 Greenshot for Mac (Community) contributors
// Based on Greenshot, Copyright (C) 2007-2026 Thomas Braun, Jens Klingen, Robin Krom
// SPDX-License-Identifier: GPL-3.0-or-later

import AppKit
import GreenshotCore

/// The operations on the whole image (upstream's Effects split button and the resize, rotate and canvas buttons
/// of `ImageEditorForm`): their toolbar items and their actions, which the Image menu also reaches.
extension EditorWindowController {
    /// The toolbar items between Undo/Redo and the element properties.
    func imageToolbarItems() -> [NSView] {
        // Upstream's Effects menu: a pull-down whose first item is its button.
        let effects = NSPopUpButton(frame: .zero, pullsDown: true)
        effects.controlSize = .small
        effects.toolTip = "Effects on the whole image"
        effects.addItem(withTitle: "Effects")
        effects.item(at: 0)?.image = NSImage(systemSymbolName: "sparkles", accessibilityDescription: nil)
        for (index, effect) in ImageEffect.allCases.enumerated() {
            let item = NSMenuItem(title: effect.title, action: #selector(applyEffect(_:)), keyEquivalent: "")
            item.target = self
            item.tag = index
            effects.menu?.addItem(item)
        }
        return [effects]
    }

    /// An item of the Effects menu (in the window and the main menu); its tag is the effect's index.
    @objc func applyEffect(_ sender: NSMenuItem) {
        guard ImageEffect.allCases.indices.contains(sender.tag) else { return }
        canvas.apply(ImageEffect.allCases[sender.tag])
    }
}
