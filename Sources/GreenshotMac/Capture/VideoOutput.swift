// Greenshot for Mac (Community) - an unofficial macOS port of Greenshot
// Copyright (C) 2026 Greenshot for Mac (Community) contributors
// Based on Greenshot, Copyright (C) 2007-2026 Thomas Braun, Jens Klingen, Robin Krom
// SPDX-License-Identifier: GPL-3.0-or-later

import AppKit
import GreenshotCore
import UniformTypeIdentifiers

/// Where a finished recording goes. The MP4 is already in the video folder; then Settings › Video's "After a
/// recording": a menu, Finder, the default player, the share menu, the path on the clipboard. Upstream passes the file
/// on in the recipe (`VideoFilePath`); the image destinations (editor, clipboard, printer, …) don't take a video.
@MainActor
enum VideoOutput {
    /// The message, and with `destinations` the destinations of the settings.
    static func deliver(_ result: VideoRecordingResult, settings: SettingsStore, saver: ImageSaver, destinations: Bool = true) {
        let url = result.fileURL
        let folder = (url.deletingLastPathComponent().path as NSString).abbreviatingWithTildeInPath
        let facts = "\(RecordingText.elapsed(result.duration)), \(RecordingText.fileSize(result.fileSize))"
        let place = BidiText.isolatedLTR(folder)
        saver.notify(String(localized: "Saved \(url.lastPathComponent)"),
                     detail: String(localized: "\(facts) in \(place) – click to show in Finder", comment: "The length and size of a recording in its folder")) {
            NSWorkspace.shared.activateFileViewerSelecting([url])
        }
        guard destinations else { return }
        for destination in settings.value.video.destinations {
            perform(destination, url: url)
        }
    }

    static func perform(_ destination: VideoDestination, url: URL) {
        switch destination {
        case .picker: popUp(pickerMenu(for: url))
        case .showInFinder: NSWorkspace.shared.activateFileViewerSelecting([url])
        case .open: NSWorkspace.shared.open(url)
        case .share: ShareDestination.share(file: url, window: nil)
        case .copyPath: Clipboard.copy(text: url.path)
        }
    }

    /// "Ask every time": the choices for the file.
    static func pickerMenu(for url: URL) -> NSMenu {
        let menu = NSMenu(title: url.lastPathComponent)
        menu.autoenablesItems = false
        let title = NSMenuItem(title: url.lastPathComponent, action: nil, keyEquivalent: "")
        title.isEnabled = false
        menu.addItem(title)
        menu.addItem(.separator())
        menu.addItem(ClosureMenuItem(title: String(localized: "Show in Finder")) { perform(.showInFinder, url: url) })
        menu.addItem(ClosureMenuItem(title: String(localized: "Open", comment: "Verb: opens the recording")) { perform(.open, url: url) })
        let openWith = NSMenuItem(title: String(localized: "Open With"), action: nil, keyEquivalent: "")
        let apps = NSMenu(title: String(localized: "Open With"))
        apps.autoenablesItems = false
        openWithItems(for: url).forEach(apps.addItem)
        openWith.submenu = apps
        menu.addItem(openWith)
        menu.addItem(ClosureMenuItem(title: String(localized: "Share…")) { perform(.share, url: url) })
        menu.addItem(ClosureMenuItem(title: String(localized: "Copy File Path")) { perform(.copyPath, url: url) })
        return menu
    }

    /// The apps that play MP4 files, the default one first, then "Other…".
    private static func openWithItems(for url: URL) -> [NSMenuItem] {
        let workspace = NSWorkspace.shared
        let preferred = workspace.urlForApplication(toOpen: .mpeg4Movie)
        var seen = Set<String>()
        let apps = workspace.urlsForApplications(toOpen: .mpeg4Movie).filter { app in
            let id = Bundle(url: app)?.bundleIdentifier ?? app.path
            return id != Bundle.main.bundleIdentifier && seen.insert(id).inserted
        }.sorted { a, b in
            if a == preferred { return true }
            if b == preferred { return false }
            return OpenWithDestination.name(of: a).localizedStandardCompare(OpenWithDestination.name(of: b)) == .orderedAscending
        }
        var items: [NSMenuItem] = apps.prefix(30).map { app in
            let item = ClosureMenuItem(title: OpenWithDestination.name(of: app)) { open(url, with: app) }
            let icon = workspace.icon(forFile: app.path)
            icon.size = NSSize(width: 16, height: 16)
            item.image = icon
            return item
        }
        if !items.isEmpty { items.append(.separator()) }
        items.append(ClosureMenuItem(title: String(localized: "Other…")) {
            let panel = NSOpenPanel()
            panel.title = String(localized: "Open the Recording With")
            panel.prompt = String(localized: "Open", comment: "Verb: opens the recording")
            panel.directoryURL = URL(fileURLWithPath: "/Applications")
            panel.allowedContentTypes = [.application]
            NSApp.activate()
            if panel.runModal() == .OK, let app = panel.url { open(url, with: app) }
        })
        return items
    }

    private static func open(_ url: URL, with app: URL) {
        let configuration = NSWorkspace.OpenConfiguration()
        configuration.activates = true
        NSWorkspace.shared.open([url], withApplicationAt: app, configuration: configuration) { _, error in
            guard let error else { return }
            DispatchQueue.main.async {
                MainActor.assumeIsolated {
                    ErrorPresenter.show(error, title: String(localized: "\(OpenWithDestination.name(of: app)) could not open the recording"))
                }
            }
        }
    }

    /// A menu at the mouse (like `OutputManager.popUp`).
    private static func popUp(_ menu: NSMenu) {
        if !NSApp.windows.contains(where: { $0.isVisible && $0.canBecomeMain }) {
            NSApp.activate()
        }
        menu.popUp(positioning: nil, at: NSEvent.mouseLocation, in: nil)
    }
}
