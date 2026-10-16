// Greenshot for Mac (Community) - an unofficial macOS port of Greenshot
// Copyright (C) 2026 Greenshot for Mac (Community) contributors
// Based on Greenshot, Copyright (C) 2007-2026 Thomas Braun, Jens Klingen, Robin Krom
// SPDX-License-Identifier: GPL-3.0-or-later

import AppKit
import GreenshotCore

/// The settings dialogs of the effects: upstream `Greenshot.Editor/Views/DropShadowSettingsWindow.xaml(.cs)` and
/// `TornEdgeSettingsWindow.xaml(.cs)`. They are sheets on the editor window with OK and Cancel.
@MainActor
enum EffectSettingsDialog {
    /// Shows `content` in a sheet on `window` (a modal alert without one); `onOK` runs when OK is clicked.
    /// `owner` (the object behind the controls) is kept alive while the sheet is open.
    static func run(title: String, message: String, content: NSView, owner: AnyObject, okTitle: String = "OK",
                    for window: NSWindow?, onOK: @escaping () -> Void) {
        let alert = NSAlert()
        alert.messageText = title
        alert.informativeText = message
        alert.addButton(withTitle: okTitle)
        alert.addButton(withTitle: "Cancel")
        content.layoutSubtreeIfNeeded()
        content.frame.size = content.fittingSize
        alert.accessoryView = content
        let finish: (NSApplication.ModalResponse) -> Void = { response in
            withExtendedLifetime(owner) {
                if response == .alertFirstButtonReturn { onOK() }
            }
        }
        if let window {
            alert.beginSheetModal(for: window, completionHandler: finish)
        } else {
            finish(alert.runModal())
        }
    }

    /// A grid of label / control rows, labels right aligned like a macOS form.
    static func form(_ rows: [[NSView]]) -> NSGridView {
        let grid = NSGridView(views: rows)
        grid.rowSpacing = 8
        grid.columnSpacing = 8
        grid.column(at: 0).xPlacement = .trailing
        grid.rowAlignment = .firstBaseline
        return grid
    }

    static func label(_ text: String) -> NSTextField {
        NSTextField(labelWithString: text)
    }
}

/// A slider with its value shown next to it (upstream's sliders with a "{0:0} px" text).
@MainActor
final class SliderField: NSObject {
    let slider: NSSlider
    let valueLabel = NSTextField(labelWithString: "")
    private let format: (Int) -> String
    /// Called after the user moved the slider.
    var onChange: (() -> Void)?

    init(range: ClosedRange<Int>, value: Int, width: CGFloat = 200, format: @escaping (Int) -> String = { "\($0) px" }) {
        slider = NSSlider(value: Double(min(max(value, range.lowerBound), range.upperBound)),
                          minValue: Double(range.lowerBound), maxValue: Double(range.upperBound), target: nil, action: nil)
        self.format = format
        super.init()
        slider.target = self
        slider.action = #selector(changed(_:))
        slider.widthAnchor.constraint(equalToConstant: width).isActive = true
        valueLabel.font = .monospacedDigitSystemFont(ofSize: NSFont.systemFontSize, weight: .regular)
        valueLabel.widthAnchor.constraint(greaterThanOrEqualToConstant: 48).isActive = true
        update()
    }

    var value: Int {
        get { Int(slider.doubleValue.rounded()) }
        set {
            slider.doubleValue = Double(newValue)
            update()
        }
    }

    var isEnabled: Bool {
        get { slider.isEnabled }
        set { slider.isEnabled = newValue }
    }

    /// The row of a form: the label, the slider and its value.
    func row(_ title: String) -> [NSView] {
        [EffectSettingsDialog.label(title), NSStackView(views: [slider, valueLabel])]
    }

    @objc private func changed(_ sender: Any?) {
        update()
        onChange?()
    }

    private func update() {
        valueLabel.stringValue = format(value)
    }
}

/// Upstream `DropShadowSettingsWindow`: thickness 1...20, offset -20...20, darkness as 1...40 (0.025...1).
@MainActor
final class DropShadowSettingsForm: NSObject {
    let thickness: SliderField
    let offsetX: SliderField
    let offsetY: SliderField
    let darkness: SliderField
    private(set) var view = NSView()

