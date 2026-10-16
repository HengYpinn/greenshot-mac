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
