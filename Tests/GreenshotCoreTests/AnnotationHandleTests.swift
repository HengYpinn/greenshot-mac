// Greenshot for Mac (Community) - an unofficial macOS port of Greenshot
// Copyright (C) 2026 Greenshot for Mac (Community) contributors
// Based on Greenshot, Copyright (C) 2007-2026 Thomas Braun, Jens Klingen, Robin Krom
// SPDX-License-Identifier: GPL-3.0-or-later

import AppKit
import CoreGraphics
import Foundation
import Testing
@testable import GreenshotCore

/// Resizing with Shift and Option, drawing lines with Shift, the crop modes' areas and the freehand spacing
/// (upstream `ScaleHelper`, `LineAngleRoundBehavior`, `CropContainer`, `FreehandContainer`).
struct AnnotationHandleTests {
    func box(_ kind: AnnotationKind, _ w: CGFloat = 40, _ h: CGFloat = 20) -> Annotation {
        Annotation(kind: kind, start: .zero, end: CGPoint(x: w, y: h))
    }

    @Test func shiftKeepsTheRatioOfEveryBoxOnItsCorners() {
        for kind in [AnnotationKind.rectangle, .ellipse, .text, .speechBubble, .highlight, .obfuscate, .image] {
            let kept = Handle.bottomRight.drag(box(kind), to: CGPoint(x: 60, y: 60), keepAspect: true)
            #expect(kept.bounds == CGRect(x: 0, y: 0, width: 120, height: 60), "\(kind)")
        }
        // An edge only moves its side, like upstream's `AdjustCoordsForRationalScale` (corners only).
        let edge = Handle.right.drag(box(.rectangle), to: CGPoint(x: 80, y: 5), keepAspect: true)
        #expect(edge.bounds == CGRect(x: 0, y: 0, width: 80, height: 20))
    }

    @Test func countersAndEmojiStaySquareWithCornerHandles() {
        let counter = Annotation(kind: .counter, start: .zero, end: CGPoint(x: 30, y: 30))
        #expect(Handle.handles(for: counter) == Handle.cornerHandles)
        let dragged = Handle.bottomRight.drag(counter, to: CGPoint(x: 50, y: 40))
        #expect(dragged.bounds == CGRect(x: 0, y: 0, width: 50, height: 50))
        let emoji = Annotation(kind: .emoji, start: .zero, end: CGPoint(x: 30, y: 30))
        #expect(Handle.topLeft.drag(emoji, to: CGPoint(x: 10, y: 20)).bounds == CGRect(x: 10, y: 10, width: 20, height: 20))
    }

    @Test func optionResizesAroundTheCentre() {
        let a = Annotation(kind: .rectangle, start: CGPoint(x: 10, y: 10), end: CGPoint(x: 50, y: 30))
        // The right side moves out by 10, the left one too.
        #expect(Handle.right.drag(a, to: CGPoint(x: 60, y: 20), centered: true).bounds == CGRect(x: 0, y: 10, width: 60, height: 20))
        #expect(Handle.top.drag(a, to: CGPoint(x: 30, y: 15), centered: true).bounds == CGRect(x: 10, y: 15, width: 40, height: 10))
        #expect(Handle.bottomRight.drag(a, to: CGPoint(x: 55, y: 35), centered: true).bounds
            == CGRect(x: 5, y: 5, width: 50, height: 30))
        // With Shift as well: the ratio stays and the centre too.
        let both = Handle.bottomRight.drag(a, to: CGPoint(x: 70, y: 30), keepAspect: true, centered: true).bounds
        #expect(both == CGRect(x: -10, y: 0, width: 80, height: 40))
        #expect(both.midX == 30 && both.midY == 20)
    }

    @Test func lineEndsIgnoreTheBoxOptions() {
        let line = Annotation(kind: .line, start: .zero, end: CGPoint(x: 10, y: 10))
        #expect(Handle.end.drag(line, to: CGPoint(x: 30, y: 5), keepAspect: true, centered: true).end == CGPoint(x: 30, y: 5))
    }

    @Test func shiftSnapsLinesToFifteenDegrees() {
        let snapped = Geometry.snapAngle(from: .zero, to: CGPoint(x: 100, y: 30), degrees: 15)
        // atan(0.3) is 16.7°, the nearest step 15°; the length stays.
        #expect(abs(atan2(snapped.y, snapped.x) * 180 / .pi - 15) < 0.001)
        #expect(abs(Geometry.distance(.zero, snapped) - Geometry.distance(.zero, CGPoint(x: 100, y: 30))) < 0.001)
        #expect(Geometry.snapAngle(from: .zero, to: .zero, degrees: 15) == .zero)
        // The 45° helper still snaps to 45°.
        let diagonal = Geometry.snap45(from: .zero, to: CGPoint(x: 10, y: 8))
        #expect(abs(diagonal.x - diagonal.y) < 0.001)
    }

    @Test func mirroringMakesTheOtherCorner() {
        #expect(Geometry.mirrored(CGPoint(x: 30, y: 40), around: CGPoint(x: 20, y: 20)) == CGPoint(x: 10, y: 0))
    }

    @Test func cropModesShapeTheArea() {
        let size = CGSize(width: 200, height: 100)
        let from = CGPoint(x: 50, y: 20), to = CGPoint(x: 80, y: 60)
        #expect(Geometry.cropSelection(.crop, from: from, to: to, imageSize: size) == CGRect(x: 50, y: 20, width: 30, height: 40))
        // Cutting columns out spans the whole height, rows the whole width (upstream `CropContainer.HandleMouseMove`).
        #expect(Geometry.cropSelection(.vertical, from: from, to: to, imageSize: size) == CGRect(x: 50, y: 0, width: 30, height: 100))
        #expect(Geometry.cropSelection(.horizontal, from: from, to: to, imageSize: size) == CGRect(x: 0, y: 20, width: 200, height: 40))
        // Outside the image is cut off.
        #expect(Geometry.cropSelection(.crop, from: CGPoint(x: 150, y: 50), to: CGPoint(x: 300, y: 300), imageSize: size)
            == CGRect(x: 150, y: 50, width: 50, height: 50))
    }

    @Test func cropModeSymbolsExist() {
        for mode in CropMode.allCases {
            #expect(NSImage(systemSymbolName: mode.symbolName, accessibilityDescription: nil) != nil, "\(mode)")
        }
    }

    @Test func cropModesHaveTheirHandles() {
        #expect(CropMode.crop.handles == Handle.boxHandles)
        #expect(CropMode.vertical.handles == [.left, .right])
        #expect(CropMode.horizontal.handles == [.top, .bottom])
        let area = CGRect(x: 10, y: 10, width: 100, height: 50)
        #expect(CropMode.vertical.handle(at: CGPoint(x: 109, y: 36), of: area, reach: 4) == .right)
        #expect(CropMode.vertical.handle(at: CGPoint(x: 60, y: 10), of: area, reach: 4) == nil)
        // Dragging a handle of the area changes only its side.
        #expect(Handle.left.drag(area, to: CGPoint(x: 30, y: 0)) == CGRect(x: 30, y: 10, width: 80, height: 50))
    }

    @Test func freehandSpacingFollowsTheSensitivity() {
        // Upstream records a point at twice the sensitivity (3 by default), here in points of the capture.
        #expect(Geometry.freehandSpacing(sensitivity: 3, scale: 2) == 12)
        #expect(Geometry.freehandSpacing(sensitivity: 0, scale: 1) == 2)
        #expect(Geometry.freehandSpacing(sensitivity: 500, scale: 1) == 200)
        #expect(AppSettings().freehandSensitivity == 3)
    }
}