    init(_ settings: DropShadowSettings) {
        thickness = SliderField(range: 1...20, value: settings.size)
        offsetX = SliderField(range: -20...20, value: settings.offsetX)
        offsetY = SliderField(range: -20...20, value: settings.offsetY)
        darkness = SliderField(range: 1...40, value: Self.sliderValue(darkness: settings.darkness), format: { "\($0)" })
        super.init()
        view = EffectSettingsDialog.form([
            thickness.row("Thickness:"),
            offsetX.row("Offset X:"),
            offsetY.row("Offset Y:"),
            darkness.row("Darkness:"),
        ])
    }

    /// Upstream `ShowSettings`: darkness * 40, kept to 1...40.
    static func sliderValue(darkness: Double) -> Int {
        let steps: Double = darkness * 40
        return min(max(Int(steps), 1), 40)
    }

    var settings: DropShadowSettings {
        DropShadowSettings(darkness: Double(darkness.value) / 40, size: thickness.value,
                           offsetX: offsetX.value, offsetY: offsetY.value)
    }
}

/// Upstream `TornEdgeSettingsWindow`: the edges to tear (with "All"), the tooth size and ranges 0...40, the
/// background color, and the shadow with its thickness, offset and darkness like the drop shadow dialog.
@MainActor
final class TornEdgeSettingsForm: NSObject {
    let toothHeight: SliderField
    let horizontalRange: SliderField
    let verticalRange: SliderField
    let shadowThickness: SliderField
    let shadowOffsetX: SliderField
    let shadowOffsetY: SliderField
    let shadowDarkness: SliderField
    let backgroundColorWell = NSColorWell(style: .minimal)
    private let top = NSButton(checkboxWithTitle: "Top", target: nil, action: nil)
    private let left = NSButton(checkboxWithTitle: "Left", target: nil, action: nil)
    private let right = NSButton(checkboxWithTitle: "Right", target: nil, action: nil)
    private let bottom = NSButton(checkboxWithTitle: "Bottom", target: nil, action: nil)
    private let all = NSButton(checkboxWithTitle: "All", target: nil, action: nil)
    private let shadow = NSButton(checkboxWithTitle: "With shadow", target: nil, action: nil)
    private(set) var view = NSView()

