// Greenshot for Mac (Community) - an unofficial macOS port of Greenshot
// Copyright (C) 2026 Greenshot for Mac (Community) contributors
// Based on Greenshot, Copyright (C) 2007-2026 Thomas Braun, Jens Klingen, Robin Krom
// SPDX-License-Identifier: GPL-3.0-or-later

import CoreGraphics
import Foundation
import Testing
@testable import GreenshotCore

/// The element clipboard and the operations on several selected elements.
struct ElementTransferTests {
    func box(_ x: CGFloat, _ y: CGFloat, _ w: CGFloat = 20, _ h: CGFloat = 10, kind: AnnotationKind = .rectangle) -> Annotation {
        Annotation(kind: kind, start: CGPoint(x: x, y: y), end: CGPoint(x: x + w, y: y + h))
    }

    @Test func roundTripsThroughJSON() throws {
        var text = Annotation(kind: .speechBubble, start: .zero, end: CGPoint(x: 50, y: 30), text: "Hi", tail: CGPoint(x: 80, y: 80))
        text.style.bold = false
        let freehand = Annotation(kind: .freehand, start: .zero, end: .zero, points: [.zero, CGPoint(x: 3, y: 4)])
        let transfer = ElementTransfer(elements: [text, freehand], scale: 2, sourceDocument: UUID())
        let decoded = try #require(ElementTransfer.decode(try transfer.encoded()))
        #expect(decoded == transfer)
    }

    @Test func rejectsOtherData() {
        #expect(ElementTransfer.decode(Data("not json".utf8)) == nil)
        #expect(ElementTransfer.decode(Data("{}".utf8)) == nil)
    }

    @Test func pastedElementsGetNewIDs() {
        let original = box(10, 10)
        let pasted = ElementTransfer(elements: [original], scale: 1).placed(in: CGSize(width: 100, height: 100), scale: 1, documentID: UUID())
        #expect(pasted.count == 1)
        #expect(pasted[0].id != original.id)
    }

    @Test func pastingIntoTheSameDocumentMovesByTenPoints() {
        let document = UUID()
        let transfer = ElementTransfer(elements: [box(10, 10), box(40, 20)], scale: 2, sourceDocument: document)
        let pasted = transfer.placed(in: CGSize(width: 200, height: 200), scale: 2, documentID: document)
        #expect(pasted.map(\.start) == [CGPoint(x: 30, y: 30), CGPoint(x: 60, y: 40)])
        // Into another document they keep their place.
        let elsewhere = transfer.placed(in: CGSize(width: 200, height: 200), scale: 2, documentID: UUID())
        #expect(elsewhere.map(\.start) == [CGPoint(x: 10, y: 10), CGPoint(x: 40, y: 20)])
    }

    @Test func pastingAtTheEdgeMovesBackInstead() {
        let document = UUID()
        let transfer = ElementTransfer(elements: [box(75, 85)], scale: 1, sourceDocument: document)
        let pasted = transfer.placed(in: CGSize(width: 100, height: 100), scale: 1, documentID: document)
        #expect(pasted[0].start == CGPoint(x: 65, y: 75))
    }

    @Test func pastingIntoASmallerImageMovesInsideIt() {
        let transfer = ElementTransfer(elements: [box(150, 20, 30, 10)], scale: 1, sourceDocument: UUID())
        let pasted = transfer.placed(in: CGSize(width: 100, height: 100), scale: 1, documentID: UUID())
        #expect(pasted[0].bounds == CGRect(x: 70, y: 20, width: 30, height: 10))
    }

    @Test func pastingAtThePointerPutsTheTopLeftThere() {
        let transfer = ElementTransfer(elements: [box(10, 10), box(40, 30)], scale: 1)
        let pasted = transfer.placed(in: CGSize(width: 200, height: 200), scale: 1, documentID: nil, at: CGPoint(x: 100, y: 50))
        #expect(pasted.map(\.start) == [CGPoint(x: 100, y: 50), CGPoint(x: 130, y: 70)])
    }

    @Test func pastingIntoAnImageWithOtherPixelsPerPointKeepsThePointSize() {
        let transfer = ElementTransfer(elements: [box(10, 10, 20, 10)], scale: 1)
        let pasted = transfer.placed(in: CGSize(width: 400, height: 400), scale: 2, documentID: UUID())
        #expect(pasted[0].bounds == CGRect(x: 20, y: 20, width: 40, height: 20))
    }
}

