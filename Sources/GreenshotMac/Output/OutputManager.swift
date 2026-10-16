// Greenshot for Mac (Community) - an unofficial macOS port of Greenshot
// Copyright (C) 2026 Greenshot for Mac (Community) contributors
// Based on Greenshot, Copyright (C) 2007-2026 Thomas Braun, Jens Klingen, Robin Krom
// SPDX-License-Identifier: GPL-3.0-or-later

import AppKit
import GreenshotCore

/// Where one menu entry sends a capture: a destination, or one of the entries some destinations have per item
/// (upstream has a destination object per external command and per Office application).
enum DestinationTarget: Equatable {
    case destination(CaptureDestination)
    /// "Save as PDF…": asks for the file name (the `.pdf` destination saves directly).
    case pdfAs
    case externalCommand(ExternalCommand)
    case application(URL)
}

/// A `DestinationTarget` as a menu item's `representedObject`.
final class DestinationTargetBox: NSObject {
    let target: DestinationTarget

    init(_ target: DestinationTarget) {
        self.target = target
    }
}

/// Sends a capture to the configured destinations, or asks with upstream's destination picker menu
/// (`Greenshot/Destinations/PickerDestination.cs`).
@MainActor
final class OutputManager {
    let settings: SettingsStore
    let saver: ImageSaver
    private let editors: EditorManager

    init(settings: SettingsStore, saver: ImageSaver, editors: EditorManager) {
        self.settings = settings
        self.saver = saver
        self.editors = editors
    }

    func handle(_ capture: Capture) {
        let destinations = settings.value.destinations
        if destinations.isEmpty || destinations.contains(.picker) {
            showPicker(for: capture)
        } else {
            destinations.forEach { perform($0, with: capture) }
        }
    }

    /// `window` is the editor the capture comes from, if any (dialogs and the share menu attach to it).
    func perform(_ target: DestinationTarget, with capture: Capture, window: NSWindow? = nil) {
        switch target {
        case .destination(let destination):
            perform(destination, with: capture, window: window)
        case .pdfAs:
            PdfDestination.save(capture, settings: settings, saver: saver, ask: true)
        case .externalCommand(let command):
            ExternalCommandRunner.run(command, capture: capture, settings: settings, saver: saver)
        case .application:
            break
        }
    }

    func perform(_ destination: CaptureDestination, with capture: Capture, window: NSWindow? = nil) {
        switch destination {
        case .picker:
            showPicker(for: capture)
        case .editor:
            editors.open(capture)
        case .clipboard:
            Clipboard.copy(capture.image, scale: capture.scale)
            saver.notify("Copied to the clipboard")
        case .file:
            saver.saveDirectly(capture.image, scale: capture.scale, title: capture.title, date: capture.date)
        case .fileAs:
            saver.saveAs(capture.image, scale: capture.scale, title: capture.title, date: capture.date)
        case .printer:
            Printing.print(capture.image, scale: capture.scale, window: window, title: capture.title, date: capture.date)
        case .email:
            EmailDestination.send(capture, settings: settings, saver: saver)
        case .share:
            ShareDestination.share(capture, settings: settings, window: window)
        case .ocr:
            TextDestination.copyText(capture, settings: settings, saver: saver)
        case .externalCommand:
            runExternalCommand(with: capture, window: window)
        case .pdf:
            PdfDestination.save(capture, settings: settings, saver: saver, ask: false)
        case .openWith, .qrCode:
            ErrorPresenter.show(message: "\(destination.displayName) isn't available yet", detail: "")
        }
    }

    /// The menu entries of every destination, for the picker (upstream's order: editor, files, clipboard, the rest).
    func pickerItems(for capture: Capture) -> [NSMenuItem] {
        let folder = (settings.value.outputFolderURL.path as NSString).abbreviatingWithTildeInPath
        var items: [NSMenuItem] = []
        func add(_ title: String, _ target: DestinationTarget) {
            // NSMenu sends the action after it has closed, so dialogs and windows open normally, and before
            // popUp returns, so the caller sees an opened editor when it decides where the focus goes.
            items.append(ClosureMenuItem(title: title) { [weak self] in self?.perform(target, with: capture) })
        }
        add("Open in Image Editor", .destination(.editor))
        add("Save Directly (\(folder))", .destination(.file))
        add("Save As…", .destination(.fileAs))
        add("Save as PDF…", .pdfAs)
        add("Copy to Clipboard", .destination(.clipboard))
        add("Copy Text (OCR)", .destination(.ocr))
        add("Print…", .destination(.printer))
        add("Email…", .destination(.email))
        add("Share…", .destination(.share))
        for command in settings.value.externalCommands {
            add("External: \(command.name)", .externalCommand(command))
        }
        return items
    }

    /// The external command destination: the one command, or a menu to choose with several.
    private func runExternalCommand(with capture: Capture, window: NSWindow?) {
        let commands = settings.value.externalCommands
        if commands.count == 1 {
            perform(.externalCommand(commands[0]), with: capture, window: window)
            return
        }
        guard !commands.isEmpty else {
            ErrorPresenter.show(message: "No external command is set up", detail: "Add one in Settings › Destinations.")
            return
        }
        let menu = NSMenu(title: "External command")
        menu.autoenablesItems = false
        for command in commands {
            menu.addItem(ClosureMenuItem(title: command.name) { [weak self] in
                self?.perform(.externalCommand(command), with: capture, window: window)
            })
        }
        popUp(menu)
    }

    /// The menu at the mouse that asks where the capture goes.
    private func showPicker(for capture: Capture) {
        let menu = NSMenu(title: "Send screenshot to")
        menu.autoenablesItems = false
        let header = NSMenuItem(title: "\(capture.image.width) × \(capture.image.height) – \(capture.title)", action: nil, keyEquivalent: "")
        header.isEnabled = false
        menu.addItem(header)
        menu.addItem(.separator())
        pickerItems(for: capture).forEach(menu.addItem)
        menu.addItem(.separator())
        menu.addItem(ClosureMenuItem(title: "Discard") {})
        popUp(menu)
    }

    /// Shows a menu at the mouse.
    func popUp(_ menu: NSMenu) {
        // Activating (for keyboard navigation in the menu) while an editor window is open could switch to that
        // window's Space, away from where the user captured; the menu works with the mouse without it.
        if !NSApp.windows.contains(where: { $0.isVisible && $0.canBecomeMain }) {
            NSApp.activate()
        }
        menu.popUp(positioning: nil, at: NSEvent.mouseLocation, in: nil)
    }
}
