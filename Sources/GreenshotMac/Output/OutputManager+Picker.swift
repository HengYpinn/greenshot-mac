// Greenshot for Mac (Community) - an unofficial macOS port of Greenshot
// Copyright (C) 2026 Greenshot for Mac (Community) contributors
// Based on Greenshot, Copyright (C) 2007-2026 Thomas Braun, Jens Klingen, Robin Krom
// SPDX-License-Identifier: GPL-3.0-or-later

import AppKit
import GreenshotCore

/// The destination picker: port of upstream `Greenshot/Destinations/PickerDestination.cs` and
/// `Greenshot.Base/Wpf/DestinationPicker.cs`. The destinations that are available, by priority and name, with their
/// icons and File menu keys; the dynamic ones (open editors, printers, Jira issues, Confluence pages, external
/// commands, apps) as sub-menus with the destination itself first.
extension OutputManager {
    /// Shows the picker until an export succeeds or the user closes it (upstream `PickerDestination.ExportAsync`): a
    /// cancelled or failed export (its problem was shown already) brings the picker back.
    func showPicker(for capture: Capture, completion: ExportCompletion? = nil) {
        let menu = NSMenu(title: "Send screenshot to")
        menu.autoenablesItems = false
        let header = NSMenuItem(title: "\(capture.image.width) × \(capture.image.height) – \(capture.title)", action: nil, keyEquivalent: "")
        header.isEnabled = false
        menu.addItem(header)
        menu.addItem(.separator())
        // NSMenu sends the action after it has closed and before popUp returns: the entries only note the choice.
        var picked: DestinationTarget?
        pickerItems(for: capture) { picked = $0 }.forEach(menu.addItem)
        menu.addItem(.separator())
        let discard = ClosureMenuItem(title: "Discard") {}
        discard.image = Self.symbol("xmark")
        menu.addItem(discard)
        popUp(menu)
        guard let target = picked else {
            // Closed, Discard, or an entry that did its job itself (the QR code actions).
            completion?(.declined)
            return
        }
        perform(target, with: capture) { [weak self] result in
            guard !result.isSucceeded else {
                completion?(result)
                return
            }
            // After the dialogs of the failed export have closed.
            DispatchQueue.main.async { self?.showPicker(for: capture, completion: completion) }
        }
    }

