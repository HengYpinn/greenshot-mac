// Greenshot for Mac (Community) - an unofficial macOS port of Greenshot
// Copyright (C) 2026 Greenshot for Mac (Community) contributors
// Based on Greenshot, Copyright (C) 2007-2026 Thomas Braun, Jens Klingen, Robin Krom
// SPDX-License-Identifier: GPL-3.0-or-later

import CoreGraphics
import Foundation
import Testing
@testable import GreenshotCore

/// Torn edges as an element (upstream `TornEdgeContainer`, commit 9f6726c0).
struct TornEdgeTests {
    let size = CGSize(width: 200, height: 120)

    private func shape(_ layout: CutEdgeLayout = CutEdgeLayout(), style: CutMarkStyle = .torn, teeth: CGFloat = 12,
                       range: CGFloat = 20, seed: UInt64 = 7) -> TornEdge.Shape? {
        TornEdge.shape(imageSize: size, layout: layout, style: style, toothHeight: teeth, toothRange: range, seed: seed)
    }

    private func element(_ change: (inout Annotation) -> Void = { _ in }) -> Annotation {
        var a = Annotation(kind: .tornEdge, start: .zero, end: CGPoint(x: size.width, y: size.height))
        a.seed = 7
        a.cutEdges = CutEdgeLayout()
        change(&a)
        return a
    }

