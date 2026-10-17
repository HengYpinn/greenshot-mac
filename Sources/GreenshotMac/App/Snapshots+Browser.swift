// Greenshot for Mac (Community) - an unofficial macOS port of Greenshot
// Copyright (C) 2026 Greenshot for Mac (Community) contributors
// Based on Greenshot, Copyright (C) 2007-2026 Thomas Braun, Jens Klingen, Robin Krom
// SPDX-License-Identifier: GPL-3.0-or-later

import AppKit
import GreenshotCore
import SwiftUI

extension Snapshots {
    /// Renders of Settings › Expert › Browser extension, with made-up browsers (nothing on this Mac is read or written).
    static func renderBrowserExtras(to folder: URL, sample: CGImage, settings: SettingsStore) throws {
        let host = "/Applications/Greenshot for Mac (Community).app/Contents/Helpers/greenshot-native-host"
        let integration = BrowserIntegration(home: URL(fileURLWithPath: "/nonexistent"), hostPath: host,
                                             extensionSource: URL(fileURLWithPath: "/nonexistent"), appInstalled: { _ in false })
        func browser(_ id: String) -> BrowserTarget {
            BrowserHostManifest.browsers.first { $0.id == id }!
        }
        let rows: [BrowserIntegration.Row] = [
            .init(browser: browser("chrome"), state: .installed),
            .init(browser: browser("edge"), state: .notInstalled),
            .init(browser: browser("firefox"), state: .stale("/Users/me/Downloads/Greenshot for Mac (Community).app/Contents/Helpers/greenshot-native-host")),
        ]
        let section = Form { BrowserExtensionSettingsSection(store: settings, integration: integration, rows: rows) }
            .formStyle(.grouped)
        let size = NSSize(width: 760, height: 330)
        let hosting = NSHostingView(rootView: section.frame(width: size.width, height: size.height))
        hosting.frame = NSRect(origin: .zero, size: size)
        try write(form(hosting), to: folder.appendingPathComponent("browser-settings.png"))
    }
}
