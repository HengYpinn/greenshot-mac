// Greenshot for Mac (Community) - an unofficial macOS port of Greenshot
// Copyright (C) 2026 Greenshot for Mac (Community) contributors
// Based on Greenshot, Copyright (C) 2007-2026 Thomas Braun, Jens Klingen, Robin Krom
// SPDX-License-Identifier: GPL-3.0-or-later

import AppKit
import GreenshotCore

/// The image editor window (upstream `ImageEditorForm`): tools on the left, the properties of the current tool
/// or selected element on top, the image in the middle.
@MainActor
final class EditorWindowController: NSWindowController, NSWindowDelegate {
    let editorDocument: EditorDocument
    private let settings: SettingsStore
    private let saver: ImageSaver
    private let onClose: (EditorWindowController) -> Void

    let canvas: CanvasView
    private let scrollView = NSScrollView()
    private var toolButtons: [EditorTool: NSButton] = [:]
    private let undoButton = EditorWindowController.iconButton("arrow.uturn.backward", "Undo (⌘Z)")
    private let redoButton = EditorWindowController.iconButton("arrow.uturn.forward", "Redo (⇧⌘Z)")
    private let statusLabel = NSTextField(labelWithString: "")

    // Properties
    private let lineColorWell = NSColorWell(style: .minimal)
    private let fillColorWell = NSColorWell(style: .minimal)
    private let lineColorLabel = NSTextField(labelWithString: "Line")
    private let lineWidthPopup = NSPopUpButton()
    private let shadowCheckbox = NSButton(checkboxWithTitle: "Shadow", target: nil, action: nil)
    private let fontSizePopup = NSPopUpButton()
    private let boldButton = EditorWindowController.iconButton("bold", "Bold")
    private let italicButton = EditorWindowController.iconButton("italic", "Italic")
    private let arrowHeadsPopup = NSPopUpButton()
    private let highlightPopup = NSPopUpButton()
    private let obfuscatePopup = NSPopUpButton()
    private let effectSizePopup = NSPopUpButton()
    private var propertyGroups: [(view: NSView, kinds: Set<AnnotationKind>)] = []
    private let cropGroup = NSStackView()

    private static let lineWidths = [0, 1, 2, 3, 4, 5, 6, 8, 10]
    private static let fontSizes = [9, 11, 13, 15, 18, 22, 28, 36, 48, 64, 96]
    private static let effectSizes = [2, 3, 5, 8, 12, 16, 24]

    init(document: EditorDocument, settings: SettingsStore, saver: ImageSaver, onClose: @escaping (EditorWindowController) -> Void) {
        self.editorDocument = document
        self.settings = settings
        self.saver = saver
        self.onClose = onClose
        canvas = CanvasView(document: document)
        let window = NSWindow(contentRect: NSRect(x: 0, y: 0, width: 900, height: 600),
                              styleMask: [.titled, .closable, .miniaturizable, .resizable],
                              backing: .buffered, defer: false)
        window.isReleasedWhenClosed = false
        window.tabbingMode = .disallowed
        window.minSize = NSSize(width: 640, height: 360)
        super.init(window: window)
        window.delegate = self
        buildUI()
        wireCanvas()
        sizeWindowToImage()
        refreshAll()
    }

    required init?(coder: NSCoder) {
        fatalError("not used")
    }

    // MARK: Layout

    private static func iconButton(_ symbol: String, _ tooltip: String) -> NSButton {
        let button = NSButton(image: NSImage(systemSymbolName: symbol, accessibilityDescription: tooltip) ?? NSImage(),
                              target: nil, action: nil)
        button.bezelStyle = .toolbar
        button.toolTip = tooltip
        return button
    }

    private func button(_ symbol: String, _ tooltip: String, _ action: Selector) -> NSButton {
        let button = Self.iconButton(symbol, tooltip)
        button.target = self
        button.action = action
        return button
    }

