// Greenshot for Mac (Community) - an unofficial macOS port of Greenshot
// Copyright (C) 2026 Greenshot for Mac (Community) contributors
// Based on Greenshot, Copyright (C) 2007-2026 Thomas Braun, Jens Klingen, Robin Krom
// SPDX-License-Identifier: GPL-3.0-or-later

import AppKit
import GreenshotCore

/// The picture of a window beside a window list menu (upstream `Greenshot.Base/Wpf/ThumbnailWindow.cs`): never active,
/// never takes the mouse, above the open menus.
@MainActor
final class MenuBarWindowThumbnail {
    static let padding: CGFloat = 6
    private let panel: NSPanel

    init() {
        panel = NSPanel(contentRect: NSRect(x: 0, y: 0, width: 10, height: 10), styleMask: [.borderless, .nonactivatingPanel],
                        backing: .buffered, defer: true)
        // Menus are at the pop-up menu level; one above, or the picture would be under the menu.
        panel.level = NSWindow.Level(rawValue: NSWindow.Level.popUpMenu.rawValue + 1)
        panel.isOpaque = false
        panel.backgroundColor = .clear
        panel.hasShadow = true
        panel.ignoresMouseEvents = true
        panel.isReleasedWhenClosed = false
        panel.hidesOnDeactivate = false
        panel.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary, .ignoresCycle, .transient]
    }

    /// To tell this panel from the menu windows in the window list.
    var windowNumber: Int { panel.windowNumber }

    /// Shows `image` (with `scale` pixels per point) beside `menuFrame`, at the mouse's height; AppKit coordinates.
    func show(_ image: CGImage, scale: CGFloat, mouse: NSPoint, menuFrame: NSRect?) {
        let picture = NSImage(cgImage: image, size: NSSize(width: CGFloat(image.width) / scale, height: CGFloat(image.height) / scale))
        let content = Self.contentView(image: picture)
        let screen = NSScreen.screens.first { NSMouseInRect(mouse, $0.frame, false) } ?? NSScreen.main
        guard let visible = screen?.visibleFrame else { return }
        let frame = MenuBarThumbnailLayout.frame(size: content.frame.size, menuFrame: menuFrame, mouse: mouse, screen: visible)
        panel.contentView = content
        panel.setFrame(frame, display: true)
        panel.orderFrontRegardless()
    }

    func hide() {
        panel.orderOut(nil)
    }

    func close() {
        panel.close()
    }

    /// The picture on a menu-like rounded background, sized to it.
    static func contentView(image: NSImage) -> NSView {
        let size = NSSize(width: image.size.width + 2 * padding, height: image.size.height + 2 * padding)
        let background = NSVisualEffectView(frame: NSRect(origin: .zero, size: size))
        background.material = .menu
        background.blendingMode = .behindWindow
        background.state = .active
        background.wantsLayer = true
        background.layer?.cornerRadius = 8
        background.layer?.masksToBounds = true
        let imageView = NSImageView(frame: NSRect(x: padding, y: padding, width: image.size.width, height: image.size.height))
        imageView.image = image
        imageView.imageScaling = .scaleProportionallyUpOrDown
        background.addSubview(imageView)
        return background
    }
}
