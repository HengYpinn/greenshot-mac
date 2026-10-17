// Greenshot for Mac (Community) - an unofficial macOS port of Greenshot
// Copyright (C) 2026 Greenshot for Mac (Community) contributors
// Based on Greenshot, Copyright (C) 2007-2026 Thomas Braun, Jens Klingen, Robin Krom
// SPDX-License-Identifier: GPL-3.0-or-later

import AppKit
import GreenshotCore

/// The Obfuscate Text dialog (upstream `Greenshot.Editor/Views/TextObfuscationWindow.xaml(.cs)`,
/// `TEXT_OBFUSCATION_FEATURE.md`): finds text with the Vision text recognition and covers every matching word or
/// line with a pixelate, blur, highlight or magnify element. A sheet on the editor window.
///
/// Like upstream, the text is recognized when the dialog opens, the matches are searched again 300 ms after every
/// change (or at once with Search), their number is shown ("Matches found: N") and the elements are previewed on the
/// image (`onPreview`) until Apply adds them as one step or Cancel takes them away. Unlike upstream, which needs three
/// characters, an empty search matches all text.
@MainActor
final class TextObfuscationSheet: NSObject, NSTextFieldDelegate {
    private let image: CGImage
    private let language: String
    /// Saves the options when Apply is clicked.
    var onSaveSettings: ((TextObfuscationSettings) -> Void)?
    /// Adds the elements for the matched boxes (image pixels) with the options of the dialog.
    var onApply: (([CGRect], TextObfuscationSettings) -> Void)?
    /// Shows these elements on the image as a preview (upstream `ShowPreview`); an empty list takes the preview away.
    var onPreview: (([Annotation]) -> Void)?

    private let panel: NSPanel
    private let searchField = NSTextField()
    private let regexBox = NSButton(checkboxWithTitle: "Regular expression", target: nil, action: nil)
    private let caseBox = NSButton(checkboxWithTitle: "Case sensitive", target: nil, action: nil)
    private let scopePopup = NSPopUpButton()
    private let effectPopup = NSPopUpButton()
    private let pixelSize: SliderField
    private let blurRadius: SliderField
    private let magnification: SliderField
    private let highlightColorWell = NSColorWell(style: .minimal)
    private var options = NSGridView()
    private let advancedButton = NSButton()
    private var advancedView = NSView()
    private let paddingHorizontal: SliderField
    private let paddingVertical: SliderField
    private let offsetX: SliderField
    private let offsetY: SliderField
    private let statusLabel = NSTextField(wrappingLabelWithString: "")
    private let matchLabel = NSTextField(labelWithString: "")
    private let searchButton = NSButton(title: "Search", target: nil, action: nil)
    private var debounce: Timer?
    /// Apply was clicked while the text was still being recognized.
    private var applyWhenRecognized = false
    private let spinner = NSProgressIndicator()
    private let applyButton = NSButton(title: "Apply", target: nil, action: nil)
    private let cancelButton = NSButton(title: "Cancel", target: nil, action: nil)
    private var lines: [RecognizedLine]?
    private var recognition: Task<Void, Never>?
    /// The sheet keeps itself alive while it is open.
    private var keepAlive: TextObfuscationSheet?

    private static let scopes: [(TextObfuscationSettings.Scope, String)] = [(.words, "Words"), (.lines, "Lines")]
    private static let effects: [(TextObfuscationSettings.Effect, String)] = [
        (.pixelate, "Pixelate"), (.blur, "Blur"), (.highlight, "Highlight"), (.magnify, "Magnify"),
    ]

