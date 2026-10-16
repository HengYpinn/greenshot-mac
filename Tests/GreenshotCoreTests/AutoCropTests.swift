// SPDX-License-Identifier: GPL-3.0-or-later

import CoreGraphics
import Foundation
import Testing
@testable import GreenshotCore

struct AutoCropTests {
    /// White with a red box from (10, 5) to (29, 19).
    let framed = TestImage.make(width: 40, height: 30) { x, y in
        (10..<30).contains(x) && (5..<20).contains(y) ? .red : .white
    }

    @Test func findsTheContentBox() {
        #expect(AutoCrop.contentRect(of: framed, difference: 10) == CGRect(x: 10, y: 5, width: 20, height: 15))
    }

    @Test func aUniformImageCannotBeCropped() {
        #expect(AutoCrop.contentRect(of: TestImage.solid(width: 20, height: 20, .blue), difference: 10) == nil)
    }

    @Test func contentThatFillsTheImageCannotBeCropped() {
        // The corners differ, so every corner color finds the whole image.
        let image = TestImage.make(width: 10, height: 10) { x, y in x == 0 && y == 0 ? .red : (x == 9 && y == 9 ? .blue : .white) }
        #expect(AutoCrop.contentRect(of: image, difference: 10) == nil)
    }

    @Test func smallDifferencesAreIgnored() {
        let image = TestImage.make(width: 20, height: 20) { x, y in
            if x == 2 && y == 2 { return RGBA(r: 250, g: 250, b: 250, a: 255) }
            return (8..<12).contains(x) && (8..<12).contains(y) ? .black : .white
        }
        #expect(AutoCrop.contentRect(of: image, difference: 10) == CGRect(x: 8, y: 8, width: 4, height: 4))
        #expect(AutoCrop.contentRect(of: image, difference: 0) == CGRect(x: 2, y: 2, width: 10, height: 10))
    }

    @Test func searchesOnlyTheGivenArea() {
        let area = CGRect(x: 0, y: 0, width: 20, height: 30)
        #expect(AutoCrop.contentRect(of: framed, difference: 10, area: area) == CGRect(x: 10, y: 5, width: 10, height: 15))
    }

    @Test func autoCropIsOneUndoStepAndMovesTheElements() {
        let doc = EditorDocument(image: framed, scale: 1, title: "test", isModified: false)
        // Inside the content and without a shadow: what the elements draw counts as content too.
        let box = Annotation(kind: .rectangle, start: CGPoint(x: 15, y: 10), end: CGPoint(x: 20, y: 12),
                               style: AnnotationStyle(shadow: false))
        doc.change { doc.add(box) }
        doc.change { #expect(doc.autoCrop(difference: 10)) }
        #expect(doc.imageSize == CGSize(width: 20, height: 15))
        #expect(doc.annotations[0].start == CGPoint(x: 5, y: 5))
        doc.change { #expect(!doc.autoCrop(difference: 10)) }
        doc.undo()
        #expect(doc.imageSize == CGSize(width: 40, height: 30))
    }

    @Test func opaqueBoundsFindTheTransparentMargin() {
        let image = TestImage.make(width: 10, height: 10) { x, y in
            (3..<6).contains(x) && (2..<9).contains(y) ? .red : RGBA(r: 0, g: 0, b: 0, a: 0)
        }
        #expect(AutoCrop.opaqueBounds(of: image) == CGRect(x: 3, y: 2, width: 3, height: 7))
        #expect(AutoCrop.opaqueBounds(of: framed) == nil)
        #expect(AutoCrop.opaqueBounds(of: TestImage.solid(width: 4, height: 4, RGBA(r: 0, g: 0, b: 0, a: 0))) == nil)
    }
}
