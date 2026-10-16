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
            let item = NSMenuItem(title: effect.menuTitle, action: #selector(applyEffect(_:)), keyEquivalent: "")
            item.target = self
            item.tag = index
            effects.menu?.addItem(item)
        }
        return [effects]
    }

    // MARK: Effects

    /// An item of the Effects menu (in the window and the main menu); its tag is the effect's index. Drop shadow
    /// and torn edges ask for their settings first (upstream opens the dialog with a right click), the others apply.
    @objc func applyEffect(_ sender: NSMenuItem) {
        guard ImageEffect.allCases.indices.contains(sender.tag) else { return }
        let effect = ImageEffect.allCases[sender.tag]
        switch effect {
        case .dropShadow: showDropShadowSettings()
        case .tornEdge: showTornEdgeSettings()
        default: applyWithSettings(effect)
        }
    }

    private func showDropShadowSettings() {
        let form = DropShadowSettingsForm(settings.value.dropShadowSettings)
        EffectSettingsDialog.run(title: "Drop Shadow", message: "A soft shadow behind the image.", content: form.view,
                                 owner: form, for: window) { [weak self] in
            self?.settings.update { $0.dropShadowSettings = form.settings }
            self?.applyWithSettings(.dropShadow)
        }
    }

    private func showTornEdgeSettings() {
        let form = TornEdgeSettingsForm(settings.value.tornEdgeSettings)
        EffectSettingsDialog.run(title: "Torn Edges", message: "Tears the chosen edges of the image.", content: form.view,
                                 owner: form, for: window) { [weak self] in
            self?.settings.update { $0.tornEdgeSettings = form.settings }
            self?.applyWithSettings(.tornEdge)
        }
    }

    private func applyWithSettings(_ effect: ImageEffect) {
        let shadow = settings.value.dropShadowSettings
        let torn = settings.value.tornEdgeSettings
        performImageOperation { $0.apply(effect, dropShadow: shadow, tornEdge: torn) }
    }

    // MARK: Helpers

    /// Runs `operation` on the document as one undo step and shows the result. Returns what the operation returned.
    @discardableResult
    func performImageOperation(_ operation: (EditorDocument) -> Bool) -> Bool {
        canvas.commitEditing()
        canvas.cancelCrop()
        var done = false
        editorDocument.change { done = operation(editorDocument) }
        canvas.documentChanged()
        return done
    }
}

extension ImageEffect {
    /// The title in menus: the effects that open a settings dialog end in an ellipsis.
    var menuTitle: String {
        switch self {
        case .dropShadow, .tornEdge: return title + "…"
        default: return title
        }
    }

    /// The Image menu's shortcut, with ⌃⌘. Upstream uses Ctrl+B/Q/T/G/I, but ⌘B/I/T/G/Q are bold, italic, fonts,
    /// find next and quit on a Mac, and ⌃⌘Q locks the screen (the app never sees it), so the drop shadow is ⌃⌘S.
    var keyEquivalent: String {
        switch self {
        case .border: return "b"
        case .dropShadow: return "s"
        case .tornEdge: return "t"
        case .grayscale: return "g"
        case .invert: return "i"
        }
    }
}
