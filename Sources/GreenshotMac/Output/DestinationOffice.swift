// Greenshot for Mac (Community) - an unofficial macOS port of Greenshot
// Copyright (C) 2026 Greenshot for Mac (Community) contributors
// Based on Greenshot, Copyright (C) 2007-2026 Thomas Braun, Jens Klingen, Robin Krom
// SPDX-License-Identifier: GPL-3.0-or-later

import AppKit
import GreenshotCore

private let log = Log("Office")

/// A failed Office script, explained with the app's name.
struct OfficeExportError: LocalizedError {
    let app: OfficeApplication
    let failure: AppleScriptFailure

    var errorDescription: String? {
        var text = failure.explanation(appName: app.name)
        if app == .outlook, failure.kind == .notSupported {
            text += " New Outlook can't be scripted: turn it off (Outlook › Legacy Outlook) or use Email…"
        }
        return text
    }
}

/// The Office destinations by AppleScript: ports of upstream `Greenshot.Plugin.Office/Destinations/*` (Word, Excel,
/// PowerPoint, Outlook) and Notes in OneNote's place. A new document, workbook, presentation, mail or note, or an open
/// one (upstream's dynamic destinations); an automatic export asks new or open when documents are open (upstream
/// `PickAndExportAsync`).
@MainActor
enum OfficeDestination {
    /// Pretends these apps are installed and nothing else, for the snapshots.
    static var installedOverride: Set<OfficeApplication>?
    /// Pretends these apps run with these open documents, for the snapshots (with `installedOverride`).
    static var openItemsOverride: [OfficeApplication: [OfficeOpenItem]] = [:]

    /// The Office apps and Notes of the destinations (Mail belongs to Email).
    static let applications: [OfficeApplication] = [.word, .excel, .powerpoint, .outlook, .notes]

    static func isRunning(_ app: OfficeApplication) -> Bool {
        if installedOverride != nil { return openItemsOverride[app] != nil }
        return AppleScriptRunner.isRunning(app.bundleID)
    }

    static func isInstalled(_ app: OfficeApplication) -> Bool {
        if let installedOverride { return installedOverride.contains(app) }
        return AppleScriptRunner.applicationURL(app.bundleID) != nil
    }

    /// The app's icon, 16 points, for menus.
    static func icon(_ app: OfficeApplication) -> NSImage? {
        guard installedOverride == nil, let url = AppleScriptRunner.applicationURL(app.bundleID) else {
            return NSImage(systemSymbolName: app.destination.symbolName, accessibilityDescription: nil)
        }
        let icon = NSWorkspace.shared.icon(forFile: url.path)
        icon.size = NSSize(width: 16, height: 16)
        return icon
    }

    /// "New Document" and the like: the first entry of an app's sub-menu.
    static func newItemTitle(_ app: OfficeApplication) -> String {
        switch app {
        case .word: return "New Document"
        case .excel: return "New Workbook"
        case .powerpoint: return "New Presentation"
        case .outlook, .mail: return "New Email"
        case .notes: return "New Note"
        }
    }

    /// The open documents or messages of the app, when it runs and Greenshot may already control it: never starts the
    /// app or makes macOS ask (the picker builds its menu with it).
    static func openItems(_ app: OfficeApplication) async -> [OfficeOpenItem] {
        if installedOverride != nil { return openItemsOverride[app] ?? [] }
        guard app.hasOpenItems, isRunning(app), let call = OfficeScripts.openItems(of: app) else { return [] }
        guard await AppleScriptRunner.permission(for: app.bundleID) == .allowed else { return [] }
        do {
            return OfficeScripts.openItems(of: app, fromOutput: try await AppleScriptRunner.run(call, timeout: 10))
        } catch {
            log.warn("Could not list the open items of \(app.name)", error: error)
            return []
        }
    }

    /// The destination as configured or from the File menu: with open documents (Word, PowerPoint) or messages
    /// (Outlook) a menu asks for a new or an open one, like upstream when not "manually initiated".
    static func exportAutomatically(_ app: OfficeApplication, capture: Capture, settings: SettingsStore, saver: ImageSaver,
                                    popUp: @escaping (NSMenu) -> Void, completion: @escaping ExportCompletion) {
        guard [.word, .powerpoint, .outlook].contains(app), isRunning(app) else {
            export(app, item: nil, capture: capture, settings: settings, saver: saver, completion: completion)
            return
        }
        Task { @MainActor in
            let items = await openItems(app)
            guard !items.isEmpty else {
                export(app, item: nil, capture: capture, settings: settings, saver: saver, completion: completion)
                return
            }
            let menu = NSMenu(title: app.name)
            menu.autoenablesItems = false
            var chosen: OfficeOpenItem??
            let new = ClosureMenuItem(title: newItemTitle(app)) { chosen = .some(nil) }
            new.image = icon(app)
            menu.addItem(new)
            menu.addItem(.separator())
            for item in items {
                menu.addItem(ClosureMenuItem(title: FilenamePattern.menuTitle(item.title, length: 40)) { chosen = .some(item) })
            }
            popUp(menu)
            guard let choice = chosen else {
                completion(.declined)
                return
            }
            export(app, item: choice, capture: capture, settings: settings, saver: saver, completion: completion)
        }
    }

