// Greenshot for Mac (Community) - an unofficial macOS port of Greenshot
// Copyright (C) 2026 Greenshot for Mac (Community) contributors
// Based on Greenshot, Copyright (C) 2007-2026 Thomas Braun, Jens Klingen, Robin Krom
// SPDX-License-Identifier: GPL-3.0-or-later

import CoreGraphics
import Foundation
import Testing
@testable import GreenshotCore

/// Counters show the number of the order they were added, whatever their drawing order (upstream `StepLabelContainer`
/// and `Surface.CountStepLabels`, which walks `_stepLabels`, a list Bring to Front and the like don't change).
struct CounterOrderTests {
    func document() -> EditorDocument {
        EditorDocument(image: TestImage.solid(width: 200, height: 100, .white), scale: 1, title: "test", isModified: false)
    }

    func counter(_ x: CGFloat, _ y: CGFloat = 0) -> Annotation {
        Annotation(kind: .counter, start: CGPoint(x: x, y: y), end: CGPoint(x: x + 30, y: y + 30))
    }

    /// Three counters added one after the other, from left to right.
    func counters(in doc: EditorDocument) -> [Annotation] {
        let added = [counter(0), counter(50), counter(100)]
        for element in added { doc.change { doc.add(element) } }
        return added
    }

    func numbers(_ doc: EditorDocument, _ elements: [Annotation]) -> [Int?] {
        elements.map { doc.counterNumber(for: $0.id) }
    }

    func bytes(_ image: CGImage) -> Data? {
        image.dataProvider?.data as Data?
    }

    @Test func arrangingKeepsTheNumbers() {
        let doc = document()
        let c = counters(in: doc)
        doc.change { doc.bringToFront(c[0].id) }
        #expect(doc.annotations.map(\.id) == [c[1].id, c[2].id, c[0].id])
        #expect(numbers(doc, c) == [1, 2, 3])
        doc.change { doc.sendToBack([c[2].id]) }
        doc.change { doc.bringForward([c[1].id]) }
        doc.change { doc.sendBackward([c[0].id]) }
        #expect(numbers(doc, c) == [1, 2, 3])
    }

    @Test func theImageShowsTheSameNumbersAfterArranging() throws {
        let doc = document()
        let c = counters(in: doc)
        let before = try #require(bytes(doc.flattened()))
        doc.change { doc.bringToFront(c[0].id) }
        let after = try #require(bytes(doc.flattened()))
        #expect(after == before)
    }

    @Test func removingRenumbersAndUndoBringsTheNumbersBack() {
        let doc = document()
        let c = counters(in: doc)
        doc.change { doc.bringToFront(c[0].id) }
        doc.change { doc.remove(c[1].id) }
        #expect(doc.counterNumber(for: c[0].id) == 1)
        #expect(doc.counterNumber(for: c[2].id) == 2)
        doc.undo()
        #expect(numbers(doc, c) == [1, 2, 3])
        doc.undo()
        doc.redo()
        #expect(numbers(doc, c) == [1, 2, 3])
    }

    /// Adding nothing (an empty elements file) changes nothing, also after a counter was removed.
    @Test func addingNothingIsNoChange() {
        let doc = document()
        let c = counters(in: doc)
        doc.change { doc.remove(c[1].id) }
        let before = doc.annotations
        let count = doc.changeCount
        doc.change { doc.add([]) }
        #expect(doc.annotations == before)
        #expect(doc.changeCount == count)
    }

    /// The canvas drags a new counter with the copy it made before adding it: that copy has no place in the order yet.
    @Test func updatingWithACopyKeepsThePlace() {
        let doc = document()
        let first = counter(0)
        doc.beginChange()
        doc.add(first)
        var moved = first
        moved.move(by: CGVector(dx: 5, dy: 5))
        doc.update(moved)
        doc.endChange()
        let second = counter(100)
        doc.change { doc.add(second) }
        doc.change { doc.sendToBack(second.id) }
        #expect(doc.counterNumber(for: first.id) == 1)
        #expect(doc.counterNumber(for: second.id) == 2)
    }