    /// `lines` are text lines already recognized (for snapshots); without them the dialog recognizes the text itself.
    init(image: CGImage, settings: TextObfuscationSettings, language: String, lines: [RecognizedLine]? = nil) {
        self.image = image
        self.language = language
        self.lines = lines
        pixelSize = SliderField(range: 2...50, value: settings.pixelSize, width: 160)
        blurRadius = SliderField(range: 1...30, value: settings.blurRadius, width: 160)
        magnification = SliderField(range: 1...10, value: settings.magnification, width: 160, format: { "\($0)×" })
        paddingHorizontal = SliderField(range: -50...100, value: settings.paddingHorizontal, width: 160, format: { "\($0) %" })
        paddingVertical = SliderField(range: -50...100, value: settings.paddingVertical, width: 160, format: { "\($0) %" })
        offsetX = SliderField(range: -100...100, value: settings.offsetX, width: 160)
        offsetY = SliderField(range: -100...100, value: settings.offsetY, width: 160)
        panel = NSPanel(contentRect: NSRect(x: 0, y: 0, width: 420, height: 300), styleMask: [.titled, .docModalWindow],
                        backing: .buffered, defer: true)
        super.init()
        searchField.stringValue = settings.searchPattern
        searchField.placeholderString = "Empty: all text"
        searchField.widthAnchor.constraint(equalToConstant: 240).isActive = true
        regexBox.state = settings.useRegex ? .on : .off
        caseBox.state = settings.caseSensitive ? .on : .off
        scopePopup.addItems(withTitles: Self.scopes.map(\.1))
        scopePopup.selectItem(at: Self.scopes.firstIndex { $0.0 == settings.scope } ?? 0)
        effectPopup.addItems(withTitles: Self.effects.map(\.1))
        effectPopup.selectItem(at: Self.effects.firstIndex { $0.0 == settings.effect } ?? 0)
        effectPopup.target = self
        effectPopup.action = #selector(effectChanged(_:))
        highlightColorWell.color = NSColor(cgColor: settings.highlightColor.cgColor) ?? .yellow
        buildLayout()
        refreshEffectRows()
        wireLiveSearch()
    }

    /// Shows the dialog as a sheet on `window` and starts recognizing the text, then previews the matches.
    func begin(for window: NSWindow) {
        keepAlive = self
        window.beginSheet(panel) { [weak self] _ in
            self?.recognition?.cancel()
            self?.debounce?.invalidate()
            self?.keepAlive = nil
        }
        panel.makeFirstResponder(searchField)
        if lines == nil { recognize() } else { searchNow() }
    }

    /// The dialog's content, for offscreen snapshots.
    var contentView: NSView? { panel.contentView }

    /// Opens the Advanced options (for snapshots).
    func showAdvanced() {
        advancedButton.state = .on
        advancedView.isHidden = false
    }

    /// The options as they are set in the dialog.
    var settings: TextObfuscationSettings {
        var settings = TextObfuscationSettings()
        settings.searchPattern = searchField.stringValue
        settings.useRegex = regexBox.state == .on
        settings.caseSensitive = caseBox.state == .on
        settings.scope = Self.scopes[max(scopePopup.indexOfSelectedItem, 0)].0
        settings.effect = Self.effects[max(effectPopup.indexOfSelectedItem, 0)].0
        settings.paddingHorizontal = paddingHorizontal.value
        settings.paddingVertical = paddingVertical.value
        settings.offsetX = offsetX.value
        settings.offsetY = offsetY.value
        settings.pixelSize = pixelSize.value
        settings.blurRadius = blurRadius.value
        settings.magnification = magnification.value
        settings.highlightColor = RGBAColor(highlightColorWell.color)
        return settings
    }

    /// The effect chosen in the dialog.
    var effect: TextObfuscationSettings.Effect {
        Self.effects[max(effectPopup.indexOfSelectedItem, 0)].0
    }

    // MARK: Layout

