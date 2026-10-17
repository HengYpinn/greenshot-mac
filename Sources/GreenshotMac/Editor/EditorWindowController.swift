// Greenshot for Mac (Community) - an unofficial macOS port of Greenshot
// Copyright (C) 2026 Greenshot for Mac (Community) contributors
// Based on Greenshot, Copyright (C) 2007-2026 Thomas Braun, Jens Klingen, Robin Krom
// SPDX-License-Identifier: GPL-3.0-or-later

import AppKit
import GreenshotCore
import UniformTypeIdentifiers

/// The image editor window (upstream `ImageEditorForm`): the actions and destinations on top (upstream
/// `destinationsToolStrip`), under them the properties of the current tool or selected element
/// (`propertiesToolStrip`), tools on the left, the image in the middle and the status bar at the bottom.
/// Zoom is in EditorWindowController+Zoom.swift, exports and the status bar's messages in
/// EditorWindowController+Export.swift, the window's size and place in EditorWindowController+Placement.swift.
@MainActor
final class EditorWindowController: NSWindowController, NSWindowDelegate, NSMenuItemValidation, NSMenuDelegate {
    let editorDocument: EditorDocument
    let settings: SettingsStore
    let saver: ImageSaver
    private let onClose: (EditorWindowController) -> Void
    /// File › Close All (the editor manager closes every editor).
    var onCloseAll: (() -> Void)?
    /// After the image, the elements or the saved state changed (the editor manager keeps unsaved editors for the next
    /// start).
    var onDocumentStateChange: ((EditorWindowController) -> Void)?

    let canvas: CanvasView
    let scrollView = EditorWindowScrollView()
    private var toolButtons: [EditorTool: NSButton] = [:]
    /// The counter tool's icon shows the next number (upstream `btnStepLabel01`…); the symbol shown now.
    private var counterSymbol = ""
    let undoButton = EditorWindowController.iconButton("arrow.uturn.backward", "Undo (⌘Z)")
    let redoButton = EditorWindowController.iconButton("arrow.uturn.forward", "Redo (⇧⌘Z)")
    private(set) lazy var statusBar = EditorStatusBar(zoomItems: MainMenu.zoomItems(target: self, withKeys: false))
    private var actionBar: EditorActionBar?

    // What the last exports left (upstream `Surface.LastSaveFullPath` and `UploadUrl`), see +Export.
    /// The file this image was last saved or exported to.
    var lastSavedURL: URL?
    /// The link of the last upload.
    var uploadURL: URL?

    // Window placement, see +Placement.
    /// The window's frame when it was last neither zoomed nor minimised: what is remembered for the next editor.
    var normalFrame: NSRect?
    /// Whether the user zoomed the window with the zoom button (upstream `ShowWindowCommand` Maximize); not AppKit's
    /// `isZoomed`, which is also true for a window fitted to a screen-sized capture.
    var wasZoomed = false
    /// Zoom the window once it is on screen (the remembered editor was zoomed).
    var zoomsWhenShown = false
    /// While the zoom button animates the window, its frames aren't the normal frame.
    var isZoomAnimating = false
    /// The image size the window was last fitted to (with "match size to capture").
    var fittedImageSize: CGSize?

    // Properties
    private let lineColorWell = NSColorWell(style: .minimal)
    private let fillColorWell = NSColorWell(style: .minimal)
    private let lineColorLabel = NSTextField(labelWithString: "Line")
    private let lineWidthField = PropertyNumberField(range: 0...100, tooltip: "Line thickness in points (0: no line)")
    private let shadowCheckbox = NSButton(checkboxWithTitle: "Shadow", target: nil, action: nil)
    private let fontSizeField = PropertyNumberField(range: 7...500, tooltip: "Font size in points")
    private let boldButton = EditorWindowController.iconButton("bold", "Bold")
    private let italicButton = EditorWindowController.iconButton("italic", "Italic")
    private let arrowHeadsPopup = NSPopUpButton()
    private let highlightPopup = NSPopUpButton()
    private let obfuscatePopup = NSPopUpButton()
    private let pixelSizeField = PropertyNumberField(range: 2...100, tooltip: "Pixel size")
    private let blurRadiusField = PropertyNumberField(range: 0...100, tooltip: "Blur radius")
    private let brightnessField = PropertyNumberField(range: 0...200, step: 5, tooltip: "Brightness of the area around the highlight, in percent")
    private let emojiPopup = NSPopUpButton()
    private let cutMarkStylePopup = NSPopUpButton()
    private let toothHeightPopup = NSPopUpButton()
    private let toothRangePopup = NSPopUpButton()
    private let fontFamilyPopup = NSPopUpButton()
    private var fontMenuStyled = false
    private let horizontalAlignmentControl = NSSegmentedControl()
    private let verticalAlignmentControl = NSSegmentedControl()
    private let counterStartField = NSTextField()
    private let counterStartStepper = NSStepper()
    private let magnificationPopup = NSPopUpButton()
    /// Groups that depend on a mode as well as on the kind: shown by `refreshProperties`.
    private var magnificationGroup: NSView?
    private var pixelSizeGroup: NSView?
    private var blurRadiusGroup: NSView?
    private var brightnessGroup: NSView?
    /// The font families in the font popup after "System Font".
    private let fontFamilies = NSFontManager.shared.availableFontFamilies.sorted {
        $0.localizedStandardCompare($1) == .orderedAscending
    }
    private var propertyGroups: [(view: NSView, kinds: Set<AnnotationKind>)] = []
    private let cropGroup = NSStackView()
    /// The crop tool's modes (upstream's crop mode buttons, `CropContainer.CropModes`).
    private let cropModeControl = NSSegmentedControl()
    /// How the joint of a cut-out is marked (upstream's cut mark style drop-down of the crop tool).
    private let cutOutJointPopup = NSPopUpButton()

