// Greenshot for Mac (Community) - an unofficial macOS port of Greenshot
// Copyright (C) 2026 Greenshot for Mac (Community) contributors
// Based on Greenshot, Copyright (C) 2007-2026 Thomas Braun, Jens Klingen, Robin Krom
// SPDX-License-Identifier: GPL-3.0-or-later

import CoreGraphics
import Foundation
import Testing
@testable import GreenshotCore

/// Cutting a strip out of the image and joining the sides (upstream `Surface.ApplyCutOut`, `CutOutTests.cs`).
struct CutOutTests {
    static let green = RGBA(r: 0, g: 255, b: 0, a: 255)

    /// 100 × 100: rows 0–29 red, 30–59 green, 60–99 blue; the same bands as columns when `columns`.
    func striped(columns: Bool = false) -> CGImage {
        TestImage.make(width: 100, height: 100) { x, y in
            let along = columns ? x : y
            return along < 30 ? .red : along < 60 ? Self.green : .blue
        }
    }

    func document(_ image: CGImage? = nil, scale: CGFloat = 1) -> EditorDocument {
        EditorDocument(image: image ?? striped(), scale: scale, title: "test", isModified: false)
    }

    func box(_ x: CGFloat, _ y: CGFloat, _ w: CGFloat = 10, _ h: CGFloat = 10) -> Annotation {
        Annotation(kind: .rectangle, start: CGPoint(x: x, y: y), end: CGPoint(x: x + w, y: y + h))
    }

    @Test func placementOfElementsAroundAHorizontalCut() {
        // Rows 30 up to 60 are cut out.
        func placement(top: CGFloat, height: CGFloat) -> ImageOperations.CutOutPlacement {
            ImageOperations.cutOutPlacement(of: CGRect(x: 5, y: top, width: 10, height: height), cutStart: 30, cutSize: 30, horizontal: true)
        }
        #expect(placement(top: 10, height: 10) == .before)
        #expect(placement(top: 20, height: 10) == .before)
        #expect(placement(top: 25, height: 10) == .across)
        #expect(placement(top: 30, height: 30) == .inside)
        #expect(placement(top: 40, height: 10) == .inside)
        #expect(placement(top: 55, height: 10) == .across)
        #expect(placement(top: 60, height: 10) == .after)
        #expect(placement(top: 20, height: 50) == .across)
        // A line drawn upwards has a negative height.
        #expect(placement(top: 50, height: -10) == .inside)
    }

    @Test func placementAroundAVerticalCutUsesColumns() {
        #expect(ImageOperations.cutOutPlacement(of: CGRect(x: 70, y: 0, width: 10, height: 100), cutStart: 30, cutSize: 30, horizontal: false) == .after)
        #expect(ImageOperations.cutOutPlacement(of: CGRect(x: 35, y: 0, width: 10, height: 100), cutStart: 30, cutSize: 30, horizontal: false) == .inside)
    }

