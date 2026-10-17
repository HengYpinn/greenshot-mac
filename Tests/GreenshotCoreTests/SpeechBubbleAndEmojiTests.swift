// SPDX-License-Identifier: GPL-3.0-or-later

import CoreGraphics
import Foundation
import Testing
@testable import GreenshotCore

struct SpeechBubbleTests {
    /// A 100 × 60 bubble whose tail points straight down from its middle (70, 50) to (70, 150).
    func bubble(text: String = "", shadow: Bool = false) -> Annotation {
        var style = AnnotationStyle.defaults(for: .speechBubble)
        style.shadow = shadow
        return Annotation(kind: .speechBubble, start: CGPoint(x: 20, y: 20), end: CGPoint(x: 120, y: 80), text: text,
                          tail: CGPoint(x: 70, y: 150), style: style)
    }

    @Test func defaultsAreUpstreams() {
        let style = AnnotationStyle.defaults(for: .speechBubble)
        #expect(style.lineColor == .blue && style.fillColor == .white && style.lineWidth == 2)
        #expect(style.bold && !style.italic && !style.shadow && style.fontSize == 20)
        #expect(AnnotationKind.speechBubble.hasEditableText && AnnotationKind.text.hasEditableText)
        #expect(!AnnotationKind.emoji.hasEditableText)
    }

    @Test func tailTipIsAHandleThatMovesOnlyTheTip() {
        let a = bubble()
        #expect(Handle.handles(for: a) == Handle.boxHandles + [.tail])
        #expect(Handle.tail.position(in: a) == CGPoint(x: 70, y: 150))
        let dragged = Handle.tail.drag(a, to: CGPoint(x: 200, y: 10))
        #expect(dragged.tail == CGPoint(x: 200, y: 10))
        #expect(dragged.bounds == a.bounds)
    }

    @Test func resizingTheBoxLeavesTheTipWhereItIs() {
        let resized = Handle.bottomRight.drag(bubble(), to: CGPoint(x: 160, y: 100))
        #expect(resized.bounds == CGRect(x: 20, y: 20, width: 140, height: 80))
        #expect(resized.tailTip == CGPoint(x: 70, y: 150))
    }

    @Test func movingTheBubbleMovesItsTail() {
        var a = bubble()
        a.move(by: CGVector(dx: 5, dy: -10))
        #expect(a.tail == CGPoint(x: 75, y: 140))
    }

    @Test func withoutATailItPointsBelowTheBottomLeftCorner() {
        let a = Annotation(kind: .speechBubble, start: CGPoint(x: 100, y: 100), end: CGPoint(x: 200, y: 160))
        #expect(a.tail == nil)
        #expect(a.tailTip == CGPoint(x: 80, y: 185))
    }

    @Test func theTailIsClickableOutsideTheBox() {
        let a = bubble()
        #expect(a.hitTest(CGPoint(x: 70, y: 120), scale: 1, tolerance: 4))
        #expect(a.hitTest(CGPoint(x: 70, y: 152), scale: 1, tolerance: 4))
        #expect(a.hitTest(CGPoint(x: 50, y: 50), scale: 1, tolerance: 4))
        #expect(!a.hitTest(CGPoint(x: 30, y: 120), scale: 1, tolerance: 4))
        #expect(!a.hitTest(CGPoint(x: 200, y: 50), scale: 1, tolerance: 4))
    }

    let black = TestImage.solid(width: 160, height: 170, .black)

    func render(_ annotations: [Annotation], hiding: UUID? = nil) throws -> CGImage {
        try #require(AnnotationRenderer.flatten(base: black, annotations: annotations, scale: 1, hiding: hiding))
    }

