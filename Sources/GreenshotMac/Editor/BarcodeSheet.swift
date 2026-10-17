// Greenshot for Mac (Community) - an unofficial macOS port of Greenshot
// Copyright (C) 2026 Greenshot for Mac (Community) contributors
// Based on Greenshot, Copyright (C) 2007-2026 Thomas Braun, Jens Klingen, Robin Krom
// SPDX-License-Identifier: GPL-3.0-or-later

import AppKit
import GreenshotCore

/// The Insert QR / Barcode dialog (upstream `Greenshot.Plugin.Zxing/Views/ZxingEditorWindow.xaml(.cs)`), a sheet on the
/// editor window: the format, for a QR code what it holds and the fields of that, colours, round dots, the margin, and a
/// preview that is drawn like the element. Insert (Apply when an element is edited again) hands the spec back.
@MainActor
final class BarcodeSheet: NSObject, NSTextFieldDelegate, NSTextViewDelegate {
    /// Called with the spec when Insert or Apply is clicked.
    var onApply: ((BarcodeSpec) -> Void)?

    private(set) var spec: BarcodeSpec
    private let isEditing: Bool
    private let panel: NSPanel
    private let formatPopup = NSPopUpButton()
    private let typePopup = NSPopUpButton()
    private let choices = NSGridView()
    private let fieldsBox = NSBox()
    private var panels: [QRPayloadType: NSView] = [:]
    private var textFields: [(field: NSTextField, key: WritableKeyPath<BarcodeSpec, String>)] = []
    private var textViews: [(view: NSTextView, key: WritableKeyPath<BarcodeSpec, String>)] = []
    private let encryptionPopup = NSPopUpButton()
    private let previewView = NSImageView()
    private let foregroundWell = NSColorWell(style: .minimal)
    private let backgroundWell = NSColorWell(style: .minimal)
    private let roundedBox = NSButton(checkboxWithTitle: "Rounded Dots", target: nil, action: nil)
    private let marginPopup = NSPopUpButton()
    private let statusLabel = NSTextField(wrappingLabelWithString: "")
    private let insertButton = NSButton(title: "Insert", target: nil, action: nil)
    private let cancelButton = NSButton(title: "Cancel", target: nil, action: nil)
    /// The sheet keeps itself alive while it is open.
    private var keepAlive: BarcodeSheet?

    private static let previewSize = CGSize(width: 300, height: 210)
    private static let fieldWidth: CGFloat = 250

    /// `spec` is the element's when it is edited again, else upstream's start: QR, Text / URL, the sample URL.
    init(spec: BarcodeSpec = BarcodeSpec(), editing: Bool = false) {
        self.spec = spec
        isEditing = editing
        panel = NSPanel(contentRect: NSRect(x: 0, y: 0, width: 720, height: 460), styleMask: [.titled, .docModalWindow],
                        backing: .buffered, defer: true)
        super.init()
        buildLayout()
        load()
        refresh()
    }

    /// Shows the dialog as a sheet on `window`.
    func begin(for window: NSWindow) {
        keepAlive = self
        window.beginSheet(panel) { [weak self] _ in self?.keepAlive = nil }
        panel.makeFirstResponder(textViews.first?.view)
    }

    /// The dialog's content, for offscreen snapshots.
    var contentView: NSView? { panel.contentView }

    // MARK: Layout