    private func buildLayout() {
        panel.title = "Obfuscate Text"
        let title = NSTextField(labelWithString: "Obfuscate Text")
        title.font = .boldSystemFont(ofSize: NSFont.systemFontSize)
        let info = NSTextField(wrappingLabelWithString:
            "Finds text in the image and covers every match with an element you can still move or remove.")
        info.textColor = .secondaryLabelColor
        info.preferredMaxLayoutWidth = 380

        // Upstream shows the row of the chosen effect only (`UpdateEffectSettingsVisibility`).
        searchButton.bezelStyle = .rounded
        searchButton.target = self
        searchButton.action = #selector(search(_:))
        matchLabel.font = .boldSystemFont(ofSize: NSFont.systemFontSize)
        options = EffectSettingsDialog.form([
            [EffectSettingsDialog.label("Search for:"), NSStackView(views: [searchField, searchButton])],
            [NSGridCell.emptyContentView, NSStackView(views: [regexBox, caseBox])],
            [EffectSettingsDialog.label("Search in:"), scopePopup],
            [NSGridCell.emptyContentView, matchLabel],
            [EffectSettingsDialog.label("Effect:"), effectPopup],
            pixelSize.row("Pixel size:"),
            blurRadius.row("Blur radius:"),
            [EffectSettingsDialog.label("Color:"), highlightColorWell],
            magnification.row("Magnification:"),
        ])

        advancedButton.bezelStyle = .disclosure
        advancedButton.setButtonType(.pushOnPushOff)
        advancedButton.title = ""
        advancedButton.state = .off
        advancedButton.target = self
        advancedButton.action = #selector(toggleAdvanced(_:))
        let advancedTitle = EffectSettingsDialog.label("Advanced")
        let advancedRow = NSStackView(views: [advancedButton, advancedTitle])
        advancedRow.spacing = 4
        advancedView = EffectSettingsDialog.form([
            paddingHorizontal.row("Horizontal padding:"),
            paddingVertical.row("Vertical padding:"),
            offsetX.row("Horizontal offset:"),
            offsetY.row("Vertical offset:"),
        ])
        advancedView.isHidden = true

        spinner.style = .spinning
        spinner.controlSize = .small
        spinner.isDisplayedWhenStopped = false
        statusLabel.preferredMaxLayoutWidth = 340
        statusLabel.textColor = .secondaryLabelColor
        let status = NSStackView(views: [spinner, statusLabel])
        status.spacing = 6

        applyButton.bezelStyle = .push
        applyButton.keyEquivalent = "\r"
        applyButton.target = self
        applyButton.action = #selector(apply(_:))
        cancelButton.bezelStyle = .push
        cancelButton.keyEquivalent = "\u{1b}"
        cancelButton.target = self
        cancelButton.action = #selector(cancel(_:))
        let spacer = NSView()
        spacer.setContentHuggingPriority(.init(1), for: .horizontal)
        let buttons = NSStackView(views: [spacer, cancelButton, applyButton])

        let stack = NSStackView(views: [title, info, options, advancedRow, advancedView, status, buttons])
        stack.orientation = .vertical
        stack.alignment = .leading
        stack.spacing = 12
        stack.edgeInsets = NSEdgeInsets(top: 20, left: 20, bottom: 20, right: 20)
        stack.translatesAutoresizingMaskIntoConstraints = false
        buttons.widthAnchor.constraint(equalTo: stack.widthAnchor, constant: -40).isActive = true
        let content = NSView()
        content.addSubview(stack)
        NSLayoutConstraint.activate([
            stack.leadingAnchor.constraint(equalTo: content.leadingAnchor),
            stack.trailingAnchor.constraint(equalTo: content.trailingAnchor),
            stack.topAnchor.constraint(equalTo: content.topAnchor),
            stack.bottomAnchor.constraint(equalTo: content.bottomAnchor),
            stack.widthAnchor.constraint(greaterThanOrEqualToConstant: 420),
        ])
        panel.contentView = content
    }

    @objc private func toggleAdvanced(_ sender: NSButton) {
        advancedView.isHidden = sender.state != .on
    }

    @objc private func effectChanged(_ sender: Any?) {
        refreshEffectRows()
        searchNow()
    }

    /// Shows the option of the chosen effect: pixel size, blur radius, highlight color or magnification.
    private func refreshEffectRows() {
        let effect = effect
        let rows: [(Int, TextObfuscationSettings.Effect)] = [(5, .pixelate), (6, .blur), (7, .highlight), (8, .magnify)]
        for (index, owner) in rows where index < options.numberOfRows {
            options.row(at: index).isHidden = owner != effect
        }
    }

    // MARK: Live search