    private static let toothHeights = [4, 6, 8, 10, 12, 16, 20, 24, 32]
    private static let toothRanges = [8, 10, 12, 16, 20, 24, 30, 40, 60]
    /// Upstream's magnification factor field goes up to 8.
    private static let magnifications = [2, 3, 4, 5, 6, 7, 8]

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
        // Open where the user is, also over a full screen app, and follow them when the app is opened again
        // elsewhere; hide when they click another app (see EditorManager).
        window.collectionBehavior = [.moveToActiveSpace, .fullScreenAuxiliary]
        window.hidesOnDeactivate = true
        window.minSize = NSSize(width: 640, height: 360)
        super.init(window: window)
        window.delegate = self
        buildUI()
        wireCanvas()
        // Hide the properties that don't apply before sizing: with all of them shown the property bar is wider than a
        // laptop screen.
        refreshAll()
        // A file opened in the editor counts as its saved file (upstream `SetImagePath`).
        lastSavedURL = document.fileURL
        placeWindow()
    }

    required init?(coder: NSCoder) {
        fatalError("not used")
    }

    // MARK: Layout

    static func iconButton(_ symbol: String, _ tooltip: String) -> NSButton {
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

    private func setUpSegments(_ control: NSSegmentedControl, symbols: [String], labels: [String], action: Selector) {
        control.segmentCount = symbols.count
        control.trackingMode = .selectOne
        control.controlSize = .small
        for (index, symbol) in symbols.enumerated() {
            if let image = NSImage(systemSymbolName: symbol, accessibilityDescription: labels[index]) {
                control.setImage(image, forSegment: index)
            } else {
                control.setLabel(labels[index], forSegment: index)
            }
            control.setToolTip(labels[index], forSegment: index)
        }
        control.target = self
        control.action = action
    }

    /// A number field of the property bar: its value goes to the style, Return gives the keyboard back to the canvas.
    private func setUp(_ field: PropertyNumberField, _ change: @escaping (inout AnnotationStyle, Double) -> Void) {
        field.onChange = { [weak self] value in self?.applyStyle { change(&$0, value) } }
        field.onCommit = { [weak self] in
            guard let self else { return }
            self.window?.makeFirstResponder(self.canvas)
        }
    }

    /// The cut edge styles with a small picture of each (upstream `CreateCutMarkPreview`).
    private func addCutMarkPreviews(_ popup: NSPopUpButton) {
        for (index, style) in CutMarkStyle.allCases.enumerated() {
            guard let item = popup.item(at: index), let preview = CutMark.previewImage(style) else { continue }
            item.image = NSImage(cgImage: preview, size: NSSize(width: 16, height: 16))
        }
    }

    private func buildUI() {
        guard let window else { return }
        undoButton.target = self
        undoButton.action = #selector(undoAction)
        redoButton.target = self
        redoButton.action = #selector(redoAction)

        // The image operations (effects, resize, rotate, canvas) live in EditorWindowController+Image.swift.
        let actionBar = EditorActionBar(editor: self, imageItems: imageToolbarItems())
        self.actionBar = actionBar
        let propertyBar = makePropertyBar()
        let body = makeBody()

        // Bars at their own height, the canvas takes the rest.
        let root = NSView()
        let rows: [NSView] = [actionBar.view, Self.horizontalDivider(), propertyBar, Self.horizontalDivider(), body,
                              Self.horizontalDivider(), statusBar]
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
        constraints.append(statusBar.heightAnchor.constraint(equalToConstant: 22))
        // Always the same height, also when the tool has no properties, so the canvas doesn't jump.
        constraints.append(propertyBar.heightAnchor.constraint(equalToConstant: 32))
        NSLayoutConstraint.activate(constraints)
        body.setHuggingPriority(.init(1), for: .vertical)
        window.contentView = root

        scrollView.onWheelZoom = { [weak self] zoomIn, point in self?.wheelZoom(zoomIn: zoomIn, at: point) }
        NotificationCenter.default.addObserver(self, selector: #selector(liveMagnifyEnded(_:)),
                                               name: NSScrollView.didEndLiveMagnifyNotification, object: scrollView)
    }

    /// The second row: the properties of the current tool or selected element, and the crop tool's bar.
    private func makePropertyBar() -> NSStackView {
        lineColorWell.target = self
        lineColorWell.action = #selector(lineColorChanged)
        fillColorWell.target = self
        fillColorWell.action = #selector(fillColorChanged)
        // Upstream's colour dialog has alpha and a Transparent button; the colour panel shows opacity with this.
        lineColorWell.supportsAlpha = true
        fillColorWell.supportsAlpha = true
        let transparentLine = button("circle.slash", "Transparent", #selector(clearLine))
        let noFill = button("circle.slash", "No fill", #selector(clearFill))
        setUp(lineWidthField) { $0.lineWidth = $1 }
        shadowCheckbox.target = self
        shadowCheckbox.action = #selector(shadowChanged)
        shadowCheckbox.controlSize = .small
        setUp(fontSizeField) { $0.fontSize = $1 }
        boldButton.setButtonType(.pushOnPushOff)
        boldButton.target = self
        boldButton.action = #selector(boldChanged)
        italicButton.setButtonType(.pushOnPushOff)
        italicButton.target = self
        italicButton.action = #selector(italicChanged)
        setUp(arrowHeadsPopup, titles: ["No heads", "Head at start", "Head at end", "Both heads"], action: #selector(arrowHeadsChanged))
        setUp(highlightPopup, titles: ["Text marker", "Highlight area", "Grayscale", "Magnify"], action: #selector(highlightChanged))
        setUp(obfuscatePopup, titles: ["Pixelate", "Blur"], action: #selector(obfuscateChanged))
        setUp(pixelSizeField) { $0.pixelSize = $1 }
        setUp(blurRadiusField) { $0.blurRadius = $1 }
        setUp(brightnessField) { $0.brightness = $1 / 100 }
        setUp(emojiPopup, titles: EmojiChoices.all, action: #selector(emojiChanged))
        emojiPopup.menu?.addItem(.separator())
        emojiPopup.addItem(withTitle: "More Emoji…")
        setUp(cutMarkStylePopup, titles: ["None", "Line", "Zig-zag", "Wave", "Torn"], action: #selector(cutMarkStyleChanged))
        addCutMarkPreviews(cutMarkStylePopup)
        setUp(toothHeightPopup, titles: Self.toothHeights.map { "\($0) pt" }, action: #selector(toothHeightChanged))
        setUp(toothRangePopup, titles: Self.toothRanges.map { "\($0) pt" }, action: #selector(toothRangeChanged))
        setUp(fontFamilyPopup, titles: ["System Font"] + fontFamilies, action: #selector(fontFamilyChanged))
        fontFamilyPopup.menu?.insertItem(.separator(), at: 1)
        // Each family is shown in its own font once the menu is first opened (upstream `FontFamilyComboBox`).
        fontFamilyPopup.menu?.delegate = self
        setUp(magnificationPopup, titles: Self.magnifications.map { "\($0)×" }, action: #selector(magnificationChanged))
        setUpSegments(horizontalAlignmentControl, symbols: ["text.alignleft", "text.aligncenter", "text.alignright"],
                      labels: ["Left", "Center", "Right"], action: #selector(horizontalAlignmentChanged))
        setUpSegments(verticalAlignmentControl, symbols: ["align.vertical.top", "align.vertical.center", "align.vertical.bottom"],
                      labels: ["Top", "Middle", "Bottom"], action: #selector(verticalAlignmentChanged))
        setUpCounterStart()

        let lineKinds = AnnotationKind.kinds(with: .lineColor)
        let fillKinds = AnnotationKind.kinds(with: .fillColor)
        let widthKinds = AnnotationKind.kinds(with: .lineWidth)
        let shadowKinds = AnnotationKind.kinds(with: .shadow)
        let pixelSize = group([label("Pixel size")] + pixelSizeField.views, for: [.obfuscate])
        let blurRadius = group([label("Blur")] + blurRadiusField.views, for: [.obfuscate, .highlight])
        let brightness = group([label("Brightness")] + brightnessField.views + [label("%")], for: [.highlight])
        let magnification = group([label("Zoom"), magnificationPopup], for: [.highlight])
        pixelSizeGroup = pixelSize
        blurRadiusGroup = blurRadius
        brightnessGroup = brightness
        magnificationGroup = magnification
        var groups: [NSView] = []
        groups.append(group([lineColorLabel, lineColorWell, transparentLine], for: lineKinds))
        groups.append(group([label("Fill"), fillColorWell, noFill], for: fillKinds))
        groups.append(group([label("Width")] + lineWidthField.views, for: widthKinds))
        groups.append(group([cutMarkStylePopup, label("Teeth"), toothHeightPopup, label("Range"), toothRangePopup],
                            for: AnnotationKind.cutEdgeKinds))
        // Apply to the Image (upstream btnApplyToImage), EditorWindowController+Elements.swift.
        groups.append(group(cutEdgeActionViews(), for: AnnotationKind.cutEdgeKinds))
        groups.append(group([arrowHeadsPopup], for: [.arrow]))
        groups.append(group([label("Size")] + fontSizeField.views, for: [.text, .counter, .speechBubble]))
        groups.append(group([boldButton, italicButton], for: [.text, .speechBubble]))
        groups.append(group([highlightPopup], for: [.highlight]))
        groups.append(group([obfuscatePopup], for: [.obfuscate]))
        groups += [pixelSize, blurRadius, brightness, magnification]
        groups.append(group([label("Emoji"), emojiPopup], for: [.emoji]))
        groups.append(group([fontFamilyPopup, horizontalAlignmentControl, verticalAlignmentControl], for: [.text, .speechBubble]))
        groups.append(group([label("Start at"), counterStartField, counterStartStepper], for: [.counter]))
        groups.append(group([shadowCheckbox], for: shadowKinds))
        let properties = NSStackView(views: groups)
        properties.spacing = 14

        setUpCropGroup()
        let spacer = NSView()
        spacer.setContentHuggingPriority(.init(1), for: .horizontal)
        let bar = NSStackView(views: [properties, cropGroup, spacer])
        bar.spacing = 6
        bar.edgeInsets = NSEdgeInsets(top: 4, left: 10, bottom: 4, right: 10)
        // When a tool has many properties, the bar is cut off at the window's edge rather than widening the window.
        bar.setClippingResistancePriority(.defaultLow, for: .horizontal)
        bar.alignment = .centerY
        return bar
    }

    /// Upstream's counter start value (`counterUpDown`).
    private func setUpCounterStart() {
        let formatter = NumberFormatter()
        formatter.minimum = 0
        formatter.maximum = 9999
        formatter.allowsFloats = false
        counterStartField.formatter = formatter
        counterStartField.controlSize = .small
        counterStartField.font = .systemFont(ofSize: NSFont.smallSystemFontSize)
        counterStartField.widthAnchor.constraint(equalToConstant: 44).isActive = true
        counterStartField.target = self
        counterStartField.action = #selector(counterStartChanged(_:))
        counterStartStepper.minValue = 0
        counterStartStepper.maxValue = 9999
        counterStartStepper.increment = 1
        counterStartStepper.valueWraps = false
        counterStartStepper.controlSize = .small
        counterStartStepper.target = self
        counterStartStepper.action = #selector(counterStartChanged(_:))
    }

    /// The crop tool's bar: its modes (upstream's four crop mode buttons), Crop and Cancel, the cut-out joint.
    private func setUpCropGroup() {
        let modes = CropMode.allCases
        setUpSegments(cropModeControl, symbols: modes.map(\.symbolName), labels: modes.map(\.title), action: #selector(cropModeChanged))
        let applyCrop = NSButton(title: "Crop", target: self, action: #selector(applyCrop))
        applyCrop.bezelStyle = .push
        applyCrop.keyEquivalent = ""
        let cancelCrop = NSButton(title: "Cancel", target: self, action: #selector(cancelCrop))
        setUp(cutOutJointPopup, titles: ["None", "Line", "Zig-zag", "Wave", "Torn"], action: #selector(cutOutJointChanged))
        addCutMarkPreviews(cutOutJointPopup)
        cutOutJointPopup.toolTip = "How the joint is marked when the selected rows or columns are cut out"
        cutOutJointPopup.selectItem(at: CutMarkStyle.allCases.firstIndex(of: settings.value.cutOutMarkStyle) ?? 0)
        cropGroup.setViews([cropModeControl, label("Drag the area to keep or to cut out"), applyCrop, cancelCrop,
                            Self.divider(), label("Cut-out joint"), cutOutJointPopup], in: .leading)
        cropGroup.spacing = 6
    }

    /// The tools on the left and the canvas.
    private func makeBody() -> NSStackView {
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
            if tool == .select || tool == .cutMark { palette.addArrangedSubview(Self.horizontalDivider()) }
        }
        palette.setHuggingPriority(.required, for: .horizontal)

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
        return body
    }

    static func divider() -> NSView {
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
        canvas.emojiProvider = { [weak self] in self?.settings.value.recentEmoji ?? AppSettings().recentEmoji }
        canvas.onPickEmoji = { [weak self] emoji in self?.pickEmoji(emoji) }
        canvas.onDocumentChange = { [weak self] in self?.refreshDocumentState() }
        canvas.onSelectionChange = { [weak self] in
            self?.refreshProperties()
            self?.refreshActionBar()
        }
        canvas.onToolChange = { [weak self] in
            self?.refreshTools()
            self?.refreshProperties()
        }
        canvas.onCopy = { [weak self] in self?.copyImage(nil) }
    }

    /// Shows another screenshot in this window (upstream's reused editor): its elements and undo are gone.
    func show(_ image: CGImage, scale: CGFloat, title: String, date: Date) {
        canvas.commitEditing()
        canvas.cancelCrop()
        canvas.select(nil)
        editorDocument.reset(image: image, scale: scale, title: title, captureDate: date)
        canvas.documentChanged()
        lastSavedURL = nil
        uploadURL = nil
        statusBar.setMessage("", isError: false, menu: nil)
        refitWindowForNewImage()
        refreshAll()
    }

    /// File › Close All.
    @objc func closeAllWindows(_ sender: Any?) {
        onCloseAll?()
    }

    // MARK: State

    func refreshAll() {
        refreshTools()
        refreshProperties()
        refreshDocumentState()
    }

    /// A crop is drawn and waits for Crop or Cancel: the other actions are off (upstream disables the form's controls
    /// while a confirmable element is pending, `ToolStripItemEndisabler`).
    var isCropPending: Bool { canvas.tool == .crop && canvas.cropRect != nil }

    private func refreshTools() {
        for (tool, button) in toolButtons { button.state = tool == canvas.tool ? .on : .off }
        cropGroup.isHidden = canvas.tool != .crop
        if let index = CropMode.allCases.firstIndex(of: canvas.cropMode) { cropModeControl.selectedSegment = index }
        refreshActionBar()
        refreshUndoButtons()
    }

    /// The edit buttons follow the selection and the clipboard (buttons don't validate like menu items).
    func refreshActionBar() {
        actionBar?.refresh(canvas: canvas, locked: isCropPending)
    }

    private func refreshUndoButtons() {
        undoButton.isEnabled = editorDocument.canUndo && !isCropPending
        redoButton.isEnabled = editorDocument.canRedo && !isCropPending
    }

    func refreshDocumentState() {
        guard let window else { return }
        window.title = editorDocument.fileURL?.lastPathComponent ?? "\(editorDocument.title) – Greenshot"
        window.representedURL = editorDocument.fileURL
        window.isDocumentEdited = editorDocument.isModified
        refreshUndoButtons()
        if counterStartField.currentEditor() == nil { counterStartField.integerValue = editorDocument.counterStart }
        counterStartStepper.integerValue = editorDocument.counterStart
        refreshCounterTool()
        statusBar.setDimensions(EditorWindowStatus.dimensions(editorDocument.imageSize))
        statusBar.setZoom(EditorWindowZoom.label(scrollView.magnification))
        refitWindowIfImageResized()
        onDocumentStateChange?(self)
    }

    /// The counter tool's icon shows the number the next counter gets (upstream's step label button images).
    private func refreshCounterTool() {
        guard let button = toolButtons[.counter] else { return }
        let next = editorDocument.counterStart + editorDocument.annotations.filter { $0.kind == .counter }.count
        let symbol = (0...50).contains(next) ? "\(next).circle" : "number.circle"
        guard symbol != counterSymbol, let image = NSImage(systemSymbolName: symbol, accessibilityDescription: "Counter") else { return }
        counterSymbol = symbol
        button.image = image
    }

    /// The kind whose properties the bar shows: the selected element's, else the tool's.
    private var activeKind: AnnotationKind? {
        canvas.selectedAnnotation?.kind ?? canvas.tool.kind
    }

    private var activeStyle: AnnotationStyle? {
        if let selected = canvas.selectedAnnotation { return selected.style }
        return activeKind.map { settings.value.style(for: $0) }
    }

    func refreshProperties() {
        let kind = activeKind
        for (view, kinds) in propertyGroups { view.isHidden = kind.map { !kinds.contains($0) } ?? true }
        guard let kind, let style = activeStyle else { return }
        refreshModeGroups(kind: kind, style: style)
        lineColorLabel.stringValue = (kind == .text || kind == .counter) ? "Text" : "Line"
        lineColorWell.color = NSColor(cgColor: style.lineColor.cgColor) ?? .red
        fillColorWell.color = NSColor(cgColor: style.fillColor.cgColor) ?? .clear
        lineWidthField.show(style.lineWidth)
        shadowCheckbox.state = style.shadow ? .on : .off
        fontSizeField.show(style.fontSize)
        let faces = Self.availableFaces(of: style.fontFamily)
        boldButton.isEnabled = faces.bold
        italicButton.isEnabled = faces.italic
        boldButton.state = style.bold && faces.bold ? .on : .off
        italicButton.state = style.italic && faces.italic ? .on : .off
        arrowHeadsPopup.selectItem(at: ArrowHeads.allCases.firstIndex(of: style.arrowHeads) ?? 2)
        highlightPopup.selectItem(at: HighlightMode.allCases.firstIndex(of: style.highlightMode) ?? 0)
        obfuscatePopup.selectItem(at: ObfuscateMode.allCases.firstIndex(of: style.obfuscateMode) ?? 0)
        pixelSizeField.show(style.pixelSize)
        blurRadiusField.show(style.blurRadius)
        brightnessField.show((style.brightness * 100).rounded())
        cutMarkStylePopup.selectItem(at: CutMarkStyle.allCases.firstIndex(of: style.cutMarkStyle) ?? 4)
        selectClosest(toothHeightPopup, values: Self.toothHeights, to: style.toothHeight)
        selectClosest(toothRangePopup, values: Self.toothRanges, to: style.toothRange)
        if let index = fontFamilies.firstIndex(of: style.fontFamily) {
            fontFamilyPopup.selectItem(at: index + 2)
        } else {
            fontFamilyPopup.selectItem(at: 0)
        }
        horizontalAlignmentControl.selectedSegment = HorizontalTextAlignment.allCases.firstIndex(of: style.horizontalAlignment) ?? 1
        verticalAlignmentControl.selectedSegment = VerticalTextAlignment.allCases.firstIndex(of: style.verticalAlignment) ?? 1
        selectClosest(magnificationPopup, values: Self.magnifications, to: style.magnification)
        counterStartField.integerValue = editorDocument.counterStart
        counterStartStepper.integerValue = editorDocument.counterStart
        refreshEmoji()
    }

    /// The groups that also depend on a mode: pixel size for pixelate; blur radius for blur and the area highlight;
    /// brightness for the area highlight (upstream `BRIGHTNESS`); the zoom factor for the magnifier.
    private func refreshModeGroups(kind: AnnotationKind, style: AnnotationStyle) {
        let obfuscate = kind == .obfuscate
        let highlight = kind == .highlight
        let area = highlight && style.highlightMode == .area
        pixelSizeGroup?.isHidden = !(obfuscate && style.obfuscateMode == .pixelate)
        blurRadiusGroup?.isHidden = !((obfuscate && style.obfuscateMode == .blur) || area)
        brightnessGroup?.isHidden = !area
        magnificationGroup?.isHidden = !(highlight && style.highlightMode == .magnify)
    }

    private func refreshEmoji() {
        let emoji = canvas.selectedAnnotation.flatMap { $0.kind == .emoji ? $0.text : nil } ?? settings.value.recentEmoji
        // An emoji from the Character Viewer that isn't in the short list shows as an extra item at the top.
        if emojiPopup.item(at: 0)?.tag == Self.extraEmojiTag { emojiPopup.removeItem(at: 0) }
        if let index = EmojiChoices.all.firstIndex(of: emoji) {
            emojiPopup.selectItem(at: index)
        } else {
            emojiPopup.insertItem(withTitle: emoji, at: 0)
            emojiPopup.item(at: 0)?.tag = Self.extraEmojiTag
            emojiPopup.selectItem(at: 0)
        }
    }

    private func selectClosest(_ popup: NSPopUpButton, values: [Int], to value: Double) {
        let index = values.indices.min { abs(Double(values[$0]) - value) < abs(Double(values[$1]) - value) } ?? 0
        popup.selectItem(at: index)
    }

    /// Which faces a font family has, so Bold and Italic are off when it has none (upstream `FontPropertyChanged`).
    private static var facesCache: [String: (bold: Bool, italic: Bool)] = [:]

    static func availableFaces(of family: String) -> (bold: Bool, italic: Bool) {
        // The system font has both.
        guard !family.isEmpty else { return (true, true) }
        if let cached = facesCache[family] { return cached }
        var bold = false
        var italic = false
        for member in NSFontManager.shared.availableMembers(ofFontFamily: family) ?? [] where member.count >= 4 {
            let weight = (member[2] as? NSNumber)?.intValue ?? 5
            let traits = NSFontTraitMask(rawValue: (member[3] as? NSNumber)?.uintValue ?? 0)
            if traits.contains(.boldFontMask) || weight >= 8 { bold = true }
            if traits.contains(.italicFontMask) { italic = true }
        }
        let faces = (bold: bold, italic: italic)
        facesCache[family] = faces
        return faces
    }

    /// Applies a property change to the selected element and remembers it for new elements of that kind.
    func applyStyle(_ change: (inout AnnotationStyle) -> Void) {
        guard let kind = activeKind else { return }
        var remembered = settings.value.style(for: kind)
        change(&remembered)
        settings.update { $0.editorStyles[kind.rawValue] = remembered }
        // With several elements selected the change applies to all of them, as one undo step.
        let selected = canvas.selectedAnnotations
        if !selected.isEmpty {
            editorDocument.change {
                for var element in selected {
                    change(&element.style)
                    editorDocument.update(element)
                }
            }
            canvas.documentChanged()
        }
        refreshProperties()
    }

    // MARK: Font menu

    func menuNeedsUpdate(_ menu: NSMenu) {
        guard menu === fontFamilyPopup.menu, !fontMenuStyled else { return }
        fontMenuStyled = true
        let size = NSFont.systemFontSize
        for (index, family) in fontFamilies.enumerated() {
            guard let item = menu.item(at: index + 2), let font = NSFont(name: family, size: size)
                ?? NSFontManager.shared.font(withFamily: family, traits: [], weight: 5, size: size) else { continue }
            item.attributedTitle = NSAttributedString(string: family, attributes: [.font: font])
        }
    }

    // MARK: Property actions

    @objc private func lineColorChanged() { applyStyle { $0.lineColor = RGBAColor(lineColorWell.color) } }
    @objc private func fillColorChanged() { applyStyle { $0.fillColor = RGBAColor(fillColorWell.color) } }
    @objc private func clearLine() { applyStyle { $0.lineColor = .clear } }
    @objc private func clearFill() { applyStyle { $0.fillColor = .clear } }
    @objc private func shadowChanged() { applyStyle { $0.shadow = shadowCheckbox.state == .on } }
    @objc private func boldChanged() { applyStyle { $0.bold = boldButton.state == .on } }
    @objc private func italicChanged() { applyStyle { $0.italic = italicButton.state == .on } }
    @objc private func arrowHeadsChanged() { applyStyle { $0.arrowHeads = ArrowHeads.allCases[arrowHeadsPopup.indexOfSelectedItem] } }
    @objc private func highlightChanged() { applyStyle { $0.highlightMode = HighlightMode.allCases[highlightPopup.indexOfSelectedItem] } }
    @objc private func obfuscateChanged() { applyStyle { $0.obfuscateMode = ObfuscateMode.allCases[obfuscatePopup.indexOfSelectedItem] } }

    @objc private func fontFamilyChanged() {
        let index = fontFamilyPopup.indexOfSelectedItem
        let family = index >= 2 && index - 2 < fontFamilies.count ? fontFamilies[index - 2] : ""
        applyStyle { $0.fontFamily = family }
    }

    @objc private func horizontalAlignmentChanged() {
        let index = horizontalAlignmentControl.selectedSegment
        guard HorizontalTextAlignment.allCases.indices.contains(index) else { return }
        applyStyle { $0.horizontalAlignment = HorizontalTextAlignment.allCases[index] }
    }

    @objc private func verticalAlignmentChanged() {
        let index = verticalAlignmentControl.selectedSegment
        guard VerticalTextAlignment.allCases.indices.contains(index) else { return }
        applyStyle { $0.verticalAlignment = VerticalTextAlignment.allCases[index] }
    }

    @objc private func magnificationChanged() {
        applyStyle { $0.magnification = Double(Self.magnifications[magnificationPopup.indexOfSelectedItem]) }
    }

    /// The first counter's number; the others count on from it. An undo step of its own.
    @objc private func counterStartChanged(_ sender: NSControl) {
        let value = min(max(sender.integerValue, 0), 9999)
        if value != editorDocument.counterStart {
            editorDocument.change { editorDocument.counterStart = value }
            canvas.documentChanged()
        }
        refreshProperties()
        if sender === counterStartField { window?.makeFirstResponder(canvas) }
    }

    @objc private func cutMarkStyleChanged() {
        applyStyle { $0.cutMarkStyle = CutMarkStyle.allCases[cutMarkStylePopup.indexOfSelectedItem] }
    }

    @objc private func cutOutJointChanged() {
        let index = cutOutJointPopup.indexOfSelectedItem
        guard CutMarkStyle.allCases.indices.contains(index) else { return }
        settings.update { $0.cutOutMarkStyle = CutMarkStyle.allCases[index] }
    }

    @objc private func cropModeChanged() {
        let index = cropModeControl.selectedSegment
        guard CropMode.allCases.indices.contains(index) else { return }
        canvas.selectCropMode(CropMode.allCases[index])
        window?.makeFirstResponder(canvas)
    }

    @objc private func toothRangeChanged() {
        applyStyle { $0.toothRange = Double(Self.toothRanges[toothRangePopup.indexOfSelectedItem]) }
    }

    /// The band of a selected cut mark grows or shrinks with its teeth, so its gap keeps its size.
    @objc private func toothHeightChanged() {
        let height = Double(Self.toothHeights[toothHeightPopup.indexOfSelectedItem])
        guard let kind = activeKind else { return }
        var remembered = settings.value.style(for: kind)
        remembered.toothHeight = height
        settings.update { $0.editorStyles[kind.rawValue] = remembered }
        let selected = canvas.selectedAnnotations
        if !selected.isEmpty {
            editorDocument.change {
                for element in selected { editorDocument.update(element.withToothHeight(height, scale: editorDocument.scale)) }
            }
            canvas.documentChanged()
        }
        refreshProperties()
    }

    private static let extraEmojiTag = 1

    @objc private func emojiChanged() {
        guard let item = emojiPopup.selectedItem else { return }
        if item.title == "More Emoji…" {
            refreshProperties()
            canvas.showEmojiPalette()
            return
        }
        pickEmoji(item.title)
    }

    /// Changes the selected emoji element and remembers the emoji for new ones (upstream `RecentEmoji`).
    private func pickEmoji(_ emoji: String) {
        settings.update { $0.recentEmoji = emoji }
        let selected = canvas.selectedAnnotations.filter { $0.kind == .emoji }
        if !selected.isEmpty {
            editorDocument.change {
                for var element in selected {
                    element.text = emoji
                    editorDocument.update(element)
                }
            }
            canvas.documentChanged()
        }
        refreshProperties()
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
        if let url = editorDocument.fileURL, GreenshotFile.isGreenshotFile(url) {
            // The image with its elements, editable again later (EditorWindowController+Files.swift).
            return saveGreenshotFile(to: url)
        }
        if let url = editorDocument.fileURL, ImageFormat(fileExtension: url.pathExtension) == nil {
            // Opened from a format this app can't write (HEIC, WebP, ...): never overwrite it, ask for a new file.
            saveImageAs(nil)
            return !editorDocument.isModified
        }
        let image = editorDocument.flattened()
        let saved: URL
        if let url = editorDocument.fileURL {
            guard saver.write(image, scale: editorDocument.scale, to: url) else { return false }
            saver.notifySaved(url)
            saved = url
        } else {
            guard let url = saver.saveDirectly(image, scale: editorDocument.scale, title: editorDocument.title, date: editorDocument.captureDate) else { return false }
            editorDocument.fileURL = url
            saved = url
        }
        showExportResult(.succeeded(fileURL: saved), destination: "Save")
        return true
    }

    @objc func saveImageAs(_ sender: Any?) {
        canvas.commitEditing()
        guard let url = saver.saveAs(editorDocument.flattened(), scale: editorDocument.scale, title: editorDocument.title,
                                     date: editorDocument.captureDate, suggestedURL: editorDocument.fileURL) else { return }
        editorDocument.fileURL = url
        showExportResult(.succeeded(fileURL: url), destination: "Save As")
    }

    @objc func copyImage(_ sender: Any?) {
        canvas.commitEditing()
        Clipboard.copy(editorDocument.flattened(), scale: editorDocument.scale)
        saver.notify("Copied to the clipboard")
        showExportResult(.succeeded(), destination: "Clipboard")
        refreshActionBar()
    }

    /// Print goes through the output manager like the other destinations, which reports how it ended.
    @objc func printImage(_ sender: Any?) {
        export(.destination(.printer))
    }

    // MARK: Elements files (Object menu)

    private static var elementsFileType: UTType {
        UTType(filenameExtension: ElementTransfer.fileExtension, conformingTo: .json) ?? .json
    }

    /// Upstream "Save objects to file": every element, as JSON.
    @objc func saveElements(_ sender: Any?) {
        canvas.commitEditing()
        guard let window else { return }
        let panel = NSSavePanel()
        panel.allowedContentTypes = [Self.elementsFileType]
        panel.nameFieldStringValue = "\(editorDocument.title).\(ElementTransfer.fileExtension)"
        panel.beginSheetModal(for: window) { [weak self] response in
            guard let self, response == .OK, let url = panel.url else { return }
            do {
                try ElementTransfer.file(of: self.editorDocument).encoded().write(to: url, options: .atomic)
            } catch {
                ErrorPresenter.show(message: "The elements could not be saved", detail: error.localizedDescription)
            }
        }
    }

    /// Upstream "Load objects from file": adds the elements of a file, as one undo step, and selects them. Also reads
    /// the `.gst` element files of Greenshot for Windows.
    @objc func loadElements(_ sender: Any?) {
        canvas.commitEditing()
        guard let window else { return }
        let panel = NSOpenPanel()
        panel.allowedContentTypes = [Self.elementsFileType, Self.windowsElementsFileType]
        panel.allowsMultipleSelection = false
        panel.beginSheetModal(for: window) { [weak self] response in
            guard let self, response == .OK, let url = panel.url else { return }
            let transfer: ElementTransfer
            var message: String?
            if url.pathExtension.caseInsensitiveCompare(GreenshotFile.templateExtension) == .orderedSame {
                guard let loaded = self.windowsElements(from: url) else { return }
                transfer = ElementTransfer(elements: loaded.elements, scale: self.editorDocument.scale)
                message = loaded.message
            } else {
                guard let data = try? Data(contentsOf: url), let decoded = ElementTransfer.decode(data) else {
                    ErrorPresenter.show(message: "The elements could not be loaded", detail: url.lastPathComponent)
                    return
                }
                transfer = decoded
            }
            let added = transfer.load(into: self.editorDocument)
            self.canvas.documentChanged()
            self.canvas.select(added.map(\.id))
            if let message { self.showStatusMessage(message) }
        }
    }

    // MARK: Insert window (Edit menu)

    /// Upstream Edit › Insert window: captures the window and adds it as an image element at the top left.
    @objc func insertWindow(_ sender: NSMenuItem) {
        canvas.commitEditing()
        guard let number = sender.representedObject as? NSNumber,
              let target = ScreenCapturer.onScreenWindows().first(where: { $0.id == number.uint32Value }) else {
            ErrorPresenter.show(message: "The window could not be captured", detail: CaptureError.windowNotFound.localizedDescription)
            return
        }
        let includeShadow = settings.value.includeWindowShadow
        Task { @MainActor [weak self] in
            do {
                let capture = try await ScreenCapturer.capture(window: target, showsCursor: false, includeShadow: includeShadow)
                guard let self else { return }
                let document = self.editorDocument
                guard let element = Annotation.picture(capture.image, pictureScale: capture.scale, at: .zero,
                                                       documentScale: document.scale, fitting: document.imageSize) else { return }
                self.canvas.insert([element])
            } catch {
                ErrorPresenter.show(message: "The window could not be captured", detail: error.localizedDescription)
            }
        }
    }

    /// The actions that wait while a crop is pending (upstream leaves Close, Help and Settings).
    private static let lockedWhileCropping: Set<Selector> = [
        #selector(saveImage(_:)), #selector(saveImageAs(_:)), #selector(copyImage(_:)), #selector(printImage(_:)),
        #selector(saveElements(_:)), #selector(loadElements(_:)), #selector(insertWindow(_:)), #selector(insertBarcode(_:)),
        #selector(saveAsGreenshotFile(_:)),
    ]

    func validateMenuItem(_ item: NSMenuItem) -> Bool {
        if let action = item.action, isCropPending, Self.lockedWhileCropping.contains(action) { return false }
        if let imageItem = validateImageMenuItem(item) { return imageItem }
        if let exportItem = validateExportMenuItem(item) { return exportItem }
        switch item.action {
        case #selector(saveElements(_:)): return !editorDocument.annotations.isEmpty
        case #selector(zoomPreset(_:)):
            item.state = EditorWindowZoom.matches(scrollView.magnification, percent: item.tag) ? .on : .off
            return true
        default: return true
        }
    }

    // MARK: Window

    func windowDidResize(_ notification: Notification) {
        refreshDocumentState()
        rememberNormalFrame()
    }

    func windowDidMove(_ notification: Notification) {
        rememberNormalFrame()
    }

    func windowDidBecomeKey(_ notification: Notification) {
        refreshActionBar()
        restoreZoomIfNeeded()
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
        guard editorDocument.isModified, !settings.value.suppressSaveDialogAtClose, let window else { return true }
        NSApp.activate()
        window.makeKeyAndOrderFront(nil)
        return resolveChanges(makeSaveAlert().runModal())
    }

    /// Before another screenshot replaces this one (reuse editor): true when it may go. Asks to save a changed one;
    /// unlike closing, "suppress the save dialog" doesn't apply, so a new capture never silently discards edits.
    func confirmReplace() -> Bool {
        canvas.commitEditing()
        guard editorDocument.isModified, let window else { return true }
        NSApp.activate()
        window.makeKeyAndOrderFront(nil)
        return resolveChanges(makeSaveAlert().runModal())
    }

    func windowShouldClose(_ sender: NSWindow) -> Bool {
        canvas.commitEditing()
        // Upstream `SuppressSaveDialogAtClose`: closing a changed screenshot doesn't ask.
        guard editorDocument.isModified, !settings.value.suppressSaveDialogAtClose else { return true }
        makeSaveAlert().beginSheetModal(for: sender) { [weak self] response in
            guard let self, self.resolveChanges(response) else { return }
            self.window?.close()
        }
        return false
    }

    func windowWillClose(_ notification: Notification) {
        savePlacement()
        NotificationCenter.default.removeObserver(self, name: NSScrollView.didEndLiveMagnifyNotification, object: scrollView)
        onClose(self)
    }
}