    private func buildLayout() {
        // Upstream: "Insert QR / Barcode", or "Edit QR / Barcode" with an Apply button for an element's model.
        panel.title = isEditing ? "Edit QR / Barcode" : "Insert QR / Barcode"
        let title = NSTextField(labelWithString: panel.title)
        title.font = .boldSystemFont(ofSize: NSFont.systemFontSize)

        formatPopup.addItems(withTitles: BarcodeSymbology.allCases.map(\.title))
        typePopup.addItems(withTitles: QRPayloadType.allCases.map(\.title))
        encryptionPopup.addItems(withTitles: WiFiEncryption.allCases.map(\.title))
        marginPopup.addItems(withTitles: BarcodeSpec.marginRange.map(String.init))
        for popup in [formatPopup, typePopup, encryptionPopup, marginPopup] {
            popup.target = self
            popup.action = #selector(controlChanged(_:))
        }
        for well in [foregroundWell, backgroundWell] {
            well.supportsAlpha = true
            well.target = self
            well.action = #selector(controlChanged(_:))
        }
        roundedBox.target = self
        roundedBox.action = #selector(controlChanged(_:))

        let formatLabel = Self.label("Barcode Format:")
        choices.addRow(with: [formatLabel, formatPopup])
        choices.addRow(with: [Self.label("QR Type:"), typePopup])
        choices.rowSpacing = 8
        choices.columnSpacing = 8
        choices.column(at: 0).xPlacement = .trailing
        choices.rowAlignment = .firstBaseline
        formatPopup.widthAnchor.constraint(equalToConstant: Self.fieldWidth).isActive = true

        buildPanels()
        let fieldsStack = NSStackView(views: QRPayloadType.allCases.compactMap { panels[$0] })
        fieldsStack.orientation = .vertical
        fieldsStack.alignment = .leading
        fieldsBox.titleFont = .boldSystemFont(ofSize: NSFont.smallSystemFontSize)
        fieldsBox.contentView = Self.padded(fieldsStack, inset: 8)
        // The space the taller preview column leaves goes below the fields.
        let bottomFiller = NSView()
        bottomFiller.setContentHuggingPriority(.init(1), for: .vertical)
        for view in [choices, fieldsBox] as [NSView] {
            view.setContentHuggingPriority(.defaultHigh, for: .vertical)
        }
        let left = NSStackView(views: [title, choices, fieldsBox, bottomFiller])
        left.orientation = .vertical
        left.alignment = .leading
        left.spacing = 12
        fieldsBox.widthAnchor.constraint(equalToConstant: 400).isActive = true

        // The preview: drawn at its size on screen by the same code as the element.
        previewView.imageScaling = .scaleProportionallyDown
        previewView.imageAlignment = .alignCenter
        let previewBox = NSBox()
        previewBox.title = "Preview"
        previewBox.titleFont = .boldSystemFont(ofSize: NSFont.smallSystemFontSize)
        previewBox.contentView = Self.padded(previewView, inset: 8)
        previewView.widthAnchor.constraint(equalToConstant: Self.previewSize.width).isActive = true
        previewView.heightAnchor.constraint(equalToConstant: Self.previewSize.height).isActive = true

        let colours = NSStackView(views: [foregroundWell, Self.label("Foreground"), Self.spacer(width: 16),
                                          backgroundWell, Self.label("Background")])
        colours.spacing = 6
        let marginLabel = Self.label("Margin:")
        let style = NSStackView(views: [roundedBox, Self.spacer(width: 24), marginLabel, marginPopup])
        style.spacing = 6
        statusLabel.preferredMaxLayoutWidth = Self.previewSize.width
        statusLabel.font = .systemFont(ofSize: NSFont.smallSystemFontSize)

        insertButton.title = isEditing ? "Apply" : "Insert"
        insertButton.bezelStyle = .push
        insertButton.keyEquivalent = "\r"
        insertButton.target = self
        insertButton.action = #selector(insert(_:))
        cancelButton.bezelStyle = .push
        cancelButton.keyEquivalent = "\u{1b}"
        cancelButton.target = self
        cancelButton.action = #selector(cancel(_:))
        let filler = NSView()
        filler.setContentHuggingPriority(.init(1), for: .horizontal)
        let buttons = NSStackView(views: [filler, cancelButton, insertButton])

        let right = NSStackView(views: [previewBox, colours, style, statusLabel, buttons])
        right.orientation = .vertical
        right.alignment = .leading
        right.spacing = 10
        buttons.widthAnchor.constraint(equalTo: right.widthAnchor).isActive = true

        let columns = NSStackView(views: [left, right])
        columns.alignment = .top
        columns.spacing = 20
        columns.edgeInsets = NSEdgeInsets(top: 20, left: 20, bottom: 20, right: 20)
        columns.translatesAutoresizingMaskIntoConstraints = false
        let content = NSView()
        content.addSubview(columns)
        NSLayoutConstraint.activate([
            columns.leadingAnchor.constraint(equalTo: content.leadingAnchor),
            columns.trailingAnchor.constraint(equalTo: content.trailingAnchor),
            columns.topAnchor.constraint(equalTo: content.topAnchor),
            columns.bottomAnchor.constraint(equalTo: content.bottomAnchor),
        ])
        panel.contentView = content
    }

