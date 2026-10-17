// Greenshot for Mac (Community) - an unofficial macOS port of Greenshot
// Copyright (C) 2026 Greenshot for Mac (Community) contributors
// Based on Greenshot, Copyright (C) 2007-2026 Thomas Braun, Jens Klingen, Robin Krom
// SPDX-License-Identifier: GPL-3.0-or-later

import CoreGraphics
import Foundation
import Testing
@testable import GreenshotCore

/// The element context menu's Expand capture and move outside, Stretch, Dock to edge and Reset size (upstream
/// `DrawableContainerList.AddContextMenuItems`).
struct ElementLayoutTests {
    func document(_ width: Int = 200, _ height: Int = 100, scale: CGFloat = 1) -> EditorDocument {
        EditorDocument(image: TestImage.solid(width: width, height: height, .white), scale: scale, title: "t", isModified: false)
    }

    func rectangle(_ x: CGFloat, _ y: CGFloat, _ w: CGFloat, _ h: CGFloat) -> Annotation {
        Annotation(kind: .rectangle, start: CGPoint(x: x, y: y), end: CGPoint(x: x + w, y: y + h))
    }

    @Test func dockingMovesAgainstEachEdge() throws {
        let doc = document()
        let a = rectangle(50, 30, 20, 10)
        doc.add(a)
        let expected: [(ElementEdge, CGRect)] = [(.left, CGRect(x: 0, y: 30, width: 20, height: 10)),
                                                 (.right, CGRect(x: 180, y: 30, width: 20, height: 10)),
                                                 (.top, CGRect(x: 50, y: 0, width: 20, height: 10)),
                                                 (.bottom, CGRect(x: 50, y: 90, width: 20, height: 10))]
        for (edge, rect) in expected {
            doc.update(a)
            doc.dock([a.id], to: edge)
            #expect(try #require(doc.annotation(a.id)).bounds == rect, "\(edge)")
        }
    }

    @Test func stretchingMakesItAsWideOrHighAsTheImage() throws {
        let doc = document()
        let a = rectangle(50, 30, 20, 10)
        let line = Annotation(kind: .line, start: CGPoint(x: 60, y: 10), end: CGPoint(x: 60, y: 40))
        let freehand = Annotation(kind: .freehand, start: .zero, end: .zero, points: [CGPoint(x: 10, y: 10), CGPoint(x: 30, y: 20)])
        doc.add([a, line, freehand])
        doc.stretch([a.id, line.id, freehand.id], width: true)
        #expect(try #require(doc.annotation(a.id)).bounds == CGRect(x: 0, y: 30, width: 200, height: 10))
        // A vertical line has no width: it becomes a diagonal across the image, like upstream setting `Width`.
        let stretchedLine = try #require(doc.annotation(line.id))
        #expect(stretchedLine.start == CGPoint(x: 0, y: 10) && stretchedLine.end == CGPoint(x: 200, y: 40))
        #expect(try #require(doc.annotation(freehand.id)).points == [CGPoint(x: 0, y: 10), CGPoint(x: 200, y: 20)])
        doc.stretch([a.id], width: false)
        #expect(try #require(doc.annotation(a.id)).bounds == CGRect(x: 0, y: 0, width: 200, height: 100))
    }

    @Test func pushingOutGrowsTheCanvasAndPutsTheElementInTheNewStrip() throws {
        for edge in ElementEdge.allCases {
            let doc = document()
            let a = rectangle(50, 30, 20, 10)
            let other = rectangle(10, 10, 5, 5)
            doc.add([a, other])
            var done = false
            doc.change { done = doc.pushOut(a.id, to: edge) }
            #expect(done)
            let moved = try #require(doc.annotation(a.id)).bounds
            let otherNow = try #require(doc.annotation(other.id)).bounds
            switch edge {
            case .right:
                #expect(doc.imageSize == CGSize(width: 220, height: 100))
                #expect(moved == CGRect(x: 200, y: 30, width: 20, height: 10))
                #expect(otherNow.origin == CGPoint(x: 10, y: 10))
            case .left:
                #expect(doc.imageSize == CGSize(width: 220, height: 100))
                #expect(moved == CGRect(x: 0, y: 30, width: 20, height: 10))
                // The rest of the image moved right with the canvas.
                #expect(otherNow.origin == CGPoint(x: 30, y: 10))
            case .top:
                #expect(doc.imageSize == CGSize(width: 200, height: 110))
                #expect(moved == CGRect(x: 50, y: 0, width: 20, height: 10))
                #expect(otherNow.origin == CGPoint(x: 10, y: 20))
            case .bottom:
                #expect(doc.imageSize == CGSize(width: 200, height: 110))
                #expect(moved == CGRect(x: 50, y: 100, width: 20, height: 10))
            }
            // One undo step brings the image and the element back.
            doc.undo()
            #expect(doc.imageSize == CGSize(width: 200, height: 100))
            #expect(try #require(doc.annotation(a.id)).bounds == CGRect(x: 50, y: 30, width: 20, height: 10))
            #expect(!doc.canUndo)
        }
    }

    @Test func aLineWithoutHeightCannotBePushedOutAtTheTop() {
        let doc = document()
        let line = Annotation(kind: .line, start: CGPoint(x: 10, y: 50), end: CGPoint(x: 90, y: 50))
        doc.add(line)
        #expect(!doc.pushOut(line.id, to: .top))
        #expect(doc.imageSize == CGSize(width: 200, height: 100))
    }

    @Test func resetSizeGivesAnImageElementItsPictureSize() throws {
        // A 20 × 10 pixel picture at 1× in a 2× document is 40 × 20 pixels there; at 2× it stays 20 × 10.
        let picture = TestImage.solid(width: 20, height: 10, .red)
        let oneX = try #require(Annotation.picture(picture, pictureScale: 1, at: CGPoint(x: 5, y: 5), documentScale: 2))
        let twoX = try #require(Annotation.picture(picture, pictureScale: 2, at: CGPoint(x: 5, y: 5), documentScale: 2))
        #expect(oneX.defaultSize(documentScale: 2) == CGSize(width: 40, height: 20))
        #expect(twoX.defaultSize(documentScale: 2) == CGSize(width: 20, height: 10))

        let doc = document(scale: 2)
        var squeezed = oneX
        squeezed.end = CGPoint(x: 100, y: 90)
        let shape = rectangle(0, 0, 30, 30)
        doc.add([squeezed, shape])
        #expect(doc.canResetSize([squeezed.id, shape.id]))
        #expect(!doc.canResetSize([shape.id]))
        doc.resetSize([squeezed.id, shape.id])
        #expect(try #require(doc.annotation(squeezed.id)).bounds == CGRect(x: 5, y: 5, width: 40, height: 20))
        #expect(try #require(doc.annotation(shape.id)).bounds == CGRect(x: 0, y: 0, width: 30, height: 30))
    }

    @Test func movingKeepsATailAlongButResizingDoesNot() {
        let bubble = Annotation(kind: .speechBubble, start: .zero, end: CGPoint(x: 40, y: 20), tail: CGPoint(x: 60, y: 60))
        #expect(bubble.withBounds(CGRect(x: 10, y: 10, width: 40, height: 20)).tail == CGPoint(x: 70, y: 70))
        #expect(bubble.withBounds(CGRect(x: 0, y: 0, width: 80, height: 20)).tail == CGPoint(x: 60, y: 60))
    }
}
