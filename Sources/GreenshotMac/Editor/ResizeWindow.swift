// Greenshot for Mac (Community) - an unofficial macOS port of Greenshot
// Copyright (C) 2026 Greenshot for Mac (Community) contributors
// Based on Greenshot, Copyright (C) 2007-2026 Thomas Braun, Jens Klingen, Robin Krom
// SPDX-License-Identifier: GPL-3.0-or-later

import AppKit
import GreenshotCore

/// The Resize dialog (upstream `Greenshot.Editor/Views/ResizeSettingsWindow.xaml(.cs)`): width and height in pixels
/// or percent of the current size, keeping the aspect ratio by default.
@MainActor
final class ResizeForm: NSObject, NSTextFieldDelegate {
    private enum Unit: Int { case pixels, percent }

    private let original: CGSize
    private(set) var width: Double
    private(set) var height: Double
    private let widthField = NSTextField()
    private let heightField = NSTextField()
    private let widthUnit = NSPopUpButton()
    private let heightUnit = NSPopUpButton()
    private let keepAspectRatio = NSButton(checkboxWithTitle: String(localized: "Keep aspect ratio"), target: nil, action: nil)
    private(set) var view = NSView()

    /// `size` is the image's current size in pixels.
    init(size: CGSize) {
        original = size
        width = Double(size.width)
        height = Double(size.height)
        super.init()
        for (field, popup) in [(widthField, widthUnit), (heightField, heightUnit)] {
            field.delegate = self
            field.alignment = .right
            field.widthAnchor.constraint(equalToConstant: 80).isActive = true
            popup.addItems(withTitles: [String(localized: "pixels", comment: "Unit of the new width or height"),
                                        String(localized: "percent", comment: "Unit of the new width or height")])
            popup.target = self
            popup.action = #selector(unitChanged(_:))
        }
        keepAspectRatio.state = .on
        keepAspectRatio.target = self
        keepAspectRatio.action = #selector(aspectChanged(_:))
        display(widthField)
        display(heightField)
        // Pixel sizes as plain digits (an interpolated Int would be grouped: "2,560").
        let currentWidth = String(Int(size.width))
        let currentHeight = String(Int(size.height))
        let current = EffectSettingsDialog.label(String(localized: "Now \(currentWidth) × \(currentHeight) pixels"))
        current.textColor = .secondaryLabelColor
        view = EffectSettingsDialog.form([
            [EffectSettingsDialog.label(String(localized: "Width:")), NSStackView(views: [widthField, widthUnit])],
            [EffectSettingsDialog.label(String(localized: "Height:")), NSStackView(views: [heightField, heightUnit])],
            [NSGridCell.emptyContentView, keepAspectRatio],
            [NSGridCell.emptyContentView, current],
        ])
    }

    /// The new size in pixels, nil when it is not a usable size.
    var size: CGSize? {
        let size = CGSize(width: width.rounded(), height: height.rounded())
        guard size.width >= 1, size.height >= 1, size.width <= 32768, size.height <= 32768 else { return nil }
        return size
    }

    /// The first responder of the dialog.
    var initialField: NSView { widthField }

    // MARK: Editing

    func controlTextDidChange(_ notification: Notification) {
        guard let field = notification.object as? NSTextField else { return }
        let typed = Double(field.stringValue.replacingOccurrences(of: ",", with: ".")
                            .trimmingCharacters(in: .whitespaces)) ?? 0
        let isWidth = field === widthField
        let unit = Unit(rawValue: (isWidth ? widthUnit : heightUnit).indexOfSelectedItem) ?? .pixels
        let base = Double(isWidth ? original.width : original.height)
        let pixels = unit == .percent ? base * typed / 100 : typed
        if isWidth { width = pixels } else { height = pixels }
        guard keepAspectRatio.state == .on, original.width > 0, original.height > 0 else { return }
        if isWidth {
            height = width * Double(original.height / original.width)
            display(heightField)
        } else {
            width = height * Double(original.width / original.height)
            display(widthField)
        }
    }

    @objc private func unitChanged(_ sender: NSPopUpButton) {
        display(sender === widthUnit ? widthField : heightField)
    }

    @objc private func aspectChanged(_ sender: NSButton) {
        guard sender.state == .on, original.width > 0 else { return }
        height = width * Double(original.height / original.width)
        display(heightField)
    }

    private func display(_ field: NSTextField) {
        let isWidth = field === widthField
        let unit = Unit(rawValue: (isWidth ? widthUnit : heightUnit).indexOfSelectedItem) ?? .pixels
        let pixels = isWidth ? width : height
        switch unit {
        case .pixels:
            field.stringValue = String(Int(pixels.rounded()))
        case .percent:
            let base = Double(isWidth ? original.width : original.height)
            field.stringValue = Self.format(percent: base > 0 ? pixels / base * 100 : 100)
        }
    }

    /// A percentage with at most one decimal.
    static func format(percent: Double) -> String {
        let tenths: Double = (percent * 10).rounded() / 10
        return tenths == tenths.rounded() ? String(Int(tenths)) : String(tenths)
    }
}