    /// The fields of every QR type (upstream's `Pnl*` panels); the text panel is also the value of the other formats.
    private func buildPanels() {
        panels[.text] = multiline("Enter plain text or URL:", \.text, height: 68)
        panels[.wifi] = grid([
            row("Network Name (SSID):", \.wifiSSID),
            row("Password:", \.wifiPassword),
            [Self.label("Encryption Type:"), encryptionPopup],
        ])
        panels[.vCard] = grid([
            row("First Name:", \.vCardFirstName), row("Last Name:", \.vCardLastName), row("Phone:", \.vCardPhone),
            row("Email:", \.vCardEmail), row("Company:", \.vCardCompany), row("URL:", \.vCardURL),
        ])
        panels[.epcTransfer] = grid([
            row("Recipient:", \.epcName), row("IBAN:", \.epcIBAN), row("BIC (optional):", \.epcBIC),
            row("Amount (EUR):", \.epcAmount), row("Reference:", \.epcReference), row("Message:", \.epcMessage),
        ])
        panels[.email] = stack([grid([row("To:", \.emailTo), row("Subject:", \.emailSubject)]),
                                multiline("Body:", \.emailBody, height: 70)])
        panels[.calendarEvent] = grid([
            row("Title:", \.eventTitle), row("Location:", \.eventLocation),
            row("Start (UTC):", \.eventStart, placeholder: "20261017T090000Z"),
            row("End (UTC):", \.eventEnd, placeholder: "20261017T100000Z"),
            row("Description:", \.eventDescription),
        ])
        panels[.phone] = grid([row("Phone Number:", \.phoneNumber)])
        panels[.sms] = stack([grid([row("Recipient Number:", \.smsNumber)]), multiline("Message:", \.smsMessage, height: 70)])
        panels[.geo] = grid([row("Latitude:", \.latitude, placeholder: "52.5163"), row("Longitude:", \.longitude, placeholder: "13.3777")])
    }

    private func row(_ title: String, _ key: WritableKeyPath<BarcodeSpec, String>, placeholder: String? = nil) -> [NSView] {
        let field = NSTextField()
        field.placeholderString = placeholder
        field.delegate = self
        field.widthAnchor.constraint(equalToConstant: 200).isActive = true
        textFields.append((field, key))
        return [Self.label(title), field]
    }

    private func grid(_ rows: [[NSView]]) -> NSGridView {
        let grid = NSGridView(views: rows)
        grid.rowSpacing = 8
        grid.columnSpacing = 8
        grid.column(at: 0).xPlacement = .trailing
        grid.rowAlignment = .firstBaseline
        return grid
    }

    private func stack(_ views: [NSView]) -> NSStackView {
        let stack = NSStackView(views: views)
        stack.orientation = .vertical
        stack.alignment = .leading
        stack.spacing = 8
        return stack
    }

    /// A label over a text area that takes Return (upstream `AcceptsReturn`, wrapping).
    private func multiline(_ title: String, _ key: WritableKeyPath<BarcodeSpec, String>, height: CGFloat) -> NSView {
        let scroll = NSTextView.scrollableTextView()
        scroll.borderType = .bezelBorder
        scroll.hasVerticalScroller = true
        if let textView = scroll.documentView as? NSTextView {
            textView.isRichText = false
            textView.allowsUndo = true
            textView.font = .systemFont(ofSize: NSFont.systemFontSize)
            textView.isAutomaticQuoteSubstitutionEnabled = false
            textView.isAutomaticDashSubstitutionEnabled = false
            textView.isAutomaticTextReplacementEnabled = false
            textView.isAutomaticSpellingCorrectionEnabled = false
            textView.delegate = self
            textViews.append((textView, key))
        }
        scroll.widthAnchor.constraint(equalToConstant: 350).isActive = true
        scroll.heightAnchor.constraint(equalToConstant: height).isActive = true
        return stack([Self.label(title), scroll])
    }

    private static func label(_ text: String) -> NSTextField {
        NSTextField(labelWithString: text)
    }

    private static func spacer(width: CGFloat) -> NSView {
        let view = NSView()
        view.widthAnchor.constraint(equalToConstant: width).isActive = true
        return view
    }

    /// `view` inside an inset container, for the content of a box.
    private static func padded(_ view: NSView, inset: CGFloat) -> NSView {
        let container = NSView()
        view.translatesAutoresizingMaskIntoConstraints = false
        container.addSubview(view)
        NSLayoutConstraint.activate([
            view.leadingAnchor.constraint(equalTo: container.leadingAnchor, constant: inset),
            view.trailingAnchor.constraint(lessThanOrEqualTo: container.trailingAnchor, constant: -inset),
            view.topAnchor.constraint(equalTo: container.topAnchor, constant: inset),
            view.bottomAnchor.constraint(equalTo: container.bottomAnchor, constant: -inset),
        ])
        return container
    }

