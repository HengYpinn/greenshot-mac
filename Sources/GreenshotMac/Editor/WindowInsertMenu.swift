// Greenshot for Mac (Community) - an unofficial macOS port of Greenshot
// Copyright (C) 2026 Greenshot for Mac (Community) contributors
// Based on Greenshot, Copyright (C) 2007-2026 Thomas Braun, Jens Klingen, Robin Krom
// SPDX-License-Identifier: GPL-3.0-or-later

import AppKit
import GreenshotCore
import ScreenCaptureKit

/// The windows of Edit › Insert Window (upstream `Greenshot.Editor/Controls/CaptureWindowMenuBuilder.cs`): the list
/// is made each time the menu opens, so it shows the windows that are on screen then. Titles are cut to
/// `maxMenuItemLength` like the menu bar's window list; pointing at a window shows a picture of it beside the menu when
/// `thumbnailPreview` is on (upstream `ShowThumbnailOnEnter` with `ThumbnailWindow`).
@MainActor
final class WindowInsertMenu: NSObject, NSMenuDelegate {
    static let shared = WindowInsertMenu()

    private var pictures: WindowPictureSource?
    private var hover: Task<Void, Never>?
    private var thumbnail: MenuBarWindowThumbnail?

    /// Where an inserted window goes: 100 points from the top left like upstream's `AddImageContainer(image, 100, 100)`,
    /// at the top left when the image isn't bigger than twice that (image pixels).
    static func insertOrigin(imageSize: CGSize, scale: CGFloat) -> CGPoint {
        let offset = 100 * max(scale, 1)
        guard imageSize.width > 2 * offset, imageSize.height > 2 * offset else { return .zero }
        return CGPoint(x: offset, y: offset)
    }

    func menuNeedsUpdate(_ menu: NSMenu) {
        menu.removeAllItems()
        let windows = ScreenCapturer.onScreenWindows()
        guard !windows.isEmpty else {
            menu.addItem(withTitle: String(localized: "No Windows"), action: nil, keyEquivalent: "").isEnabled = false
            return
        }
        let settings = (NSApp.delegate as? AppDelegate)?.settings.value
        let maxLength = settings?.maxMenuItemLength ?? 25
        for window in windows {
            let title = MenuBarText.windowTitle(appName: window.appName, title: window.title, maxLength: maxLength)
            let item = NSMenuItem(title: title, action: #selector(EditorWindowController.insertWindow(_:)), keyEquivalent: "")
            item.representedObject = NSNumber(value: window.id)
            if title != window.menuTitle { item.toolTip = window.menuTitle }
            if let icon = NSRunningApplication(processIdentifier: window.pid)?.icon?.copy() as? NSImage {
                icon.size = NSSize(width: 16, height: 16)
                item.image = icon
            }
            menu.addItem(item)
        }
    }

    func menuWillOpen(_ menu: NSMenu) {
        // The pictures need the screen recording permission, and pointing at a window must never ask for it.
        let wanted = (NSApp.delegate as? AppDelegate)?.settings.value.thumbnailPreview ?? false
        pictures = wanted && CGPreflightScreenCaptureAccess() ? WindowPictureSource() : nil
    }

    func menu(_ menu: NSMenu, willHighlight item: NSMenuItem?) {
        hover?.cancel()
        guard let pictures, let number = item?.representedObject as? NSNumber else {
            thumbnail?.hide()
            return
        }
        let id = CGWindowID(number.uint32Value)
        hover = Task { [weak self] in
            // Moving down the list shouldn't take a picture of every window on the way.
            try? await Task.sleep(nanoseconds: 100_000_000)
            guard !Task.isCancelled, let picture = await pictures.picture(of: id), !Task.isCancelled else { return }
            self?.show(picture)
        }
    }

    func menuDidClose(_ menu: NSMenu) {
        hover?.cancel()
        hover = nil
        pictures = nil
        thumbnail?.close()
        thumbnail = nil
    }

    private func show(_ picture: (image: CGImage, scale: CGFloat)) {
        let panel = thumbnail ?? MenuBarWindowThumbnail()
        thumbnail = panel
        panel.show(picture.image, scale: picture.scale, mouse: NSEvent.mouseLocation,
                   menuFrame: WindowPictureSource.openMenuFrame(excluding: panel.windowNumber))
    }
}

/// Small pictures of windows for a window list while its menu is open (the same as the menu bar's window list,
/// `MenuBarWindowList`): the shareable content is fetched once, each picture is taken once.
@MainActor
final class WindowPictureSource {
    private let content: Task<SCShareableContent?, Never>
    private var cache: [CGWindowID: (image: CGImage, scale: CGFloat)] = [:]

    init() {
        content = Task { try? await SCShareableContent.excludingDesktopWindows(true, onScreenWindowsOnly: true) }
    }

    /// The window as a picture at most `MenuBarThumbnailLayout` big, at the window's pixels per point.
    func picture(of id: CGWindowID) async -> (image: CGImage, scale: CGFloat)? {
        if let cached = cache[id] { return cached }
        guard let shareable = await content.value,
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
        cache[id] = (image, scale)
        return (image, scale)
    }

    /// The frame (AppKit coordinates) of this app's menu window under the mouse, without the picture's own panel. Nil
    /// when macOS's window list doesn't show it; the picture then goes beside the mouse.
    static func openMenuFrame(excluding panelNumber: Int) -> NSRect? {
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
