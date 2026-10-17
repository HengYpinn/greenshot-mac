// Greenshot for Mac (Community) - an unofficial macOS port of Greenshot
// Copyright (C) 2026 Greenshot for Mac (Community) contributors
// Based on Greenshot, Copyright (C) 2007-2026 Thomas Braun, Jens Klingen, Robin Krom
// SPDX-License-Identifier: GPL-3.0-or-later

import AppKit
import GreenshotCore

/// The editor's upper toolbar (upstream `ImageEditorForm` `destinationsToolStrip`): save, copy and print the image,
/// delete, cut, copy and paste elements, undo, the image operations, a button per destination (upstream
/// `AddDestinations`: the destinations after the first ones, with a drop-down when they have sub-entries), settings
/// and help. In a narrow window the destinations go first, then settings and help.
@MainActor
final class EditorActionBar: NSObject {
    let view = NSStackView()
    private weak var editor: EditorWindowController?
    private let deleteButton: NSButton
    private let cutButton: NSButton
    private let copyButton: NSButton
    private let pasteButton: NSButton
    /// Off while a crop is pending.
    private var lockable: [NSControl] = []
    /// The drop-downs' menus are filled when they open (their delegates are weak).
    private let openWithMenus = DynamicFileMenus(.openWith, keepsTitleItem: true)
    private let externalCommandMenus = DynamicFileMenus(.externalCommands, keepsTitleItem: true)

    /// Visibility priorities: what a narrow window drops first.
    private enum Priority {
        static let destinations = NSStackView.VisibilityPriority(rawValue: 500)
        static let appButtons = NSStackView.VisibilityPriority(rawValue: 600)
        static let imageItems = NSStackView.VisibilityPriority(rawValue: 700)
        static let editButtons = NSStackView.VisibilityPriority(rawValue: 800)
    }