    @Test func untornSidesStayOnTheBorder() throws {
        let layout = CutEdgeLayout(top: true, right: false, bottom: false, left: false)
        let result = try #require(shape(layout, style: .zigZag))
        #expect(result.tornSides.count == 1)
        let top = try #require(result.tornSides.first)
        for p in top {
            #expect(p.y >= 0)
            #expect(p.y <= 12)
        }
        // The other three sides are the image's corners.
        let rest = result.outline.dropFirst(top.count)
        #expect(Array(rest) == [CGPoint(x: 200, y: 0), CGPoint(x: 200, y: 120), CGPoint(x: 200, y: 120),
                                CGPoint(x: 0, y: 120), CGPoint(x: 0, y: 120), CGPoint(x: 0, y: 0)])
    }

    @Test func tornSidesStayWithinTheirTeeth() throws {
        for style in [CutMarkStyle.line, .zigZag, .wave, .torn] {
            let result = try #require(shape(style: style))
            #expect(result.tornSides.count == 4)
            let top = result.tornSides[0], right = result.tornSides[1], bottom = result.tornSides[2], left = result.tornSides[3]
            #expect(top.allSatisfy { $0.y >= 0 && $0.y <= 12 }, "\(style)")
            #expect(right.allSatisfy { $0.x >= 188 && $0.x <= 200 }, "\(style)")
            #expect(bottom.allSatisfy { $0.y >= 108 && $0.y <= 120 }, "\(style)")
            #expect(left.allSatisfy { $0.x >= 0 && $0.x <= 12 }, "\(style)")
        }
    }

    @Test func aTornSideLeavesTheCornerToItsNeighbour() throws {
        let result = try #require(shape(style: .line))
        // Straight torn sides along the border, each inset by the teeth where the next side is torn too.
        let top = try #require(result.tornSides.first)
        #expect(top.first == CGPoint(x: 12, y: 0))
        #expect(top.last == CGPoint(x: 188, y: 0))
    }

    @Test func theSameSeedGivesTheSameEdges() throws {
        let a = try #require(shape(seed: 42))
        let b = try #require(shape(seed: 42))
        let c = try #require(shape(seed: 43))
        #expect(a.outline == b.outline)
        #expect(a.outline != c.outline)
    }

    @Test func theTeethAreAtMostAThirdOfTheImage() throws {
        let small = TornEdge.shape(imageSize: CGSize(width: 30, height: 30), layout: CutEdgeLayout(), style: .line,
                                   toothHeight: 40, toothRange: 20, seed: 1)
        let top = try #require(small?.tornSides.first)
        #expect(top.first == CGPoint(x: 10, y: 0))
    }

    @Test func noneOrNoSideDrawsNothing() {
        #expect(shape(style: .none) == nil)
        #expect(shape(CutEdgeLayout(top: false, right: false, bottom: false, left: false)) == nil)
        let tooSmall = TornEdge.shape(imageSize: CGSize(width: 20, height: 20),
                                      layout: CutEdgeLayout(marginTop: 9, marginRight: 9, marginBottom: 9, marginLeft: 9),
                                      style: .torn, toothHeight: 12, toothRange: 20, seed: 1)
        #expect(tooSmall == nil)
    }

    @Test func theEdgesAreInsideTheRoomForTheShadow() throws {
        let layout = CutEdgeLayout(marginTop: 10, marginRight: 20, marginBottom: 30, marginLeft: 40)
        let result = try #require(shape(layout))
        let inside = CGRect(x: 40, y: 10, width: 140, height: 80)
        for p in result.outline {
            #expect(inside.insetBy(dx: -0.001, dy: -0.001).contains(p), "\(p)")
        }
    }

    @Test func theElementCoversTheWholeImageAndDoesNotMove() {
        let doc = EditorDocument(image: TestImage.solid(width: 200, height: 120, .white), scale: 1, title: "test")
        var a = element()
        a.start = CGPoint(x: 30, y: 30)
        doc.add(a)
        #expect(doc.annotations[0].bounds == CGRect(x: 0, y: 0, width: 200, height: 120))
        doc.move([a.id], by: CGVector(dx: 15, dy: 5))
        #expect(doc.annotations[0].bounds == CGRect(x: 0, y: 0, width: 200, height: 120))
        doc.resizeCanvas(left: 10, right: 0, top: 0, bottom: 4)
        #expect(doc.annotations[0].bounds == CGRect(x: 0, y: 0, width: 210, height: 124))
        #expect(Handle.handles(for: doc.annotations[0]).isEmpty)
        let docked = doc.annotations[0].docked(to: .right, imageSize: CGSize(width: 400, height: 400))
        #expect(docked.bounds == doc.annotations[0].bounds)
        #expect(!doc.pushOut(a.id, to: .right))
    }

    @Test func onlyTheTornSidesCanBeClicked() {
        let a = element { $0.cutEdges = CutEdgeLayout(top: true, right: false, bottom: false, left: true) }
        #expect(a.hitTest(CGPoint(x: 100, y: 5), scale: 1, tolerance: 4))
        #expect(a.hitTest(CGPoint(x: 5, y: 60), scale: 1, tolerance: 4))
        #expect(!a.hitTest(CGPoint(x: 100, y: 60), scale: 1, tolerance: 4))
        #expect(!a.hitTest(CGPoint(x: 100, y: 115), scale: 1, tolerance: 4))
        #expect(!a.hitTest(CGPoint(x: 195, y: 60), scale: 1, tolerance: 4))
        #expect(!a.hitTest(CGPoint(x: 100, y: 130), scale: 1, tolerance: 4))
    }

    @Test func addingTornEdgesMakesRoomForTheShadow() throws {
        let doc = EditorDocument(image: TestImage.solid(width: 100, height: 80, .white), scale: 2, title: "test")
        let box = Annotation(kind: .rectangle, start: CGPoint(x: 10, y: 10), end: CGPoint(x: 30, y: 30))
        doc.add(box)
        // Upstream GetShadowMargin: shadow size 7 + the larger offset 1 = 8 points, 16 pixels on a Retina capture.
        let id = try #require(doc.addTornEdges(TornEdgeSettings(), seed: 3))
        #expect(doc.imageSize == CGSize(width: 132, height: 112))
        #expect(doc.annotations[0].start == CGPoint(x: 26, y: 26))
        let torn = try #require(doc.annotation(id))
        #expect(torn.kind == .tornEdge)
        #expect(torn.bounds == CGRect(x: 0, y: 0, width: 132, height: 112))
        #expect(torn.cutEdges?.marginLeft == 16)
        #expect(torn.cutEdges?.marginBottom == 16)
        #expect(torn.seed == 3)
        // There is only one: adding again picks the existing torn edges and changes nothing.
        let again = doc.addTornEdges(TornEdgeSettings())
        #expect(again == id)
        #expect(doc.imageSize == CGSize(width: 132, height: 112))
        #expect(doc.annotations.count == 2)
    }

    @Test func withoutAShadowTheCanvasStays() throws {
        let doc = EditorDocument(image: TestImage.solid(width: 100, height: 80, .white), scale: 1, title: "test")
        var settings = TornEdgeSettings()
        settings.shadow = false
        settings.top = false
        let id = try #require(doc.addTornEdges(settings))
        #expect(doc.imageSize == CGSize(width: 100, height: 80))
        let torn = try #require(doc.annotation(id))
        #expect(torn.cutEdges?.top == false)
        #expect(torn.cutEdges?.marginTop == 0)
        #expect(!torn.style.shadow)
    }

    @Test func theSettingsGoBackAndForth() {
        let settings = TornEdgeSettings(toothHeight: 9, horizontalToothRange: 25, verticalToothRange: 25, top: true,
                                        left: false, right: true, bottom: false, shadow: true, shadowDarkness: 0.5,
                                        shadowSize: 5, shadowOffsetX: 3, shadowOffsetY: -2, backgroundColor: .yellow)
        let torn = Annotation.tornEdges(settings, imageSize: size, margin: 4)
        #expect(torn.cutEdgeSettings == settings)
        #expect(torn.style.cutMarkStyle == .torn)
        #expect(torn.cutEdges?.marginRight == 4)
    }

    @Test func theTornOffPartsAreTransparentOrFilled() throws {
        let doc = EditorDocument(image: TestImage.solid(width: 120, height: 120, .white), scale: 1, title: "test")
        doc.add(Annotation.tornEdges(TornEdgeSettings(shadow: false), imageSize: doc.imageSize, margin: 0, seed: 5))
        let image = doc.flattened()
        #expect(TestImage.pixel(image, 0, 0).a == 0)
        #expect(TestImage.pixel(image, 119, 60).a == 0)
        #expect(TestImage.pixel(image, 60, 60) == .white)

        var filled = doc.annotations[0]
        filled.style.fillColor = .red
        doc.update(filled)
        let red = doc.flattened()
        #expect(TestImage.pixel(red, 0, 0) == .red)
        #expect(TestImage.pixel(red, 60, 60) == .white)
    }

    @Test func theShadowFallsIntoTheTornOffPart() throws {
        // With seed 5 the right torn edge is near x 113 at y 60; the shadow falls 2 points right of it and fades.
        func rightEdge(shadow: Bool) -> RGBA {
            let doc = EditorDocument(image: TestImage.solid(width: 120, height: 120, .white), scale: 1, title: "test")
            var settings = TornEdgeSettings()
            settings.shadow = shadow
            doc.add(Annotation.tornEdges(settings, imageSize: doc.imageSize, margin: 0, seed: 5))
            return TestImage.pixel(doc.flattened(), 115, 60)
        }
        #expect(rightEdge(shadow: false).a == 0)
        let shadow = rightEdge(shadow: true)
        #expect(shadow.a > 40)
        #expect(shadow.r < 20)
    }

    @Test func theLineFollowsTheTornSides() throws {
        let doc = EditorDocument(image: TestImage.solid(width: 120, height: 120, .white), scale: 1, title: "test")
        var torn = Annotation.tornEdges(TornEdgeSettings(shadow: false), imageSize: doc.imageSize, margin: 0, seed: 5)
        torn.style.cutMarkStyle = .line
        torn.style.lineWidth = 4
        torn.style.lineColor = .blue
        doc.add(torn)
        let image = doc.flattened()
        #expect(TestImage.pixel(image, 60, 0).isClose(to: .blue, tolerance: 30))
        #expect(TestImage.pixel(image, 60, 60) == .white)
    }

    @Test func rotatingTurnsTheSidesAndTheirRoom() throws {
        let doc = EditorDocument(image: TestImage.solid(width: 200, height: 120, .white), scale: 1, title: "test")
        let torn = element { $0.cutEdges = CutEdgeLayout(top: true, right: false, bottom: false, left: false, marginTop: 5) }
        doc.add(torn)
        doc.rotateImage(clockwise: true)
        let turned = try #require(doc.annotation(torn.id))
        #expect(turned.bounds == CGRect(x: 0, y: 0, width: 120, height: 200))
        #expect(turned.cutEdges?.right == true)
        #expect(turned.cutEdges?.top == false)
        #expect(turned.cutEdges?.marginRight == 5)
        doc.rotateImage(clockwise: false)
        let back = try #require(doc.annotation(torn.id))
        #expect(back.cutEdges == torn.cutEdges)
    }

    @Test func resizingScalesTheRoom() throws {
        let doc = EditorDocument(image: TestImage.solid(width: 200, height: 120, .white), scale: 1, title: "test")
        let torn = element { $0.cutEdges = CutEdgeLayout(marginTop: 10, marginRight: 10, marginBottom: 10, marginLeft: 10) }
        doc.add(torn)
        doc.resizeImage(to: CGSize(width: 400, height: 60))
        let resized = try #require(doc.annotation(torn.id))
        #expect(resized.bounds == CGRect(x: 0, y: 0, width: 400, height: 60))
        #expect(resized.cutEdges?.marginLeft == 20)
        #expect(resized.cutEdges?.marginTop == 5)
    }

    @Test func aCropTakesTheEdgesOfTheSidesItCutOff() throws {
        let doc = EditorDocument(image: TestImage.solid(width: 200, height: 120, .white), scale: 1, title: "test")
        let torn = element { $0.cutEdges = CutEdgeLayout(marginTop: 3, marginRight: 3, marginBottom: 3, marginLeft: 3) }
        doc.add(torn)
        #expect(doc.cropKeepingEdges(to: CGRect(x: 0, y: 0, width: 150, height: 120)))
        let cropped = try #require(doc.annotation(torn.id))
        #expect(cropped.bounds == CGRect(x: 0, y: 0, width: 150, height: 120))
        #expect(cropped.cutEdges?.right == false)
        #expect(cropped.cutEdges?.marginRight == 0)
        #expect(cropped.cutEdges?.left == true)
        #expect(cropped.cutEdges?.marginLeft == 3)
        // Cutting off every remaining torn side removes the element.
        #expect(doc.cropKeepingEdges(to: CGRect(x: 10, y: 10, width: 100, height: 100)))
        #expect(doc.annotation(torn.id) == nil)
    }

    @Test func applyingTornEdgesDrawsThemIntoTheImage() throws {
        let doc = EditorDocument(image: TestImage.solid(width: 120, height: 120, .white), scale: 1, title: "test")
        let torn = Annotation.tornEdges(TornEdgeSettings(shadow: false), imageSize: doc.imageSize, margin: 0, seed: 5)
        doc.add(torn)
        let box = Annotation(kind: .rectangle, start: CGPoint(x: 40, y: 40), end: CGPoint(x: 80, y: 80))
        doc.add(box)
        var applied = false
        doc.change { applied = doc.applyToImage([torn.id, box.id]) }
        #expect(applied)
        // Only the torn edges went into the image; the rectangle stays an element.
        #expect(doc.annotations.map(\.id) == [box.id])
        #expect(TestImage.pixel(doc.baseImage, 0, 0).a == 0)
        #expect(TestImage.pixel(doc.baseImage, 60, 60) == .white)
        doc.undo()
        #expect(doc.annotations.map(\.id) == [torn.id, box.id])
        #expect(TestImage.pixel(doc.baseImage, 0, 0) == .white)
        #expect(!doc.applyToImage([box.id]))
    }

    @Test func layoutsFromElsewhereAreLimited() throws {
        let empty = try JSONDecoder().decode(CutEdgeLayout.self, from: Data("{}".utf8))
        #expect(empty == CutEdgeLayout())
        let json = #"{"shadowSize": 99, "shadowDarkness": 3, "shadowOffsetX": -50, "marginTop": -5, "marginLeft": 100000, "top": false}"#
        let wild = try JSONDecoder().decode(CutEdgeLayout.self, from: Data(json.utf8))
        #expect(wild.shadowSize == 20)
        #expect(wild.shadowDarkness == 1)
        #expect(wild.shadowOffsetX == -20)
        #expect(wild.marginTop == 0)
        #expect(wild.marginLeft == 4000)
        #expect(!wild.top)
    }

    @Test func anElementKeepsItsLayoutThroughCoding() throws {
        let torn = Annotation.tornEdges(TornEdgeSettings(), imageSize: size, margin: 6, seed: 11)
        let data = try JSONEncoder().encode(torn)
        let decoded = try JSONDecoder().decode(Annotation.self, from: data)
        #expect(decoded == torn)
    }
}
