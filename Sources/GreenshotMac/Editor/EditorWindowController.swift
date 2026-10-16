// Greenshot for Mac (Community) - an unofficial macOS port of Greenshot
// Copyright (C) 2026 Greenshot for Mac (Community) contributors
// Based on Greenshot, Copyright (C) 2007-2026 Thomas Braun, Jens Klingen, Robin Krom
// SPDX-License-Identifier: GPL-3.0-or-later

import AppKit
import GreenshotCore
import UniformTypeIdentifiers

/// The image editor window (upstream `ImageEditorForm`): tools on the left, the properties of the current tool
/// or selected element on top, the image in the middle.
@MainActor
final class EditorWindowController: NSWindowController, NSWindowDelegate, NSMenuItemValidation {
    let editorDocument: EditorDocument
    let settings: SettingsStore
    let saver: ImageSaver
    private let onClose: (EditorWindowController) -> Void
    /// File › Close All (the editor manager closes every editor).
    var onCloseAll: (() -> Void)?
    /// The last frame of an editor window, used when the window isn't sized to the screenshot.
    private static let frameDefaultsKey = "editorWindowFrame"

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
    private let emojiPopup = NSPopUpButton()
    private let cutMarkStylePopup = NSPopUpButton()
    private let toothHeightPopup = NSPopUpButton()
    private let toothRangePopup = NSPopUpButton()
    private let fontFamilyPopup = NSPopUpButton()
    private let horizontalAlignmentControl = NSSegmentedControl()
    private let verticalAlignmentControl = NSSegmentedControl()
    private let counterStartField = NSTextField()
    private let counterStartStepper = NSStepper()
    private let magnificationPopup = NSPopUpButton()
    private var magnificationGroup: NSView?
    /// The font families in the font popup after "System Font".
    private let fontFamilies = NSFontManager.shared.availableFontFamilies.sorted {
        $0.localizedStandardCompare($1) == .orderedAscending
    }
    private var propertyGroups: [(view: NSView, kinds: Set<AnnotationKind>)] = []
    private let cropGroup = NSStackView()
    /// How the joint of a cut-out is marked (upstream's cut mark style drop-down of the crop tool).
    private let cutOutJointPopup = NSPopUpButton()

    private static let lineWidths = [0, 1, 2, 3, 4, 5, 6, 8, 10]
    private static let fontSizes = [9, 11, 13, 15, 18, 22, 27, 36, 48, 64, 96]
    private static let effectSizes = [2, 3, 5, 8, 12, 16, 24]
    private static let toothHeights = [4, 6, 8, 10, 12, 16, 20, 24, 32]
    private static let toothRanges = [8, 10, 12, 16, 20, 24, 30, 40, 60]
    private static let magnifications = [2, 3, 4]

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
        // Hide the properties that don't apply before sizing: with all of them shown the top bar is wider than a
        // laptop screen, and the window would grow to fit it.
        refreshAll()
        sizeWindowToImage()
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

