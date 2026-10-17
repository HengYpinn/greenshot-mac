// Greenshot for Mac (Community) - an unofficial macOS port of Greenshot
// Copyright (C) 2026 Greenshot for Mac (Community) contributors
// Based on Greenshot, Copyright (C) 2007-2026 Thomas Braun, Jens Klingen, Robin Krom
// SPDX-License-Identifier: GPL-3.0-or-later

import AppKit

/// The scroll view around the editor's canvas: ⌘ with the scroll wheel zooms one step at a time (upstream
/// `ImageEditorForm.PanelMouseWheel`: Ctrl + wheel, at most one step per 100 ms). Pinch zooming is the scroll view's own.
final class EditorWindowScrollView: NSScrollView {
    /// Zooms one step in (true) or out (false), keeping the given point of the document view under the mouse.
    var onWheelZoom: ((_ zoomIn: Bool, _ documentPoint: NSPoint) -> Void)?
    private var lastWheelZoom = Date.distantPast
    /// Upstream waits 100 ms before the next zoom step.
    private static let wheelZoomInterval: TimeInterval = 0.1

    /// Image coordinates: the scroller, the origin and the canvas stay left to right in a right-to-left language (L10N).
    override var userInterfaceLayoutDirection: NSUserInterfaceLayoutDirection {
        get { .leftToRight }
        set {}
    }

    override func scrollWheel(with event: NSEvent) {
        guard event.modifierFlags.contains(.command), let onWheelZoom, let documentView else {
            super.scrollWheel(with: event)
            return
        }
        // The direction of the wheel itself, whatever "natural scrolling" says: away from the user zooms in.
        let delta = event.isDirectionInvertedFromDevice ? -event.scrollingDeltaY : event.scrollingDeltaY
        let now = Date()
        guard delta != 0, now.timeIntervalSince(lastWheelZoom) >= Self.wheelZoomInterval else { return }
        lastWheelZoom = now
        onWheelZoom(delta > 0, documentView.convert(event.locationInWindow, from: nil))
    }
}
