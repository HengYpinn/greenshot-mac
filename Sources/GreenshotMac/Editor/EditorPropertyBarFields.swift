// Greenshot for Mac (Community) - an unofficial macOS port of Greenshot
// Copyright (C) 2026 Greenshot for Mac (Community) contributors
// Based on Greenshot, Copyright (C) 2007-2026 Thomas Braun, Jens Klingen, Robin Krom
// SPDX-License-Identifier: GPL-3.0-or-later

import AppKit

/// A whole number with a stepper beside it, for the property bar (upstream's `NumericUpDown` fields: line thickness,
/// font size, pixel size, blur radius, brightness). A typed value is clamped to the range; Return or leaving the field
/// applies it.
@MainActor
final class PropertyNumberField: NSObject {
    let field = NSTextField()
    let stepper = NSStepper()
    private let range: ClosedRange<Double>
    /// The value shown last, so leaving the field unchanged applies nothing (no empty undo step).
    private var shown: Double?
    /// The new value, after the user changed it.
    var onChange: ((Double) -> Void)?
    /// After Return in the field: give the keyboard back (to the canvas).
    var onCommit: (() -> Void)?

    init(range: ClosedRange<Double>, step: Double = 1, width: CGFloat = 40, tooltip: String) {
        self.range = range
        super.init()
        let formatter = NumberFormatter()
        formatter.allowsFloats = false
        field.formatter = formatter
        field.controlSize = .small
        field.font = .monospacedDigitSystemFont(ofSize: NSFont.smallSystemFontSize, weight: .regular)
        field.alignment = .right
        field.toolTip = tooltip
        field.widthAnchor.constraint(equalToConstant: width).isActive = true
        field.cell?.sendsActionOnEndEditing = true
        field.target = self
        field.action = #selector(fieldChanged)
        stepper.minValue = range.lowerBound
        stepper.maxValue = range.upperBound
        stepper.increment = step
        stepper.valueWraps = false
        stepper.controlSize = .small
        stepper.toolTip = tooltip
        stepper.target = self
        stepper.action = #selector(stepperChanged)
    }

    var views: [NSView] { [field, stepper] }

    /// Shows a value without reporting it; a field the user is typing in is left alone.
    func show(_ value: Double) {
        let clamped = clamp(value)
        if field.currentEditor() == nil { field.doubleValue = clamped.rounded() }
        stepper.doubleValue = clamped
        shown = clamped
    }

    private func clamp(_ value: Double) -> Double {
        min(max(value.isFinite ? value : range.lowerBound, range.lowerBound), range.upperBound)
    }

    @objc private func fieldChanged() {
        let value = clamp(field.doubleValue.rounded())
        field.doubleValue = value
        stepper.doubleValue = value
        if value != shown {
            shown = value
            onChange?(value)
        }
        if NSApp.currentEvent?.type == .keyDown { onCommit?() }
    }

    @objc private func stepperChanged() {
        let value = clamp(stepper.doubleValue)
        field.doubleValue = value
        shown = value
        onChange?(value)
    }
}