    /// The zoom factor of the magnifier, shown only for the Magnify highlight (upstream `MAGNIFICATION_FACTOR`).
    private func magnifyGroup() -> NSView {
        let view = group([label("Zoom"), magnificationPopup], for: [.highlight])
        magnificationGroup = view
        return view
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
        setUp(emojiPopup, titles: EmojiChoices.all, action: #selector(emojiChanged))
        emojiPopup.menu?.addItem(.separator())
        emojiPopup.addItem(withTitle: "More Emoji…")
        setUp(cutMarkStylePopup, titles: ["None", "Line", "Zig-zag", "Wave", "Torn"], action: #selector(cutMarkStyleChanged))
        setUp(toothHeightPopup, titles: Self.toothHeights.map { "\($0) pt" }, action: #selector(toothHeightChanged))
        setUp(toothRangePopup, titles: Self.toothRanges.map { "\($0) pt" }, action: #selector(toothRangeChanged))
        setUp(fontFamilyPopup, titles: ["System Font"] + fontFamilies, action: #selector(fontFamilyChanged))
        fontFamilyPopup.menu?.insertItem(.separator(), at: 1)
        setUp(magnificationPopup, titles: Self.magnifications.map { "\($0)×" }, action: #selector(magnificationChanged))
        setUpSegments(horizontalAlignmentControl, symbols: ["text.alignleft", "text.aligncenter", "text.alignright"],
                      labels: ["Left", "Center", "Right"], action: #selector(horizontalAlignmentChanged))
        setUpSegments(verticalAlignmentControl, symbols: ["align.vertical.top", "align.vertical.center", "align.vertical.bottom"],
                      labels: ["Top", "Middle", "Bottom"], action: #selector(verticalAlignmentChanged))
        // Upstream's counter start value (`counterUpDown`).
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

        let properties = NSStackView(views: [
            group([lineColorLabel, lineColorWell], for: [.rectangle, .ellipse, .line, .arrow, .freehand, .text, .counter, .speechBubble, .cutMark]),
            group([label("Fill"), fillColorWell, noFill], for: [.rectangle, .ellipse, .text, .counter, .highlight, .speechBubble, .cutMark]),
            group([label("Width"), lineWidthPopup], for: [.rectangle, .ellipse, .line, .arrow, .freehand, .speechBubble, .counter, .cutMark]),
            group([cutMarkStylePopup, label("Teeth"), toothHeightPopup, label("Range"), toothRangePopup], for: [.cutMark]),
            group([arrowHeadsPopup], for: [.arrow]),
            group([label("Size"), fontSizePopup], for: [.text, .counter, .speechBubble]),
            group([boldButton, italicButton], for: [.text, .speechBubble]),
            group([highlightPopup], for: [.highlight]),
            group([obfuscatePopup, label("Size"), effectSizePopup], for: [.obfuscate]),
            group([label("Emoji"), emojiPopup], for: [.emoji]),
            group([fontFamilyPopup, horizontalAlignmentControl, verticalAlignmentControl], for: [.text, .speechBubble]),
            group([label("Start at"), counterStartField, counterStartStepper], for: [.counter]),
            magnifyGroup(),
            group([shadowCheckbox], for: [.rectangle, .ellipse, .line, .arrow, .freehand, .text, .speechBubble, .highlight,
                                          .obfuscate, .counter, .emoji, .image, .cutMark]),
        ])
        properties.spacing = 14

        let applyCrop = NSButton(title: "Crop", target: self, action: #selector(applyCrop))
        applyCrop.bezelStyle = .push
        applyCrop.keyEquivalent = ""
        let cancelCrop = NSButton(title: "Cancel", target: self, action: #selector(cancelCrop))
        setUp(cutOutJointPopup, titles: ["None", "Line", "Zig-zag", "Wave", "Torn"], action: #selector(cutOutJointChanged))
        cutOutJointPopup.toolTip = "How the joint is marked when the selected rows or columns are cut out"
        cutOutJointPopup.selectItem(at: CutMarkStyle.allCases.firstIndex(of: settings.value.cutOutMarkStyle) ?? 0)
        cropGroup.setViews([label("Drag the area to keep, or the rows or columns to cut out"), applyCrop, cancelCrop,
                            Self.divider(), label("Cut-out joint"), cutOutJointPopup], in: .leading)
        cropGroup.spacing = 6

        // The image operations (effects, resize, rotate, canvas) live in EditorWindowController+Image.swift.
        let imageItems = imageToolbarItems()

        let spacer = NSView()
        spacer.setContentHuggingPriority(.init(1), for: .horizontal)
        let topBar = NSStackView(views: [save, saveAs, copy, print, Self.divider(), undoButton, redoButton] + imageItems +
                                        [Self.divider(), properties, cropGroup, spacer])
        topBar.spacing = 6
        topBar.edgeInsets = NSEdgeInsets(top: 6, left: 10, bottom: 6, right: 10)
        // When a tool has many properties, the bar is cut off at the window's edge rather than widening the window.
        topBar.setClippingResistancePriority(.defaultLow, for: .horizontal)
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
            if tool == .select || tool == .cutMark { palette.addArrangedSubview(Self.horizontalDivider()) }
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
        canvas.onSelectionChange = { [weak self] in self?.refreshProperties() }
        canvas.onToolChange = { [weak self] in
            self?.refreshTools()
            self?.refreshProperties()
        }
        canvas.onCopy = { [weak self] in self?.copyImage(nil) }
    }

    /// Opens the window at the image's size, up to most of the screen; larger images are zoomed to fit. With
    /// "match size to capture" off (upstream `MatchSizeToCapture`) it keeps the last editor window's size instead.
    private func sizeWindowToImage() {
        guard let window else { return }
        if !settings.value.matchSizeToCapture, let frame = UserDefaults.standard.string(forKey: Self.frameDefaultsKey) {
            window.setFrame(from: frame)
            window.layoutIfNeeded()
            zoomToFitIfLarger()
            return
        }
        let visible = (NSScreen.main ?? NSScreen.screens[0]).visibleFrame
        let image = canvas.pointSize
        let chrome = NSSize(width: 60, height: 90)
        let width = min(max(image.width + chrome.width, 760), visible.width * 0.9)
        let height = min(max(image.height + chrome.height, 420), visible.height * 0.9)
        window.setContentSize(NSSize(width: width, height: height))
        window.center()
        window.layoutIfNeeded()
        zoomToFitIfLarger()
    }

    private func zoomToFitIfLarger() {
        let image = canvas.pointSize
        let viewport = scrollView.contentSize
        if image.width > viewport.width || image.height > viewport.height {
            zoomToFit(nil)
        } else {
            setMagnification(1)
        }
    }

    /// Shows another screenshot in this window (upstream's reused editor): its elements and undo are gone.
    func show(_ image: CGImage, scale: CGFloat, title: String, date: Date) {
        canvas.commitEditing()
        canvas.cancelCrop()
        canvas.select(nil)
        editorDocument.reset(image: image, scale: scale, title: title, captureDate: date)
        canvas.documentChanged()
        if settings.value.matchSizeToCapture {
            sizeWindowToImage()
        } else {
            zoomToFitIfLarger()
        }
        refreshAll()
    }

    private func rememberFrame() {
        guard let window, window.isVisible, !window.isMiniaturized else { return }
        UserDefaults.standard.set(window.frameDescriptor, forKey: Self.frameDefaultsKey)
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

    private func refreshTools() {
        for (tool, button) in toolButtons { button.state = tool == canvas.tool ? .on : .off }
        cropGroup.isHidden = canvas.tool != .crop
    }

    func refreshDocumentState() {
        guard let window else { return }
        window.title = editorDocument.fileURL?.lastPathComponent ?? "\(editorDocument.title) – Greenshot"
        window.representedURL = editorDocument.fileURL
        window.isDocumentEdited = editorDocument.isModified
        undoButton.isEnabled = editorDocument.canUndo
        redoButton.isEnabled = editorDocument.canRedo
        if counterStartField.currentEditor() == nil { counterStartField.integerValue = editorDocument.counterStart }
        counterStartStepper.integerValue = editorDocument.counterStart
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

    func refreshProperties() {
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
        magnificationGroup?.isHidden = kind != .highlight || style.highlightMode != .magnify
        counterStartField.integerValue = editorDocument.counterStart
        counterStartStepper.integerValue = editorDocument.counterStart
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

    /// Applies a property change to the selected element and remembers it for new elements of that kind.
    private func applyStyle(_ change: (inout AnnotationStyle) -> Void) {
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

    // MARK: Property actions

    @objc private func lineColorChanged() { applyStyle { $0.lineColor = RGBAColor(lineColorWell.color) } }
    @objc private func fillColorChanged() { applyStyle { $0.fillColor = RGBAColor(fillColorWell.color) } }
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
        if let url = editorDocument.fileURL, ImageFormat(fileExtension: url.pathExtension) == nil {
            // Opened from a format this app can't write (HEIC, WebP, ...): never overwrite it, ask for a new file.
            saveImageAs(nil)
            return !editorDocument.isModified
        }
        let image = editorDocument.flattened()
        if let url = editorDocument.fileURL {
            guard saver.write(image, scale: editorDocument.scale, to: url) else { return false }
            saver.notifySaved(url)
        } else {
            guard let url = saver.saveDirectly(image, scale: editorDocument.scale, title: editorDocument.title, date: editorDocument.captureDate) else { return false }
            editorDocument.fileURL = url
        }
        editorDocument.markSaved()
        refreshDocumentState()
        return true
    }

    @objc func saveImageAs(_ sender: Any?) {
        canvas.commitEditing()
        guard let url = saver.saveAs(editorDocument.flattened(), scale: editorDocument.scale, title: editorDocument.title,
                                     date: editorDocument.captureDate, suggestedURL: editorDocument.fileURL) else { return }
        editorDocument.fileURL = url
        editorDocument.markSaved()
        refreshDocumentState()
    }

    @objc func copyImage(_ sender: Any?) {
        canvas.commitEditing()
        Clipboard.copy(editorDocument.flattened(), scale: editorDocument.scale)
        editorDocument.markSaved()
        refreshDocumentState()
        saver.notify("Copied to the clipboard")
    }

    @objc func printImage(_ sender: Any?) {
        canvas.commitEditing()
        Printing.print(editorDocument.flattened(), scale: editorDocument.scale, window: window)
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

    /// Upstream "Load objects from file": adds the elements of a file, as one undo step, and selects them.
    @objc func loadElements(_ sender: Any?) {
        canvas.commitEditing()
        guard let window else { return }
        let panel = NSOpenPanel()
        panel.allowedContentTypes = [Self.elementsFileType]
        panel.allowsMultipleSelection = false
        panel.beginSheetModal(for: window) { [weak self] response in
            guard let self, response == .OK, let url = panel.url else { return }
            guard let data = try? Data(contentsOf: url), let transfer = ElementTransfer.decode(data) else {
                ErrorPresenter.show(message: "The elements could not be loaded", detail: url.lastPathComponent)
                return
            }
            let added = transfer.load(into: self.editorDocument)
            self.canvas.documentChanged()
            self.canvas.select(added.map(\.id))
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

    func validateMenuItem(_ item: NSMenuItem) -> Bool {
        if let imageItem = validateImageMenuItem(item) { return imageItem }
        switch item.action {
        case #selector(saveElements(_:)): return !editorDocument.annotations.isEmpty
        case #selector(zoomPreset(_:)):
            item.state = abs(scrollView.magnification - Self.zoomFactor(percent: item.tag)) < 0.005 ? .on : .off
            return true
        default: return true
        }
    }

    // MARK: Zoom (View menu)

    @objc func zoomIn(_ sender: Any?) { setMagnification(scrollView.magnification * 1.25) }
    @objc func zoomOut(_ sender: Any?) { setMagnification(scrollView.magnification / 1.25) }
    @objc func actualSize(_ sender: Any?) { setMagnification(1) }

    /// Upstream's zoom presets (`ImageEditorForm` zoom menu); the menu item's tag is the percentage.
    static let zoomPresets = [25, 50, 66, 75, 100, 200, 300, 400, 600]

    /// 66 % is two thirds, like upstream's.
    static func zoomFactor(percent: Int) -> CGFloat {
        percent == 66 ? 2.0 / 3.0 : CGFloat(percent) / 100
    }

    @objc func zoomPreset(_ sender: NSMenuItem) {
        setMagnification(Self.zoomFactor(percent: sender.tag))
    }

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
        rememberFrame()
    }

    func windowDidMove(_ notification: Notification) {
        rememberFrame()
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
        rememberFrame()
        onClose(self)
    }
}