    /// Sends the capture to a new item (`item` nil) or an open one, with a progress panel and Cancel when it takes long.
    static func export(_ app: OfficeApplication, item: OfficeOpenItem?, capture: Capture, settings: SettingsStore,
                       saver: ImageSaver, completion: @escaping ExportCompletion) {
        guard isInstalled(app) else {
            ErrorPresenter.show(message: "\(app.name) is not installed", detail: "Install it, or choose another destination in Settings › Destinations.")
            completion(.failed("\(app.name) is not installed."))
            return
        }
        let s = settings.value
        let isOffice = app != .notes && app != .mail
        let format = isOffice ? OfficeLayout.fileFormat(for: s.outputFormat) : .png
        let file: URL
        do {
            file = try TemporaryCaptureFile.write(capture, settings: settings, format: format,
                                                  in: isOffice ? TemporaryCaptureFile.officeRoot : nil)
        } catch {
            log.error("The screenshot could not be written for \(app.name)", error: error)
            ErrorPresenter.show(error, title: "The screenshot could not be written")
            completion(.failed(error.localizedDescription))
            return
        }
        let title = "The screenshot could not be sent to \(app.name)"
        Uploads.run(title, progress: "Sending the screenshot to \(app.name)…", completion: completion, showError: { error in
            if let office = error as? OfficeExportError {
                AppleScriptRunner.present(office.failure, appName: app.name, title: title, message: office.localizedDescription)
            } else {
                ErrorPresenter.show(error, title: title)
            }
        }) {
            do {
                let target = try await run(app, item: item, file: file, capture: capture, settings: settings)
                log.info("Sent a screenshot to \(app.name)\(target.map { " (\($0))" } ?? "")")
                return .succeeded(fileURL: file, target: target, clearsModified: false)
            } catch let failure as AppleScriptFailure {
                if failure.kind == .cancelled { throw CancellationError() }
                throw OfficeExportError(app: app, failure: failure)
            }
        }
    }

    /// The script(s) of the export; the name of the document or message the capture went to.
    private static func run(_ app: OfficeApplication, item: OfficeOpenItem?, file: URL, capture: Capture,
                            settings: SettingsStore) async throws -> String? {
        let s = settings.value
        let path = file.path
        let size = OfficeLayout.pointSize(pixelWidth: capture.image.width, pixelHeight: capture.image.height, scale: capture.scale)
        switch app {
        case .word:
            return try await AppleScriptRunner.run(OfficeScripts.wordInsert(imagePath: path, documentName: item?.id,
                                                                             lockAspectRatio: s.office.wordLockAspectRatio))
        case .excel:
            return try await AppleScriptRunner.run(OfficeScripts.excelInsert(imagePath: path, workbookName: item?.id, size: size))
        case .powerpoint:
            let answer = try await AppleScriptRunner.run(OfficeScripts.powerPointSlide(presentationName: item?.id,
                                                                                       layout: s.office.powerpointSlideLayout,
                                                                                       title: capture.title))
            guard let slide = PowerPointSlide(output: answer) else {
                throw AppleScriptFailure(number: nil, message: "PowerPoint gave an unexpected answer: \(answer)")
            }
            let frame = OfficeLayout.pictureFrame(imageSize: size, slide: slide)
            return try await AppleScriptRunner.run(OfficeScripts.powerPointPicture(
                presentationName: slide.presentationName, slideIndex: slide.index, imagePath: path, frame: frame,
                lockAspectRatio: s.office.powerpointLockAspectRatio))
        case .outlook:
            if let item {
                return try await AppleScriptRunner.run(OfficeScripts.outlookAttach(imagePath: path, windowID: item.id))
            }
            _ = try await AppleScriptRunner.run(OfficeScripts.outlookNewMail(
                imagePath: path, subject: EmailDestination.subject(for: capture, settings: settings),
                to: DestinationSupport.recipients(s.email.to), cc: DestinationSupport.recipients(s.email.cc),
                bcc: DestinationSupport.recipients(s.email.bcc), format: s.office.outlookEmailFormat))
            return nil
        case .mail:
            if let item {
                return try await AppleScriptRunner.run(OfficeScripts.mailAttach(imagePath: path, messageID: item.id))
            }
            _ = try await AppleScriptRunner.run(OfficeScripts.mailNewMessage(
                imagePath: path, subject: EmailDestination.subject(for: capture, settings: settings),
                to: DestinationSupport.recipients(s.email.to), cc: DestinationSupport.recipients(s.email.cc),
                bcc: DestinationSupport.recipients(s.email.bcc)))
            return nil
        case .notes:
            let title = capture.title.trimmingCharacters(in: .whitespacesAndNewlines)
            _ = try await AppleScriptRunner.run(OfficeScripts.notesNewNote(imagePath: path, title: title.isEmpty ? "Screenshot" : title))
            return nil
        }
    }
}

/// The editor's File menu entries of the Office destinations (upstream's editor lists every destination).
@MainActor
enum OfficeMenus {
    /// The File menu's entries for the installed Office apps and Notes (`MainMenu.destinationItem`s).
    static func fileMenuItems() -> [NSMenuItem] {
        OfficeDestination.applications.filter(OfficeDestination.isInstalled).map { app in
            let item = MainMenu.destinationItem(app.destination.displayName + "…", .destination(app.destination))
            item.image = OfficeDestination.icon(app)
            return item
        }
    }
}
