// Greenshot for Mac (Community) - an unofficial macOS port of Greenshot
// Copyright (C) 2026 Greenshot for Mac (Community) contributors
// Based on Greenshot, Copyright (C) 2007-2026 Thomas Braun, Jens Klingen, Robin Krom
// SPDX-License-Identifier: GPL-3.0-or-later

import AppKit
import GreenshotCore

/// "Transferring data to Jira, please wait…" with Cancel: port of upstream `ProgressWindow` as
/// `InteractiveUserInteraction.RunWithProgressAsync` shows it, only for work that takes longer than 300 ms (no flicker
/// for quick uploads).
@MainActor
final class UploadProgressPanel: NSObject {
    /// Upstream `ProgressDialogDelay`.
    static let delay: TimeInterval = 0.3

    let panel: NSPanel
    let contentView: NSView
    private let onCancel: () -> Void

    init(message: String, onCancel: @escaping () -> Void) {
        self.onCancel = onCancel
        let label = NSTextField(wrappingLabelWithString: message)
        label.preferredMaxLayoutWidth = 300
        let spinner = NSProgressIndicator()
        spinner.style = .bar
        spinner.isIndeterminate = true
        spinner.widthAnchor.constraint(equalToConstant: 300).isActive = true
        let cancel = NSButton(title: String(localized: "Cancel"), target: nil, action: nil)
        cancel.keyEquivalent = "\u{1b}"
        let buttons = NSStackView(views: [NSView(), cancel])
        let stack = NSStackView(views: [label, spinner, buttons])
        stack.orientation = .vertical
        stack.alignment = .leading
        stack.spacing = 12
        stack.edgeInsets = NSEdgeInsets(top: 20, left: 20, bottom: 16, right: 20)
        buttons.widthAnchor.constraint(equalTo: spinner.widthAnchor).isActive = true
        contentView = stack
        panel = NSPanel(contentRect: NSRect(x: 0, y: 0, width: 340, height: 120), styleMask: [.titled], backing: .buffered, defer: true)
        super.init()
        cancel.target = self
        cancel.action = #selector(cancelClicked)
        spinner.startAnimation(nil)
        panel.title = "Greenshot"
        panel.contentView = stack
        panel.isReleasedWhenClosed = false
        panel.level = .floating
        panel.setContentSize(stack.fittingSize)
    }

    func show() {
        panel.center()
        panel.orderFrontRegardless()
    }

    func close() {
        panel.orderOut(nil)
    }

    @objc private func cancelClicked() {
        close()
        onCancel()
    }
}
