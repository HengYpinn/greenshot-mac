// Greenshot for Mac (Community) - an unofficial macOS port of Greenshot
// Copyright (C) 2026 Greenshot for Mac (Community) contributors
// Based on Greenshot, Copyright (C) 2007-2026 Thomas Braun, Jens Klingen, Robin Krom
// SPDX-License-Identifier: GPL-3.0-or-later

import AppKit
import GreenshotCore
import ScreenCaptureKit

/// "Capture Window from List" of the menu bar menu (upstream `Greenshot/Shell/TrayMenu.cs` `CreateWindowListItem`,
/// `FillWindowList`, `ShowThumbnail`): the windows are listed when the submenu opens, with titles cut to
/// `maxMenuItemLength`; pointing at one shows a picture of it beside the menu when `thumbnailPreview` is on.
@MainActor
final class MenuBarWindowList: NSObject, NSMenuDelegate {
    private unowned let app: AppDelegate
    private var thumbnailsOn = false
    private var content: Task<SCShareableContent?, Never>?
    private var pictures: [CGWindowID: (image: CGImage, scale: CGFloat)] = [:]
    private var hover: Task<Void, Never>?
    private var thumbnail: MenuBarWindowThumbnail?

    init(app: AppDelegate) {
        self.app = app
    }

    /// The menu item with the window list; the list is made when it opens.
    func makeItem() -> NSMenuItem {
        let item = NSMenuItem(title: "Capture Window from List", action: nil, keyEquivalent: "")
        let menu = NSMenu(title: "Windows")
        menu.autoenablesItems = false
        menu.delegate = self
        // A placeholder, so the item has a submenu (upstream does the same).
        menu.addItem(withTitle: "…", action: nil, keyEquivalent: "").isEnabled = false
        item.submenu = menu
        return item
    }

    func menuNeedsUpdate(_ menu: NSMenu) {
        menu.removeAllItems()
        let windows = ScreenCapturer.onScreenWindows()
        if windows.isEmpty {
            menu.addItem(withTitle: "No Windows", action: nil, keyEquivalent: "").isEnabled = false
        }
        let maxLength = app.settings.value.maxMenuItemLength
        let capture = app.capture
        for window in windows.prefix(40) {
            let title = MenuBarText.windowTitle(appName: window.appName, title: window.title, maxLength: maxLength)
            let entry = ClosureMenuItem(title: title) { capture.capture(window: window) }
            entry.representedObject = NSNumber(value: window.id)
            if title != window.menuTitle { entry.toolTip = window.menuTitle }
            if let icon = NSRunningApplication(processIdentifier: window.pid)?.icon?.copy() as? NSImage {
                icon.size = NSSize(width: 16, height: 16)
                entry.image = icon
            }
            menu.addItem(entry)
        }
    }

    func menuWillOpen(_ menu: NSMenu) {
        // The pictures need the screen recording permission, and pointing at a window must never ask for it.
        thumbnailsOn = app.settings.value.thumbnailPreview && CGPreflightScreenCaptureAccess()
        guard thumbnailsOn else { return }
        content = Task { try? await SCShareableContent.excludingDesktopWindows(true, onScreenWindowsOnly: true) }
    }

    func menu(_ menu: NSMenu, willHighlight item: NSMenuItem?) {
        hover?.cancel()
        guard thumbnailsOn, let number = item?.representedObject as? NSNumber else {
            thumbnail?.hide()
            return
        }
        let id = CGWindowID(number.uint32Value)
        hover = Task { [weak self] in
            // Moving down the list shouldn't take a picture of every window on the way.
            try? await Task.sleep(nanoseconds: 100_000_000)
            guard !Task.isCancelled, let picture = await self?.picture(of: id), !Task.isCancelled else { return }
            self?.show(picture)
        }
    }

    func menuDidClose(_ menu: NSMenu) {
        hover?.cancel()
        hover = nil
        content?.cancel()
        content = nil
        thumbnail?.close()
        thumbnail = nil
        pictures = [:]
    }

    /// A small picture of the window, kept while the menu is open.
    private func picture(of id: CGWindowID) async -> (image: CGImage, scale: CGFloat)? {
        if let cached = pictures[id] { return cached }
        guard let shareable = await content?.value,
              let window = shareable.windows.first(where: { $0.windowID == id }) else { return nil }
        let filter = SCContentFilter(desktopIndependentWindow: window)
        let size = MenuBarThumbnailLayout.size(for: filter.contentRect.size)
        let scale = CGFloat(filter.pointPixelScale)
        let configuration = SCStreamConfiguration()
        configuration.width = max(Int((size.width * scale).rounded()), 1)
        configuration.height = max(Int((size.height * scale).rounded()), 1)
        configuration.showsCursor = false
        configuration.ignoreShadowsSingleWindow = true
        guard let image = try? await SCScreenshotManager.captureImage(contentFilter: filter, configuration: configuration) else {
            return nil
        }
        pictures[id] = (image, scale)
        return (image, scale)
    }

    private func show(_ picture: (image: CGImage, scale: CGFloat)) {
        let panel = thumbnail ?? MenuBarWindowThumbnail()
        thumbnail = panel
        panel.show(picture.image, scale: picture.scale, mouse: NSEvent.mouseLocation, menuFrame: openMenuFrame(excluding: panel.windowNumber))
    }

    /// The frame (AppKit coordinates) of this app's menu window under the mouse: the window list. Nil when the window
    /// list of macOS doesn't show it; the picture then goes beside the mouse.
    private func openMenuFrame(excluding panelNumber: Int) -> NSRect? {
        guard let list = CGWindowListCopyWindowInfo([.optionOnScreenOnly], kCGNullWindowID) as? [[String: Any]] else { return nil }
        let me = ProcessInfo.processInfo.processIdentifier
        let menuLevel = Int(CGWindowLevelForKey(.popUpMenuWindow))
        let mouse = ScreenSpace.mouseLocation
        for info in list {
            guard info[kCGWindowOwnerPID as String] as? pid_t == me,
                  let layer = info[kCGWindowLayer as String] as? Int, layer >= menuLevel,
                  let number = info[kCGWindowNumber as String] as? Int, number != panelNumber,
                  let boundsInfo = info[kCGWindowBounds as String] as? NSDictionary,
                  let bounds = CGRect(dictionaryRepresentation: boundsInfo), bounds.contains(mouse) else { continue }
            // Flipping between Quartz (y down) and AppKit (y up) is the same both ways.
            return Geometry.quartzRect(fromAppKit: bounds, primaryScreenHeight: ScreenSpace.primaryScreenHeight)
        }
        return nil
    }
}
