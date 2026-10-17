// Greenshot for Mac (Community) - an unofficial macOS port of Greenshot
// Copyright (C) 2026 Greenshot for Mac (Community) contributors
// Based on Greenshot, Copyright (C) 2007-2026 Thomas Braun, Jens Klingen, Robin Krom
// SPDX-License-Identifier: GPL-3.0-or-later
// Owned by L10N-INFRA after the wave 5 prep.

import AppKit
import GreenshotCore

/// Help › Greenshot Help and the menu bar's Help (upstream `Greenshot.Base/Help/HelpFileLoader.cs`): the online help in
/// the UI language, else the English online help, else (offline) the page bundled in Contents/Resources/Help
/// (`HelpPages`).
@MainActor
enum HelpOpener {
    static func open() {
        let pack = LanguageStartup.current
        Task { @MainActor in
            let page = await HelpPages.page(for: pack, status: { await httpStatus($0) }, bundled: bundledPage)
            NSWorkspace.shared.open(page)
        }
    }

    /// The HTTP status of `url` (a HEAD request, 5 s), nil when the website can't be reached (upstream `GetHttpStatusAsync`).
    nonisolated private static func httpStatus(_ url: URL) async -> Int? {
        var request = URLRequest(url: url, cachePolicy: .reloadIgnoringLocalCacheData, timeoutInterval: 5)
        request.httpMethod = "HEAD"
        do {
            let (_, response) = try await URLSession.shared.data(for: request)
            return (response as? HTTPURLResponse)?.statusCode
        } catch {
            return nil
        }
    }

    nonisolated private static func bundledPage(_ name: String) -> URL? {
        guard let url = Bundle.main.resourceURL?.appendingPathComponent("Help", isDirectory: true).appendingPathComponent(name),
              FileManager.default.fileExists(atPath: url.path) else { return nil }
        return url
    }
}
