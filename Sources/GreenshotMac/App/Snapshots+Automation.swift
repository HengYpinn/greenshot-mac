// Greenshot for Mac (Community) - an unofficial macOS port of Greenshot
// Copyright (C) 2026 Greenshot for Mac (Community) contributors
// SPDX-License-Identifier: GPL-3.0-or-later

import AppKit
import GreenshotCore
import SwiftUI

extension Snapshots {
    /// Renders of links, the command line tool and the other automation.
    static func renderAutomationExtras(to folder: URL, sample: CGImage, settings: SettingsStore) throws {
        // Settings › Expert › Automation, with a fixed tool path (a snapshot build has no bundle)
        let section = Form { AutomationSettingsSection(store: settings, toolPath: AutomationSettingsSection.snapshotToolPath) }
            .formStyle(.grouped)
        let hosting = NSHostingView(rootView: section.frame(width: 620, height: 210))
        hosting.frame = NSRect(x: 0, y: 0, width: 620, height: 210)
        try write(form(hosting), to: folder.appendingPathComponent("aut-settings-automation.png"))

        // The second start of a copy while another runs
        let alert = AutomationStartup.alreadyRunningAlert(path: "/Applications/Greenshot for Mac (Community).app/Contents/MacOS/GreenshotMac")
        alert.layout()
        if let content = alert.window.contentView {
            try write(form(content), to: folder.appendingPathComponent("aut-instance-running.png"))
        }
    }
}