    /// Copies are new counters: they come after all others, among themselves in the order of the counters they copy.
    @Test func duplicatedAndPastedCountersComeLast() throws {
        let doc = document()
        let c = counters(in: doc)
        doc.change { doc.bringToFront(c[0].id) }
        var copies: [Annotation] = []
        doc.change { copies = doc.duplicate([c[0].id, c[1].id], offset: CGVector(dx: 0, dy: 40)) }
        let copyOfFirst = try #require(copies.first { $0.start.x == 0 })
        let copyOfSecond = try #require(copies.first { $0.start.x == 50 })
        #expect(doc.counterNumber(for: copyOfFirst.id) == 4)
        #expect(doc.counterNumber(for: copyOfSecond.id) == 5)

        let transfer = ElementTransfer(elements: doc.annotations([c[0].id, c[1].id]), scale: 1)
        let pasted = transfer.load(into: doc)
        let pastedFirst = try #require(pasted.first { $0.start.x == 0 })
        let pastedSecond = try #require(pasted.first { $0.start.x == 50 })
        #expect(doc.counterNumber(for: pastedFirst.id) == 6)
        #expect(doc.counterNumber(for: pastedSecond.id) == 7)
        #expect(numbers(doc, c) == [1, 2, 3])
    }

    @Test func aSavedFileKeepsTheNumbers() throws {
        let doc = document()
        let c = counters(in: doc)
        doc.change { doc.bringToFront(c[0].id) }
        let read = try #require(GreenshotFile.read(try GreenshotFile.Contents(of: doc).encoded()))
        let opened = EditorDocument(opening: read, from: URL(fileURLWithPath: "/tmp/Counters.greenshot"))
        // The ids change on reading: the counters are told apart by their place.
        #expect(opened.annotations.map(\.start.x) == [50, 100, 0])
        #expect(opened.annotations.map { opened.counterNumber(for: $0.id) } == [2, 3, 1])
    }

    /// Files of earlier versions have no order: their counters keep the numbers they showed (drawing order), and keep
    /// them when arranged.
    @Test func countersOfEarlierFilesKeepTheirNumbers() throws {
        let contents = GreenshotFile.Contents(image: TestImage.solid(width: 200, height: 100, .white), scale: 1,
                                              elements: [counter(100), counter(0)])
        let read = try #require(GreenshotFile.read(try contents.encoded()))
        let opened = EditorDocument(opening: read, from: URL(fileURLWithPath: "/tmp/Earlier.greenshot"))
        let ids = opened.annotations.map(\.id)
        #expect(ids.map { opened.counterNumber(for: $0) } == [1, 2])
        opened.change { opened.bringToFront(ids[0]) }
        #expect(ids.map { opened.counterNumber(for: $0) } == [1, 2])
    }

    /// Elements not on a document yet (a recipe adds them to the capture) count after those that are, in drawing order.
    @Test func countersWithoutAPlaceComeAfterThoseWithOne() {
        var placed = counter(0)
        placed.counterOrder = 7
        let unplaced = [counter(50), counter(100)]
        let numbers = Annotation.counterNumbers(unplaced + [placed], from: 1)
        #expect(numbers[placed.id] == 1)
        #expect(numbers[unplaced[0].id] == 2)
        #expect(numbers[unplaced[1].id] == 3)
    }

    /// What lies below an area or grayscale highlight is kept between draws: a counter there changes its number when
    /// one added before it, above the highlight, goes.
    @Test func aCounterBelowAHighlightShowsItsNewNumber() throws {
        let doc = document()
        let c = counters(in: doc)
        var style = AnnotationStyle.defaults(for: .highlight)
        style.highlightMode = .grayscale
        doc.change { doc.add(Annotation(kind: .highlight, start: CGPoint(x: 150, y: 50), end: CGPoint(x: 190, y: 90), style: style)) }
        doc.change { doc.bringToFront(c[0].id) }
        _ = doc.flattened()
        doc.change { doc.remove(c[0].id) }
        let kept = try #require(bytes(doc.flattened()))
        AnnotationRenderer.forgetKeptEffects()
        let fresh = try #require(bytes(doc.flattened()))
        #expect(kept == fresh)
    }
}
