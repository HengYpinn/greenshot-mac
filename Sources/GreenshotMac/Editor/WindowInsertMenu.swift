// Greenshot for Mac (Community) - an unofficial macOS port of Greenshot
// Copyright (C) 2026 Greenshot for Mac (Community) contributors
// Based on Greenshot, Copyright (C) 2007-2026 Thomas Braun, Jens Klingen, Robin Krom
// SPDX-License-Identifier: GPL-3.0-or-later

import AppKit
import GreenshotCore

/// The windows of Edit › Insert Window (upstream `Greenshot.Editor/Controls/CaptureWindowMenuBuilder.cs`): the list
/// is made each time the menu opens, so it shows the windows that are on screen then.
@MainActor
final class WindowInsertMenu: NSObject, NSMenuDelegate {
    static let shared = WindowInsertMenu()

    func menuNeedsUpdate(_ menu: NSMenu) {
        menu.removeAllItems()
        let windows = ScreenCapturer.onScreenWindows()
        guard !windows.isEmpty else {
            menu.addItem(withTitle: "No Windows", action: nil, keyEquivalent: "").isEnabled = false
            return
        }
        for window in windows {
            let item = NSMenuItem(title: window.menuTitle, action: #selector(EditorWindowController.insertWindow(_:)), keyEquivalent: "")
            item.representedObject = NSNumber(value: window.id)
            if let icon = NSRunningApplication(processIdentifier: window.pid)?.icon?.copy() as? NSImage {
                icon.size = NSSize(width: 16, height: 16)
                item.image = icon
            }
            menu.addItem(item)
        }
    }
}
