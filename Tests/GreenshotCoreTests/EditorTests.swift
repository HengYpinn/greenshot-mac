// SPDX-License-Identifier: GPL-3.0-or-later

import CoreGraphics
import Foundation
import Testing
@testable import GreenshotCore

struct AnnotationTests {
    func rectangle(fill: RGBAColor = .clear) -> Annotation {
        var style = AnnotationStyle.defaults(for: .rectangle)
        style.fillColor = fill
        return Annotation(kind: .rectangle, start: CGPoint(x: 10, y: 10), end: CGPoint(x: 110, y: 60), style: style)
    }

    @Test func unfilledRectangleIsOnlyHitNearItsOutline() {
        let a = rectangle()
        #expect(a.hitTest(CGPoint(x: 11, y: 30), scale: 1, tolerance: 4))
        #expect(!a.hitTest(CGPoint(x: 60, y: 35), scale: 1, tolerance: 4))
        #expect(rectangle(fill: .yellow).hitTest(CGPoint(x: 60, y: 35), scale: 1, tolerance: 4))
    }

    @Test func lineIsHitNearTheSegment() {
        let line = Annotation(kind: .line, start: .zero, end: CGPoint(x: 100, y: 0))
        #expect(line.hitTest(CGPoint(x: 50, y: 3), scale: 1, tolerance: 4))
        #expect(!line.hitTest(CGPoint(x: 50, y: 20), scale: 1, tolerance: 4))
    }

    @Test func draggingACornerPastTheOppositeOneFlipsTheBox() {
        let a = rectangle()
        let resized = Handle.topLeft.drag(a, to: CGPoint(x: 200, y: 100))
        #expect(resized.bounds == CGRect(x: 110, y: 60, width: 90, height: 40))
        #expect(Handle.right.drag(a, to: CGPoint(x: 150, y: 0)).bounds == CGRect(x: 10, y: 10, width: 140, height: 50))
    }

    @Test func lineEndsAreDraggedSeparately() {
        let line = Annotation(kind: .arrow, start: .zero, end: CGPoint(x: 10, y: 10))
        #expect(Handle.handles(for: line) == [.start, .end])
        #expect(Handle.end.drag(line, to: CGPoint(x: 50, y: 0)).end == CGPoint(x: 50, y: 0))
    }

    @Test func movingFreehandMovesItsPath() {
        var a = Annotation(kind: .freehand, start: .zero, end: .zero, points: [.zero, CGPoint(x: 5, y: 5)])
        a.move(by: CGVector(dx: 10, dy: 1))
        #expect(a.points == [CGPoint(x: 10, y: 1), CGPoint(x: 15, y: 6)])
        #expect(a.bounds == CGRect(x: 10, y: 1, width: 5, height: 5))
    }
}

struct EditorDocumentTests {
    func document() -> EditorDocument {
        EditorDocument(image: TestImage.solid(width: 100, height: 80, .white), scale: 1, title: "test", isModified: false)
    }

    @Test func undoAndRedo() {
        let doc = document()
        let a = Annotation(kind: .rectangle, start: .zero, end: CGPoint(x: 10, y: 10))
        doc.change { doc.add(a) }
        #expect(doc.canUndo && doc.isModified)
        doc.undo()
        #expect(doc.annotations.isEmpty && doc.canRedo)
        doc.redo()
        #expect(doc.annotations == [a])
    }

    @Test func aChangeThatChangesNothingLeavesNoUndoStep() {
        let doc = document()
        doc.change {}
        #expect(!doc.canUndo && !doc.isModified)
    }

    @Test func aGestureIsOneUndoStep() {
        let doc = document()
        var a = Annotation(kind: .line, start: .zero, end: .zero)
        doc.beginChange()
        doc.add(a)
        for x in 1...5 {
            a.end = CGPoint(x: x, y: x)
            doc.update(a)
        }
        doc.endChange()
        doc.undo()
        #expect(doc.annotations.isEmpty && !doc.canUndo)
    }

