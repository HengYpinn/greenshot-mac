// Greenshot for Mac (Community) - an unofficial macOS port of Greenshot
// Copyright (C) 2026 Greenshot for Mac (Community) contributors
// SPDX-License-Identifier: GPL-3.0-or-later

import AppKit

/// The menu bar icon: the app icon's viewfinder corners around a selection (`scripts/make-icon.swift`) without its
/// green square. It is a template image, so macOS tints it for light and dark menu bars and for the open menu.
enum MenuBarIcon {
    /// The canvas of a menu bar icon, in points.
    static let size = NSSize(width: 18, height: 18)

    static func make() -> NSImage {
        let image = NSImage(size: size, flipped: false) { _ in
            draw()
            return true
        }
        image.isTemplate = true
        image.accessibilityDescription = AppInfo.name
        return image
    }

    /// Lines sit on half points so their edges fall on Retina pixels.
    private static func draw() {
        NSColor.black.setStroke()

        // Viewfinder corners: a 14 pt square, as big and bold as the Wi-Fi icon, each arm about a quarter of its side
        // like the app icon.
        let frame = NSRect(x: 2.75, y: 2.75, width: 12.5, height: 12.5)
        let arm: CGFloat = 3.5
        let corners = NSBezierPath()
        corners.lineWidth = 1.5
        corners.lineCapStyle = .round
        corners.lineJoinStyle = .round
        let ends: [(x: CGFloat, y: CGFloat, dx: CGFloat, dy: CGFloat)] = [
            (frame.minX, frame.minY, 1, 1), (frame.maxX, frame.minY, -1, 1),
            (frame.minX, frame.maxY, 1, -1), (frame.maxX, frame.maxY, -1, -1)
        ]
        for (x, y, dx, dy) in ends {
            corners.move(to: NSPoint(x: x + dx * arm, y: y))
            corners.line(to: NSPoint(x: x, y: y))
            corners.line(to: NSPoint(x: x, y: y + dy * arm))
        }
        corners.stroke()

        // The selection in the middle: a quarter-tone fill with a thinner border, 7:5 like the app icon's 10:7.
        let selection = NSBezierPath(roundedRect: NSRect(x: 5.5, y: 6.5, width: 7, height: 5), xRadius: 1, yRadius: 1)
        NSColor.black.withAlphaComponent(0.25).setFill()
        selection.fill()
        selection.lineWidth = 1
        selection.stroke()
    }
}