    /// The picker's entries; `pick` gets the chosen target.
    func pickerItems(for capture: Capture, pick: @escaping (DestinationTarget) -> Void) -> [NSMenuItem] {
        let s = settings.value
        var entries: [(priority: Int, title: String, item: NSMenuItem)] = []
        func item(_ title: String, _ target: DestinationTarget, symbol: String? = nil,
                  shortcut: DestinationShortcut? = nil) -> NSMenuItem {
            let entry = ClosureMenuItem(title: title) { pick(target) }
            entry.image = symbol.flatMap(Self.symbol)
            if let shortcut {
                entry.keyEquivalent = shortcut.key
                var modifiers: NSEvent.ModifierFlags = .command
                if shortcut.shift { modifiers.insert(.shift) }
                if shortcut.option { modifiers.insert(.option) }
                entry.keyEquivalentModifierMask = modifiers
            }
            return entry
        }
        func add(_ destination: CaptureDestination, title: String? = nil, _ target: DestinationTarget? = nil) {
            let title = title ?? destination.pickerTitle
            entries.append((destination.pickerPriority, title,
                            item(title, target ?? .destination(destination), symbol: destination.symbolName,
                                 shortcut: destination.shortcut)))
        }
        /// An entry with a sub-menu: the destination itself first, then its dynamic destinations (upstream
        /// `DestinationPicker.AddDynamicDestinationsAsync`).
        func addGroup(_ destination: CaptureDestination, title: String, _ subItems: [NSMenuItem]) {
            guard !subItems.isEmpty else { return add(destination) }
            let group = NSMenuItem(title: title, action: nil, keyEquivalent: "")
            group.image = Self.symbol(destination.symbolName)
            let submenu = NSMenu(title: title)
            submenu.autoenablesItems = false
            submenu.addItem(item(destination.pickerTitle, .destination(destination), symbol: destination.symbolName,
                                 shortcut: destination.shortcut))
            submenu.addItem(.separator())
            subItems.forEach(submenu.addItem)
            group.submenu = submenu
            entries.append((destination.pickerPriority, title, group))
        }

        let folder = (saver.outputFolderURL(title: capture.title, date: capture.date).path as NSString).abbreviatingWithTildeInPath
        add(.file, title: "Save Directly (\(folder))")
        add(.fileAs)
        entries.append((CaptureDestination.pdf.pickerPriority, "Save as PDF…",
                        item("Save as PDF…", .pdfAs, symbol: CaptureDestination.pdf.symbolName, shortcut: CaptureDestination.pdf.shortcut)))
        addGroup(.editor, title: "Open in Image Editor", editors.openEditors.map { editor in
            item("Add to Editor – \(FilenamePattern.menuTitle(editor.title))", .addToEditor(editor.id), symbol: "plus.rectangle.on.rectangle")
        })
        add(.clipboard)
        add(.ocr)
        addGroup(.printer, title: "Print", Printing.printerNames().map { name in item(name, .printer(name), symbol: "printer") })
        if EmailDestination.isAvailable {
            // Mail's messages being written, to add the capture to (the Mac's stand-in for Outlook's open inspectors).
            if EmailDestination.defaultAppIsMail, OfficeDestination.isRunning(.mail) {
                let group = officeGroup(.mail, title: CaptureDestination.email.pickerTitle, newTarget: .destination(.email), item)
                entries.append((CaptureDestination.email.pickerPriority, group.title, group))
            } else {
                add(.email)
            }
        }
        // The Office apps (upstream `Greenshot.Plugin.Office`) and Notes, when installed; a running app lists its open
        // documents.
        for app in OfficeDestination.applications where OfficeDestination.isInstalled(app) {
            let destination = app.destination
            let entry: NSMenuItem
            if app.hasOpenItems, OfficeDestination.isRunning(app) {
                entry = officeGroup(app, title: destination.pickerTitle, newTarget: .office(app, nil), item)
            } else {
                entry = item(destination.pickerTitle, .office(app, nil), symbol: destination.symbolName)
            }
            entry.image = OfficeDestination.icon(app)
            entries.append((destination.pickerPriority, destination.pickerTitle, entry))
        }
        add(.share)
        if DestinationAvailability.isSetUp(.jira, in: s) {
            addGroup(.jira, title: "Upload to Jira", jiraIssueItems(item))
        }
        if DestinationAvailability.isSetUp(.confluence, in: s) {
            addGroup(.confluence, title: "Upload to Confluence", s.confluence.recentPages.map { page in
                item("Upload to Confluence: “\(FilenamePattern.menuTitle(page.title, length: 40))”", .confluencePage(page), symbol: "doc.text")
            })
        }
        for upload in [CaptureDestination.box, .dropbox] where DestinationAvailability.isSetUp(upload, in: s) {
            add(upload)
        }

        let openWith = NSMenuItem(title: CaptureDestination.openWith.pickerTitle, action: nil, keyEquivalent: "")
        openWith.image = Self.symbol(CaptureDestination.openWith.symbolName)
        openWith.submenu = NSMenu(title: "Open With")
        openWith.submenu?.autoenablesItems = false
        OpenWithDestination.menuItems(format: s.outputFormat) { app in pick(.application(app)) }.forEach { openWith.submenu?.addItem($0) }
        entries.append((CaptureDestination.openWith.pickerPriority, openWith.title, openWith))

        // Commands whose program is gone are left out (upstream removes them from the settings at startup).
        for command in s.externalCommands where ExternalCommandRunner.isAvailable(command) {
            let entry = item("External: \(command.name)", .externalCommand(command))
            entry.image = ExternalCommandRunner.icon(for: command)
            entries.append((CaptureDestination.externalCommand.pickerPriority, entry.title, entry))
        }

        let qrCode = NSMenuItem(title: CaptureDestination.qrCode.pickerTitle, action: nil, keyEquivalent: "")
        qrCode.image = Self.symbol(CaptureDestination.qrCode.symbolName)
        // Upstream offers QR code actions only when codes were found: the entry goes once the search finds none.
        qrCode.submenu = QRCodeDestination.pickerSubmenu(for: capture, saver: saver) { [weak qrCode] in
            guard let qrCode, let menu = qrCode.menu else { return }
            menu.removeItem(qrCode)
        }
        entries.append((CaptureDestination.qrCode.pickerPriority, qrCode.title, qrCode))

        return DestinationOrder.sorted(entries) { ($0.priority, $0.title) }.map(\.item)
    }