struct MultiSelectionTests {
    func document() -> EditorDocument {
        EditorDocument(image: TestImage.solid(width: 100, height: 80, .white), scale: 1, title: "test", isModified: false)
    }

    func box(_ x: CGFloat) -> Annotation {
        Annotation(kind: .rectangle, start: CGPoint(x: x, y: 0), end: CGPoint(x: x + 5, y: 5))
    }

    @Test func movesAndRemovesSeveralElementsAsOneStep() {
        let doc = document()
        let a = box(0), b = box(10), c = box(20)
        doc.change { doc.add([a, b, c]) }
        doc.change { doc.move([a.id, c.id], by: CGVector(dx: 1, dy: 2)) }
        #expect(doc.annotations.map(\.start) == [CGPoint(x: 1, y: 2), CGPoint(x: 10, y: 0), CGPoint(x: 21, y: 2)])
        doc.change { doc.remove([a.id, b.id]) }
        #expect(doc.annotations.map(\.id) == [c.id])
        doc.undo()
        #expect(doc.annotations.count == 3)
    }

    @Test func duplicatesWithNewIDsOnTop() {
        let doc = document()
        let a = box(0), b = box(10), c = box(20)
        doc.add([a, b, c])
        let copies = doc.duplicate([a.id, b.id], offset: CGVector(dx: 10, dy: 10))
        #expect(copies.count == 2)
        #expect(Set(copies.map(\.id)).isDisjoint(with: [a.id, b.id, c.id]))
        #expect(doc.annotations.suffix(2).map(\.start) == [CGPoint(x: 10, y: 10), CGPoint(x: 20, y: 10)])
    }

    @Test func bringingSeveralToFrontKeepsTheirOrder() {
        let doc = document()
        let a = box(0), b = box(10), c = box(20), d = box(30)
        doc.add([a, b, c, d])
        doc.bringToFront([a.id, c.id])
        #expect(doc.annotations.map(\.id) == [b.id, d.id, a.id, c.id])
        doc.sendToBack([d.id, c.id])
        #expect(doc.annotations.map(\.id) == [d.id, c.id, b.id, a.id])
    }
}

struct ArrangeTests {
    func document(_ count: Int) -> (EditorDocument, [Annotation]) {
        let doc = EditorDocument(image: TestImage.solid(width: 10, height: 10, .white), scale: 1, title: "test")
        let elements = (0..<count).map { Annotation(kind: .rectangle, start: CGPoint(x: $0, y: 0), end: CGPoint(x: $0 + 1, y: 1)) }
        doc.add(elements)
        return (doc, elements)
    }

    @Test func bringsForwardOneLevel() {
        let (doc, e) = document(4)
        doc.bringForward([e[1].id])
        #expect(doc.annotations.map(\.id) == [e[0], e[2], e[1], e[3]].map(\.id))
    }

    @Test func neighboursMoveTogetherInsteadOfLeapfrogging() {
        let (doc, e) = document(4)
        doc.bringForward([e[0].id, e[1].id])
        #expect(doc.annotations.map(\.id) == [e[2], e[0], e[1], e[3]].map(\.id))
        doc.sendBackward([e[0].id, e[1].id])
        #expect(doc.annotations.map(\.id) == [e[0], e[1], e[2], e[3]].map(\.id))
    }

    @Test func topmostElementsCantGoFurther() {
        let (doc, e) = document(3)
        #expect(!doc.canBringForward([e[2].id]))
        #expect(!doc.canBringForward([e[1].id, e[2].id]))
        #expect(doc.canBringForward([e[0].id, e[2].id]))
        #expect(!doc.canSendBackward([e[0].id]))
        #expect(doc.canSendBackward([e[0].id, e[2].id]))
        #expect(!doc.canBringForward(Set(e.map(\.id))))
        #expect(!doc.canSendBackward([]))
        doc.bringForward([e[2].id])
        #expect(doc.annotations.map(\.id) == e.map(\.id))
    }
}