    // MARK: Values

    /// Puts the spec into the controls (upstream `LoadFromModel`).
    private func load() {
        formatPopup.selectItem(at: spec.symbology.upstreamIndex)
        typePopup.selectItem(at: spec.qrType.upstreamIndex)
        encryptionPopup.selectItem(at: WiFiEncryption.allCases.firstIndex(of: spec.wifiEncryption) ?? 0)
        marginPopup.selectItem(at: spec.margin - BarcodeSpec.marginRange.lowerBound)
        foregroundWell.color = NSColor(cgColor: spec.foreground.cgColor) ?? .black
        backgroundWell.color = NSColor(cgColor: spec.background.cgColor) ?? .white
        roundedBox.state = spec.roundedDots ? .on : .off
        for (field, key) in textFields { field.stringValue = spec[keyPath: key] }
        for (view, key) in textViews { view.string = spec[keyPath: key] }
    }

    /// Reads the controls into the spec (upstream `PopulateModel`).
    private func read() {
        spec.symbology = BarcodeSymbology(upstreamIndex: formatPopup.indexOfSelectedItem) ?? .qrCode
        spec.qrType = QRPayloadType(upstreamIndex: typePopup.indexOfSelectedItem) ?? .text
        spec.wifiEncryption = WiFiEncryption.allCases[max(encryptionPopup.indexOfSelectedItem, 0)]
        spec.margin = BarcodeSpec.marginRange.lowerBound + max(marginPopup.indexOfSelectedItem, 0)
        spec.foreground = RGBAColor(foregroundWell.color)
        spec.background = RGBAColor(backgroundWell.color)
        spec.roundedDots = roundedBox.state == .on
        for (field, key) in textFields { spec[keyPath: key] = field.stringValue }
        for (view, key) in textViews { spec[keyPath: key] = view.string }
    }

    /// Shows the fields of the chosen type and the preview (upstream `UpdateCategoryVisibility` and `UpdatePreview`).
    private func refresh() {
        let isQR = spec.symbology == .qrCode
        choices.row(at: 1).isHidden = !isQR
        let shown: QRPayloadType = isQR ? spec.qrType : .text
        for (type, view) in panels { view.isHidden = type != shown }
        fieldsBox.title = isQR ? spec.qrType.fieldsTitle : "Text / Number Value"
        roundedBox.isHidden = !spec.symbology.hasRoundedDots

        guard !spec.payload.isEmpty else {
            show(nil, status: spec.requiredInputHint, isError: false)
            return
        }
        let size = Self.fitted(spec.defaultSize, in: Self.previewSize)
        let scale = panel.backingScaleFactor > 0 ? panel.backingScaleFactor : 2
        do {
            let image = try AnnotationRenderer.barcodeImage(spec, size: CGSize(width: size.width * scale, height: size.height * scale))
            show(NSImage(cgImage: image, size: size), status: "", isError: false)
        } catch {
            show(nil, status: error.localizedDescription, isError: true)
        }
    }

    private func show(_ preview: NSImage?, status: String, isError: Bool) {
        previewView.image = preview
        statusLabel.stringValue = status
        statusLabel.textColor = isError ? .systemRed : .secondaryLabelColor
        insertButton.isEnabled = preview != nil
    }

    /// `size` made as big as fits in `box`, keeping its aspect ratio.
    private static func fitted(_ size: CGSize, in box: CGSize) -> CGSize {
        guard size.width > 0, size.height > 0 else { return box }
        let factor = min(box.width / size.width, box.height / size.height)
        return CGSize(width: (size.width * factor).rounded(), height: (size.height * factor).rounded())
    }

    // MARK: Actions

    @objc private func controlChanged(_ sender: Any?) {
        read()
        refresh()
    }

    func controlTextDidChange(_ notification: Notification) {
        controlChanged(nil)
    }

    func textDidChange(_ notification: Notification) {
        controlChanged(nil)
    }

    /// Fills in the fields (for snapshots).
    func set(_ change: (inout BarcodeSpec) -> Void) {
        change(&spec)
        load()
        refresh()
    }

    @objc private func insert(_ sender: Any?) {
        read()
        guard (try? spec.matrix()) != nil else { return }
        onApply?(spec)
        close()
    }

    @objc private func cancel(_ sender: Any?) {
        close()
    }

    private func close() {
        if let parent = panel.sheetParent {
            parent.endSheet(panel)
        } else {
            panel.orderOut(nil)
            keepAlive = nil
        }
    }
}
