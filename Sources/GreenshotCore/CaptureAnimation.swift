// Greenshot for Mac (Community) - an unofficial macOS port of Greenshot
// Copyright (C) 2026 Greenshot for Mac (Community) contributors
// Based on Greenshot, Copyright (C) 2007-2026 Thomas Braun, Jens Klingen, Robin Krom
// SPDX-License-Identifier: GPL-3.0-or-later

import CoreGraphics
import Foundation

/// The timing of the capture screen's movements (upstream `Greenshot/Capturing/Views/CaptureWindow.xaml`): the window
/// selection slides from window to window, the panels slide to another corner and fade in and out, so the eye can
/// follow them; the labels of a window selection fade in after it moved.
public enum CaptureAnimation {
    /// Upstream `WindowSelectionDuration`.
    public static let selectionDuration: TimeInterval = 0.7
    /// Upstream `PanelDuration`.
    public static let panelMoveDuration: TimeInterval = 0.35
    /// Upstream `PanelFadeAnimation`.
    public static let panelFadeDuration: TimeInterval = 0.15
    /// Upstream `ShowLabelsStoryboard`: hidden at first, then fading in.
    public static let labelsHiddenFor: TimeInterval = 0.25
    public static let labelsShownAfter: TimeInterval = 0.55
    /// How long the selection has to stay the same before the panels move out of its way (upstream `SelectionSettleTime`).
    public static let selectionSettleTime: TimeInterval = 0.3

    /// Upstream's `QuinticEase` with `EaseOut`: fast at first, then slowing down.
    public static func easeOutQuint(_ t: Double) -> Double {
        let rest = 1 - min(max(t, 0), 1)
        return 1 - rest * rest * rest * rest * rest
    }

    /// How far an animation of `duration` that started at `start` is at `now`, 0…1.
    public static func progress(from start: Date, to now: Date, duration: TimeInterval) -> Double {
        guard duration > 0 else { return 1 }
        return min(max(now.timeIntervalSince(start) / duration, 0), 1)
    }

    /// The rectangle `t` (0…1) of the way from `from` to `to`.
    public static func interpolate(_ from: CGRect, _ to: CGRect, _ t: CGFloat) -> CGRect {
        CGRect(x: from.minX + (to.minX - from.minX) * t, y: from.minY + (to.minY - from.minY) * t,
               width: from.width + (to.width - from.width) * t, height: from.height + (to.height - from.height) * t)
    }

    /// The opacity of the labels `elapsed` seconds after a window selection started moving.
    public static func labelsOpacity(after elapsed: TimeInterval) -> CGFloat {
        let fade = labelsShownAfter - labelsHiddenFor
        return CGFloat(min(max((elapsed - labelsHiddenFor) / fade, 0), 1))
    }

    /// A panel only grows while it is shown, so it doesn't wobble when a value changes between e.g. 99 and 100
    /// (upstream `UpdatePanelSize`).
    public static func grownSize(_ shown: CGSize?, _ size: CGSize) -> CGSize {
        guard let shown else { return size }
        return CGSize(width: max(shown.width, size.width), height: max(shown.height, size.height))
    }
}

/// A rectangle sliding to `to` with upstream's quintic ease-out.
public struct CaptureMotion: Equatable, Sendable {
    public var from: CGRect
    public var to: CGRect
    public var start: Date
    public var duration: TimeInterval

    public init(from: CGRect, to: CGRect, start: Date, duration: TimeInterval) {
        self.from = from
        self.to = to
        self.start = start
        self.duration = duration
    }

    public func value(at now: Date) -> CGRect {
        let t = CaptureAnimation.easeOutQuint(CaptureAnimation.progress(from: start, to: now, duration: duration))
        return CaptureAnimation.interpolate(from, to, CGFloat(t))
    }

    public func isFinished(at now: Date) -> Bool {
        now.timeIntervalSince(start) >= duration
    }
}