    init(_ settings: TornEdgeSettings) {
        toothHeight = SliderField(range: 0...40, value: settings.toothHeight)
        horizontalRange = SliderField(range: 0...40, value: settings.horizontalToothRange)
        verticalRange = SliderField(range: 0...40, value: settings.verticalToothRange)
        shadowThickness = SliderField(range: 1...20, value: settings.shadowSize)
        shadowOffsetX = SliderField(range: -20...20, value: settings.shadowOffsetX)
        shadowOffsetY = SliderField(range: -20...20, value: settings.shadowOffsetY)
        shadowDarkness = SliderField(range: 1...40, value: DropShadowSettingsForm.sliderValue(darkness: settings.shadowDarkness),
                                     format: { "\($0)" })
        super.init()
        for (box, on) in [(top, settings.top), (left, settings.left), (right, settings.right), (bottom, settings.bottom)] {
            box.state = on ? .on : .off
            box.target = self
            box.action = #selector(edgeChanged(_:))
        }
        all.target = self
        all.action = #selector(allChanged(_:))
        all.allowsMixedState = false
        shadow.state = settings.shadow ? .on : .off
        shadow.target = self
        shadow.action = #selector(shadowChanged(_:))
        backgroundColorWell.color = NSColor(cgColor: settings.backgroundColor.cgColor) ?? .clear
        backgroundColorWell.toolTip = "The color of the torn off parts; transparent by default"
        // The color panel doesn't offer transparency: a button brings it back, like "No fill" in the property bar.
        let transparent = NSButton(title: "Transparent", target: self, action: #selector(clearBackground(_:)))
        transparent.bezelStyle = .rounded
        transparent.controlSize = .small
        let background = NSStackView(views: [backgroundColorWell, transparent])
        background.spacing = 6
        refreshAll()
        refreshShadow()

        // Upstream lays the edges out around "All": top above, left and right beside, bottom below.
        let edges = NSGridView(views: [[NSGridCell.emptyContentView, top, NSGridCell.emptyContentView],
                                       [left, all, right],
                                       [NSGridCell.emptyContentView, bottom, NSGridCell.emptyContentView]])
        edges.rowSpacing = 4
        edges.columnSpacing = 12
        for column in 0..<3 { edges.column(at: column).xPlacement = .center }
        view = EffectSettingsDialog.form([
            [EffectSettingsDialog.label("Edges:"), edges],
            toothHeight.row("Tooth size:"),
            horizontalRange.row("Horizontal range:"),
            verticalRange.row("Vertical range:"),
            [EffectSettingsDialog.label("Background:"), background],
            [EffectSettingsDialog.label("Shadow:"), shadow],
            shadowThickness.row("Thickness:"),
            shadowOffsetX.row("Offset X:"),
            shadowOffsetY.row("Offset Y:"),
            shadowDarkness.row("Darkness:"),
        ])
    }

    var settings: TornEdgeSettings {
        TornEdgeSettings(toothHeight: toothHeight.value, horizontalToothRange: horizontalRange.value,
                         verticalToothRange: verticalRange.value,
                         top: top.state == .on, left: left.state == .on, right: right.state == .on,
                         bottom: bottom.state == .on, shadow: shadow.state == .on,
                         shadowDarkness: Double(shadowDarkness.value) / 40, shadowSize: shadowThickness.value,
                         shadowOffsetX: shadowOffsetX.value, shadowOffsetY: shadowOffsetY.value,
                         backgroundColor: RGBAColor(backgroundColorWell.color))
    }

    @objc private func edgeChanged(_ sender: NSButton) {
        refreshAll()
    }

    @objc private func allChanged(_ sender: NSButton) {
        for box in [top, left, right, bottom] { box.state = sender.state == .on ? .on : .off }
    }

    @objc private func shadowChanged(_ sender: NSButton) {
        refreshShadow()
    }

    @objc private func clearBackground(_ sender: Any?) {
        backgroundColorWell.color = .clear
    }

    private func refreshAll() {
        all.state = [top, left, right, bottom].allSatisfy { $0.state == .on } ? .on : .off
    }

    /// The shadow's sliders only work while there is a shadow (upstream binds the group to the checkbox).
    private func refreshShadow() {
        let on = shadow.state == .on
        for field in [shadowThickness, shadowOffsetX, shadowOffsetY, shadowDarkness] { field.isEnabled = on }
    }
}

extension RGBAColor {
    /// The color of a color well, in sRGB.
    init(_ color: NSColor) {
        let c = color.usingColorSpace(.sRGB) ?? color
        self.init(red: Double(c.redComponent), green: Double(c.greenComponent), blue: Double(c.blueComponent),
                  alpha: Double(c.alphaComponent))
    }
}

/// Brightness, contrast and gamma of upstream `AdjustEffect` (which has no dialog upstream). Percent sliders,
/// 100 % changes nothing; not kept in the settings.
@MainActor
final class AdjustSettingsForm: NSObject {
    let brightness = SliderField(range: 0...200, value: 100, format: { "\($0) %" })
    let contrast = SliderField(range: 0...200, value: 100, format: { "\($0) %" })
    let gamma = SliderField(range: 10...500, value: 100, format: { String(format: "%.2f", Double($0) / 100) })
    private(set) var view = NSView()

    override init() {
        super.init()
        view = EffectSettingsDialog.form([
            brightness.row("Brightness:"),
            contrast.row("Contrast:"),
            gamma.row("Gamma:"),
        ])
    }

    var isNeutral: Bool { brightness.value == 100 && contrast.value == 100 && gamma.value == 100 }

    func apply(to image: CGImage) -> CGImage? {
        ImageEffects.adjust(image, brightness: Double(brightness.value) / 100, contrast: Double(contrast.value) / 100,
                            gamma: Double(gamma.value) / 100)
    }
}