struct PictureElementTests {
    @Test func isSizedInPointsAndFitsTheImage() throws {
        let picture = TestImage.solid(width: 40, height: 20, .blue)
        // A 2x picture on a 1x image is half as many pixels wide.
        let a = try #require(Annotation.picture(picture, pictureScale: 2, at: CGPoint(x: 5, y: 5), documentScale: 1))
        #expect(a.kind == .image && a.bounds == CGRect(x: 5, y: 5, width: 20, height: 10))
        let fitted = try #require(Annotation.picture(picture, pictureScale: 1, at: .zero, documentScale: 1,
                                                     fitting: CGSize(width: 20, height: 100)))
        #expect(fitted.bounds.size == CGSize(width: 20, height: 10))
    }

    @Test func drawsThePictureIntoItsBox() throws {
        let picture = TestImage.make(width: 10, height: 10) { _, y in y < 5 ? .red : .blue }
        let a = try #require(Annotation.picture(picture, pictureScale: 1, at: CGPoint(x: 10, y: 10), documentScale: 1))
        var stretched = a
        stretched.end = CGPoint(x: 30, y: 50)
        let base = TestImage.solid(width: 60, height: 60, .white)
        let image = try #require(AnnotationRenderer.flatten(base: base, annotations: [stretched], scale: 1))
        #expect(TestImage.pixel(image, 15, 15).isClose(to: .red))
        #expect(TestImage.pixel(image, 15, 45).isClose(to: .blue))
        #expect(TestImage.pixel(image, 40, 45).isClose(to: .white))
    }

    @Test func survivesTheClipboard() throws {
        let a = try #require(Annotation.picture(TestImage.solid(width: 4, height: 4, .red), pictureScale: 1, at: .zero, documentScale: 1))
        let decoded = try #require(ElementTransfer.decode(try ElementTransfer(elements: [a], scale: 1).encoded()))
        #expect(decoded.elements[0].imageData == a.imageData)
        #expect(AnnotationRenderer.picture(of: decoded.elements[0])?.width == 4)
    }

    @Test func shiftKeepsTheAspectRatio() throws {
        let a = Annotation(kind: .image, start: .zero, end: CGPoint(x: 40, y: 20))
        let free = Handle.bottomRight.drag(a, to: CGPoint(x: 60, y: 60))
        #expect(free.bounds.size == CGSize(width: 60, height: 60))
        let kept = Handle.bottomRight.drag(a, to: CGPoint(x: 60, y: 60), keepAspect: true)
        #expect(kept.bounds == CGRect(x: 0, y: 0, width: 120, height: 60))
        let fromTopLeft = Handle.topLeft.drag(a, to: CGPoint(x: 20, y: 15), keepAspect: true)
        #expect(fromTopLeft.bounds == CGRect(x: 20, y: 10, width: 20, height: 10))
    }
}

struct ElementsFileTests {
    @Test func savedElementsLoadIntoAnotherDocumentAsOneStep() throws {
        let source = EditorDocument(image: TestImage.solid(width: 100, height: 100, .white), scale: 2, title: "a")
        let rectangle = Annotation(kind: .rectangle, start: CGPoint(x: 10, y: 10), end: CGPoint(x: 30, y: 30))
        let text = Annotation(kind: .text, start: CGPoint(x: 40, y: 40), end: CGPoint(x: 90, y: 60), text: "Hello")
        source.add([rectangle, text])
        let data = try ElementTransfer.file(of: source).encoded()

        let target = EditorDocument(image: TestImage.solid(width: 100, height: 100, .white), scale: 2, title: "b", isModified: false)
        let existing = Annotation(kind: .ellipse, start: .zero, end: CGPoint(x: 5, y: 5))
        target.add(existing)
        let loaded = try #require(ElementTransfer.decode(data)).load(into: target)
        #expect(loaded.map(\.text) == ["", "Hello"])
        #expect(loaded.map(\.bounds) == [rectangle.bounds, text.bounds])
        #expect(target.annotations.count == 3 && target.annotations[0].id == existing.id)
        #expect(!loaded.contains { $0.id == rectangle.id || $0.id == text.id })
        target.undo()
        #expect(target.annotations.map(\.id) == [existing.id])
    }
}

struct ReusedDocumentTests {
    @Test func resetStartsOverWithTheNewScreenshot() {
        let doc = EditorDocument(image: TestImage.solid(width: 10, height: 10, .white), scale: 1, title: "old",
                                 fileURL: URL(fileURLWithPath: "/tmp/old.png"), isModified: false)
        doc.change {
            doc.add(Annotation(kind: .rectangle, start: .zero, end: CGPoint(x: 5, y: 5)))
            doc.counterStart = 3
        }
        doc.reset(image: TestImage.solid(width: 40, height: 20, .blue), scale: 2, title: "new")
        #expect(doc.imageSize == CGSize(width: 40, height: 20) && doc.scale == 2 && doc.title == "new")
        #expect(doc.annotations.isEmpty && doc.counterStart == 1 && doc.fileURL == nil)
        #expect(!doc.canUndo && !doc.canRedo && doc.isModified)
    }
}
