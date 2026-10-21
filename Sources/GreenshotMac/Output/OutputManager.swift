// Greenshot for Mac (Community) - an unofficial macOS port of Greenshot
// Copyright (C) 2026 Greenshot for Mac (Community) contributors
// Based on Greenshot, Copyright (C) 2007-2026 Thomas Braun, Jens Klingen, Robin Krom
// SPDX-License-Identifier: GPL-3.0-or-later

import AppKit
import GreenshotCore

/// Called once when an export ended (upstream `ExportResult`).
typealias ExportCompletion = @MainActor (ExportResult) -> Void

/// Where one menu entry sends a capture: a destination, or one of the entries some destinations have per item
/// (upstream's dynamic destinations: one per external command, open editor, printer, Jira issue, Confluence page).
enum DestinationTarget: Equatable {
    case destination(CaptureDestination)
    /// "Save as PDF…": asks for the file name (the `.pdf` destination saves directly).
    case pdfAs
    case externalCommand(ExternalCommand)
    /// Open with that app; nil asks for one.
    case application(URL?)
    /// Add the capture to the open editor with this `EditorDocument.id` (upstream "Add to editor - <title>").
    case addToEditor(UUID)
    /// Print on this printer without the print panel (upstream `PrinterDestination(printerName)`).
    case printer(String)
    /// Attach to this Jira issue without asking (upstream `JiraDestination(jiraIssue)`).
    case jiraIssue(String)
    /// Attach to this Confluence page without asking (upstream `ConfluenceDestination(page)`).
    case confluencePage(ConfluencePage)
    /// A new document of an Office app (nil) or an open one, without asking (upstream `WordDestination(caption)`,
    /// `OutlookDestination(inspector)`, …); Mail's open messages too.
    case office(OfficeApplication, OfficeOpenItem?)

    /// The destination's name for messages ("Exported to: …").
    var displayName: String {
        func plain(_ title: String) -> String { title.hasSuffix("…") ? String(title.dropLast()) : title }
        switch self {
        case .destination(let destination): return plain(destination.pickerTitle)
        case .pdfAs: return String(localized: "Save as PDF")
        case .externalCommand(let command): return command.name
        case .application(let app):
            guard let app else { return String(localized: "Open With") }
            return String(localized: "Open with \(OpenWithDestination.name(of: app))")
        case .addToEditor: return String(localized: "Add to Editor")
        case .printer(let name): return String(localized: "Print – \(name)")
        case .jiraIssue(let key): return String(localized: "Upload to Jira – \(key)")
        case .confluencePage(let page): return String(localized: "Upload to Confluence – \(page.title)")
        case .office(let app, let item):
            let name = app == .mail ? String(localized: "Email") : app.name
            return item.map { "\(name) – \($0.title)" } ?? name
        }
    }
}

/// A `DestinationTarget` as a menu item's `representedObject`.
final class DestinationTargetBox: NSObject {
    let target: DestinationTarget

    init(_ target: DestinationTarget) {
        self.target = target
    }
}

/// Sends a capture to the configured destinations, or asks with upstream's destination picker menu
/// (`Greenshot/Destinations/PickerDestination.cs`, the menu is in `OutputManager+Picker.swift`).
@MainActor
final class OutputManager {
    let settings: SettingsStore
    let saver: ImageSaver
    let editors: EditorManager

    init(settings: SettingsStore, saver: ImageSaver, editors: EditorManager) {
        self.settings = settings
        self.saver = saver
        self.editors = editors
    }

    func handle(_ capture: Capture) {
        // One notification for all exports of this capture (upstream Notification step, `ExportNotification`).
        let log = NotificationExportLog(capture: capture, settings: settings)
        let destinations = settings.value.destinations
        if destinations.isEmpty || destinations.contains(.picker) {
            showPicker(for: capture, completion: log.expect())
        } else {
            destinations.forEach { perform(.destination($0), with: capture, completion: log.expect()) }
        }
        log.close()
    }

    /// `window` is the editor the capture comes from, if any: dialogs and the share menu attach to it, and it shows how
    /// the export ended (upstream `ExportResultHandler`). `completion` gets the result once.
    func perform(_ target: DestinationTarget, with capture: Capture, window: NSWindow? = nil,
                 completion: ExportCompletion? = nil) {
        let editor = window?.windowController as? EditorWindowController
        // The editor's state the capture shows: an upload that ends after more changes doesn't count them as saved.
        let exportedChange = editor?.editorDocument.changeCount
        let finish: ExportCompletion = { result in
            var result = result
            // The innermost destination names itself; the picker and menus pass its result on unchanged.
            if result.exportedBy == nil { result.exportedBy = target.displayName }
            editor?.showExportResult(result, destination: target.displayName, exportedChange: exportedChange)
            completion?(result)
        }
        if let refusal = ManagedHooks.refusal(for: target, settings: settings.value) {
            finish(refusal)
            return
        }
        switch target {
        case .destination(let destination):
            perform(destination, with: capture, window: window, completion: finish)
        case .pdfAs:
            finish(PdfDestination.save(capture, settings: settings, saver: saver, ask: true))
        case .externalCommand(let command):
            ExternalCommandRunner.run(command, capture: capture, settings: settings, saver: saver,
                                      savedFile: Self.savedFile(of: editor), completion: finish)
        case .application(let app):
            OpenWithDestination.open(capture, with: app, settings: settings, completion: finish)
        case .addToEditor(let id):
            finish(editors.addImage(capture, toEditor: id)
                   ? .succeeded(clearsModified: false)
                   : .failed(String(localized: "The editor was closed."), target: String(localized: "Add to Editor")))
        case .printer(let name):
            Printing.print(capture.image, scale: capture.scale, window: window, title: capture.title, date: capture.date,
                           printer: name, completion: finish)
        case .jiraIssue(let key):
            JiraDestination.upload(capture, settings: settings, saver: saver, issueKey: key, completion: finish)
        case .confluencePage(let page):
            ConfluenceDestination.upload(capture, settings: settings, saver: saver, page: page, completion: finish)
        case .office(let app, let item):
            OfficeDestination.export(app, item: item, capture: capture, settings: settings, saver: saver, completion: finish)
        }
    }