    private func group(_ views: [NSView], for kinds: Set<AnnotationKind>) -> NSStackView {
        let stack = NSStackView(views: views)
        stack.spacing = 4
        propertyGroups.append((stack, kinds))
        return stack
    }

    private func label(_ text: String) -> NSTextField {
        let field = NSTextField(labelWithString: text)
        field.font = .systemFont(ofSize: NSFont.smallSystemFontSize)
        field.textColor = .secondaryLabelColor
        return field
    }

    private func setUp(_ popup: NSPopUpButton, titles: [String], action: Selector) {
        popup.removeAllItems()
        popup.addItems(withTitles: titles)
        popup.controlSize = .small
        popup.target = self
        popup.action = action
    }

    private func buildUI() {
        guard let window else { return }

        // Actions
        let save = button("square.and.arrow.down", "Save (⌘S)", #selector(saveImage(_:)))
        let saveAs = button("square.and.arrow.down.on.square", "Save As… (⇧⌘S)", #selector(saveImageAs(_:)))
        let copy = button("doc.on.doc", "Copy image to the clipboard (⇧⌘C)", #selector(copyImage(_:)))
        let print = button("printer", "Print… (⌘P)", #selector(printImage(_:)))
        undoButton.target = self
        undoButton.action = #selector(undoAction)
        redoButton.target = self
        redoButton.action = #selector(redoAction)

        // Properties
        lineColorWell.target = self
        lineColorWell.action = #selector(lineColorChanged)
        fillColorWell.target = self
        fillColorWell.action = #selector(fillColorChanged)
        let noFill = button("circle.slash", "No fill", #selector(clearFill))
        setUp(lineWidthPopup, titles: Self.lineWidths.map { $0 == 0 ? "No line" : "\($0) pt" }, action: #selector(lineWidthChanged))
        shadowCheckbox.target = self
        shadowCheckbox.action = #selector(shadowChanged)
        shadowCheckbox.controlSize = .small
        setUp(fontSizePopup, titles: Self.fontSizes.map { "\($0) pt" }, action: #selector(fontSizeChanged))
        boldButton.setButtonType(.pushOnPushOff)
        boldButton.target = self
        boldButton.action = #selector(boldChanged)
        italicButton.setButtonType(.pushOnPushOff)
        italicButton.target = self
        italicButton.action = #selector(italicChanged)
        setUp(arrowHeadsPopup, titles: ["No heads", "Head at start", "Head at end", "Both heads"], action: #selector(arrowHeadsChanged))
        setUp(highlightPopup, titles: ["Text marker", "Highlight area", "Grayscale", "Magnify"], action: #selector(highlightChanged))
        setUp(obfuscatePopup, titles: ["Pixelate", "Blur"], action: #selector(obfuscateChanged))
        setUp(effectSizePopup, titles: Self.effectSizes.map { "\($0) pt" }, action: #selector(effectSizeChanged))

        let properties = NSStackView(views: [
            group([lineColorLabel, lineColorWell], for: [.rectangle, .ellipse, .line, .arrow, .freehand, .text, .counter]),
            group([label("Fill"), fillColorWell, noFill], for: [.rectangle, .ellipse, .text, .counter, .highlight]),
            group([label("Width"), lineWidthPopup], for: [.rectangle, .ellipse, .line, .arrow, .freehand]),
            group([arrowHeadsPopup], for: [.arrow]),
            group([label("Size"), fontSizePopup], for: [.text, .counter]),
            group([boldButton, italicButton], for: [.text]),
            group([highlightPopup], for: [.highlight]),
            group([obfuscatePopup, label("Size"), effectSizePopup], for: [.obfuscate]),
            group([shadowCheckbox], for: [.rectangle, .ellipse, .line, .arrow, .text]),
        ])
        properties.spacing = 14

        let applyCrop = NSButton(title: "Crop", target: self, action: #selector(applyCrop))
        applyCrop.bezelStyle = .push
        applyCrop.keyEquivalent = ""
        let cancelCrop = NSButton(title: "Cancel", target: self, action: #selector(cancelCrop))
        cropGroup.setViews([label("Drag the area to keep"), applyCrop, cancelCrop], in: .leading)
        cropGroup.spacing = 6

        let spacer = NSView()
        spacer.setContentHuggingPriority(.init(1), for: .horizontal)
        let topBar = NSStackView(views: [save, saveAs, copy, print, Self.divider(), undoButton, redoButton, Self.divider(),
                                         properties, cropGroup, spacer])
        topBar.spacing = 6
        topBar.edgeInsets = NSEdgeInsets(top: 6, left: 10, bottom: 6, right: 10)
        topBar.alignment = .centerY

        // Tools
        let palette = NSStackView()
        palette.orientation = .vertical
        palette.spacing = 4
        palette.edgeInsets = NSEdgeInsets(top: 8, left: 6, bottom: 8, right: 6)
        for tool in EditorTool.allCases {
            let b = button(tool.symbolName, "\(tool.title) (\(String(tool.shortcut).uppercased()))", #selector(toolClicked(_:)))
            b.setButtonType(.pushOnPushOff)
            b.tag = EditorTool.allCases.firstIndex(of: tool) ?? 0
            b.widthAnchor.constraint(equalToConstant: 34).isActive = true
            b.heightAnchor.constraint(equalToConstant: 30).isActive = true
            toolButtons[tool] = b
            palette.addArrangedSubview(b)
            if tool == .select || tool == .counter { palette.addArrangedSubview(Self.horizontalDivider()) }
        }
        palette.setHuggingPriority(.required, for: .horizontal)

        // Canvas
        let clip = CenteringClipView()
        clip.drawsBackground = true
        clip.backgroundColor = .underPageBackgroundColor
        scrollView.contentView = clip
        scrollView.documentView = canvas
        scrollView.hasVerticalScroller = true
        scrollView.hasHorizontalScroller = true
        scrollView.allowsMagnification = true
        scrollView.minMagnification = 0.1
        scrollView.maxMagnification = 16
        scrollView.borderType = .noBorder
        scrollView.autohidesScrollers = true

        let body = NSStackView(views: [palette, Self.verticalLine(), scrollView])
        body.spacing = 0
        body.alignment = .top
        palette.topAnchor.constraint(equalTo: body.topAnchor).isActive = true
        scrollView.topAnchor.constraint(equalTo: body.topAnchor).isActive = true
        scrollView.bottomAnchor.constraint(equalTo: body.bottomAnchor).isActive = true

        statusLabel.font = .monospacedDigitSystemFont(ofSize: NSFont.smallSystemFontSize, weight: .regular)
        statusLabel.textColor = .secondaryLabelColor
        let statusBar = NSStackView(views: [statusLabel])
        statusBar.edgeInsets = NSEdgeInsets(top: 3, left: 10, bottom: 4, right: 10)

        // Bars at their own height, the canvas takes the rest.
        let root = NSView()
        let rows = [topBar, Self.horizontalDivider(), body, Self.horizontalDivider(), statusBar]
        var constraints: [NSLayoutConstraint] = []
        var previousBottom = root.topAnchor
        for row in rows {
            row.translatesAutoresizingMaskIntoConstraints = false
            root.addSubview(row)
            constraints += [row.leadingAnchor.constraint(equalTo: root.leadingAnchor),
                            row.trailingAnchor.constraint(equalTo: root.trailingAnchor),
                            row.topAnchor.constraint(equalTo: previousBottom)]
            previousBottom = row.bottomAnchor
        }
        constraints.append(statusBar.bottomAnchor.constraint(equalTo: root.bottomAnchor))
        NSLayoutConstraint.activate(constraints)
        body.setHuggingPriority(.init(1), for: .vertical)
        window.contentView = root
    }

    private static func divider() -> NSView {
        let box = NSBox()
        box.boxType = .separator
        box.heightAnchor.constraint(equalToConstant: 20).isActive = true
        return box
    }

    private static func horizontalDivider() -> NSView {
        let box = NSBox()
        box.boxType = .separator
        return box
    }

    private static func verticalLine() -> NSView {
        let box = NSBox()
        box.boxType = .separator
        box.widthAnchor.constraint(equalToConstant: 1).isActive = true
        return box
    }

    private func wireCanvas() {
        canvas.styleProvider = { [weak self] kind in self?.settings.value.style(for: kind) ?? .defaults(for: kind) }
        canvas.onDocumentChange = { [weak self] in self?.refreshDocumentState() }
        canvas.onSelectionChange = { [weak self] in self?.refreshProperties() }
        canvas.onToolChange = { [weak self] in
            self?.refreshTools()
            self?.refreshProperties()
        }
        canvas.onCopy = { [weak self] in self?.copyImage(nil) }
    }

    /// Opens the window at the image's size, up to most of the screen; larger images are zoomed to fit.
    private func sizeWindowToImage() {
        guard let window else { return }
        let visible = (NSScreen.main ?? NSScreen.screens[0]).visibleFrame
        let image = canvas.pointSize
        let chrome = NSSize(width: 60, height: 90)
        let width = min(max(image.width + chrome.width, 760), visible.width * 0.9)
        let height = min(max(image.height + chrome.height, 420), visible.height * 0.9)
        window.setContentSize(NSSize(width: width, height: height))
        window.center()
        window.layoutIfNeeded()
        let viewport = scrollView.contentSize
        if image.width > viewport.width || image.height > viewport.height {
            zoomToFit(nil)
        }
    }

    // MARK: State

    private func refreshAll() {
        refreshTools()
        refreshProperties()
        refreshDocumentState()
    }

    private func refreshTools() {
        for (tool, button) in toolButtons { button.state = tool == canvas.tool ? .on : .off }
        cropGroup.isHidden = canvas.tool != .crop
    }

    private func refreshDocumentState() {
        guard let window else { return }
        window.title = editorDocument.fileURL?.lastPathComponent ?? "\(editorDocument.title) – Greenshot"
        window.representedURL = editorDocument.fileURL
        window.isDocumentEdited = editorDocument.isModified
        undoButton.isEnabled = editorDocument.canUndo
        redoButton.isEnabled = editorDocument.canRedo
        let size = editorDocument.imageSize
        statusLabel.stringValue = "\(Int(size.width)) × \(Int(size.height)) px   \(Int((scrollView.magnification * 100).rounded())) %"
    }

    /// The kind whose properties the bar shows: the selected element's, else the tool's.
    private var activeKind: AnnotationKind? {
        canvas.selectedAnnotation?.kind ?? canvas.tool.kind
    }

    private var activeStyle: AnnotationStyle? {
        if let selected = canvas.selectedAnnotation { return selected.style }
        return activeKind.map { settings.value.style(for: $0) }
    }

    private func refreshProperties() {
        let kind = activeKind
        for (view, kinds) in propertyGroups { view.isHidden = kind.map { !kinds.contains($0) } ?? true }
        guard let kind, let style = activeStyle else { return }
        lineColorLabel.stringValue = (kind == .text || kind == .counter) ? "Text" : "Line"
        lineColorWell.color = NSColor(cgColor: style.lineColor.cgColor) ?? .red
        fillColorWell.color = NSColor(cgColor: style.fillColor.cgColor) ?? .clear
        selectClosest(lineWidthPopup, values: Self.lineWidths, to: style.lineWidth)
        shadowCheckbox.state = style.shadow ? .on : .off
        selectClosest(fontSizePopup, values: Self.fontSizes, to: style.fontSize)
        boldButton.state = style.bold ? .on : .off
        italicButton.state = style.italic ? .on : .off
        arrowHeadsPopup.selectItem(at: ArrowHeads.allCases.firstIndex(of: style.arrowHeads) ?? 2)
        highlightPopup.selectItem(at: HighlightMode.allCases.firstIndex(of: style.highlightMode) ?? 0)
        obfuscatePopup.selectItem(at: ObfuscateMode.allCases.firstIndex(of: style.obfuscateMode) ?? 0)
        selectClosest(effectSizePopup, values: Self.effectSizes,
                      to: style.obfuscateMode == .pixelate ? style.pixelSize : style.blurRadius)
    }

    private func selectClosest(_ popup: NSPopUpButton, values: [Int], to value: Double) {
        let index = values.indices.min { abs(Double(values[$0]) - value) < abs(Double(values[$1]) - value) } ?? 0
        popup.selectItem(at: index)
    }

    /// Applies a property change to the selected element and remembers it for new elements of that kind.
    private func applyStyle(_ change: (inout AnnotationStyle) -> Void) {
        guard let kind = activeKind else { return }
        var remembered = settings.value.style(for: kind)
        change(&remembered)
        settings.update { $0.editorStyles[kind.rawValue] = remembered }
        if var selected = canvas.selectedAnnotation {
            change(&selected.style)
            editorDocument.change { editorDocument.update(selected) }
            canvas.documentChanged()
        }
        refreshProperties()
    }

    private func rgba(_ color: NSColor) -> RGBAColor {
        let c = color.usingColorSpace(.sRGB) ?? color
        return RGBAColor(red: Double(c.redComponent), green: Double(c.greenComponent), blue: Double(c.blueComponent),
                         alpha: Double(c.alphaComponent))
    }

    // MARK: Property actions

    @objc private func lineColorChanged() { applyStyle { $0.lineColor = rgba(lineColorWell.color) } }
    @objc private func fillColorChanged() { applyStyle { $0.fillColor = rgba(fillColorWell.color) } }
    @objc private func clearFill() { applyStyle { $0.fillColor = .clear } }
    @objc private func lineWidthChanged() { applyStyle { $0.lineWidth = Double(Self.lineWidths[lineWidthPopup.indexOfSelectedItem]) } }
    @objc private func shadowChanged() { applyStyle { $0.shadow = shadowCheckbox.state == .on } }
    @objc private func fontSizeChanged() { applyStyle { $0.fontSize = Double(Self.fontSizes[fontSizePopup.indexOfSelectedItem]) } }
    @objc private func boldChanged() { applyStyle { $0.bold = boldButton.state == .on } }
    @objc private func italicChanged() { applyStyle { $0.italic = italicButton.state == .on } }
    @objc private func arrowHeadsChanged() { applyStyle { $0.arrowHeads = ArrowHeads.allCases[arrowHeadsPopup.indexOfSelectedItem] } }
    @objc private func highlightChanged() { applyStyle { $0.highlightMode = HighlightMode.allCases[highlightPopup.indexOfSelectedItem] } }
    @objc private func obfuscateChanged() { applyStyle { $0.obfuscateMode = ObfuscateMode.allCases[obfuscatePopup.indexOfSelectedItem] } }
    @objc private func effectSizeChanged() {
        let size = Double(Self.effectSizes[effectSizePopup.indexOfSelectedItem])
        applyStyle {
            if $0.obfuscateMode == .pixelate { $0.pixelSize = size } else { $0.blurRadius = size }
        }
    }

    @objc private func toolClicked(_ sender: NSButton) {
        canvas.tool = EditorTool.allCases[sender.tag]
        window?.makeFirstResponder(canvas)
        refreshTools()
    }

    @objc private func applyCrop() { canvas.applyCrop() }
    @objc private func cancelCrop() { canvas.tool = .select }
    @objc private func undoAction() { canvas.undo(nil) }
    @objc private func redoAction() { canvas.redo(nil) }

    // MARK: File actions (also reached through the main menu)

    @objc func saveImage(_ sender: Any?) {
        save()
    }

    /// Saves to the file it came from, or like "Save directly" the first time.
    @discardableResult
    func save() -> Bool {
        canvas.commitEditing()
        if let url = editorDocument.fileURL, ImageFormat(fileExtension: url.pathExtension) == nil {
            // Opened from a format this app can't write (HEIC, WebP, ...): never overwrite it, ask for a new file.
            saveImageAs(nil)
            return !editorDocument.isModified
        }
        let image = editorDocument.flattened()
        if let url = editorDocument.fileURL {
            guard saver.write(image, to: url) else { return false }
            saver.notifySaved(url)
        } else {
            guard let url = saver.saveDirectly(image, title: editorDocument.title, date: editorDocument.captureDate) else { return false }
            editorDocument.fileURL = url
        }
        editorDocument.markSaved()
        refreshDocumentState()
        return true
    }

    @objc func saveImageAs(_ sender: Any?) {
        canvas.commitEditing()
        guard let url = saver.saveAs(editorDocument.flattened(), title: editorDocument.title, date: editorDocument.captureDate,
                                     suggestedURL: editorDocument.fileURL) else { return }
        editorDocument.fileURL = url
        editorDocument.markSaved()
        refreshDocumentState()
    }

    @objc func copyImage(_ sender: Any?) {
        canvas.commitEditing()
        Clipboard.copy(editorDocument.flattened())
        editorDocument.markSaved()
        refreshDocumentState()
        saver.notify("Copied to the clipboard")
    }

    @objc func printImage(_ sender: Any?) {
        canvas.commitEditing()
        Printing.print(editorDocument.flattened(), scale: editorDocument.scale, window: window)
    }

    // MARK: Zoom (View menu)

    @objc func zoomIn(_ sender: Any?) { setMagnification(scrollView.magnification * 1.25) }
    @objc func zoomOut(_ sender: Any?) { setMagnification(scrollView.magnification / 1.25) }
    @objc func actualSize(_ sender: Any?) { setMagnification(1) }

    @objc func zoomToFit(_ sender: Any?) {
        let viewport = scrollView.contentView.bounds.size.applying(CGAffineTransform(scaleX: scrollView.magnification, y: scrollView.magnification))
        let image = canvas.pointSize
        guard image.width > 0, image.height > 0 else { return }
        setMagnification(min(viewport.width / image.width, viewport.height / image.height, 1))
    }

    private func setMagnification(_ value: CGFloat) {
        let clamped = min(max(value, scrollView.minMagnification), scrollView.maxMagnification)
        scrollView.setMagnification(clamped, centeredAt: NSPoint(x: canvas.bounds.midX, y: canvas.bounds.midY))
        refreshDocumentState()
    }

    // MARK: Window

    func windowDidResize(_ notification: Notification) {
        refreshDocumentState()
    }

    private func makeSaveAlert() -> NSAlert {
        let alert = NSAlert()
        alert.messageText = "Do you want to save the screenshot “\(editorDocument.title)”?"
        alert.informativeText = "It will be lost if you don't save it."
        alert.addButton(withTitle: "Save")
        alert.addButton(withTitle: "Don't Save")
        alert.addButton(withTitle: "Cancel")
        return alert
    }

    /// Saves or discards the changes, after asking. False when the user cancelled or saving failed.
    private func resolveChanges(_ response: NSApplication.ModalResponse) -> Bool {
        switch response {
        case .alertFirstButtonReturn:
            return save()
        case .alertSecondButtonReturn:
            editorDocument.markSaved()
            return true
        default:
            return false
        }
    }

    /// Before quitting (quitting doesn't ask the windows): true when the window may go.
    func confirmCloseBeforeQuit() -> Bool {
        canvas.commitEditing()
        guard editorDocument.isModified, let window else { return true }
        NSApp.activate()
        window.makeKeyAndOrderFront(nil)
        return resolveChanges(makeSaveAlert().runModal())
    }

    func windowShouldClose(_ sender: NSWindow) -> Bool {
        canvas.commitEditing()
        guard editorDocument.isModified else { return true }
        makeSaveAlert().beginSheetModal(for: sender) { [weak self] response in
            guard let self, self.resolveChanges(response) else { return }
            self.window?.close()
        }
        return false
    }

    func windowWillClose(_ notification: Notification) {
        onClose(self)
    }
}
