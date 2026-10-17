// Greenshot for Mac (Community) - an unofficial macOS port of Greenshot
// Copyright (C) 2026 Greenshot for Mac (Community) contributors
// Based on Greenshot, Copyright (C) 2007-2026 Thomas Braun, Jens Klingen, Robin Krom
// SPDX-License-Identifier: GPL-3.0-or-later

import CoreGraphics

/// Where a panel of the capture screen goes (the keys, the info, the preview, the sizes): in a corner of the display
/// with the mouse, away from the mouse and from everything else that should stay visible.
/// Port of upstream `Greenshot/Capturing/PanelPlacement.cs`. All rectangles are in the same space (the display's points).
public enum CapturePanelPlacement {
    /// Distance between a panel and the edge of the display.
    public static let margin: CGFloat = 10
    /// A panel keeps at least this distance from the mouse.
    public static let cursorClearance: CGFloat = 40
    /// A panel may cover this part of what it only loosely avoids (the selection) before it moves.
    public static let toleratedOverlap: CGFloat = 0.25

    /// The bounds for a panel. A panel stays where it is (`current`) unless it comes close to the mouse, overlaps a
    /// rectangle of `avoid` (the other panels), or covers a good part of `avoidLoosely` (the selection) while a
    /// completely free corner exists.
    public static func place(size: CGSize, monitor: CGRect, cursor: CGPoint, current: CGRect?,
                             avoid: [CGRect], avoidLoosely: [CGRect] = []) -> CGRect {
        let avoidList = avoid.filter { !$0.isEmpty }
        let looseList = avoidLoosely.filter { !$0.isEmpty }
        let cursorArea = CGRect(x: cursor.x - cursorClearance, y: cursor.y - cursorClearance,
                                width: 2 * cursorClearance, height: 2 * cursorClearance)

        func awayFromCursor(_ rect: CGRect) -> Bool { monitor.contains(rect) && !rect.intersects(cursorArea) }
        func clearOfPanels(_ rect: CGRect) -> Bool { !avoidList.contains { rect.intersects($0) } }
        func free(_ rect: CGRect) -> Bool {
            awayFromCursor(rect) && clearOfPanels(rect) && !looseList.contains { rect.intersects($0) }
        }

        let left = monitor.minX + margin
        let top = monitor.minY + margin
        let right = monitor.maxX - margin - size.width
        let bottom = monitor.maxY - margin - size.height
        // The corner farthest from the mouse first.
        let corners = [CGPoint(x: left, y: top), CGPoint(x: right, y: top), CGPoint(x: left, y: bottom), CGPoint(x: right, y: bottom)]
            .map { CGRect(origin: $0, size: size) }
            .sorted { distanceSquared($0, cursor) > distanceSquared($1, cursor) }
        let freeCorner = corners.first(where: free)

        if let current, !current.isEmpty {
            // A panel that changed size grows away from its corner, so its outer edges stay where they are.
            let resized = resize(current, to: size, in: monitor)
            if awayFromCursor(resized) && clearOfPanels(resized)
                && (freeCorner == nil || coveredPart(resized, looseList) <= toleratedOverlap) {
                return resized
            }
        }
        if let freeCorner { return freeCorner }
        // Everything is covered: keep away from the mouse and the other panels, or at least from the mouse.
        return corners.first { awayFromCursor($0) && clearOfPanels($0) } ?? corners.first(where: awayFromCursor) ?? corners[0]
    }

    /// The panel with a new size, keeping the edges that face the nearest corner of the display.
    public static func resize(_ current: CGRect, to size: CGSize, in monitor: CGRect) -> CGRect {
        let right = current.midX > monitor.midX
        let bottom = current.midY > monitor.midY
        return CGRect(x: right ? current.maxX - size.width : current.minX,
                      y: bottom ? current.maxY - size.height : current.minY,
                      width: size.width, height: size.height)
    }

    /// The largest part of the panel, or of one of the rectangles, that they share.
    static func coveredPart(_ panel: CGRect, _ rects: [CGRect]) -> CGFloat {
        var covered: CGFloat = 0
        for rect in rects {
            let overlap = panel.intersection(rect)
            guard !overlap.isNull, !overlap.isEmpty else { continue }
            let smaller = max(1, min(panel.width * panel.height, rect.width * rect.height))
            covered = max(covered, overlap.width * overlap.height / smaller)
        }
        return covered
    }

