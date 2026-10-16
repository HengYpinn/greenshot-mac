// Greenshot for Mac (Community) - an unofficial macOS port of Greenshot
// Copyright (C) 2026 Greenshot for Mac (Community) contributors
// Based on Greenshot, Copyright (C) 2007-2026 Thomas Braun, Jens Klingen, Robin Krom
// SPDX-License-Identifier: GPL-3.0-or-later

import AppKit
import GreenshotCore

/// The dialog to add or change an external command: port of upstream
/// `Greenshot.Plugin.ExternalCommand/Views/SettingsFormDetail` (name, command, arguments and the options).
@MainActor
enum ExternalCommandEditor {
    /// The changed command, or nil when cancelled.
    static func edit(_ command: ExternalCommand?) -> ExternalCommand? {
        let original = command ?? ExternalCommand(name: "", command: "", arguments: "\"{0}\"")
        let name = NSTextField(string: original.name)
        let program = NSTextField(string: original.command)
        let arguments = NSTextField(string: original.arguments)
        program.placeholderString = "/usr/bin/open, /Applications/Preview.app or a name in the PATH"
        arguments.placeholderString = "\"{0}\" is the image file"
        let background = NSButton(checkboxWithTitle: "Run in the background (errors as a message, not a dialog)", target: nil, action: nil)
        let copyURL = NSButton(checkboxWithTitle: "Copy the first URL in the output to the clipboard", target: nil, action: nil)
        let copyOutput = NSButton(checkboxWithTitle: "Copy all output to the clipboard", target: nil, action: nil)
        background.state = original.runInBackground ? .on : .off
        copyURL.state = original.copyURLFromOutput ? .on : .off
        copyOutput.state = original.copyOutputToClipboard ? .on : .off

        let choose = ClosureButton(title: "Choose…") {
            let panel = NSOpenPanel()
            panel.canChooseFiles = true
            panel.canChooseDirectories = false
            panel.treatsFilePackagesAsDirectories = false
            panel.directoryURL = URL(fileURLWithPath: "/Applications")
            if panel.runModal() == .OK, let url = panel.url {
                program.stringValue = url.path
                if name.stringValue.isEmpty { name.stringValue = url.deletingPathExtension().lastPathComponent }
            }
        }
        let grid = NSGridView(views: [
            [NSTextField(labelWithString: "Name:"), name],
            [NSTextField(labelWithString: "Command:"), NSStackView(views: [program, choose])],
            [NSTextField(labelWithString: "Arguments:"), arguments],
            [NSGridCell.emptyContentView, background],
            [NSGridCell.emptyContentView, copyURL],
            [NSGridCell.emptyContentView, copyOutput],
        ])
        grid.column(at: 0).xPlacement = .trailing
        grid.rowSpacing = 8
        for field in [name, arguments] { field.widthAnchor.constraint(equalToConstant: 340).isActive = true }
        program.widthAnchor.constraint(equalToConstant: 260).isActive = true
        grid.frame = NSRect(origin: .zero, size: grid.fittingSize)

        let alert = NSAlert()
        alert.messageText = command == nil ? "Add External Command" : "Edit External Command"
        alert.informativeText = "The screenshot is saved as a temporary PNG; {0} in the arguments is its path. Quotes group words."
        alert.accessoryView = grid
        alert.addButton(withTitle: command == nil ? "Add" : "OK")
        alert.addButton(withTitle: "Cancel")
        alert.window.initialFirstResponder = name
        NSApp.activate()
        guard alert.runModal() == .alertFirstButtonReturn else { return nil }
        var result = original
        result.name = name.stringValue.trimmingCharacters(in: .whitespaces)
        result.command = program.stringValue.trimmingCharacters(in: .whitespaces)
        result.arguments = arguments.stringValue
        result.runInBackground = background.state == .on
        result.copyURLFromOutput = copyURL.state == .on
        result.copyOutputToClipboard = copyOutput.state == .on
        if result.name.isEmpty { result.name = (result.command as NSString).lastPathComponent }
        guard !result.command.isEmpty else { return nil }
        return result
    }
}

/// A push button that runs a closure.
final class ClosureButton: NSButton {
    private var handler: (() -> Void)?

    convenience init(title: String, handler: @escaping () -> Void) {
        self.init(frame: .zero)
        self.title = title
        bezelStyle = .rounded
        self.handler = handler
        target = self
        action = #selector(run)
    }

    @objc private func run() {
        handler?()
    }
}
