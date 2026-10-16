// Greenshot for Mac (Community) - an unofficial macOS port of Greenshot
// Copyright (C) 2026 Greenshot for Mac (Community) contributors
// Based on Greenshot, Copyright (C) 2007-2026 Thomas Braun, Jens Klingen, Robin Krom
// SPDX-License-Identifier: GPL-3.0-or-later

import AppKit
import GreenshotCore

/// The print options asked before printing: port of upstream `Greenshot/Views/PrintOptionsWindow.xaml`.
@MainActor
enum PrintOptionsDialog {
    /// Shows the options; OK saves them in the settings (and "Don't ask again" turns the dialog off). False when
    /// cancelled.
    static func run(settings: SettingsStore, window: NSWindow? = nil) -> Bool {
        let options = settings.value.printing
        let form = PrintOptionsForm(options: options)
        let alert = NSAlert()
        alert.messageText = "Print Options"
        alert.informativeText = "These can be changed later in Settings › Printer."
        alert.accessoryView = form.view
        alert.showsSuppressionButton = true
        alert.suppressionButton?.title = "Don't ask again"
        alert.addButton(withTitle: "Print")
        alert.addButton(withTitle: "Cancel")
        NSApp.activate()
        guard alert.runModal() == .alertFirstButtonReturn else { return false }
        let dontAsk = alert.suppressionButton?.state == .on
        settings.update {
            $0.printing = form.result(from: $0.printing)
            if dontAsk { $0.printing.promptOptions = false }
        }
        return true
    }
}

/// The checkboxes and radio buttons of the print options, also used for the snapshot.
@MainActor
final class PrintOptionsForm: NSObject {
    let view: NSView
    private let inverted = NSButton(checkboxWithTitle: "Inverted colours", target: nil, action: nil)
    private let color = NSButton(radioButtonWithTitle: "Colour", target: nil, action: nil)
    private let grayscale = NSButton(radioButtonWithTitle: "Grayscale", target: nil, action: nil)
    private let monochrome = NSButton(radioButtonWithTitle: "Black and white (monochrome)", target: nil, action: nil)
    private let footer = NSButton(checkboxWithTitle: "Print date / time and title at the bottom of the page", target: nil, action: nil)
    private let shrink = NSButton(checkboxWithTitle: "Shrink to fit the paper", target: nil, action: nil)
    private let enlarge = NSButton(checkboxWithTitle: "Enlarge to fit the paper", target: nil, action: nil)
    private let rotate = NSButton(checkboxWithTitle: "Rotate to the page orientation", target: nil, action: nil)
    private let center = NSButton(checkboxWithTitle: "Center on the page", target: nil, action: nil)

    init(options: PrintSettings) {
        func heading(_ text: String) -> NSTextField {
            let label = NSTextField(labelWithString: text)
            label.font = .boldSystemFont(ofSize: NSFont.systemFontSize)
            return label
        }
        let radios = NSStackView(views: [color, grayscale, monochrome])
        radios.orientation = .vertical
        radios.alignment = .leading
        radios.spacing = 4
        let stack = NSStackView(views: [heading("Colours"), radios, inverted, heading("Layout"), shrink, enlarge, rotate, center, footer])
        stack.orientation = .vertical
        stack.alignment = .leading
        stack.spacing = 6
        stack.setCustomSpacing(12, after: inverted)
        stack.frame = NSRect(origin: .zero, size: stack.fittingSize)
        view = stack
        super.init()
        // Radio buttons with the same superview and action form a group.
        for radio in [color, grayscale, monochrome] {
            radio.target = self
            radio.action = #selector(colorModeChanged(_:))
        }
        inverted.state = options.inverted ? .on : .off
        (options.monochrome ? monochrome : options.grayscale ? grayscale : color).state = .on
        footer.state = options.footer ? .on : .off
        shrink.state = options.allowShrink ? .on : .off
        enlarge.state = options.allowEnlarge ? .on : .off
        rotate.state = options.allowRotate ? .on : .off
        center.state = options.center ? .on : .off
        objc_setAssociatedObject(view, "PrintOptionsForm", self, .OBJC_ASSOCIATION_RETAIN)
    }

    @objc private func colorModeChanged(_ sender: NSButton) {}

    func result(from options: PrintSettings) -> PrintSettings {
        var result = options
        result.inverted = inverted.state == .on
        result.grayscale = grayscale.state == .on
        result.monochrome = monochrome.state == .on
        result.footer = footer.state == .on
        result.allowShrink = shrink.state == .on
        result.allowEnlarge = enlarge.state == .on
        result.allowRotate = rotate.state == .on
        result.center = center.state == .on
        return result
    }
}
