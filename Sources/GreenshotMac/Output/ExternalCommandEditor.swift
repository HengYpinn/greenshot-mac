// Greenshot for Mac (Community) - an unofficial macOS port of Greenshot
// Copyright (C) 2026 Greenshot for Mac (Community) contributors
// Based on Greenshot, Copyright (C) 2007-2026 Thomas Braun, Jens Klingen, Robin Krom
// SPDX-License-Identifier: GPL-3.0-or-later

import AppKit
import GreenshotCore

/// The dialog to add or change an external command: port of upstream
/// `Greenshot.Plugin.ExternalCommand/Views/SettingsFormDetail` (name, command, arguments, image format and the
/// options). A name another command has already is refused (upstream `tooltip_duplicate_name`).
@MainActor
enum ExternalCommandEditor {
    /// The changed command, or nil when cancelled. `others` are the other commands, for the name check.
    static func edit(_ command: ExternalCommand?, others: [ExternalCommand] = []) -> ExternalCommand? {
        let form = ExternalCommandForm(command ?? ExternalCommand(name: "", command: "", arguments: "\"{0}\""))
        while true {
            let alert = NSAlert()
            alert.messageText = command == nil ? "Add External Command" : "Edit External Command"
            alert.informativeText = "{0} in the arguments is the screenshot's file; quotes group words. The command and the arguments can use the file name pattern variables, e.g. ${title}."
            alert.accessoryView = form.view
            alert.addButton(withTitle: command == nil ? "Add" : "OK")
            alert.addButton(withTitle: "Cancel")
            alert.window.initialFirstResponder = form.nameField
            NSApp.activate()
            guard alert.runModal() == .alertFirstButtonReturn else { return nil }
            var result = form.command
            guard !result.command.isEmpty else { return nil }
            if result.name.isEmpty { result.name = (result.command as NSString).lastPathComponent }
            guard ExternalCommandLine.isDuplicate(name: result.name, of: command?.id, among: others) else { return result }
            // Upstream keeps the dialog open with the message at the name.
            form.showDuplicateName()
        }
    }
}

/// The fields of the external command dialog.
@MainActor
final class ExternalCommandForm: NSObject {
    let view: NSView
    let nameField: NSTextField
    private let original: ExternalCommand
    private let program: NSTextField
    private let arguments: NSTextField
    private let formatPopup = NSPopUpButton()
    private let message = NSTextField(labelWithString: "")
    private let background = NSButton(checkboxWithTitle: "Run in the background (errors as a message, not a dialog)", target: nil, action: nil)
    private let copyURL = NSButton(checkboxWithTitle: "Copy the first URL in the output to the clipboard", target: nil, action: nil)
    private let copyOutput = NSButton(checkboxWithTitle: "Copy all output to the clipboard", target: nil, action: nil)
    /// Upstream `ShowStandardOutputInLog` (per command `ShowStandardOutputInLogCommand`); its errors always go to the log.
    private let outputToLog = NSButton(checkboxWithTitle: String(localized: "Write the output to the log"), target: nil, action: nil)

    init(_ command: ExternalCommand) {
        original = command
        nameField = NSTextField(string: command.name)
        program = NSTextField(string: command.command)
        arguments = NSTextField(string: command.arguments)
        program.placeholderString = "/usr/bin/open, /Applications/Preview.app or a name in the PATH"
        arguments.placeholderString = "\"{0}\" is the image file"
        background.state = command.runInBackground ? .on : .off
        copyURL.state = command.copyURLFromOutput ? .on : .off
        copyOutput.state = command.copyOutputToClipboard ? .on : .off
        outputToLog.state = command.showOutputInLog ? .on : .off
        // A command gets a plain image, never a .greenshot file.
        for format in ImageFormat.imageFormats {
            formatPopup.addItem(withTitle: format.displayName)
            formatPopup.lastItem?.representedObject = format.rawValue
        }
        formatPopup.selectItem(at: ImageFormat.imageFormats.firstIndex(of: command.format) ?? 0)
        message.textColor = .systemRed
        message.font = .systemFont(ofSize: NSFont.smallSystemFontSize)
        let program = self.program
        let nameField = self.nameField
        let choose = ClosureButton(title: "Choose…") {
            let panel = NSOpenPanel()
            panel.canChooseFiles = true
            panel.canChooseDirectories = false
            panel.treatsFilePackagesAsDirectories = false
            panel.directoryURL = URL(fileURLWithPath: "/Applications")
            if panel.runModal() == .OK, let url = panel.url {
                program.stringValue = url.path
                if nameField.stringValue.isEmpty { nameField.stringValue = url.deletingPathExtension().lastPathComponent }
            }
        }
        let grid = NSGridView(views: [
            [NSTextField(labelWithString: "Name:"), nameField],
            [NSGridCell.emptyContentView, message],
            [NSTextField(labelWithString: "Command:"), NSStackView(views: [program, choose])],
            [NSTextField(labelWithString: "Arguments:"), arguments],
            [NSTextField(labelWithString: "Image format:"), formatPopup],
            [NSGridCell.emptyContentView, background],
            [NSGridCell.emptyContentView, copyURL],
            [NSGridCell.emptyContentView, copyOutput],
            [NSGridCell.emptyContentView, outputToLog],
        ])
        grid.column(at: 0).xPlacement = .trailing
        grid.rowSpacing = 8
        for field in [nameField, arguments] { field.widthAnchor.constraint(equalToConstant: 340).isActive = true }
        program.widthAnchor.constraint(equalToConstant: 260).isActive = true
        grid.row(at: 1).isHidden = true
        view = grid
        super.init()
        resize()
    }

    /// The command as the fields say.
    var command: ExternalCommand {
        var result = original
        result.name = nameField.stringValue.trimmingCharacters(in: .whitespaces)
        result.command = program.stringValue.trimmingCharacters(in: .whitespaces)
        result.arguments = arguments.stringValue
        result.runInBackground = background.state == .on
        result.copyURLFromOutput = copyURL.state == .on
        result.copyOutputToClipboard = copyOutput.state == .on
        result.showOutputInLog = outputToLog.state == .on
        if let raw = formatPopup.selectedItem?.representedObject as? String, let format = ImageFormat(rawValue: raw) {
            result.format = format
        }
        return result
    }

    func showDuplicateName() {
        message.stringValue = "A command with this name already exists. Please choose a different name."
        (view as? NSGridView)?.row(at: 1).isHidden = false
        resize()
    }

    private func resize() {
        view.frame = NSRect(origin: .zero, size: view.fittingSize)
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
