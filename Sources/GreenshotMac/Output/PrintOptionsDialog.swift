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
        guard let answer = present(settings.value.printing, policy: settings.policy, forThisPrintOnly: false) else { return false }
        settings.update {
            $0.printing = answer.form.result(from: $0.printing)
            if answer.dontAsk { $0.printing.promptOptions = false }
        }
        return true
    }

    /// Asks the options of one print (a recipe's print options), starting from `options`; nothing is saved. Nil when
    /// cancelled. What `policy` locks can't be changed.
    static func ask(_ options: PrintSettings, policy: ManagedPolicy, window: NSWindow? = nil) -> PrintSettings? {
        present(options, policy: policy, forThisPrintOnly: true).map { $0.form.result(from: options) }
    }

    /// The options in an alert; the controls of what an administrator locked are greyed out with a lock, like in
    /// Settings › Printer (`.managed`).
    private static func present(_ options: PrintSettings, policy: ManagedPolicy,
                                forThisPrintOnly: Bool) -> (form: PrintOptionsForm, dontAsk: Bool)? {
        let form = PrintOptionsForm(options: options, policy: policy)
        let alert = NSAlert()
        alert.messageText = String(localized: "Print Options")
        alert.informativeText = forThisPrintOnly ? String(localized: "These are for this print only.")
                                                 : String(localized: "These can be changed later in Settings › Printer.")
        alert.accessoryView = form.view
        // "Don't ask again" changes the settings; a print with its own options doesn't, nor does a locked setting.
        alert.showsSuppressionButton = !forThisPrintOnly && !policy.isLocked(\AppSettings.printing.promptOptions)
        alert.suppressionButton?.title = String(localized: "Don't ask again")
        alert.addButton(withTitle: String(localized: "Print", comment: "Button: prints the screenshot"))
        alert.addButton(withTitle: String(localized: "Cancel"))
        NSApp.activate()
        guard alert.runModal() == .alertFirstButtonReturn else { return nil }
        return (form, alert.suppressionButton?.state == .on)
    }
}

/// The checkboxes and radio buttons of the print options, also used for the snapshot.
@MainActor
final class PrintOptionsForm: NSObject {
    let view: NSView
    private let inverted = NSButton(checkboxWithTitle: String(localized: "Inverted colours"), target: nil, action: nil)
    private let color = NSButton(radioButtonWithTitle: String(localized: "Colour", comment: "Print in colour"), target: nil, action: nil)
    private let grayscale = NSButton(radioButtonWithTitle: String(localized: "Grayscale"), target: nil, action: nil)
    private let monochrome = NSButton(radioButtonWithTitle: String(localized: "Black and white (monochrome)"), target: nil, action: nil)
    private let footer = NSButton(checkboxWithTitle: String(localized: "Print date / time and title at the bottom of the page"), target: nil, action: nil)
    private let shrink = NSButton(checkboxWithTitle: String(localized: "Shrink to fit the paper"), target: nil, action: nil)
    private let enlarge = NSButton(checkboxWithTitle: String(localized: "Enlarge to fit the paper"), target: nil, action: nil)
    private let rotate = NSButton(checkboxWithTitle: String(localized: "Rotate to the page orientation"), target: nil, action: nil)
    private let center = NSButton(checkboxWithTitle: String(localized: "Center on the page"), target: nil, action: nil)

    /// `policy`'s locked options are shown greyed out with a lock and keep their value.
    init(options: PrintSettings, policy: ManagedPolicy = ManagedPolicy()) {
        func heading(_ text: String) -> NSTextField {
            let label = NSTextField(labelWithString: text)
            label.font = .boldSystemFont(ofSize: NSFont.systemFontSize)
            return label
        }
        let radios = NSStackView(views: [color, grayscale, monochrome])
        radios.orientation = .vertical
        radios.alignment = .leading
        radios.spacing = 4
        let colours = heading(String(localized: "Colours"))
        let layout = heading(String(localized: "Layout", comment: "How the screenshot is placed on the page"))
        let colourLocked = policy.isLocked(\AppSettings.printing.grayscale) || policy.isLocked(\AppSettings.printing.monochrome)
        let rows: [NSView] = [
            colours, Self.row(radios, controls: [color, grayscale, monochrome], locked: colourLocked),
            Self.row(inverted, locked: policy.isLocked(\AppSettings.printing.inverted)), layout,
            Self.row(shrink, locked: policy.isLocked(\AppSettings.printing.allowShrink)),
            Self.row(enlarge, locked: policy.isLocked(\AppSettings.printing.allowEnlarge)),
            Self.row(rotate, locked: policy.isLocked(\AppSettings.printing.allowRotate)),
            Self.row(center, locked: policy.isLocked(\AppSettings.printing.center)),
            Self.row(footer, locked: policy.isLocked(\AppSettings.printing.footer)),
        ]
        let stack = NSStackView(views: rows)
        stack.orientation = .vertical
        stack.alignment = .leading
        stack.spacing = 6
        stack.setCustomSpacing(12, after: rows[2])
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

    /// `view` as it is, or locked: its controls disabled, a lock after it saying who set it.
    private static func row(_ view: NSView, controls: [NSButton]? = nil, locked: Bool) -> NSView {
        guard locked else { return view }
        for control in controls ?? [view as? NSButton].compactMap({ $0 }) {
            control.isEnabled = false
            control.toolTip = ManagedPolicy.lockedHelp
        }
        let lock = NSImageView()
        lock.image = NSImage(systemSymbolName: "lock.fill", accessibilityDescription: ManagedPolicy.lockedHelp)
        lock.symbolConfiguration = NSImage.SymbolConfiguration(textStyle: .caption1)
        lock.contentTintColor = .secondaryLabelColor
        lock.toolTip = ManagedPolicy.lockedHelp
        let row = NSStackView(views: [view, lock])
        row.orientation = .horizontal
        row.alignment = .centerY
        row.spacing = 6
        return row
    }

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
