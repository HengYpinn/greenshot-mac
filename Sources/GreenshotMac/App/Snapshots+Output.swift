// Greenshot for Mac (Community) - an unofficial macOS port of Greenshot
// Copyright (C) 2026 Greenshot for Mac (Community) contributors
// SPDX-License-Identifier: GPL-3.0-or-later

import AppKit
import GreenshotCore
import SwiftUI

extension Snapshots {
    /// Renders for destinations, the picker and their settings. Writes PNG files into `folder` with `write(_:to:)`; the helpers in Snapshots.swift
    /// (`editorWindow`, `overlay`, `form`, `settingsTab`, `capture`) do most of the work.
    static func renderOutputExtras(to folder: URL, sample: CGImage, settings: SettingsStore) throws {
        let quality = QualityForm(format: .jpg, quality: 80, reduceColors: false, reduceColorsTo: 256)
        let command = ExternalCommandForm(ExternalCommand(name: "Preview", command: "/usr/bin/open",
                                                          arguments: "-a Preview \"{0}\" --args ${title}", format: .jpg))
        command.showDuplicateName()
        let progress = UploadProgressPanel(message: "Transferring data to Jira, please wait…") {}
        keepAlive += [quality, command, progress]
        try write(form(quality.view), to: folder.appendingPathComponent("dialog-quality.png"))
        try write(form(command.view), to: folder.appendingPathComponent("dialog-external-command.png"))
        try write(form(progress.contentView), to: folder.appendingPathComponent("dialog-upload-progress.png"))
        try write(uploadPanel(jira()), to: folder.appendingPathComponent("dialog-upload-jira.png"))
        try write(uploadPanel(confluence()), to: folder.appendingPathComponent("dialog-upload-confluence.png"))
        try write(uploadPanel(confluence(browse: true)), to: folder.appendingPathComponent("dialog-upload-confluence-browse.png"))
        try write(uploadPanel(atlassianLogin()), to: folder.appendingPathComponent("dialog-atlassian-login.png"))
        try write(serverSections(), to: folder.appendingPathComponent("settings-destinations-servers.png"))
        try write(destinationSections(), to: folder.appendingPathComponent("settings-destinations-commands.png"))
        try pickerDump().write(to: folder.appendingPathComponent("picker-menu.txt"), atomically: true, encoding: .utf8)
        print("Wrote \(folder.appendingPathComponent("picker-menu.txt").path)")
    }

    private static let site = AtlassianSite(url: "https://example.atlassian.net", email: "", apiToken: "")!

    /// The Jira dialog with a favourite filter chosen and made-up issues (no server).
    private static func jira() -> NSView? {
        let client = JiraClient(site: site, http: URLSession.shared)
        let panel = UploadPickerPanel(JiraPicker.configuration(client: client, settings: AppSettings(), filename: "2026-10-17 12_00_00-Safari.png"))
        let created = Date(timeIntervalSince1970: 1_790_000_000)
        let bug = URL(string: "https://example.atlassian.net/bug.png")!
        let task = URL(string: "https://example.atlassian.net/task.png")!
        let issues = [
            JiraIssue(key: "SHOT-12", summary: "Torn edge shadow is cut off at the bottom", type: "Bug", typeIconURL: bug,
                      created: created, assignee: "Alex Example", reporter: "Sam Example"),
            JiraIssue(key: "SHOT-9", summary: "Add the printer list to the picker", type: "Task", typeIconURL: task,
                      created: created.addingTimeInterval(-86_400 * 3), assignee: "Sam Example", reporter: "Alex Example"),
            JiraIssue(key: "SHOT-4", summary: "Pick a Confluence space before searching", type: "Task", typeIconURL: task,
                      created: created.addingTimeInterval(-86_400 * 9), assignee: nil, reporter: "Sam Example"),
        ]
        func icon(_ symbol: String, _ color: NSColor) -> NSImage {
            let image = NSImage(systemSymbolName: symbol, accessibilityDescription: nil)!
                .withSymbolConfiguration(NSImage.SymbolConfiguration(paletteColors: [color]))!
            image.size = NSSize(width: 16, height: 16)
            return image
        }
        panel.preview(rows: issues.map(JiraPicker.row), scopes: [.init(id: "1", title: "My open issues")], selectedScope: "1",
                      icons: [JiraClient.pngIconURL(bug): icon("ladybug.fill", .systemRed),
                              JiraClient.pngIconURL(task): icon("checkmark.square.fill", .systemBlue)])
        keepAlive.append(panel)
        return panel.contentView
    }

    /// The Confluence dialog with a space chosen and made-up pages, or its page tree.
    private static func confluence(browse: Bool = false) -> NSView? {
        let defaults = UserDefaults(suiteName: "greenshot-mac-snapshots-output")!
        defaults.removePersistentDomain(forName: "greenshot-mac-snapshots-output")
        let store = SettingsStore(defaults: defaults)
        let client = ConfluenceClient(site: AtlassianSite(url: "https://example.atlassian.net/wiki", email: "", apiToken: "")!,
                                      http: URLSession.shared)
        let picker = ConfluencePicker(client: client, settings: store, filename: "2026-10-17 12_00_00-Safari.png")
        let pages = [
            ConfluencePage(id: "1", title: "Release checklist", spaceName: "Engineering", url: URL(string: "https://example.atlassian.net/wiki/1")!),
            ConfluencePage(id: "2", title: "Release notes 2026", spaceName: "Engineering", url: URL(string: "https://example.atlassian.net/wiki/2")!),
        ]
        let spaces = [ConfluenceSpace(key: "ENG", name: "Engineering", homepageID: "10"),
                      ConfluenceSpace(key: "HR", name: "People", homepageID: "20")]
        picker.preview(pages: pages, spaces: spaces, selected: "ENG")
        if browse {
            let home = ConfluencePage(id: "10", title: "Engineering Home", spaceName: "Engineering", url: URL(string: "https://example.atlassian.net/wiki/10")!)
            picker.previewBrowse(spaces: spaces, homepage: home, children: pages)
        }
        keepAlive.append(picker)
        return picker.contentView
    }

