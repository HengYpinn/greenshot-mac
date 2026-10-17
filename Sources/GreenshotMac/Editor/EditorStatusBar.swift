// Greenshot for Mac (Community) - an unofficial macOS port of Greenshot
// Copyright (C) 2026 Greenshot for Mac (Community) contributors
// Based on Greenshot, Copyright (C) 2007-2026 Thomas Braun, Jens Klingen, Robin Krom
// SPDX-License-Identifier: GPL-3.0-or-later

import AppKit
import GreenshotCore

/// The editor's status bar (upstream `ImageEditorForm` `statusStrip1`): the image size, the last message (after a save
/// a click on it offers to copy the path or show the file, upstream `fileSavedStatusContextMenu`) and the zoom button
/// with upstream's zoom menu (`zoomStatusDropDownBtn`).
@MainActor
final class EditorStatusBar: NSStackView {
    private let dimensionsLabel = NSTextField(labelWithString: "")
    private let messageLabel = StatusMessageLabel(labelWithString: "")
    let zoomButton = NSPopUpButton(frame: .zero, pullsDown: true)

    /// `zoomItems` are the zoom menu's entries; the button's title is the zoom.
    init(zoomItems: [NSMenuItem]) {
        super.init(frame: .zero)
        let font = NSFont.monospacedDigitSystemFont(ofSize: NSFont.smallSystemFontSize, weight: .regular)
        dimensionsLabel.font = font
        dimensionsLabel.textColor = .secondaryLabelColor
        dimensionsLabel.setContentCompressionResistancePriority(.required, for: .horizontal)
        messageLabel.font = font
        messageLabel.textColor = .secondaryLabelColor
        messageLabel.lineBreakMode = .byTruncatingMiddle
        messageLabel.setContentCompressionResistancePriority(.init(1), for: .horizontal)
        messageLabel.setContentHuggingPriority(.init(1), for: .horizontal)

        zoomButton.controlSize = .small
        zoomButton.font = font
        zoomButton.isBordered = false
        zoomButton.toolTip = "Zoom"
        zoomButton.addItem(withTitle: "100%")
        zoomItems.forEach { zoomButton.menu?.addItem($0) }
        zoomButton.setContentCompressionResistancePriority(.required, for: .horizontal)

        let divider = NSBox()
        divider.boxType = .separator
        divider.heightAnchor.constraint(equalToConstant: 12).isActive = true
        setViews([dimensionsLabel, divider, messageLabel, zoomButton], in: .leading)
        spacing = 8
        alignment = .centerY
        edgeInsets = NSEdgeInsets(top: 2, left: 10, bottom: 2, right: 6)
    }

    required init?(coder: NSCoder) {
        fatalError("not used")
    }

    func setDimensions(_ text: String) {
        dimensionsLabel.stringValue = text
    }

    func setZoom(_ title: String) {
        zoomButton.item(at: 0)?.title = title
        zoomButton.setTitle(title)
    }

    /// The message, in red after an error; `menu` opens on a click on it.
    func setMessage(_ text: String, isError: Bool, menu: NSMenu?) {
        messageLabel.stringValue = text
        messageLabel.textColor = isError ? .systemRed : .secondaryLabelColor
        messageLabel.toolTip = menu == nil ? text : "\(text)\nClick for more"
        messageLabel.clickMenu = menu
    }

    var message: String { messageLabel.stringValue }
}

/// The status bar message: a click (or a right click) opens its menu, like upstream's `StatusLabelClicked`.
private final class StatusMessageLabel: NSTextField {
    var clickMenu: NSMenu? {
        didSet { window?.invalidateCursorRects(for: self) }
    }

    override func mouseDown(with event: NSEvent) {
        guard let clickMenu else { return super.mouseDown(with: event) }
        // Under the label.
        clickMenu.popUp(positioning: nil, at: NSPoint(x: 0, y: isFlipped ? bounds.height + 2 : -2), in: self)
    }

    override func menu(for event: NSEvent) -> NSMenu? {
        clickMenu ?? super.menu(for: event)
    }

    override func resetCursorRects() {
        if clickMenu != nil { addCursorRect(bounds, cursor: .pointingHand) }
    }
}
