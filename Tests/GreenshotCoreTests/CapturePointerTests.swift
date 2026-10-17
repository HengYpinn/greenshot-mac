// Greenshot for Mac (Community) - an unofficial macOS port of Greenshot
// Copyright (C) 2026 Greenshot for Mac (Community) contributors
// SPDX-License-Identifier: GPL-3.0-or-later

import CoreGraphics
import Testing
@testable import GreenshotCore

/// The mouse pointer on its own (CAP-019): where it goes in the capture and whether it was drawn at all.
struct CapturePointerTests {
    private func screen(_ id: UInt32, x: CGFloat, width: CGFloat = 100, height: CGFloat = 80, scale: CGFloat) -> FrozenScreen {
        let pixelWidth = Int(width * scale)
        let pixelHeight = Int(height * scale)
        return FrozenScreen(displayID: id, frame: CGRect(x: x, y: 0, width: width, height: height), scale: scale,
                            image: TestImage.solid(width: pixelWidth, height: pixelHeight, .white))
    }

    @Test func theHotSpotLandsOnTheMouse() {
        let origin = CapturedPointer.origin(mouse: CGPoint(x: 50, y: 30), hotSpot: CGPoint(x: 4, y: 2),
                                            imageTopLeft: CGPoint(x: 40, y: 20), scale: 2)
        #expect(origin == CGPoint(x: 16, y: 18))
    }

    @Test func oneDisplayCropsOnItsPixelGrid() {
        let display = screen(1, x: 0, scale: 2)
        // 10.3 points is pixel 20.6: the crop starts at pixel 20, so the mouse at 30 points (pixel 60) is pixel 40 of it.
        let rect = CGRect(x: 10.3, y: 10.3, width: 40, height: 40)
        let origin = CapturedPointer.origin(mouse: CGPoint(x: 30, y: 30), hotSpot: CGPoint(x: 6, y: 4), rect: rect,
                                            screens: [display], scale: 2)
        #expect(origin == CGPoint(x: 34, y: 36))
    }

    @Test func severalDisplaysStartAtTheRectangle() {
        let left = screen(1, x: 0, scale: 1)
        let right = screen(2, x: 100, scale: 2)
        let rect = CGRect(x: 50, y: 0, width: 100, height: 80)
        let origin = CapturedPointer.origin(mouse: CGPoint(x: 120, y: 10), hotSpot: CGPoint(x: 2, y: 2), rect: rect,
                                            screens: [left, right], scale: 2)
        #expect(origin == CGPoint(x: 138, y: 18))
    }

    @Test func aPointerOutsideTheCaptureIsLeftOut() {
        let picture = TestImage.solid(width: 10, height: 10, .black)
        let inside = CapturedPointer(image: picture, scale: 1, hotSpot: .zero, origin: CGPoint(x: -5, y: -5))
        let outside = CapturedPointer(image: picture, scale: 1, hotSpot: .zero, origin: CGPoint(x: 40, y: 3))
        #expect(inside.touches(width: 40, height: 30))
        #expect(!outside.touches(width: 40, height: 30))
    }

    @Test func aHiddenPointerIsNotDrawn() {
        let plain = TestImage.solid(width: 40, height: 30, .white)
        let same = TestImage.solid(width: 40, height: 30, .white)
        let withPointer = TestImage.make(width: 40, height: 30) { x, y in x == 12 && y == 8 ? .black : .white }
        let around = CGRect(x: 10, y: 5, width: 8, height: 8)
        let elsewhere = CGRect(x: 25, y: 15, width: 8, height: 8)
        #expect(!CapturedPointer.isDrawn(plain: plain, withPointer: same, in: around))
        #expect(CapturedPointer.isDrawn(plain: plain, withPointer: withPointer, in: around))
        #expect(!CapturedPointer.isDrawn(plain: plain, withPointer: withPointer, in: elsewhere))
    }
}