    /// The Jira issues for the picker (upstream `JiraDestination.GetDynamicDestinationsAsync` with `JiraMonitor`):
    /// the keys in the titles of the windows on screen, then the issues uploaded to last; their summaries are filled
    /// in when the server answers, and keys it doesn't know go again.
    private func jiraIssueItems(_ item: (String, DestinationTarget, String?, DestinationShortcut?) -> NSMenuItem) -> [NSMenuItem] {
        let s = settings.value
        let seen = JiraClient.issueKeys(inTitles: ScreenCapturer.onScreenWindows().map(\.title))
            .filter { !JiraSummaries.unknown.contains($0) }
        let keys = Array((seen + s.jira.recentIssueKeys.filter { !seen.contains($0) }).prefix(JiraSettings.maxRecentIssueKeys))
        func title(_ key: String, _ summary: String) -> String {
            summary.isEmpty ? key : "\(key): \(FilenamePattern.menuTitle(summary))"
        }
        let items = keys.map { key in item(JiraSummaries.known[key].map { title(key, $0) } ?? key, .jiraIssue(key), "checklist", nil) }
        // The user first: without it the Keychain isn't asked for the token (a personal access token needs none).
        let hasUser = s.jira.login == .serverToken || !s.jira.email.trimmingCharacters(in: .whitespaces).isEmpty
        guard !items.isEmpty, hasUser, let site = Uploads.jiraSite(s), site.hasCredentials else { return items }
        let client = JiraClient(site: site, http: Uploads.http)
        for (key, entry) in zip(keys, items) where JiraSummaries.known[key] == nil {
            Task { @MainActor [weak entry] in
                do {
                    let issue = try await client.issue(key)
                    JiraSummaries.known[key] = issue.summary
                    entry?.title = title(key, issue.summary)
                } catch UploadError.http(let status, _) where status == 404 {
                    // Not an issue of this Jira (e.g. "UTF-8" in a title).
                    JiraSummaries.unknown.insert(key)
                    if let entry, let menu = entry.menu { menu.removeItem(entry) }
                } catch {
                    // Offline or not allowed: keep the key.
                }
            }
        }
        return items
    }

    /// An Office app (or Mail) with a sub-menu: a new document first, then its open documents or messages once the app
    /// answered (upstream `GetDynamicDestinationsAsync`); asking never starts the app or a permission prompt.
    private func officeGroup(_ app: OfficeApplication, title: String, newTarget: DestinationTarget,
                             _ item: @escaping (String, DestinationTarget, String?, DestinationShortcut?) -> NSMenuItem) -> NSMenuItem {
        let group = NSMenuItem(title: title, action: nil, keyEquivalent: "")
        let submenu = NSMenu(title: title)
        submenu.autoenablesItems = false
        let destination = app.destination
        let new = item(OfficeDestination.newItemTitle(app), newTarget, destination.symbolName,
                       app == .mail ? destination.shortcut : nil)
        new.image = OfficeDestination.icon(app)
        submenu.addItem(new)
        let separator = NSMenuItem.separator()
        let looking = NSMenuItem(title: "Looking for open \(app == .mail || app == .outlook ? "messages" : "documents")…",
                                 action: nil, keyEquivalent: "")
        looking.isEnabled = false
        submenu.addItem(separator)
        group.submenu = submenu
        if let known = OfficeDestination.openItemsOverride[app] {
            for open in known {
                submenu.addItem(item(FilenamePattern.menuTitle(open.title, length: 40), .office(app, open), nil, nil))
            }
            return group
        }
        submenu.addItem(looking)
        Task { @MainActor [weak submenu] in
            let items = await OfficeDestination.openItems(app)
            guard let submenu else { return }
            submenu.removeItem(looking)
            if items.isEmpty {
                submenu.removeItem(separator)
                return
            }
            for open in items {
                submenu.addItem(item(FilenamePattern.menuTitle(open.title, length: 40), .office(app, open), nil, nil))
            }
        }
        return group
    }

    static func symbol(_ name: String) -> NSImage? {
        NSImage(systemSymbolName: name, accessibilityDescription: nil)
    }
}

/// The summaries of the Jira issues the picker asked about while the app runs, so each key is fetched once (upstream
/// `JiraMonitor` keeps its recent issues in memory too).
@MainActor
private enum JiraSummaries {
    static var known: [String: String] = [:]
    /// Keys the server doesn't know (text in a title that only looks like a key).
    static var unknown: Set<String> = []
}
