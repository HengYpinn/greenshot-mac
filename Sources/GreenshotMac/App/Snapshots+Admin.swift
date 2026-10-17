// Greenshot for Mac (Community) - an unofficial macOS port of Greenshot
// Copyright (C) 2026 Greenshot for Mac (Community) contributors
// SPDX-License-Identifier: GPL-3.0-or-later

import AppKit
import GreenshotCore
import SwiftUI

extension Snapshots {
    /// Renders of settings locked by a configuration profile: the values come from `ManagedValues`, as a profile would
    /// give them (no MDM is needed).
    static func renderAdminExtras(to folder: URL, sample: CGImage, settings: SettingsStore) throws {
        let regionHotkey: [String: Any] = ["keyCode": 21, "modifiers": 6400]
        let general = adminStore("general", forced: [
            "Greenshot.theme": "light", "Greenshot.hotkeys.region": regionHotkey, "Greenshot.hotkeys.lastRegion": "",
            "Greenshot.hideMenuBarIcon": false, "Greenshot.updateCheckIntervalDays": 0, "Greenshot.hideExpertSettings": true,
        ])
        // The whole General tab (an off-screen TabView draws no tab bar, so the missing Expert tab can't be shown).
        try write(window(GeneralSettings(store: general, status: SystemStatus()).environment(\.managedPolicy, general.policy),
                         size: NSSize(width: 620, height: 1020)),
                  to: folder.appendingPathComponent("admin-settings-general.png"))

        let output = adminStore("output", forced: [
            "Greenshot.outputFolder": "~/Pictures/Screenshots", "Greenshot.outputFormat": "jpg", "Greenshot.jpegQuality": 85,
            "Greenshot.defaults": ["filenamePattern": "${title} ${capturetime:d\"yyyy-MM-dd\"}"],
        ])
        try write(settingsTab(SettingsPane.output.rawValue, settings: output),
                  to: folder.appendingPathComponent("admin-settings-output.png"))

        let destinations = adminStore("destinations", forced: [
            "Greenshot.destinations": ["clipboard", "file"], "Greenshot.excludeDestinations": ["Jira Plugin", "box", "dropbox", "Word"],
        ])
        try write(settingsTab(SettingsPane.destinations.rawValue, settings: destinations),
                  to: folder.appendingPathComponent("admin-settings-destinations.png"))

        // One member of a group: the other print options stay the user's.
        let printer = adminStore("printer", forced: ["Greenshot.printing.footer": true, "Greenshot.printing.center": false])
        try write(settingsTab(SettingsPane.printer.rawValue, settings: printer),
                  to: folder.appendingPathComponent("admin-settings-printer.png"))

        try Data(menusDump().utf8).write(to: folder.appendingPathComponent("admin-menus.txt"))
        print("Wrote \(folder.appendingPathComponent("admin-menus.txt").path)")
    }

    /// Settings with these values forced, on an empty suite of the user defaults.
    private static func adminStore(_ name: String, forced: [String: Any]) -> SettingsStore {
        let suite = "greenshot-mac-snapshots-admin-\(name)"
        let defaults = UserDefaults(suiteName: suite)!
        defaults.removePersistentDomain(forName: suite)
        return SettingsStore(defaults: defaults, managed: ManagedValues(forced: forced))
    }

    /// The menu bar menu's settings entries and the destination picker as text (NSMenu can't be drawn off screen): with
    /// locked quick settings and excluded destinations, then with Quick Settings and Settings turned off.
    private static func menusDump() -> String {
        var lines: [String] = ["Menu bar menu, mouse pointer and footer locked, Jira, Box, Word, Open With and QR codes excluded:"]
        let locked = adminStore("menus", forced: [
            "Greenshot.captureMousePointer": true, "Greenshot.printing.footer": true,
            "Greenshot.excludeDestinations": ["jira", "box", "word", "openWith", "Zxing"],
        ])
        dump(StatusItemController.settingsItems(store: locked) {}, into: &lines)

        lines.append("")
        lines.append("Destination picker with the same policy (all Office apps installed):")
        OfficeDestination.installedOverride = Set(OfficeDestination.applications)
        defer { OfficeDestination.installedOverride = nil }
        locked.update { $0.jira.url = "https://example.atlassian.net" }
        let saver = ImageSaver(settings: locked)
        let output = OutputManager(settings: locked, saver: saver, editors: EditorManager(settings: locked, saver: saver))
        let capture = Capture(image: sampleImage(width: 64, height: 48), scale: 1, title: "Safari")
        dump(output.pickerItems(for: capture) { _ in }, into: &lines)

        lines.append("")
        lines.append("Menu bar menu with DisableQuickSettings and DisableSettings (nothing):")
        let off = adminStore("menus-off", forced: ["Greenshot.disableQuickSettings": true, "Greenshot.disableSettings": true])
        let items = StatusItemController.settingsItems(store: off) {}
        if items.isEmpty { lines.append("(no entries)") }
        dump(items, into: &lines)
        return lines.joined(separator: "\n") + "\n"
    }

    private static func dump(_ items: [NSMenuItem], indent: String = "", into lines: inout [String]) {
        for item in items {
            guard !item.isSeparatorItem else {
                lines.append(indent + "———")
                continue
            }
            lines.append(indent + item.title + (item.state == .on ? "  ✓" : ""))
            if let submenu = item.submenu { dump(submenu.items, indent: indent + "    ", into: &lines) }
        }
    }
}