    private static func distanceSquared(_ rect: CGRect, _ point: CGPoint) -> CGFloat {
        let dx = rect.midX - point.x
        let dy = rect.midY - point.y
        return dx * dx + dy * dy
    }
}

/// Where the preview of the selection is on the capture screen (upstream `SelectionPreviewOverlay`): in a corner, in
/// the place of the zoomer, or off. P goes from one to the next (`NextMode`); the choice is remembered in the
/// settings `captureSelectionPreviewVisible` and `zoomerShowsPreview`, so it comes back with the next capture.
public enum SelectionPreviewPlacement: Equatable, Sendable {
    case corner, zoomer, off

    /// The placement the two settings mean.
    public init(visible: Bool, inZoomer: Bool) {
        self = visible ? (inZoomer ? .zoomer : .corner) : .off
    }

    /// After P: a corner, the zoomer's place, off, a corner again.
    public var next: SelectionPreviewPlacement {
        switch self {
        case .corner: return .zoomer
        case .zoomer: return .off
        case .off: return .corner
        }
    }

    /// `captureSelectionPreviewVisible`.
    public var isVisible: Bool { self != .off }
    /// `zoomerShowsPreview`.
    public var isInZoomer: Bool { self == .zoomer }
}

/// Where the zoomer (or the preview in its place) goes: next to the mouse, on the display, and if possible not over
/// the selection or the panels. Port of upstream `Greenshot/Capturing/ZoomerPlacement.cs`.
public enum CaptureZoomerPlacement {
    /// Distance between the mouse and the zoomer.
    public static let distance: CGFloat = 24
    /// The pixels across the zoomer shows (upstream `CaptureWindow.xaml.cs` `ZoomSourceSize`).
    public static let sourcePixels: CGFloat = 25

    /// The zoomer's diameter on a display: a fifth of its smaller side, a multiple of 4 (upstream `ZoomerPlacement.GetSize`).
    public static func size(for display: CGRect) -> CGFloat {
        let size = (min(display.width, display.height) / 5).rounded(.down)
        // At least one point per pixel, also for an unknown display.
        return max(size - size.truncatingRemainder(dividingBy: 4), sourcePixels)
    }

    /// The offset of the zoomer's top left corner from the mouse. It stays at `current` while that is fine,
    /// else it tries bottom right, bottom left, top right and top left of the mouse.
    public static func offset(cursor: CGPoint, current: CGPoint?, size: CGSize, monitor: CGRect, avoid: [CGRect]) -> CGPoint {
        func fits(_ offset: CGPoint, allowOverlap: Bool) -> Bool {
            let zoomer = CGRect(x: cursor.x + offset.x, y: cursor.y + offset.y, width: size.width, height: size.height)
            return monitor.contains(zoomer) && (allowOverlap || !avoid.contains { !$0.isEmpty && $0.intersects(zoomer) })
        }
        if let current, fits(current, allowOverlap: false) { return current }
        let candidates = [CGPoint(x: distance, y: distance), CGPoint(x: -distance - size.width, y: distance),
                          CGPoint(x: distance, y: -distance - size.height),
                          CGPoint(x: -distance - size.width, y: -distance - size.height)]
        for allowOverlap in [false, true] {
            if let candidate = candidates.first(where: { fits($0, allowOverlap: allowOverlap) }) { return candidate }
        }
        return current ?? candidates[0]
    }
}

/// The preview of the selection (upstream `Greenshot/Capturing/Overlays/SelectionPreviewOverlay.cs`).
public enum SelectionPreviewLayout {
    /// The box the preview fits into, in points.
    public static let maxSize = CGSize(width: 320, height: 200)

    /// The factor `pixels` (the selection's size in pixels) is drawn with to fit `box` (in device pixels): a whole
    /// number when enlarging, so every captured pixel is a sharp square of the same size.
    public static func scale(for pixels: CGSize, fitting box: CGSize) -> CGFloat {
        guard pixels.width > 0, pixels.height > 0 else { return 1 }
        let scale = min(box.width / pixels.width, box.height / pixels.height)
        return scale >= 1 ? scale.rounded(.down) : scale
    }

    /// "400 %", "25 %", "2.5 %".
    public static func percentText(_ scale: CGFloat) -> String {
        let percent = scale * 100
        if percent < 10 {
            let tenths = (percent * 10).rounded() / 10
            return tenths == tenths.rounded() ? "\(Int(tenths)) %" : "\(tenths) %"
        }
        return "\(Int(percent.rounded())) %"
    }
}
