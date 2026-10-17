// Greenshot for Mac (Community) - an unofficial macOS port of Greenshot
// Copyright (C) 2026 Greenshot for Mac (Community) contributors
// Based on Greenshot, Copyright (C) 2007-2026 Thomas Braun, Jens Klingen, Robin Krom
// SPDX-License-Identifier: GPL-3.0-or-later

import AppKit
import GreenshotCore

/// The window mode's areas inside windows (upstream `Greenshot.Base/Capturing/WindowCaptureTool.cs` for beta testers):
/// with "Select areas inside windows" on and Accessibility allowed, the selection follows the smallest area under the
/// mouse, like a sidebar, a toolbar or a part of a web page; PgUp selects the area around it up to the whole window,
/// PgDn the smaller one again. The areas of a window are read once, in the background (`WindowAreaReader`); until they
/// arrive the window is selected as a whole, and after `WindowAreas.busyMarkDelay` a turning mark shows next to the mouse.
extension CaptureOverlayController {
    /// Starts the reader when the capture screen shows, if the setting is on and Accessibility allowed. Never asks for
    /// the permission here: the question would be hidden behind the capture screen.
    func startAreas() {
        guard selectsAreas, Permissions.hasAccessibility else { return }
        areasAllowed = true
        areaReader = WindowAreaReader()
    }

    /// The window mode's selection in `window` (its `visible` part): the area of the current level, or the visible part
    /// of the window while it has no areas.
    func areaSelection(in window: WindowInfo, visible: CGRect) -> CGRect {
        guard areasAllowed else { return visible }
        if areaWindow != window.id {
            areaWindow = window.id
            areaLevel.reset()
        }
        guard let root = windowAreas[window.id] else {
            requestAreas(of: window)
            return visible
        }
        let scale = cursorScreen?.scale ?? 1
        let (choices, deepest) = WindowAreas.selectable(at: cursor, in: root, window: visible, scale: scale)
        let choice = choices[areaLevel.resolve(deepest: deepest, count: choices.count)]
        hoveredArea = choice.area
        return choice.rect
    }

    /// Reads the areas of `window` unless they are known or being read; a read for another window stops.
    private func requestAreas(of window: WindowInfo) {
        guard let reader = areaReader, !windowsWithoutAreas.contains(window.id), areaReading?.window != window.id else { return }
        if areaReading != nil { reader.cancel() }
        areaReading = (window.id, Date())
        animator.requestFrame()
        let scale = cursorScreen?.scale ?? 1
        reader.read(window, scale: scale) { [weak self] tree in
            self?.useWindowAreas(tree, for: window.id)
        }
    }

    /// The areas of a window arrived (nil: it has none); also for the snapshots, which have no Accessibility API.
    func useWindowAreas(_ tree: WindowArea?, for window: CGWindowID) {
        guard !finished else { return }
        if areaReading?.window == window { areaReading = nil }
        if let tree, !tree.children.isEmpty {
            windowAreas[window] = tree
        } else {
            windowsWithoutAreas.insert(window)
        }
        // The mouse may still be over that window.
        mouseMoved(to: cursor)
    }

    /// PgUp (+1, larger) and PgDn (−1, smaller).
    func stepArea(by change: Int) {
        guard areasAllowed else { return }
        areaLevel.step(by: change)
        mouseMoved(to: cursor)
    }

    func resetAreaLevel() {
        areaLevel.reset()
        areaWindow = nil
    }

    /// The turning mark shows: the areas of the window under the mouse are being read for a moment already.
    func showsAreaSpinner(at now: Date) -> Bool {
        guard mode == .window, let reading = areaReading, reading.window == hoveredWindow?.id else { return false }
        return now.timeIntervalSince(reading.since) >= WindowAreas.busyMarkDelay
    }

    /// While the areas are read the screen redraws, so the mark appears in time and turns.
    var readsAreas: Bool { mode == .window && areaReading != nil }

    /// The turning mark's angle: one turn per second (upstream `Draw`).
    func areaSpinnerAngle(at now: Date) -> CGFloat {
        guard let reading = areaReading else { return 0 }
        let elapsed = now.timeIntervalSince(reading.since)
        return CGFloat(elapsed.truncatingRemainder(dividingBy: 1)) * 2 * .pi
    }

    /// For the snapshots: the areas are on (as if Accessibility were allowed), and a read of `window` started `ago`
    /// seconds before.
    func pretendAreas(reading window: CGWindowID? = nil, since ago: TimeInterval = 0) {
        areasAllowed = true
        if let window { areaReading = (window, Date().addingTimeInterval(-ago)) }
    }
}