    @Test func cropMovesElementsAlong() {
        let doc = document()
        doc.change { doc.add(Annotation(kind: .rectangle, start: CGPoint(x: 50, y: 50), end: CGPoint(x: 60, y: 60))) }
        doc.change { #expect(doc.crop(to: CGRect(x: 40, y: 40, width: 30, height: 30))) }
        #expect(doc.imageSize == CGSize(width: 30, height: 30))
        #expect(doc.annotations[0].start == CGPoint(x: 10, y: 10))
        doc.undo()
        #expect(doc.imageSize == CGSize(width: 100, height: 80))
        #expect(doc.annotations[0].start == CGPoint(x: 50, y: 50))
    }

    @Test func croppingToTheWholeImageDoesNothing() {
        let doc = document()
        #expect(!doc.crop(to: CGRect(x: -5, y: -5, width: 200, height: 200)))
    }

    @Test func countersRenumberWhenOneIsRemoved() {
        let doc = document()
        let counters = (0..<3).map { Annotation(kind: .counter, start: CGPoint(x: $0 * 20, y: 0), end: CGPoint(x: $0 * 20 + 10, y: 10)) }
        counters.forEach(doc.add)
        #expect(doc.counterNumber(for: counters[2].id) == 3)
        doc.remove(counters[0].id)
        #expect(doc.counterNumber(for: counters[2].id) == 2)
    }

    @Test func clickPicksTheFrontMostElement() {
        var style = AnnotationStyle.defaults(for: .rectangle)
        style.fillColor = .yellow
        let doc = document()
        let back = Annotation(kind: .rectangle, start: .zero, end: CGPoint(x: 50, y: 50), style: style)
        let front = Annotation(kind: .rectangle, start: CGPoint(x: 20, y: 20), end: CGPoint(x: 70, y: 70), style: style)
        doc.add(back)
        doc.add(front)
        #expect(doc.topmostAnnotation(at: CGPoint(x: 30, y: 30), tolerance: 4)?.id == front.id)
        doc.sendToBack(front.id)
        #expect(doc.topmostAnnotation(at: CGPoint(x: 30, y: 30), tolerance: 4)?.id == back.id)
    }

    @Test func savingClearsTheModifiedFlag() {
        let doc = document()
        doc.change { doc.add(Annotation(kind: .line, start: .zero, end: CGPoint(x: 5, y: 5))) }
        doc.markSaved()
        #expect(!doc.isModified)
    }
}

struct RendererTests {
    let white = TestImage.solid(width: 100, height: 100, .white)

    func render(_ annotations: [Annotation], on base: CGImage? = nil, scale: CGFloat = 1) throws -> CGImage {
        try #require(AnnotationRenderer.flatten(base: base ?? white, annotations: annotations, scale: scale))
    }

    @Test func unfilledRectangleDrawsItsOutlineOnly() throws {
        var style = AnnotationStyle.defaults(for: .rectangle)
        style.shadow = false
        let image = try render([Annotation(kind: .rectangle, start: CGPoint(x: 20, y: 20), end: CGPoint(x: 80, y: 60), style: style)])
        #expect(image.width == 100 && image.height == 100)
        #expect(TestImage.pixel(image, 50, 20).isClose(to: .red))
        #expect(TestImage.pixel(image, 50, 40) == .white)
        #expect(TestImage.pixel(image, 50, 10) == .white)
    }

    @Test func shadowFallsToTheBottomRight() throws {
        var style = AnnotationStyle.defaults(for: .rectangle)
        style.fillColor = .red
        let image = try render([Annotation(kind: .rectangle, start: CGPoint(x: 20, y: 20), end: CGPoint(x: 60, y: 60), style: style)], scale: 2)
        let belowRight = TestImage.pixel(image, 64, 64)
        #expect(belowRight.r < 250 && belowRight.r == belowRight.b)
        #expect(TestImage.pixel(image, 16, 16) == .white)
    }

    @Test func textHighlighterKeepsTheDarkerChannel() throws {
        let base = TestImage.make(width: 100, height: 100) { x, _ in x < 50 ? .white : .black }
        let highlight = Annotation(kind: .highlight, start: CGPoint(x: 0, y: 0), end: CGPoint(x: 100, y: 50))
        let image = try render([highlight], on: base)
        #expect(TestImage.pixel(image, 10, 10).isClose(to: .yellow))
        #expect(TestImage.pixel(image, 90, 10).isClose(to: .black))
        #expect(TestImage.pixel(image, 10, 90) == .white)
    }