    /// Every option searches again after a pause (upstream's 300 ms `DispatcherTimer`).
    private func wireLiveSearch() {
        searchField.delegate = self
        for box in [regexBox, caseBox] {
            box.target = self
            box.action = #selector(optionChanged(_:))
        }
        scopePopup.target = self
        scopePopup.action = #selector(optionChanged(_:))
        highlightColorWell.target = self
        highlightColorWell.action = #selector(optionChanged(_:))
        for field in [pixelSize, blurRadius, magnification, paddingHorizontal, paddingVertical, offsetX, offsetY] {
            field.onChange = { [weak self] in self?.scheduleSearch() }
        }
    }

    func controlTextDidChange(_ notification: Notification) {
        scheduleSearch()
    }

    @objc private func optionChanged(_ sender: Any?) {
        scheduleSearch()
    }

    @objc private func search(_ sender: Any?) {
        searchNow()
    }

    private func scheduleSearch() {
        debounce?.invalidate()
        debounce = Timer.scheduledTimer(withTimeInterval: 0.3, repeats: false) { [weak self] _ in
            MainActor.assumeIsolated { self?.searchNow() }
        }
    }

    /// Upstream `UpdatePreview`: searches the recognized text with the options as they are, shows the number of
    /// matches and previews the elements. Before the text is recognized it does nothing (the search runs then).
    func searchNow() {
        debounce?.invalidate()
        guard let lines else { return }
        let settings = settings
        do {
            let boxes = try TextObfuscation.matches(in: lines, settings: settings, within: bounds)
            matchLabel.stringValue = "Matches found: \(boxes.count)"
            matchLabel.textColor = .labelColor
            onPreview?(TextObfuscation.annotations(for: boxes, settings: settings))
        } catch {
            matchLabel.stringValue = error.localizedDescription
            matchLabel.textColor = .systemRed
            onPreview?([])
        }
    }

    private var bounds: CGRect { CGRect(x: 0, y: 0, width: image.width, height: image.height) }

    private func recognize() {
        setBusy(true)
        show("Recognizing text…")
        matchLabel.stringValue = ""
        let image = image
        let language = language
        recognition = Task { [weak self] in
            let result = await Task.detached(priority: .userInitiated) {
                Result { try TextRecognizer.recognizeLines(in: image, language: language) }
            }.value
            guard let self, !Task.isCancelled else { return }
            self.setBusy(false)
            switch result {
            case .success(let lines):
                self.lines = lines
                self.show(lines.isEmpty ? "No text found in the image." : "")
                self.searchNow()
                if self.applyWhenRecognized { self.apply(nil) }
            case .failure(let error):
                self.applyWhenRecognized = false
                self.show("The text could not be recognized: \(error.localizedDescription)")
            }
        }
    }

    // MARK: Actions

    @objc private func cancel(_ sender: Any?) {
        close()
    }

    /// Upstream `ApplyButton_Click`: the preview goes, the elements of the matches are added as one step.
    @objc private func apply(_ sender: Any?) {
        let settings = settings
        onSaveSettings?(settings)
        guard let lines else {
            // Still recognizing: apply as soon as the text is there.
            applyWhenRecognized = true
            applyButton.isEnabled = false
            return
        }
        applyWhenRecognized = false
        guard !lines.isEmpty else {
            show("No text found in the image.")
            return
        }
        do {
            let boxes = try TextObfuscation.matches(in: lines, settings: settings, within: bounds)
            guard !boxes.isEmpty else {
                show("No text matches “\(settings.searchPattern)”.")
                return
            }
            onPreview?([])
            onApply?(boxes, settings)
            close()
        } catch {
            show(error.localizedDescription)
        }
    }

    private func setBusy(_ busy: Bool) {
        applyButton.isEnabled = !busy
        if busy { spinner.startAnimation(nil) } else { spinner.stopAnimation(nil) }
    }

    private func show(_ message: String) {
        statusLabel.stringValue = message
    }

    private func close() {
        recognition?.cancel()
        debounce?.invalidate()
        onPreview?([])
        if let parent = panel.sheetParent {
            parent.endSheet(panel)
        } else {
            panel.orderOut(nil)
            keepAlive = nil
        }
    }
}
