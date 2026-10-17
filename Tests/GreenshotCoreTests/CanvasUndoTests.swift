// Greenshot for Mac (Community) - an unofficial macOS port of Greenshot
// Copyright (C) 2026 Greenshot for Mac (Community) contributors
// Based on Greenshot, Copyright (C) 2007-2026 Thomas Braun, Jens Klingen, Robin Krom
// SPDX-License-Identifier: GPL-3.0-or-later

import CoreGraphics
import Foundation
import Testing
@testable import GreenshotCore

/// Undo bounded by the memory of earlier images, and merged steps (upstream `Surface.LimitUndoImages`,
/// `MakeUndoable(…, allowMerge)`).
struct CanvasUndoTests {
    func document() -> EditorDocument {
        EditorDocument(image: TestImage.solid(width: 10, height: 10, .white), scale: 1, title: "t", isModified: false)
    }

    @Test func oldImageStepsGoWhenTheyUseTooMuchMemory() {
        let doc = document()
        // Each earlier image of 10 × 10 pixels takes 400 bytes: two fit.
        doc.undoImageBudget = 900
        for _ in 0..<5 { doc.change { _ = doc.clearImage() } }
        var steps = 0
        while doc.canUndo {
            doc.undo()
            steps += 1
        }
        #expect(steps == 2)
    }

    @Test func theNewestStepStaysEvenWhenItIsTooBig() {
        let doc = document()
        doc.undoImageBudget = 10
        doc.change { _ = doc.enlargeCanvas(by: 1) }
        doc.change { _ = doc.enlargeCanvas(by: 1) }
        #expect(doc.canUndo)
        doc.undo()
        #expect(!doc.canUndo)
    }

    @Test func elementStepsCostNothingAndAreNotCapped() {
        let doc = document()
        doc.undoImageBudget = 1
        for index in 0..<150 {
            doc.change { doc.add(Annotation(kind: .rectangle, start: .zero, end: CGPoint(x: index, y: index))) }
        }
        var steps = 0
        while doc.canUndo {
            doc.undo()
            steps += 1
        }
        #expect(steps == 150)
        #expect(doc.annotations.isEmpty)
    }

    @Test func mergedChangesAreOneStep() throws {
        let doc = document()
        let a = Annotation(kind: .rectangle, start: .zero, end: CGPoint(x: 4, y: 4))
        doc.change { doc.add(a) }
        for _ in 0..<3 { doc.change(merging: "nudge a") { doc.move([a.id], by: CGVector(dx: 1, dy: 0)) } }
        #expect(try #require(doc.annotation(a.id)).start == CGPoint(x: 3, y: 0))
        doc.undo()
        #expect(try #require(doc.annotation(a.id)).start == .zero)
        // Another key, another change in between, or an undo starts a new step.
        doc.redo()
        doc.change(merging: "nudge a") { doc.move([a.id], by: CGVector(dx: 1, dy: 0)) }
        doc.change { doc.counterStart = 5 }
        doc.change(merging: "nudge a") { doc.move([a.id], by: CGVector(dx: 1, dy: 0)) }
        doc.change(merging: "nudge b") { doc.move([a.id], by: CGVector(dx: 0, dy: 1)) }
        doc.undo()
        #expect(try #require(doc.annotation(a.id)).start == CGPoint(x: 5, y: 0))
        doc.undo()
        #expect(try #require(doc.annotation(a.id)).start == CGPoint(x: 4, y: 0))
        doc.undo()
        #expect(doc.counterStart == 1)
    }
}
