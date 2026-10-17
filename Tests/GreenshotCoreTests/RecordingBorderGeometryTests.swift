// Greenshot for Mac (Community) - an unofficial macOS port of Greenshot
// Copyright (C) 2026 Greenshot for Mac (Community) contributors
// Based on Greenshot, Copyright (C) 2007-2026 Thomas Braun, Jens Klingen, Robin Krom
// SPDX-License-Identifier: GPL-3.0-or-later

import CoreGraphics
import Testing
@testable import GreenshotCore

/// The frame Greenshot draws around a recording (RecordVideo's `ShowCaptureBorder`): where its panels go.
@Suite struct RecordingBorderGeometryTests {
    let line: CGFloat = 3
    let main = CGRect(x: 0, y: 0, width: 1000, height: 800)
    let right = CGRect(x: 1000, y: 0, width: 1000, height: 800)

    @Test func outsideTheRecordedArea() throws {
        let pieces = RecordingBorderGeometry.pieces(around: CGRect(x: 100, y: 100, width: 200, height: 150), displays: [main], lineWidth: line)
        #expect(pieces.count == 1)
        let piece = try #require(pieces.first)
        #expect(piece.displayIndex == 0)
        #expect(piece.frame == CGRect(x: 97, y: 97, width: 206, height: 156))
        #expect(piece.edges == .all)
        // The hole is exactly what is recorded.
        #expect(piece.hole == CGRect(x: 3, y: 3, width: 200, height: 150))
    }

    @Test func insideWhereTheDisplayEnds() throws {
        let pieces = RecordingBorderGeometry.pieces(around: CGRect(x: 0, y: 0, width: 200, height: 150), displays: [main], lineWidth: line)
        let piece = try #require(pieces.first)
        // Top and left on the display's edges: inside; right and bottom: outside.
        #expect(piece.frame == CGRect(x: 0, y: 0, width: 203, height: 153))
        #expect(piece.edges == .all)
        #expect(piece.hole == CGRect(x: 3, y: 3, width: 197, height: 147))
    }

    @Test func notEnoughRoomGoesInside() throws {
        let pieces = RecordingBorderGeometry.pieces(around: CGRect(x: 1, y: 100, width: 200, height: 150), displays: [main], lineWidth: line)
        let piece = try #require(pieces.first)
        let minX = piece.frame.minX
        #expect(minX == 1)
    }

    @Test func aWholeDisplayIsFramedInside() throws {
        let pieces = RecordingBorderGeometry.pieces(around: main, displays: [main, right], lineWidth: line)
        #expect(pieces.count == 1)
        let piece = try #require(pieces.first)
        #expect(piece.frame == main)
        #expect(piece.edges == .all)
        #expect(piece.hole == CGRect(x: 3, y: 3, width: 994, height: 794))
    }

    @Test func overTwoDisplaysTwoPiecesWithoutALineBetween() throws {
        let window = CGRect(x: 900, y: 100, width: 200, height: 100)
        let pieces = RecordingBorderGeometry.pieces(around: window, displays: [main, right], lineWidth: line)
        #expect(pieces.count == 2)
        let first = try #require(pieces.first)
        let second = try #require(pieces.last)
        #expect(first.displayIndex == 0)
        #expect(first.frame == CGRect(x: 897, y: 97, width: 103, height: 106))
        #expect(first.edges == [.top, .left, .bottom])
        #expect(first.hole == CGRect(x: 3, y: 3, width: 100, height: 100))
        #expect(second.displayIndex == 1)
        #expect(second.frame == CGRect(x: 1000, y: 97, width: 103, height: 106))
        #expect(second.edges == [.top, .right, .bottom])
        #expect(second.hole == CGRect(x: 0, y: 3, width: 100, height: 100))
    }

    @Test func clampedToTheDisplay() throws {
        // A window half off the left of the only display: no line where it isn't on a display.
        let pieces = RecordingBorderGeometry.pieces(around: CGRect(x: -100, y: 100, width: 300, height: 100), displays: [main], lineWidth: line)
        let piece = try #require(pieces.first)
        #expect(piece.frame == CGRect(x: 0, y: 97, width: 203, height: 106))
        #expect(piece.edges == [.top, .right, .bottom])
        #expect(main.contains(piece.frame))
    }

    @Test func nothingOffTheDisplays() {
        let off = RecordingBorderGeometry.pieces(around: CGRect(x: 3000, y: 0, width: 100, height: 100), displays: [main, right], lineWidth: line)
        #expect(off.isEmpty)
        let empty = RecordingBorderGeometry.pieces(around: .zero, displays: [main], lineWidth: line)
        #expect(empty.isEmpty)
        // Larger than the display on every side: no side of it is on the screen.
        let larger = RecordingBorderGeometry.pieces(around: main.insetBy(dx: -10, dy: -10), displays: [main], lineWidth: line)
        #expect(larger.isEmpty)
    }

    @Test func aTinyAreaHasNoNegativeHole() throws {
        let pieces = RecordingBorderGeometry.pieces(around: CGRect(x: 0, y: 0, width: 4, height: 4), displays: [main], lineWidth: line)
        let piece = try #require(pieces.first)
        let hole = piece.hole
        #expect(hole.width >= 0)
        #expect(hole.height >= 0)
    }

    // MARK: What is recorded

    @Test func recordedAreaOfEachTarget() {
        let displays: [(id: CGDirectDisplayID, frame: CGRect)] = [(1, main), (2, right)]
        let display = RecordingBorderGeometry.recordedArea(of: .display(2), displays: displays, windowFrame: nil)
        #expect(display == right)
        let gone = RecordingBorderGeometry.recordedArea(of: .display(9), displays: displays, windowFrame: nil)
        #expect(gone == nil)
        let window = CGRect(x: 900, y: 100, width: 200, height: 100)
        let windowArea = RecordingBorderGeometry.recordedArea(of: .window(7), displays: displays, windowFrame: window)
        #expect(windowArea == window)
        let noWindow = RecordingBorderGeometry.recordedArea(of: .window(7), displays: displays, windowFrame: nil)
        #expect(noWindow == nil)
    }

    /// A region over two displays records the part on the display it covers most, so only that part is framed.
    @Test func aRegionIsFramedWhereItIsRecorded() {
        let displays: [(id: CGDirectDisplayID, frame: CGRect)] = [(1, main), (2, right)]
        let region = CGRect(x: 950, y: 100, width: 200, height: 100)
        let area = RecordingBorderGeometry.recordedArea(of: .region(region), displays: displays, windowFrame: nil)
        #expect(area == CGRect(x: 1000, y: 100, width: 150, height: 100))
        let offScreen = RecordingBorderGeometry.recordedArea(of: .region(CGRect(x: 5000, y: 0, width: 10, height: 10)),
                                                             displays: displays, windowFrame: nil)
        #expect(offScreen == nil)
    }
}