    @Test func boxAndTailAreOneFilledShapeWithAnOutline() throws {
        let image = try render([bubble()])
        #expect(TestImage.pixel(image, 70, 50) == .white)
        #expect(TestImage.pixel(image, 40, 80).isClose(to: .blue, tolerance: 40))
        #expect(TestImage.pixel(image, 20, 50).isClose(to: .blue, tolerance: 40))
        // No outline where the tail leaves the box.
        #expect(TestImage.pixel(image, 70, 80) == .white)
        // Inside the tail, below the box; next to it nothing.
        #expect(TestImage.pixel(image, 70, 100) == .white)
        #expect(TestImage.pixel(image, 60, 100) == .black)
        #expect(TestImage.pixel(image, 5, 5) == .black)
    }

    @Test func smallBubblesGetSmallerCorners() throws {
        let image = try render([bubble()])
        // The corner is rounded: its very tip is outside the shape.
        #expect(TestImage.pixel(image, 20, 20) == .black)
        // Too small for rounded corners inside a 4 px line: a plain rectangle, like upstream.
        let tiny = Annotation(kind: .speechBubble, start: CGPoint(x: 20, y: 20), end: CGPoint(x: 26, y: 26))
        #expect(AnnotationRenderer.speechBubbleBody(tiny, lineWidth: 4, scale: 1) == CGPath(rect: tiny.bounds, transform: nil))
    }

    func bluePixelsInside(_ image: CGImage) -> Int {
        var count = 0
        for y in 30..<70 {
            for x in 30..<110 where TestImage.pixel(image, x, y).r < 128 { count += 1 }
        }
        return count
    }

    @Test func theTextIsDrawnInsideInTheLineColor() throws {
        let image = try render([bubble(text: "Hi")])
        #expect(bluePixelsInside(image) > 20)
    }

    @Test func whileItsTextIsEditedTheBubbleIsDrawnWithoutIt() throws {
        let a = bubble(text: "Hi")
        let image = try render([a], hiding: a.id)
        #expect(TestImage.pixel(image, 40, 80).isClose(to: .blue, tolerance: 40))
        #expect(bluePixelsInside(image) == 0)
    }

    @Test func theTextStaysInsideTheOutline() {
        let rect = AnnotationRenderer.textRect(for: bubble(), scale: 2)
        // 2 pt padding plus half the 2 pt line, in pixels.
        #expect(rect == CGRect(x: 26, y: 26, width: 88, height: 48))
    }
}

struct EmojiTests {
    func emoji(_ side: CGFloat = 64) -> Annotation {
        Annotation(kind: .emoji, start: CGPoint(x: 10, y: 10), end: CGPoint(x: 10 + side, y: 10 + side), text: "🙂")
    }

    @Test func itIsResizedAtTheCornersAndStaysSquare() {
        let a = emoji()
        #expect(Handle.handles(for: a) == Handle.cornerHandles)
        let resized = Handle.bottomRight.drag(a, to: CGPoint(x: 150, y: 90))
        #expect(resized.bounds == CGRect(x: 10, y: 10, width: 140, height: 140))
        let fromTopLeft = Handle.topLeft.drag(a, to: CGPoint(x: 50, y: 60))
        #expect(fromTopLeft.bounds == CGRect(x: 50, y: 50, width: 24, height: 24))
    }

    @Test func theGlyphFillsItsBoxAndStaysInside() throws {
        let white = TestImage.solid(width: 100, height: 100, .white)
        let image = try #require(AnnotationRenderer.flatten(base: white, annotations: [emoji()], scale: 1))
        var minX = 100, minY = 100, maxX = 0, maxY = 0
        for y in 0..<100 {
            for x in 0..<100 where !TestImage.pixel(image, x, y).isClose(to: .white, tolerance: 10) {
                minX = min(minX, x); maxX = max(maxX, x)
                minY = min(minY, y); maxY = max(maxY, y)
            }
        }
        #expect(minX >= 10 && minY >= 10 && maxX < 74 && maxY < 74)
        #expect(maxX - minX > 52 && maxY - minY > 52)
    }

    @Test func clickingAnywhereInTheBoxHitsIt() {
        #expect(emoji().hitTest(CGPoint(x: 70, y: 70), scale: 1, tolerance: 4))
        #expect(!emoji().hitTest(CGPoint(x: 90, y: 90), scale: 1, tolerance: 4))
    }
}