    init(editor: EditorWindowController, imageItems: [NSView]) {
        self.editor = editor
        deleteButton = EditorWindowController.iconButton("trash", "Delete the selected elements (⌫)")
        cutButton = EditorWindowController.iconButton("scissors", "Cut the selected elements (⌘X)")
        copyButton = EditorWindowController.iconButton("doc.on.doc", "Copy the selected elements (⌘C)")
        pasteButton = EditorWindowController.iconButton("doc.on.clipboard", "Paste (⌘V)")
        super.init()
        let file = [
            button("square.and.arrow.down", "Save (⌘S)", #selector(EditorWindowController.saveImage(_:)), to: editor),
            button("square.and.arrow.down.on.square", "Save As… (⇧⌘S)", #selector(EditorWindowController.saveImageAs(_:)), to: editor),
            button("clipboard", "Copy the image to the clipboard (⇧⌘C)", #selector(EditorWindowController.copyImage(_:)), to: editor),
            button("printer", "Print… (⌘P)", #selector(EditorWindowController.printImage(_:)), to: editor),
        ]
        for (control, action) in [(deleteButton, #selector(deleteElements)), (cutButton, #selector(cutElements)),
                                  (copyButton, #selector(copyElements)), (pasteButton, #selector(pasteElements))] {
            control.target = self
            control.action = action
        }
        let settings = button("gearshape", "Settings… (⌘,)", #selector(AppDelegate.showSettings(_:)), to: nil)
        let help = button("questionmark.circle", "Greenshot Help", #selector(AppDelegate.openHelp(_:)), to: nil)
        let destinations = destinationItems()
        lockable = file + [deleteButton, cutButton, copyButton, pasteButton] + destinations.compactMap { $0 as? NSControl }

        let spacer = NSView()
        spacer.setContentHuggingPriority(.init(1), for: .horizontal)
        add(file, priority: .mustHold)
        add([EditorWindowController.divider(), deleteButton, EditorWindowController.divider(), cutButton, copyButton, pasteButton],
            priority: Priority.editButtons)
        add([editor.undoButton, editor.redoButton], priority: .mustHold)
        add([EditorWindowController.divider()] + imageItems, priority: Priority.imageItems)
        add([EditorWindowController.divider()] + destinations, priority: Priority.destinations)
        add([spacer], priority: .mustHold)
        add([settings, help], priority: Priority.appButtons)
        view.spacing = 6
        view.edgeInsets = NSEdgeInsets(top: 5, left: 10, bottom: 5, right: 10)
        view.alignment = .centerY
        view.detachesHiddenViews = true
        // Narrower than all its buttons, the bar drops buttons by visibility priority instead of widening the window.
        view.setClippingResistancePriority(.defaultLow, for: .horizontal)
    }

    private func add(_ views: [NSView], priority: NSStackView.VisibilityPriority) {
        for item in views {
            view.addArrangedSubview(item)
            view.setVisibilityPriority(priority, for: item)
        }
    }

    private func button(_ symbol: String, _ tooltip: String, _ action: Selector, to target: AnyObject?) -> NSButton {
        let button = EditorWindowController.iconButton(symbol, tooltip)
        button.target = target
        button.action = action
        return button
    }

    // MARK: Destinations

    /// Upstream's destination buttons (destinations of priority > 2: email, share, OCR, QR codes, the uploads and the
    /// Office applications, here Open With, and the external commands).
    private func destinationItems() -> [NSView] {
        var items: [NSView] = []
        // Destinations an administrator turned off are left out (upstream `ImageEditorForm`: `IsAvailableFor`).
        let settings = editor?.settings.value ?? AppSettings()
        let buttons: [(String, CaptureDestination)] = [("envelope", .email), ("square.and.arrow.up", .share),
                                                       ("text.viewfinder", .ocr), ("qrcode", .qrCode)]
        for (symbol, destination) in buttons where !settings.isDestinationExcluded(destination) {
            let item = DestinationButton(destination: .destination(destination), symbol: symbol,
                                         tooltip: EditorWindowStatus.destinationName(destination.displayName))
            item.target = self
            item.action = #selector(sendToDestination(_:))
            items.append(item)
        }
        let uploads = [CaptureDestination.jira, .confluence, .box, .dropbox].filter { !settings.isDestinationExcluded($0) }.map {
            MainMenu.destinationItem(EditorWindowStatus.destinationName($0.displayName), .destination($0))
        }
        if !uploads.isEmpty {
            items.append(pullDown("icloud.and.arrow.up", "Upload to Jira, Confluence, Box or Dropbox", items: uploads))
        }
        if !settings.isDestinationExcluded(.openWith) {
            items.append(pullDown("arrow.up.forward.app", "Open the image with another app", items: [], filler: openWithMenus))
        }
        if !settings.isDestinationExcluded(.externalCommand) {
            items.append(pullDown("terminal", "Run an external command with the image", items: [], filler: externalCommandMenus))
        }
        return items
    }

    /// An icon with a drop-down menu (upstream's destination split buttons).
    private func pullDown(_ symbol: String, _ tooltip: String, items: [NSMenuItem], filler: DynamicFileMenus? = nil) -> NSPopUpButton {
        let button = NSPopUpButton(frame: .zero, pullsDown: true)
        button.controlSize = .small
        button.toolTip = tooltip
        button.addItem(withTitle: "")
        button.item(at: 0)?.image = NSImage(systemSymbolName: symbol, accessibilityDescription: tooltip)
        items.forEach { button.menu?.addItem($0) }
        button.menu?.delegate = filler
        return button
    }

    @objc private func sendToDestination(_ sender: DestinationButton) {
        editor?.export(sender.destination)
    }

    // MARK: Edit buttons

    private var canvas: CanvasView? { editor?.canvas }

    @objc private func deleteElements() { canvas?.delete(nil); editor?.refreshActionBar() }
    @objc private func cutElements() { canvas?.cut(nil); editor?.refreshActionBar() }
    @objc private func copyElements() { canvas?.copy(nil); editor?.refreshActionBar() }
    @objc private func pasteElements() { canvas?.paste(nil); editor?.refreshActionBar() }

    /// Delete, Cut and Copy need a selection, Paste something to paste (asked of the canvas, like its menu items);
    /// while a crop is pending the buttons are off.
    func refresh(canvas: CanvasView, locked: Bool) {
        func allowed(_ action: Selector) -> Bool {
            canvas.validateMenuItem(NSMenuItem(title: "", action: action, keyEquivalent: ""))
        }
        for control in lockable { control.isEnabled = !locked }
        guard !locked else { return }
        let hasSelection = !canvas.selectedAnnotations.isEmpty
        deleteButton.isEnabled = hasSelection && allowed(#selector(CanvasView.delete(_:)))
        cutButton.isEnabled = hasSelection && allowed(#selector(CanvasView.cut(_:)))
        copyButton.isEnabled = hasSelection
        pasteButton.isEnabled = allowed(#selector(CanvasView.paste(_:)))
    }
}

/// A toolbar button that sends the image to one destination.
private final class DestinationButton: NSButton {
    let destination: DestinationTarget

    init(destination: DestinationTarget, symbol: String, tooltip: String) {
        self.destination = destination
        super.init(frame: .zero)
        image = NSImage(systemSymbolName: symbol, accessibilityDescription: tooltip)
        imagePosition = .imageOnly
        bezelStyle = .toolbar
        toolTip = tooltip
    }

    required init?(coder: NSCoder) {
        fatalError("not used")
    }
}
