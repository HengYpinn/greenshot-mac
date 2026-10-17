// Greenshot for Mac (Community) - an unofficial macOS port of Greenshot
// Copyright (C) 2026 Greenshot for Mac (Community) contributors
// Based on Greenshot, Copyright (C) 2007-2026 Thomas Braun, Jens Klingen, Robin Krom
// SPDX-License-Identifier: GPL-3.0-or-later

import AppKit
import GreenshotCore

/// The quality dialog before a save: port of upstream `Greenshot.Base/Wpf/Views/QualityWindow.cs`. "Reduce colours",
/// the JPEG quality (only for JPEG) and "Save as default quality and do not ask again".
@MainActor
final class QualityForm: NSObject {
    let view: NSView
    private let slider: NSSlider
    private let valueLabel = NSTextField(labelWithString: "")
    private let reduceColorsBox: NSButton
    private let dontAskAgainBox = NSButton(checkboxWithTitle: "Save as default quality and do not ask again", target: nil, action: nil)

    init(format: ImageFormat, quality: Int, reduceColors: Bool, reduceColorsTo: Int) {
        slider = NSSlider(value: Double(min(max(quality, 1), 100)), minValue: 1, maxValue: 100, target: nil, action: nil)
        reduceColorsBox = NSButton(checkboxWithTitle: "Reduce the amount of colours to a maximum of \(reduceColorsTo)",
                                   target: nil, action: nil)
        let qualityLabel = NSTextField(labelWithString: "JPEG quality (higher quality makes bigger files):")
        let row = NSStackView(views: [slider, valueLabel])
        let stack = NSStackView(views: [reduceColorsBox, qualityLabel, row, dontAskAgainBox])
        view = stack
        super.init()
        slider.numberOfTickMarks = 11
        slider.allowsTickMarkValuesOnly = false
        slider.target = self
        slider.action = #selector(qualityChanged)
        slider.widthAnchor.constraint(equalToConstant: 260).isActive = true
        valueLabel.font = .monospacedDigitSystemFont(ofSize: NSFont.systemFontSize, weight: .regular)
        valueLabel.widthAnchor.constraint(equalToConstant: 32).isActive = true
        valueLabel.alignment = .right
        reduceColorsBox.state = reduceColors ? .on : .off
        // Each control only where it changes the file (upstream greys the quality out for other formats than JPEG).
        let usesQuality = DestinationSupport.usesQuality(format)
        slider.isEnabled = usesQuality
        qualityLabel.textColor = usesQuality ? .labelColor : .disabledControlTextColor
        valueLabel.textColor = qualityLabel.textColor
        reduceColorsBox.isEnabled = DestinationSupport.reducesColors(format)
        stack.orientation = .vertical
        stack.alignment = .leading
        stack.spacing = 8
        stack.setCustomSpacing(14, after: row)
        qualityChanged()
        stack.frame = NSRect(origin: .zero, size: stack.fittingSize)
    }

    var quality: Int { Int(slider.doubleValue.rounded()) }
    var reduceColors: Bool { reduceColorsBox.state == .on }
    var dontAskAgain: Bool { dontAskAgainBox.state == .on }

    @objc private func qualityChanged() {
        valueLabel.stringValue = "\(quality)"
    }

    /// Asks for the quality of this save. Nil when cancelled (upstream: the user doesn't want to save). "Don't ask
    /// again" makes the choices the settings and turns the dialog off.
    static func ask(format: ImageFormat, settings: SettingsStore) -> (quality: Int, reduceColors: Bool)? {
        let s = settings.value
        let form = QualityForm(format: format, quality: s.jpegQuality, reduceColors: s.reduceColors, reduceColorsTo: s.reduceColorsTo)
        let alert = NSAlert()
        alert.messageText = "Image Quality"
        alert.informativeText = "Saving as \(format.displayName)."
        alert.accessoryView = form.view
        alert.addButton(withTitle: "Save")
        alert.addButton(withTitle: "Cancel")
        NSApp.activate()
        let response = alert.runModal()
        guard response == .alertFirstButtonReturn else { return nil }
        let choice = (quality: form.quality, reduceColors: form.reduceColors)
        if form.dontAskAgain {
            settings.update { $0.rememberQualityChoice(jpegQuality: choice.quality, reduceColors: choice.reduceColors) }
        }
        return choice
    }
}
