// Greenshot for Mac (Community) - an unofficial macOS port of Greenshot
// Copyright (C) 2026 Greenshot for Mac (Community) contributors
// Based on Greenshot, Copyright (C) 2007-2026 Thomas Braun, Jens Klingen, Robin Krom
// SPDX-License-Identifier: GPL-3.0-or-later

import CoreGraphics
import Foundation

/// Where the frame around a recording goes: the RecordVideo step's `ShowCaptureBorder` (upstream
/// `RecordVideoRecipeStep.cs:70,342`). Upstream asks Windows for its capture border
/// (`IGraphicsCaptureSession3.IsBorderRequired`, `WindowsGraphicsCaptureVideoSession.cs:403`); macOS has no such border,
/// so Greenshot draws its own frame in panels that the recording leaves out.
///
/// The lines go just outside what is recorded. Where a display ends there, they go inside instead (a whole display is
/// framed on its edges). Each display gets its own panel: a window over two displays is framed on both, without a line
/// where it goes on from one display to the next.
public enum RecordingBorderGeometry {
    /// The width of the lines, in points.
    public static let lineWidth: CGFloat = 3

    /// The sides of a frame; top and bottom as on the screen (Quartz: top is the smaller y).
    public struct Edges: OptionSet, Equatable, Sendable {
        public let rawValue: Int
        public init(rawValue: Int) { self.rawValue = rawValue }
        public static let top = Edges(rawValue: 1)
        public static let left = Edges(rawValue: 2)
        public static let bottom = Edges(rawValue: 4)
        public static let right = Edges(rawValue: 8)
        public static let all: Edges = [.top, .left, .bottom, .right]
    }

    /// The frame's part on one display: one panel.
    public struct Piece: Equatable, Sendable {
        /// The index of the display in the list given.
        public var displayIndex: Int
        /// The panel in Quartz global points.
        public var frame: CGRect
        /// The sides with a line; none where the recorded area goes on onto another display.
        public var edges: Edges
        public var lineWidth: CGFloat

        /// The inside of the lines, in the panel's points from its top left corner (y down). It reaches the panel's edge
        /// on a side without a line. The lines are the panel minus this.
        public var hole: CGRect {
            let left: CGFloat = edges.contains(.left) ? lineWidth : 0
            let right: CGFloat = edges.contains(.right) ? lineWidth : 0
            let top: CGFloat = edges.contains(.top) ? lineWidth : 0
            let bottom: CGFloat = edges.contains(.bottom) ? lineWidth : 0
            let width = max(frame.width - left - right, 0)
            let height = max(frame.height - top - bottom, 0)
            return CGRect(x: left, y: top, width: width, height: height)
        }
    }

    /// The panels of a frame around `rect` (Quartz global points) on `displays` (their frames, `CGDisplayBounds`): one per
    /// display the rect is on, in the displays' order. A side of the rect gets a line on the display it is on: outside
    /// the rect when there is room on that display, else inside. Empty when the rect is on no display.
    public static func pieces(around rect: CGRect, displays: [CGRect], lineWidth: CGFloat = lineWidth) -> [Piece] {
        let rect = rect.standardized
        guard rect.width > 0, rect.height > 0 else { return [] }
        var pieces: [Piece] = []
        for (index, display) in displays.enumerated() {
            if let piece = piece(around: rect, on: display, index: index, lineWidth: lineWidth) { pieces.append(piece) }
        }
        return pieces
    }

    private static func piece(around rect: CGRect, on display: CGRect, index: Int, lineWidth: CGFloat) -> Piece? {
        let part = display.intersection(rect)
        guard !part.isNull, part.width > 0, part.height > 0 else { return nil }
        // A side is the rect's own on this display, else the rect goes on past the display there.
        var edges: Edges = []
        if rect.minX >= display.minX { edges.insert(.left) }
        if rect.maxX <= display.maxX { edges.insert(.right) }
        if rect.minY >= display.minY { edges.insert(.top) }
        if rect.maxY <= display.maxY { edges.insert(.bottom) }
        guard !edges.isEmpty else { return nil }
        // Outside where the display has room for the line.
        let outLeft = edges.contains(.left) && part.minX - lineWidth >= display.minX
        let outRight = edges.contains(.right) && part.maxX + lineWidth <= display.maxX
        let outTop = edges.contains(.top) && part.minY - lineWidth >= display.minY
        let outBottom = edges.contains(.bottom) && part.maxY + lineWidth <= display.maxY
        let minX = outLeft ? part.minX - lineWidth : part.minX
        let maxX = outRight ? part.maxX + lineWidth : part.maxX
        let minY = outTop ? part.minY - lineWidth : part.minY
        let maxY = outBottom ? part.maxY + lineWidth : part.maxY
        let frame = CGRect(x: minX, y: minY, width: maxX - minX, height: maxY - minY)
        return Piece(displayIndex: index, frame: frame, edges: edges, lineWidth: lineWidth)
    }

    /// What a recording of `target` records, in Quartz global points: the display's frame, the part of a region on the
    /// display a stream records (`RecordingGeometry.displayRegion`, the display it covers most), or the window's frame
    /// (`windowFrame`, which the caller reads). Nil when it isn't on a display.
    public static func recordedArea(of target: VideoCaptureTarget, displays: [(id: CGDirectDisplayID, frame: CGRect)],
                                    windowFrame: CGRect?) -> CGRect? {
        switch target {
        case .display(let id):
            return displays.first { $0.id == id }?.frame
        case .region(let rect):
            return RecordingGeometry.displayRegion(for: rect, displays: displays.map(\.frame))?.globalRect
        case .window:
            guard let windowFrame, windowFrame.width > 0, windowFrame.height > 0 else { return nil }
            return windowFrame
        }
    }
}
