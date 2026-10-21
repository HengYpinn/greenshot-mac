// SPDX-License-Identifier: GPL-3.0-or-later

import CoreGraphics
import Foundation
import Testing
@testable import GreenshotCore

struct ImageOperationsTests {
    let white = TestImage.solid(width: 40, height: 30, .white)

    func document(_ image: CGImage? = nil, scale: CGFloat = 1) -> EditorDocument {
        EditorDocument(image: image ?? white, scale: scale, title: "test", isModified: false)
    }

    // MARK: Resize

    @Test func resizeScalesTheImageAndTheElements() {
        let doc = document()
        let box = Annotation(kind: .rectangle, start: CGPoint(x: 4, y: 3), end: CGPoint(x: 20, y: 15))
        let scribble = Annotation(kind: .freehand, start: .zero, end: .zero, points: [CGPoint(x: 10, y: 10), CGPoint(x: 30, y: 20)])
        let bubble = Annotation(kind: .speechBubble, start: CGPoint(x: 2, y: 2), end: CGPoint(x: 10, y: 10), tail: CGPoint(x: 30, y: 25))
        doc.change {
            doc.add(box)
            doc.add(scribble)
            doc.add(bubble)
        }
        doc.change { #expect(doc.resizeImage(to: CGSize(width: 80, height: 15))) }
        #expect(doc.imageSize == CGSize(width: 80, height: 15))
        #expect(doc.annotations[0].start == CGPoint(x: 8, y: 1.5) && doc.annotations[0].end == CGPoint(x: 40, y: 7.5))
        #expect(doc.annotations[1].points == [CGPoint(x: 20, y: 5), CGPoint(x: 60, y: 10)])
        #expect(doc.annotations[2].tail == CGPoint(x: 60, y: 12.5))
        // The style (line width, font size) stays.
        #expect(doc.annotations[0].style == box.style)
        doc.undo()
        #expect(doc.imageSize == CGSize(width: 40, height: 30) && doc.annotations[0] == box)
    }

    @Test func resizeToTheSameSizeDoesNothing() {
        let doc = document()
        doc.change { #expect(!doc.resizeImage(to: CGSize(width: 40, height: 30))) }
        #expect(!doc.canUndo)
    }

    @Test func resizeKeepsTheColors() throws {
        let image = try #require(ImageOperations.resize(TestImage.solid(width: 10, height: 10, .red), to: CGSize(width: 25, height: 5)))
        #expect(image.width == 25 && image.height == 5)
        #expect(TestImage.pixel(image, 12, 2) == .red)
    }
}

extension ImageOperationsTests {
    // MARK: Rotate

    /// A 3 × 2 image, red in the top left corner, blue in the bottom right.
    var marked: CGImage {
        TestImage.make(width: 3, height: 2) { x, y in
            if x == 0 && y == 0 { return .red }
            if x == 2 && y == 1 { return .blue }
            return .white
        }
    }

    @Test func rotateClockwiseMovesTheTopLeftToTheTopRight() throws {
        let image = try #require(ImageOperations.rotate(marked, clockwise: true))
        #expect(image.width == 2 && image.height == 3)
        #expect(TestImage.pixel(image, 1, 0) == .red)
        #expect(TestImage.pixel(image, 0, 2) == .blue)
    }

    @Test func rotateCounterClockwiseMovesTheTopLeftToTheBottomLeft() throws {
        let image = try #require(ImageOperations.rotate(marked, clockwise: false))
        #expect(image.width == 2 && image.height == 3)
        #expect(TestImage.pixel(image, 0, 2) == .red)
        #expect(TestImage.pixel(image, 1, 0) == .blue)
    }

    @Test func rotatingFourTimesRestoresTheImageAndTheElements() {
        let doc = document(marked)
        let arrow = Annotation(kind: .arrow, start: CGPoint(x: 0.5, y: 0.5), end: CGPoint(x: 2.5, y: 1.5))
        doc.change { doc.add(arrow) }
        doc.change { #expect(doc.rotateImage(clockwise: true)) }
        #expect(doc.imageSize == CGSize(width: 2, height: 3))
        // The arrow turns with the image: the top left corner goes to the top right.
        #expect(doc.annotations[0].start == CGPoint(x: 1.5, y: 0.5) && doc.annotations[0].end == CGPoint(x: 0.5, y: 2.5))
        for _ in 0..<3 { doc.change { doc.rotateImage(clockwise: true) } }
        #expect(doc.imageSize == CGSize(width: 3, height: 2))
        #expect(doc.annotations[0] == arrow)
        #expect(TestImage.pixel(doc.baseImage, 0, 0) == .red && TestImage.pixel(doc.baseImage, 2, 1) == .blue)
        doc.change { doc.rotateImage(clockwise: false) }
        doc.change { doc.rotateImage(clockwise: true) }
        #expect(doc.annotations[0] == arrow)
    }
}

extension ImageOperationsTests {
    // MARK: Canvas

    @Test func enlargeAndShrinkCanvasIsARoundTrip() {
        // An image whose own edge has no border of one color: red and blue quarters, so no corner color frames it.
        let quarters = TestImage.make(width: 40, height: 30) { x, y in (x < 20) == (y < 15) ? .red : .blue }
        let doc = document(quarters, scale: 2)
        // Without a shadow: Shrink Canvas keeps what the elements draw, a shadow included.
        let box = Annotation(kind: .rectangle, start: CGPoint(x: 4, y: 3), end: CGPoint(x: 20, y: 15),
                             style: AnnotationStyle(shadow: false))
        doc.change { doc.add(box) }
        doc.change { #expect(doc.enlargeCanvas()) }
        // 25 pt are 50 pixels at 2 pixels per point.
        #expect(doc.imageSize == CGSize(width: 140, height: 130))
        #expect(doc.annotations[0].start == CGPoint(x: 54, y: 53))
        #expect(TestImage.pixel(doc.baseImage, 10, 10).a == 0)
        #expect(TestImage.pixel(doc.baseImage, 60, 60) == .red)
        doc.change { #expect(doc.shrinkCanvas()) }
        #expect(doc.imageSize == CGSize(width: 40, height: 30))
        #expect(doc.annotations[0] == box)
        // Nothing more to shrink.
        doc.change { #expect(!doc.shrinkCanvas()) }
    }

    @Test func shrinkCanvasCutsABorderOfOneColor() {
        // Upstream shrinks like auto crop: a white border (also an almost white one) goes, the content stays.
        let framed = TestImage.make(width: 40, height: 30) { x, y in
            if (10..<30).contains(x) && (5..<20).contains(y) { return .blue }
            return x == 35 ? RGBA(r: 250, g: 250, b: 250, a: 255) : .white
        }
        let doc = document(framed)
        doc.change { #expect(doc.shrinkCanvas()) }
        #expect(doc.imageSize == CGSize(width: 20, height: 15))
        #expect(TestImage.pixel(doc.baseImage, 0, 0) == .blue)
        // A stricter difference keeps the almost white column (x 35) as content.
        let strict = document(framed)
        strict.change { #expect(strict.shrinkCanvas(difference: 2)) }
        #expect(strict.imageSize == CGSize(width: 26, height: 30))
    }

    @Test func shrinkCanvasKeepsElementsOnTheMargin() {
        let doc = document()
        doc.change { doc.enlargeCanvas() }
        let line = Annotation(kind: .line, start: CGPoint(x: 5, y: 45), end: CGPoint(x: 30, y: 45),
                              style: AnnotationStyle(lineColor: .blue, lineWidth: 2, shadow: false))
        doc.change { doc.add(line) }
        doc.change { #expect(doc.shrinkCanvas()) }
        // The line sticks out 20 pixels to the left of the image.
        #expect(doc.imageSize.width > 60 && doc.imageSize.width < 70)
    }

    @Test func resizeCanvasWithABackgroundColorAndNegativeInsets() throws {
        let result = try #require(ImageOperations.resizeCanvas(white, left: 5, right: -10, top: 0, bottom: 2,
                                                               background: CGColor(srgbRed: 1, green: 0, blue: 0, alpha: 1)))
        #expect(result.image.width == 35 && result.image.height == 32)
        #expect(result.offset == CGVector(dx: 5, dy: 0))
        #expect(TestImage.pixel(result.image, 2, 10) == .red)
        #expect(TestImage.pixel(result.image, 20, 31) == .red)
        #expect(TestImage.pixel(result.image, 20, 10) == .white)
    }

    /// A recipe can ask for any size: NaN, infinite and beyond `maxSide` fail instead of stopping the app in `Int()`;
    /// less than a pixel is one, as before.
    @Test func resizeToSizesNoImageCanHave() throws {
        let image = TestImage.solid(width: 4, height: 4, .white)
        for side in [CGFloat.nan, .infinity, 1e300, 65536] {
            #expect(ImageOperations.resize(image, to: CGSize(width: side, height: 4)) == nil)
            #expect(ImageOperations.resize(image, to: CGSize(width: 4, height: side)) == nil)
        }
        let thin = try #require(ImageOperations.resize(image, to: CGSize(width: -1e30, height: 4)))
        #expect(thin.width == 1)
    }

    /// Margins whose sum overflows Int, or makes a side beyond `maxSide`, fail.
    @Test func resizeCanvasBeyondAnyImage() throws {
        let image = TestImage.solid(width: 4, height: 4, .white)
        #expect(ImageOperations.resizeCanvas(image, left: .max / 2, right: .max / 2, top: 0, bottom: 0) == nil)
        #expect(ImageOperations.resizeCanvas(image, left: 0, right: 0, top: .min, bottom: -1) == nil)
        #expect(ImageOperations.resizeCanvas(image, left: 65532, right: 0, top: 0, bottom: 0) == nil)
        let widest = try #require(ImageOperations.resizeCanvas(image, left: 65531, right: 0, top: 0, bottom: 0))
        #expect(widest.image.width == 65535)
    }

    @Test func clearBackgroundMakesThePixelsTransparent() {
        let doc = document()
        let box = Annotation(kind: .rectangle, start: CGPoint(x: 4, y: 3), end: CGPoint(x: 20, y: 15))
        doc.change { doc.add(box) }
        doc.change { #expect(doc.clearImage()) }
        #expect(doc.imageSize == CGSize(width: 40, height: 30) && doc.annotations == [box])
        #expect(TestImage.pixel(doc.baseImage, 30, 25).a == 0)
        doc.undo()
        #expect(TestImage.pixel(doc.baseImage, 30, 25) == .white)
    }

    @Test func removeTransparencyMakesThemWhite() {
        let image = TestImage.make(width: 4, height: 1) { x, _ in
            [RGBA.red, RGBA(r: 0, g: 0, b: 0, a: 0), RGBA(r: 0, g: 0, b: 128, a: 128), .blue][x]
        }
        #expect(ImageOperations.hasTransparency(image))
        #expect(!ImageOperations.hasTransparency(white))
        let doc = document(image)
        doc.change { #expect(doc.removeTransparency()) }
        #expect(TestImage.pixel(doc.baseImage, 0, 0) == .red)
        #expect(TestImage.pixel(doc.baseImage, 1, 0) == .white)
        #expect(TestImage.pixel(doc.baseImage, 2, 0).isClose(to: RGBA(r: 127, g: 127, b: 255, a: 255)))
        #expect(!ImageOperations.hasTransparency(doc.baseImage))
        doc.change { #expect(!doc.removeTransparency()) }
    }
}
