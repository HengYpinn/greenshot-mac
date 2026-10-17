// Greenshot for Mac (Community) - an unofficial macOS port of Greenshot
// Copyright (C) 2026 Greenshot for Mac (Community) contributors
// Based on Greenshot, Copyright (C) 2007-2026 Thomas Braun, Jens Klingen, Robin Krom
// SPDX-License-Identifier: GPL-3.0-or-later

import Foundation

/// Which help page Help opens (upstream `Greenshot.Base/Help/HelpFileLoader.cs`): the online help in the UI language
/// (`https://getgreenshot.org/help/<ietf>/`, the English one at `/help/`); when that page is missing, the English
/// online help; when the website can't be reached, the page bundled with the app (`Resources/Help/help-<ietf>.html`,
/// else the English one), else the website. The pages describe Greenshot for Windows, like upstream's.
public enum HelpPages {
    /// Upstream `ExtHelpUrl`.
    public static let website = URL(string: "https://getgreenshot.org/help/")!

    /// The online help of `pack` (upstream `FindOnlineHelpUrlAsync`: the code lower-cased, none for en-US).
    public static func onlineURL(for pack: LanguagePack) -> URL {
        if pack.ietf == LanguagePacks.english.ietf { return website }
        return website.appendingPathComponent(pack.ietf.lowercased(), isDirectory: true)
    }

    /// The bundled pages to try, in order (upstream `FindLocalHelpFile`: the current language, then en-US).
    public static func localFiles(for pack: LanguagePack) -> [String] {
        var files: [String] = []
        if let own = pack.helpFile { files.append(own) }
        if let english = LanguagePacks.english.helpFile, !files.contains(english) { files.append(english) }
        return files
    }

    /// The page to open. `status` answers the HTTP status of a URL, nil when the website can't be reached;
    /// `bundled` the URL of a bundled page, nil when the app doesn't have it.
    public static func page(for pack: LanguagePack, status: (URL) async -> Int?, bundled: (String) -> URL?) async -> URL {
        let online = onlineURL(for: pack)
        var reached = false
        if let code = await status(online) {
            reached = true
            if code == 200 { return online }
            Log("Help").info("The online help \(online.absoluteString) answered \(code); trying \(website.absoluteString)")
            if online != website, await status(website) == 200 { return website }
        }
        if !reached { Log("Help").info("The online help can't be reached; opening the help bundled with the app") }
        for file in localFiles(for: pack) {
            if let url = bundled(file) { return url }
        }
        return website
    }
}