    @Test func pixelateMakesBlocksAndLeavesTheRestAlone() throws {
        let checker = TestImage.make(width: 100, height: 100) { x, y in (x + y) % 2 == 0 ? .black : .white }
        var style = AnnotationStyle.defaults(for: .obfuscate)
        style.pixelSize = 4
        let image = try render([Annotation(kind: .obfuscate, start: CGPoint(x: 0, y: 0), end: CGPoint(x: 40, y: 40), style: style)], on: checker)
        #expect(TestImage.pixel(image, 9, 9) == TestImage.pixel(image, 10, 9))
        #expect(TestImage.pixel(image, 60, 60) != TestImage.pixel(image, 61, 60))
    }

    @Test func blurSoftensTheRegion() throws {
        let checker = TestImage.make(width: 100, height: 100) { x, y in (x + y) % 2 == 0 ? .black : .white }
        var style = AnnotationStyle.defaults(for: .obfuscate)
        style.obfuscateMode = .blur
        let image = try render([Annotation(kind: .obfuscate, start: .zero, end: CGPoint(x: 50, y: 50), style: style)], on: checker)
        let p = TestImage.pixel(image, 25, 25)
        #expect(p.r > 60 && p.r < 200)
    }

    @Test func grayscaleRemovesColor() throws {
        let base = TestImage.solid(width: 50, height: 50, .red)
        var style = AnnotationStyle.defaults(for: .highlight)
        style.highlightMode = .grayscale
        let image = try render([Annotation(kind: .highlight, start: .zero, end: CGPoint(x: 20, y: 20), style: style)], on: base)
        let p = TestImage.pixel(image, 10, 10)
        #expect(abs(Int(p.r) - Int(p.g)) < 8 && abs(Int(p.g) - Int(p.b)) < 8)
        #expect(TestImage.pixel(image, 40, 40).isClose(to: .red))
    }

    @Test func counterIsAFilledCircle() throws {
        let counter = Annotation(kind: .counter, start: CGPoint(x: 20, y: 20), end: CGPoint(x: 80, y: 80))
        let image = try render([counter])
        #expect(TestImage.pixel(image, 26, 50).isClose(to: RGBA(r: 139, g: 0, b: 0, a: 255)))
        #expect(TestImage.pixel(image, 21, 21) == .white)
    }

    @Test func textIsDrawnInItsBox() throws {
        var style = AnnotationStyle.defaults(for: .text)
        style.shadow = false
        style.fontSize = 30
        let text = Annotation(kind: .text, start: .zero, end: CGPoint(x: 100, y: 100), text: "W", style: style)
        let image = try render([text])
        var redPixels = 0
        for y in stride(from: 0, to: 100, by: 2) {
            for x in stride(from: 0, to: 100, by: 2) where TestImage.pixel(image, x, y).g < 100 { redPixels += 1 }
        }
        #expect(redPixels > 20)
    }

    @Test func arrowHeadReachesTheEndPoint() throws {
        var style = AnnotationStyle.defaults(for: .arrow)
        style.shadow = false
        let arrow = Annotation(kind: .arrow, start: CGPoint(x: 10, y: 50), end: CGPoint(x: 90, y: 50), style: style)
        let image = try render([arrow])
        #expect(TestImage.pixel(image, 87, 50).isClose(to: .red, tolerance: 40))
        #expect(TestImage.pixel(image, 50, 50).isClose(to: .red, tolerance: 40))
        #expect(TestImage.pixel(image, 50, 60) == .white)
    }

    @Test func hiddenElementIsLeftOut() throws {
        let line = Annotation(kind: .line, start: CGPoint(x: 0, y: 50), end: CGPoint(x: 100, y: 50))
        let image = try #require(AnnotationRenderer.flatten(base: white, annotations: [line], scale: 1, hiding: line.id))
        #expect(TestImage.pixel(image, 50, 50) == .white)
    }
}