    @Test func cuttingRowsJoinsTheSidesAndMovesOnlyTheElementsBelow() {
        let doc = document()
        let above = box(5, 10), inside = box(5, 40), across = box(5, 25), below = box(5, 70)
        doc.change { doc.add([above, inside, across, below]) }
        doc.change { #expect(doc.cutOut(CGRect(x: 0, y: 30, width: 100, height: 30), horizontal: true)) }
        #expect(doc.imageSize == CGSize(width: 100, height: 70))
        #expect(TestImage.pixel(doc.baseImage, 50, 29) == .red)
        #expect(TestImage.pixel(doc.baseImage, 50, 30) == .blue)
        #expect(TestImage.pixel(doc.baseImage, 50, 69) == .blue)
        #expect(doc.annotations.map(\.id) == [above.id, across.id, below.id])
        #expect(doc.annotations[0].bounds.minY == 10)
        #expect(doc.annotations[1].bounds.minY == 25)
        #expect(doc.annotations[2].bounds.minY == 40)

        doc.undo()
        #expect(doc.imageSize == CGSize(width: 100, height: 100))
        #expect(doc.annotations == [above, inside, across, below])
        doc.redo()
        #expect(doc.imageSize == CGSize(width: 100, height: 70))
        #expect(doc.annotations.count == 3 && doc.annotations[2].bounds.minY == 40)
    }

    @Test func cuttingColumnsMovesOnlyTheElementsToTheRight() {
        let doc = document(striped(columns: true))
        let left = box(10, 5), right = box(70, 5)
        doc.change { doc.add([left, right]) }
        doc.change { #expect(doc.cutOut(CGRect(x: 30, y: 0, width: 30, height: 100), horizontal: false)) }
        #expect(doc.imageSize == CGSize(width: 70, height: 100))
        #expect(TestImage.pixel(doc.baseImage, 29, 50) == .red)
        #expect(TestImage.pixel(doc.baseImage, 30, 50) == .blue)
        #expect(doc.annotations[0].bounds.minX == 10)
        #expect(doc.annotations[1].bounds.minX == 40)
    }

    @Test func onlyTheRowsOrColumnsOfTheSelectionCount() {
        let doc = document()
        // A small selection in the middle: its rows are cut out across the whole width.
        doc.change { #expect(doc.cutOut(CGRect(x: 40, y: 30, width: 20, height: 30), horizontal: true)) }
        #expect(doc.imageSize == CGSize(width: 100, height: 70))
        #expect(TestImage.pixel(doc.baseImage, 5, 30) == .blue)
    }

    @Test func theWholeImageOrNothingCannotBeCutOut() {
        let doc = document()
        doc.change { #expect(!doc.cutOut(CGRect(x: 10, y: -5, width: 20, height: 200), horizontal: true)) }
        doc.change { #expect(!doc.cutOut(CGRect(x: -10, y: 0, width: 300, height: 10), horizontal: false)) }
        doc.change { #expect(!doc.cutOut(CGRect(x: 10, y: 10, width: 0, height: 0), horizontal: true)) }
        doc.change { #expect(!doc.cutOut(CGRect(x: 200, y: 200, width: 10, height: 10), horizontal: true)) }
        #expect(!doc.canUndo && doc.imageSize == CGSize(width: 100, height: 100))
    }

    @Test func aTornCutMarkKeepsTheGapAndSpansTheWidth() throws {
        let doc = document()
        let below = box(5, 70)
        doc.change { doc.add(below) }
        var style = AnnotationStyle.defaults(for: .cutMark)
        style.toothHeight = 12
        style.toothRange = 20
        doc.change {
            #expect(doc.cutOut(CGRect(x: 0, y: 30, width: 100, height: 30), horizontal: true, cutMark: .torn, markStyle: style))
        }
        // 12 rows of the strip are kept for the gap.
        #expect(doc.imageSize == CGSize(width: 100, height: 82))
        #expect(TestImage.pixel(doc.baseImage, 50, 36) == Self.green)
        #expect(TestImage.pixel(doc.baseImage, 50, 29) == .red)
        #expect(TestImage.pixel(doc.baseImage, 50, 45) == .blue)
        #expect(doc.annotations[0].bounds.minY == 52)
        let mark = try #require(doc.annotations.last)
        #expect(mark.kind == .cutMark && !mark.isVerticalCutMark)
        // The band has a tooth on both sides of the gap.
        #expect(mark.bounds == CGRect(x: 0, y: 18, width: 100, height: 36))
        #expect(mark.style.cutMarkStyle == .torn && mark.style.toothHeight == 12)
        #expect(Handle.handles(for: mark) == [.top, .bottom])

        doc.undo()
        #expect(doc.imageSize == CGSize(width: 100, height: 100))
        #expect(doc.annotations == [below])
        doc.redo()
        #expect(doc.imageSize == CGSize(width: 100, height: 82) && doc.annotations.count == 2)
    }

    @Test func aVerticalCutMarkSpansTheFullHeight() throws {
        let doc = document(striped(columns: true))
        doc.change {
            #expect(doc.cutOut(CGRect(x: 30, y: 0, width: 30, height: 100), horizontal: false, cutMark: .zigZag))
        }
        #expect(doc.imageSize == CGSize(width: 82, height: 100))
        let mark = try #require(doc.annotations.last)
        #expect(mark.isVerticalCutMark)
        #expect(mark.bounds == CGRect(x: 18, y: 0, width: 36, height: 100))
        #expect(mark.style.cutMarkStyle == .zigZag)
        #expect(Handle.handles(for: mark) == [.left, .right])
        #expect(mark.hitTest(CGPoint(x: 30, y: 95), scale: 1, tolerance: 4))
        #expect(!mark.hitTest(CGPoint(x: 70, y: 95), scale: 1, tolerance: 4))
        // It only moves sideways and stays the full height.
        doc.change { doc.move([mark.id], by: CGVector(dx: 10, dy: 5)) }
        #expect(doc.annotations.last?.bounds == CGRect(x: 28, y: 0, width: 36, height: 100))
    }

    @Test func noCutMarkAtTheEdgeOfTheImage() {
        let doc = document()
        doc.change { #expect(doc.cutOut(CGRect(x: 0, y: 0, width: 100, height: 30), horizontal: true, cutMark: .torn)) }
        #expect(doc.imageSize == CGSize(width: 100, height: 70) && doc.annotations.isEmpty)
        #expect(TestImage.pixel(doc.baseImage, 50, 0) == Self.green)
        doc.change { #expect(doc.cutOut(CGRect(x: 0, y: 30, width: 100, height: 40), horizontal: true, cutMark: .torn)) }
        #expect(doc.imageSize == CGSize(width: 100, height: 30) && doc.annotations.isEmpty)
    }

    @Test func theGapIsInPointsOfTheCapture() throws {
        let doc = document(TestImage.solid(width: 200, height: 200, .white), scale: 2)
        var style = AnnotationStyle.defaults(for: .cutMark)
        style.toothHeight = 12
        doc.change {
            #expect(doc.cutOut(CGRect(x: 0, y: 60, width: 200, height: 60), horizontal: true, cutMark: .line, markStyle: style))
        }
        // 12 pt are 24 pixels: the gap, and a tooth on each side of it.
        #expect(doc.imageSize == CGSize(width: 200, height: 164))
        let mark = try #require(doc.annotations.last)
        #expect(mark.bounds == CGRect(x: 0, y: 36, width: 200, height: 72))
    }

    @Test func aThinStripIsAllGap() throws {
        let doc = document()
        doc.change { #expect(doc.cutOut(CGRect(x: 0, y: 30, width: 100, height: 5), horizontal: true, cutMark: .wave)) }
        // Nothing is removed: the five rows are the gap.
        #expect(doc.imageSize == CGSize(width: 100, height: 100))
        let mark = try #require(doc.annotations.last)
        #expect(mark.bounds == CGRect(x: 0, y: 30 + 2 - 14, width: 100, height: 29))
        #expect(doc.canUndo)
    }

    @Test func rotatingTurnsACutMarkAcrossTheOtherAxis() throws {
        let doc = document()
        doc.change { #expect(doc.cutOut(CGRect(x: 0, y: 30, width: 100, height: 30), horizontal: true, cutMark: .line)) }
        doc.change { #expect(doc.rotateImage(clockwise: true)) }
        let mark = try #require(doc.annotations.last)
        #expect(mark.isVerticalCutMark)
        // Rows 18–54 of 82 become the columns 28–64 of the turned image.
        #expect(mark.bounds == CGRect(x: 82 - 54, y: 0, width: 36, height: 100))
        doc.change { #expect(doc.rotateImage(clockwise: false)) }
        #expect(doc.annotations.last?.isVerticalCutMark == false)
        #expect(doc.annotations.last?.bounds == CGRect(x: 0, y: 18, width: 100, height: 36))
    }

    @Test func aVerticalCutMarkDrawsItsGapDownTheImage() throws {
        let base = TestImage.solid(width: 60, height: 60, .blue)
        var mark = Annotation(kind: .cutMark, start: CGPoint(x: 10, y: 0), end: CGPoint(x: 50, y: 60))
        mark.verticalCut = true
        mark.style.cutMarkStyle = .line
        mark.style.shadow = false
        mark.style.toothHeight = 10
        let image = try #require(AnnotationRenderer.flatten(base: base, annotations: [mark], scale: 1))
        #expect(TestImage.pixel(image, 30, 5).a == 0)
        #expect(TestImage.pixel(image, 30, 55).a == 0)
        #expect(TestImage.pixel(image, 15, 30).isClose(to: .blue))
        #expect(TestImage.pixel(image, 55, 30).isClose(to: .blue))
        let shape = try #require(CutMark.shape(band: CGRect(x: 10, y: 0, width: 40, height: 60), style: .line,
                                               toothHeight: 10, toothRange: 20, seed: 1, vertical: true))
        #expect(shape.first == [CGPoint(x: 20, y: 0), CGPoint(x: 20, y: 60)])
        #expect(shape.second == [CGPoint(x: 40, y: 0), CGPoint(x: 40, y: 60)])
    }

    @Test func biggerTeethGrowAVerticalMarkSideways() {
        var mark = Annotation(kind: .cutMark, start: CGPoint(x: 20, y: 0), end: CGPoint(x: 54, y: 100))
        mark.verticalCut = true
        mark.style.toothHeight = 12
        let wider = mark.withToothHeight(16, scale: 1)
        #expect(wider.bounds == CGRect(x: 16, y: 0, width: 42, height: 100))
    }

    @Test func elementsWithoutTheOrientationStillLoadAsHorizontalMarks() throws {
        let json = #"{"id":"6F9E2D3C-1B7A-4C5D-8E9F-0A1B2C3D4E5F","kind":"cutMark","start":[0,20],"end":[100,50],"points":[],"text":"","style":{}}"#
        let mark = try JSONDecoder().decode(Annotation.self, from: Data(json.utf8))
        #expect(mark.kind == .cutMark && !mark.isVerticalCutMark && mark.verticalCut == nil)
        var vertical = mark
        vertical.verticalCut = true
        let decoded = try JSONDecoder().decode(Annotation.self, from: JSONEncoder().encode(vertical))
        #expect(decoded.isVerticalCutMark)
    }
}
