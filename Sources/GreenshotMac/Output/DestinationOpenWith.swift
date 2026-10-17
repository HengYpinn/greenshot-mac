// Greenshot for Mac (Community) - an unofficial macOS port of Greenshot
// Copyright (C) 2026 Greenshot for Mac (Community) contributors
// Based on Greenshot, Copyright (C) 2007-2026 Thomas Braun, Jens Klingen, Robin Krom
// SPDX-License-Identifier: GPL-3.0-or-later

import AppKit
import GreenshotCore
import UniformTypeIdentifiers

/// "Open with…": the screenshot as a file in another app. The Mac's stand-in for upstream's per-application
/// destinations (`Greenshot.Plugin.Office` Word/PowerPoint/Outlook, `Greenshot/Destinations/EditorDestination.cs`
/// for other editors): one entry per app that opens images, with its icon.
@MainActor
enum OpenWithDestination {
    /// The apps that open the output format (PNG for the Greenshot format), the default app first, then by name.
    static func applications(for format: ImageFormat) -> [URL] {
        let workspace = NSWorkspace.shared
        let type = format.plainImage.utType
        let all = workspace.urlsForApplications(toOpen: type)
        let preferred = workspace.urlForApplication(toOpen: type)
        var seen = Set<String>()
        let unique = all.filter { url in
            let id = Bundle(url: url)?.bundleIdentifier ?? url.path
            return id != Bundle.main.bundleIdentifier && seen.insert(id).inserted
        }
        return unique.sorted { a, b in
            if a == preferred { return true }
            if b == preferred { return false }
            return name(of: a).localizedStandardCompare(name(of: b)) == .orderedAscending
        }
    }

    nonisolated static func name(of app: URL) -> String {
        FileManager.default.displayName(atPath: app.path).replacingOccurrences(of: ".app", with: "")
    }

    /// One item per app plus "Other…"; `choose` gets the app, or nil for "Other…".
    static func menuItems(format: ImageFormat, choose: @escaping (URL?) -> Void) -> [NSMenuItem] {
        var items: [NSMenuItem] = applications(for: format).prefix(30).map { app in
            let item = ClosureMenuItem(title: name(of: app)) { choose(app) }
            let icon = NSWorkspace.shared.icon(forFile: app.path)
            icon.size = NSSize(width: 16, height: 16)
            item.image = icon
            return item
        }
        if !items.isEmpty { items.append(.separator()) }
        items.append(ClosureMenuItem(title: String(localized: "Other…", comment: "Another app, chosen in a panel")) { choose(nil) })
        return items
    }

    /// Writes the screenshot in the output format (a plain image: PNG for the Greenshot format) and opens it with `app`,
    /// or with an app chosen in a panel.
    static func open(_ capture: Capture, with app: URL?, settings: SettingsStore, completion: @escaping ExportCompletion = { _ in }) {
        guard let app = app ?? chooseApplication() else {
            completion(.declined)
            return
        }
        let file: URL
        do {
            file = try TemporaryCaptureFile.write(capture, settings: settings, format: settings.value.outputFormat.plainImage)
        } catch {
            ErrorPresenter.show(error, title: String(localized: "The screenshot could not be written"))
            completion(.failed(error.localizedDescription))
            return
        }
        let configuration = NSWorkspace.OpenConfiguration()
        configuration.activates = true
        NSWorkspace.shared.open([file], withApplicationAt: app, configuration: configuration) { _, error in
            DispatchQueue.main.async {
                MainActor.assumeIsolated {
                    guard let error else {
                        completion(.succeeded(fileURL: file, target: name(of: app), clearsModified: false))
                        return
                    }
                    ErrorPresenter.show(error, title: String(localized: "\(name(of: app)) could not open the screenshot"))
                    completion(.failed(error.localizedDescription, target: name(of: app)))
                }
            }
        }
    }

    private static func chooseApplication() -> URL? {
        let panel = NSOpenPanel()
        panel.title = String(localized: "Open the Screenshot With")
        panel.prompt = String(localized: "Open", comment: "Button of the panel that chooses an app: opens the screenshot with it")
        panel.directoryURL = URL(fileURLWithPath: "/Applications")
        panel.allowedContentTypes = [.application]
        panel.canChooseDirectories = false
        NSApp.activate()
        return panel.runModal() == .OK ? panel.url : nil
    }
}