    private func perform(_ destination: CaptureDestination, with capture: Capture, window: NSWindow?,
                         completion: @escaping ExportCompletion) {
        switch destination {
        case .picker:
            showPicker(for: capture, completion: completion)
        case .editor:
            editors.open(capture)
            completion(.succeeded(clearsModified: false))
        case .clipboard:
            Clipboard.copy(capture.image, scale: capture.scale)
            saver.notify(String(localized: "Copied to the clipboard"))
            completion(.succeeded())
        case .file:
            completion(saver.exportDirectly(capture.image, scale: capture.scale, title: capture.title, date: capture.date,
                                            editable: capture.editable))
        case .fileAs:
            completion(saver.exportAs(capture.image, scale: capture.scale, title: capture.title, date: capture.date,
                                      editable: capture.editable))
        case .printer:
            Printing.print(capture.image, scale: capture.scale, window: window, title: capture.title, date: capture.date,
                           completion: completion)
        case .email:
            EmailDestination.send(capture, settings: settings, saver: saver, completion: completion)
        case .share:
            ShareDestination.share(capture, settings: settings, window: window, completion: completion)
        case .ocr:
            TextDestination.copyText(capture, settings: settings, saver: saver, completion: completion)
        case .externalCommand:
            runExternalCommand(with: capture, window: window, completion: completion)
        case .pdf:
            completion(PdfDestination.save(capture, settings: settings, saver: saver, ask: false))
        case .openWith:
            let menu = NSMenu(title: String(localized: "Open with"))
            menu.autoenablesItems = false
            var chosen: URL??
            OpenWithDestination.menuItems(format: settings.value.outputFormat) { app in chosen = .some(app) }.forEach(menu.addItem)
            popUp(menu)
            guard let app = chosen else {
                completion(.declined)
                return
            }
            OpenWithDestination.open(capture, with: app, settings: settings, completion: completion)
        case .qrCode:
            QRCodeDestination.show(capture, saver: saver, popUp: { [weak self] menu in self?.popUp(menu) }, completion: completion)
        case .jira:
            JiraDestination.upload(capture, settings: settings, saver: saver, completion: completion)
        case .confluence:
            ConfluenceDestination.upload(capture, settings: settings, saver: saver, completion: completion)
        case .box, .dropbox:
            CloudDestination.upload(destination, capture, settings: settings, saver: saver, completion: completion)
        case .word, .excel, .powerpoint, .outlook, .notes:
            guard let app = OfficeApplication(destination: destination) else { return completion(.declined) }
            OfficeDestination.exportAutomatically(app, capture: capture, settings: settings, saver: saver,
                                                  popUp: { [weak self] menu in self?.popUp(menu) }, completion: completion)
        }
    }

    /// The file an editor shows, when it is saved and unchanged: an external command gets that file instead of a
    /// temporary copy (upstream uses `captureDetails.Filename`).
    static func savedFile(of editor: EditorWindowController?) -> URL? {
        guard let document = editor?.editorDocument, !document.isModified, let url = document.fileURL,
              FileManager.default.fileExists(atPath: url.path) else { return nil }
        return url
    }

    /// The external command destination: the one command, or a menu to choose with several.
    private func runExternalCommand(with capture: Capture, window: NSWindow?, completion: @escaping ExportCompletion) {
        let commands = settings.value.externalCommands
        if commands.count == 1 {
            perform(.externalCommand(commands[0]), with: capture, window: window, completion: completion)
            return
        }
        guard !commands.isEmpty else {
            ErrorPresenter.show(message: String(localized: "No external command is set up"),
                                detail: String(localized: "Add one in Settings › Destinations."))
            completion(.failed(String(localized: "No external command is set up.")))
            return
        }
        let menu = NSMenu(title: String(localized: "External command"))
        menu.autoenablesItems = false
        var chosen: ExternalCommand?
        for command in commands {
            let item = ClosureMenuItem(title: command.name) { chosen = command }
            item.image = ExternalCommandRunner.icon(for: command)
            menu.addItem(item)
        }
        popUp(menu)
        guard let chosen else {
            completion(.declined)
            return
        }
        perform(.externalCommand(chosen), with: capture, window: window, completion: completion)
    }

    /// Shows a menu at the mouse. True when an entry was chosen (its action has run by then).
    @discardableResult
    func popUp(_ menu: NSMenu) -> Bool {
        // Activating (for keyboard navigation in the menu) while an editor window is open could switch to that
        // window's Space, away from where the user captured; the menu works with the mouse without it.
        if !NSApp.windows.contains(where: { $0.isVisible && $0.canBecomeMain }) {
            NSApp.activate()
        }
        return menu.popUp(positioning: nil, at: NSEvent.mouseLocation, in: nil)
    }
}
