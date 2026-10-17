// Greenshot for Mac (Community) - an unofficial macOS port of Greenshot
// Copyright (C) 2026 Greenshot for Mac (Community) contributors
// SPDX-License-Identifier: GPL-3.0-or-later

import CoreGraphics
import Testing
@testable import GreenshotCore

struct CaptureSelectionTests {
    @Test func thePixelsUnderBothCornersBelongToTheSelection() {
        // UG "Region": the size shown is exactly the size of the capture.
        #expect(CaptureSelection.rect(from: CGPoint(x: 10, y: 10), to: CGPoint(x: 19, y: 19), scale: 1)
                == CGRect(x: 10, y: 10, width: 10, height: 10))
        // Any corners, any order.
        #expect(CaptureSelection.rect(from: CGPoint(x: 19.7, y: 19.2), to: CGPoint(x: 10.4, y: 10.9), scale: 1)
                == CGRect(x: 10, y: 10, width: 10, height: 10))
    }

    @Test func retinaUsesDevicePixels() {
        let rect = CaptureSelection.rect(from: CGPoint(x: 10, y: 10), to: CGPoint(x: 14.5, y: 12.25), scale: 2)
        #expect(rect == CGRect(x: 10, y: 10, width: 5, height: 2.5))
        #expect(CaptureSelection.pixelSize(of: rect, scale: 2) == (10, 5))
        // A click is one pixel: still too small to be a capture (the 3 point minimum).
        let click = CaptureSelection.rect(from: CGPoint(x: 100, y: 100), to: CGPoint(x: 100.2, y: 100.2), scale: 2)
        #expect(click.size == CGSize(width: 0.5, height: 0.5))
    }

    @Test func aSecondDisplayKeepsItsGrid() {
        let rect = CaptureSelection.rect(from: CGPoint(x: 1440, y: 0), to: CGPoint(x: 1449.5, y: 9.5), scale: 2)
        #expect(rect == CGRect(x: 1440, y: 0, width: 10, height: 10))
    }
}

struct CaptureSelectionLabelTests {
    private let display = CGRect(x: 0, y: 0, width: 1280, height: 800)
    private let label = CGSize(width: 20, height: 11)

    @Test func rulersAboveAndLeftOfTheSelection() throws {
        let selection = CGRect(x: 100, y: 100, width: 200, height: 100)
        let width = try #require(CaptureSelectionLabels.widthRuler(for: selection, labelSize: label, display: display))
        #expect(width.start == CGPoint(x: 100, y: 92.5) && width.end == CGPoint(x: 300, y: 92.5))
        #expect(width.label.midX == selection.midX && width.label.width == 24)
        let height = try #require(CaptureSelectionLabels.heightRuler(for: selection, labelSize: label, display: display))
        #expect(height.start == CGPoint(x: 92.5, y: 100) && height.end == CGPoint(x: 92.5, y: 200))
        #expect(height.label.maxX == 94.5 && height.label.midY == selection.midY)
    }

    @Test func rulersGoInsideAtTheEdgesOfTheDisplay() throws {
        let selection = CGRect(x: 0, y: 0, width: 400, height: 300)
        let width = try #require(CaptureSelectionLabels.widthRuler(for: selection, labelSize: label, display: display))
        #expect(width.start.y == 8.5)
        let height = try #require(CaptureSelectionLabels.heightRuler(for: selection, labelSize: label, display: display))
        #expect(height.start.x == 8.5 && height.label.minX == 6.5)
    }

    @Test func noRulerWithoutRoomForItsLabel() {
        let narrow = CGRect(x: 100, y: 100, width: 29, height: 20)
        #expect(CaptureSelectionLabels.widthRuler(for: narrow, labelSize: label, display: display) == nil)
        #expect(CaptureSelectionLabels.heightRuler(for: narrow, labelSize: label, display: display) == nil)
        #expect(CaptureSelectionLabels.widthRuler(for: narrow.insetBy(dx: -1, dy: 0), labelSize: label, display: display) != nil)
    }

    @Test func theSizeIsAsLargeAsFitsUpToTwentyPoints() {
        let measured = CGSize(width: 60, height: 15)
        #expect(CaptureSelectionLabels.sizeFontSize(for: CGSize(width: 1000, height: 1000), measured: measured) == 20)
        #expect(CaptureSelectionLabels.sizeFontSize(for: CGSize(width: 120, height: 30), measured: measured) == 12)
        #expect(CaptureSelectionLabels.sizeFontSize(for: CGSize(width: 60, height: 30), measured: measured) == 6)
        #expect(CaptureSelectionLabels.sizeFontSize(for: CGSize(width: 10, height: 30), measured: measured) == nil)
    }
}

struct CaptureZoomerTests {
    @Test func aFifthOfTheSmallerSideInStepsOfFour() {
        #expect(CaptureZoomerPlacement.size(for: CGRect(x: 0, y: 0, width: 1280, height: 800)) == 160)
        #expect(CaptureZoomerPlacement.size(for: CGRect(x: 0, y: 0, width: 1512, height: 982)) == 196)
        #expect(CaptureZoomerPlacement.size(for: CGRect(x: 0, y: 0, width: 1920, height: 1080)) == 216)
        #expect(CaptureZoomerPlacement.size(for: .zero) == CaptureZoomerPlacement.sourcePixels)
    }

    @Test func showsTwentyFivePixelsWithTheOneUnderTheMouseInTheMiddle() {
        let geometry = CaptureZoomerGeometry(zoom: CGRect(x: 0, y: 0, width: 200, height: 200), cursorPixel: CGPoint(x: 100, y: 50))
        #expect(geometry.magnification == 8)
        #expect(geometry.source == CGRect(x: 88, y: 38, width: 25, height: 25))
        let center = geometry.frame(ofPixels: CGRect(x: 100, y: 50, width: 1, height: 1))
        #expect(center.midX == 100 && center.midY == 100 && center.width == 8)
        // The selection's edges, so you see whether a pixel is in or out.
        #expect(geometry.frame(ofPixels: CGRect(x: 90, y: 40, width: 11, height: 11)) == CGRect(x: 16, y: 16, width: 88, height: 88))
    }

    @Test func fixedSizeSnapsLikeUpstream() {
        #expect(FixedSizeCapture.snapDistance == 8)
    }
}