    /// The login dialog of a Server / Data Center site after a wrong password.
    private static func atlassianLogin() -> NSView? {
        let site = AtlassianSite(url: "https://jira.example.com", login: .serverPassword, user: "alex", secret: "")!
        let dialog = AtlassianLoginDialog(service: .jira, site: site, problem: "HTTP 401: Unauthorized")
        dialog.alert.layout()
        keepAlive.append(dialog)
        return dialog.alert.window.contentView
    }

    /// Jira on Data Center with a password, Confluence with a personal access token and personal spaces, and a host and a
    /// fingerprint under Your own servers.
    private static func serverSections() -> NSBitmapImageRep? {
        let defaults = UserDefaults(suiteName: "greenshot-mac-snapshots-servers")!
        defaults.removePersistentDomain(forName: "greenshot-mac-snapshots-servers")
        let store = SettingsStore(defaults: defaults)
        store.update {
            $0.jira.login = .serverPassword
            $0.jira.url = "https://jira.example.com"
            $0.jira.email = "alex"
            $0.confluence.login = .serverToken
            $0.confluence.url = "https://wiki.example.com"
            $0.confluence.includePersonalSpaces = true
            $0.allowedUntrustedCertificateHosts = ["*.example.local"]
            $0.allowedCertificateThumbprints = ["2F:D2:CC:7E:80:64:6D:89:6F:E6:62:25:45:62:1E:65:B7:08:66:67:7E:7C:0D:63:5F:89:6F:A5:10:E0:8A:33"]
        }
        let hosting = NSHostingView(rootView: DestinationsSettings(store: store).serversForSnapshot)
        hosting.frame = NSRect(x: 0, y: 0, width: 620, height: 1120)
        let window = NSWindow(contentRect: hosting.frame, styleMask: [.titled], backing: .buffered, defer: false)
        window.contentView = hosting
        hosting.layoutSubtreeIfNeeded()
        keepAlive.append(window)
        return capture(hosting)
    }

    /// Settings › Destinations below the destination list: a command in JPEG, one whose program is missing, and
    /// Jira and Confluence with PNG uploads and "reduce colours".
    private static func destinationSections() -> NSBitmapImageRep? {
        let defaults = UserDefaults(suiteName: "greenshot-mac-snapshots-destinations")!
        defaults.removePersistentDomain(forName: "greenshot-mac-snapshots-destinations")
        let store = SettingsStore(defaults: defaults)
        store.update {
            $0.externalCommands[0].format = .jpg
            $0.externalCommands.append(ExternalCommand(name: "Upload script", command: "~/bin/upload-screenshot",
                                                       arguments: "\"{0}\" ${title}"))
            $0.jira.reduceColors = true
        }
        let hosting = NSHostingView(rootView: DestinationsSettings(store: store).commandsAndUploadsForSnapshot)
        hosting.frame = NSRect(x: 0, y: 0, width: 620, height: 760)
        let window = NSWindow(contentRect: hosting.frame, styleMask: [.titled], backing: .buffered, defer: false)
        window.contentView = hosting
        hosting.layoutSubtreeIfNeeded()
        keepAlive.append(window)
        return capture(hosting)
    }

    private static func uploadPanel(_ view: NSView?) -> NSBitmapImageRep? {
        guard let view else { return nil }
        view.appearance = NSAppearance(named: .aqua)
        return capture(view)
    }

    /// The picker's entries as text (NSMenu can't be drawn off screen): order, icons, keys and sub-menus, for
    /// settings with Jira set up, a recent Confluence page and a command whose program is missing.
    private static func pickerDump() -> String {
        let defaults = UserDefaults(suiteName: "greenshot-mac-snapshots-picker")!
        defaults.removePersistentDomain(forName: "greenshot-mac-snapshots-picker")
        let store = SettingsStore(defaults: defaults)
        store.update {
            $0.jira.url = "https://example.atlassian.net"
            $0.jira.recentIssueKeys = ["SHOT-12", "SHOT-9"]
            $0.confluence.url = "https://example.atlassian.net/wiki"
            $0.confluence.recentPages = [ConfluencePage(id: "1", title: "Release checklist", spaceName: "Engineering",
                                                        url: URL(string: "https://example.atlassian.net/wiki/1")!)]
            $0.externalCommands.append(ExternalCommand(name: "Gone", command: "/nonexistent/tool"))
        }
        let saver = ImageSaver(settings: store)
        let output = OutputManager(settings: store, saver: saver, editors: EditorManager(settings: store, saver: saver))
        let capture = Capture(image: sampleImage(width: 64, height: 48), scale: 1, title: "Safari")
        var lines: [String] = []
        func dump(_ items: [NSMenuItem], indent: String) {
            for item in items {
                guard !item.isSeparatorItem else {
                    lines.append(indent + "———")
                    continue
                }
                var line = indent + item.title
                if !item.keyEquivalent.isEmpty {
                    let m = item.keyEquivalentModifierMask
                    line += "    " + (m.contains(.option) ? "⌥" : "") + (m.contains(.shift) ? "⇧" : "") + "⌘" + item.keyEquivalent.uppercased()
                }
                if item.image != nil { line += "    [icon]" }
                lines.append(line)
                if let submenu = item.submenu { dump(submenu.items, indent: indent + "    ") }
            }
        }
        dump(output.pickerItems(for: capture) { _ in }, indent: "")
        return lines.joined(separator: "\n") + "\n"
    }
}
