// Greenshot for Mac (Community) - an unofficial macOS port of Greenshot
// Copyright (C) 2026 Greenshot for Mac (Community) contributors
// Based on Greenshot, Copyright (C) 2007-2026 Thomas Braun, Jens Klingen, Robin Krom
// SPDX-License-Identifier: GPL-3.0-or-later

import CoreGraphics

/// Which displays the full screen hotkey captures (upstream `ScreenCaptureMode` and `ScreenToCapture`,
/// `Greenshot.Base/Interfaces/ScreenCaptureMode.cs`).
public enum CaptureScreenChoice {
    /// The indices of `frames` (the displays in the order they are numbered, the main display first) to capture.
    /// `.auto` takes the display with the mouse (the nearest one when the mouse is on none), `.fullScreen` every
    /// display, `.fixed` the display with the 1-based `screenNumber`, or the one with the mouse when there is no such display.
    public static func screens(for mode: ScreenCaptureMode, screenNumber: Int, mouse: CGPoint, frames: [CGRect]) -> [Int] {
        guard !frames.isEmpty else { return [] }
        switch mode {
        case .fullScreen:
            return Array(frames.indices)
        case .fixed where frames.indices.contains(screenNumber - 1):
            return [screenNumber - 1]
        case .fixed, .auto:
            return [screen(at: mouse, frames: frames)]
        }
    }

    /// The display that contains `point`, else the nearest one.
    public static func screen(at point: CGPoint, frames: [CGRect]) -> Int {
        if let index = frames.firstIndex(where: { $0.contains(point) }) { return index }
        func distance(_ rect: CGRect) -> CGFloat {
            let dx = max(rect.minX - point.x, 0, point.x - rect.maxX)
            let dy = max(rect.minY - point.y, 0, point.y - rect.maxY)
            return dx * dx + dy * dy
        }
        return frames.indices.min { distance(frames[$0]) < distance(frames[$1]) } ?? 0
    }
}
