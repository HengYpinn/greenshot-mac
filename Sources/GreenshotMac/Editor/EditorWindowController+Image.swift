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
        let resize = imageButton("arrow.up.left.and.arrow.down.right", "Resize the image (⌥⌘R)", #selector(resizeImage(_:)))
        let rotateLeft = imageButton("rotate.left", "Rotate counter-clockwise (⌥⌘←)", #selector(rotateCounterClockwise(_:)))
        let rotateRight = imageButton("rotate.right", "Rotate clockwise (⌥⌘→)", #selector(rotateClockwise(_:)))
        // Upstream's crop modes (`CropContainer.CropModes`): auto crop, and the rows or columns of the crop tool's
        // selection cut out.
        let crop = NSPopUpButton(frame: .zero, pullsDown: true)
        crop.controlSize = .small
        crop.toolTip = "Auto crop, or cut the rows or columns of the crop selection out"
        crop.addItem(withTitle: "")
        crop.item(at: 0)?.image = NSImage(systemSymbolName: "crop", accessibilityDescription: "Crop modes")
        for (title, action) in Self.cropModeItems {
            let item = NSMenuItem(title: title, action: action, keyEquivalent: "")
            item.target = self
            crop.menu?.addItem(item)
        }
        return [effects, resize, rotateLeft, rotateRight, crop]
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

    /// Brightness, contrast and gamma of the image (upstream `AdjustEffect`).
    @objc func adjustImage(_ sender: Any?) {
        let form = AdjustSettingsForm()
        EffectSettingsDialog.run(title: "Adjust", message: "Brightness, contrast and gamma of the image.",
                                 content: form.view, owner: form, for: window) { [weak self] in
            guard !form.isNeutral else { return }
            self?.performImageOperation { $0.transformImage(form.apply(to:)) }
        }
    }

    // MARK: Resize

    /// Upstream's Resize button ("Z"): asks for the new size, then scales the image and its elements' positions.
    @objc func resizeImage(_ sender: Any?) {
        let form = ResizeForm(size: editorDocument.imageSize)
        EffectSettingsDialog.run(title: "Resize", message: "The new size of the image. The elements move along.",
                                 content: form.view, owner: form, okTitle: "Resize", for: window) { [weak self] in
            guard let size = form.size else { NSSound.beep(); return }
            self?.performImageOperation { $0.resizeImage(to: size) }
        }
    }

    // MARK: Rotate

    /// Upstream `RotateEffect(90)` (Ctrl+.): the image and its elements turn clockwise.
    @objc func rotateClockwise(_ sender: Any?) {
        performImageOperation { $0.rotateImage(clockwise: true) }
    }

    /// Upstream `RotateEffect(270)` (Ctrl+,).
    @objc func rotateCounterClockwise(_ sender: Any?) {
        performImageOperation { $0.rotateImage(clockwise: false) }
    }

    // MARK: Canvas

    /// Upstream "Enlarge canvas" (Ctrl+Shift+Plus, FEATURE-919): 25 pt of transparent canvas on every side.
    @objc func enlargeCanvas(_ sender: Any?) {
        performImageOperation { $0.enlargeCanvas() }
    }

    /// Upstream "Shrink canvas" (Ctrl+Shift+Minus): cuts the transparent margin away again.
    @objc func shrinkCanvas(_ sender: Any?) {
        if !performImageOperation({ $0.shrinkCanvas() }) { NSSound.beep() }
    }

    /// Upstream "Clear" (Ctrl+Delete): the image becomes transparent; its size and the elements stay.
    @objc func clearBackground(_ sender: Any?) {
        performImageOperation { $0.clearImage() }
    }

    /// Upstream "Remove transparency": the transparent parts become white.
    @objc func removeTransparency(_ sender: Any?) {
        if !performImageOperation({ $0.removeTransparency() }) { NSSound.beep() }
    }

    // MARK: Crop modes

    /// The crop mode items of the toolbar and the Image menu.
    static let cropModeItems: [(String, Selector)] = [
        ("Auto Crop", #selector(autoCrop(_:))),
        ("Cut Out the Selected Rows", #selector(cutOutSelectedRows(_:))),
        ("Cut Out the Selected Columns", #selector(cutOutSelectedColumns(_:))),
    ]

    /// Upstream `CropModes.AutoCrop` / `Surface.AutoCrop`: crops away the border of one color around the content
    /// (within the crop selection when there is one).
    @objc func autoCrop(_ sender: Any?) {
        let area = canvas.tool == .crop ? canvas.cropRect : nil
        let difference = settings.value.autoCropDifference
        if performImageOperation({ $0.autoCrop(difference: difference, area: area) }) {
            canvas.tool = .select
            return
        }
        let alert = NSAlert()
        alert.messageText = "Auto crop is not possible"
        alert.informativeText = "There is no border of one color around the content to crop away."
        if let window { alert.beginSheetModal(for: window) } else { alert.runModal() }
    }

    /// Upstream `CropModes.Horizontal`: cuts the rows of the crop selection out and joins the parts above and below.
    @objc func cutOutSelectedRows(_ sender: Any?) {
        cutOut(horizontal: true)
    }

    /// Upstream `CropModes.Vertical`: cuts the columns of the crop selection out and joins the parts left and right.
    @objc func cutOutSelectedColumns(_ sender: Any?) {
        cutOut(horizontal: false)
    }

    /// The joint is marked with the cut mark style chosen in the crop bar (a cut mark element with the last used
    /// teeth, colors and shadow), which is selected afterwards so it can be changed.
    private func cutOut(horizontal: Bool) {
        guard let selection = canvas.cropRect else { NSSound.beep(); return }
        let values = settings.value
        let markStyle = values.style(for: .cutMark)
        let joint = values.cutOutMarkStyle
        let before = Set(editorDocument.annotations.map(\.id))
        guard performImageOperation({ $0.cutOut(selection, horizontal: horizontal, cutMark: joint, markStyle: markStyle) }) else {
            NSSound.beep()
            return
        }
        canvas.tool = .select
        if let mark = editorDocument.annotations.first(where: { $0.kind == .cutMark && !before.contains($0.id) }) {
            canvas.select(mark.id)
        }
    }

    // MARK: Text obfuscation

    /// Upstream "Obfuscate Text…": covers the text found in the image with obfuscate or highlight elements.
    @objc func obfuscateText(_ sender: Any?) {
        guard let window else { return }
        canvas.commitEditing()
        let sheet = TextObfuscationSheet(image: editorDocument.baseImage, settings: settings.value.textObfuscation,
                                         language: settings.value.ocrLanguage)
        sheet.onSaveSettings = { [weak self] options in self?.settings.update { $0.textObfuscation = options } }
        sheet.onApply = { [weak self] boxes, effect in
            guard let self else { return }
            let style = self.settings.value
            let elements = TextObfuscation.annotations(for: boxes, effect: effect) { style.style(for: $0) }
            self.performImageOperation { document in
                elements.forEach(document.add)
                return true
            }
        }
        sheet.begin(for: window)
    }

    // MARK: Helpers

    /// A toolbar button with an SF Symbol, like the editor's other icon buttons.
    func imageButton(_ symbol: String, _ tooltip: String, _ action: Selector) -> NSButton {
        let button = NSButton(image: NSImage(systemSymbolName: symbol, accessibilityDescription: tooltip) ?? NSImage(),
                              target: self, action: action)
        button.bezelStyle = .toolbar
        button.toolTip = tooltip
        return button
    }

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

extension EditorWindowController {
    /// Enables the image operations that have something to do; nil for items this file doesn't know (the main
    /// `validateMenuItem` asks here first).
    func validateImageMenuItem(_ item: NSMenuItem) -> Bool? {
        switch item.action {
        case #selector(removeTransparency(_:)):
            return TransparencyCheck.hasTransparency(editorDocument.baseImage)
        case #selector(cutOutSelectedRows(_:)), #selector(cutOutSelectedColumns(_:)):
            return canvas.tool == .crop && canvas.cropRect != nil
        case #selector(clearBackground(_:)):
            // ⌘⌫ deletes to the start of the line while a text element is being typed.
            return !canvas.isEditingText
        default:
            return nil
        }
    }
}

/// Whether the image has transparent pixels, remembered for the last image: the menu asks every time it opens.
@MainActor
private enum TransparencyCheck {
    private static var image: CGImage?
    private static var result = false

    static func hasTransparency(_ image: CGImage) -> Bool {
        if image !== self.image {
            self.image = image
            result = ImageOperations.hasTransparency(image)
        }
        return result
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
