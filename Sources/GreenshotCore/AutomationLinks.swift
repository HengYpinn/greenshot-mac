// Greenshot for Mac (Community) - an unofficial macOS port of Greenshot
// Copyright (C) 2026 Greenshot for Mac (Community) contributors
// Based on Greenshot, Copyright (C) 2007-2026 Thomas Braun, Jens Klingen, Robin Krom
// SPDX-License-Identifier: GPL-3.0-or-later

import Foundation

/// The parameters of the window commands of links and greenshot-cli (upstream `HandleSettingsAsync`,
/// `HandleSelfServiceAsync`, docs §2.3).
public enum AutomationLinks {
    /// Upstream's plugins; on the Mac their settings are on the Destinations tab.
    public static let pluginNames: Set<String> = ["box", "confluence", "dropbox", "externalcommand", "imgur", "jira", "office",
                                                   "pdf", "zxing", "recipeeditor"]

    /// The tab of `settings?tab=<tab>&plugin=<name>`: upstream's tab names; `plugins`, a plugin name (also as the tab,
    /// "an unknown tab name is taken as a plugin name") and `plugin=` go to Destinations. Nil (the tab shown last) for
    /// none or an unknown name.
    public static func settingsPane(tab: String?, plugin: String?) -> SettingsPane? {
        if let plugin, !plugin.trimmingCharacters(in: .whitespaces).isEmpty { return .destinations }
        guard let tab = tab?.trimmingCharacters(in: .whitespaces), !tab.isEmpty else { return nil }
        if let pane = SettingsPane(name: tab) { return pane }
        let key = tab.lowercased()
        if key == "plugins" || key == "plugin" || pluginNames.contains(key) { return .destinations }
        return nil
    }
}
