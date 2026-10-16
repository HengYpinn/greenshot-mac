// Greenshot for Mac (Community) - an unofficial macOS port of Greenshot
// Copyright (C) 2026 Greenshot for Mac (Community) contributors
// Based on Greenshot, Copyright (C) 2007-2026 Thomas Braun, Jens Klingen, Robin Krom
// SPDX-License-Identifier: GPL-3.0-or-later

import CoreGraphics
import Foundation
import Testing
@testable import GreenshotCore

struct CutMarkTests {
    let band = CGRect(x: 0, y: 40, width: 100, height: 40)

    @Test func lineEdgesAreStraightAtTheToothHeight() throws {
        let shape = try #require(CutMark.shape(band: band, style: .line, toothHeight: 12, toothRange: 20, seed: 1))
        #expect(shape.first == [CGPoint(x: 0, y: 52), CGPoint(x: 100, y: 52)])
        #expect(shape.second == [CGPoint(x: 0, y: 68), CGPoint(x: 100, y: 68)])
        #expect(shape.gap.boundingBox == CGRect(x: 0, y: 52, width: 100, height: 16))
    }

    @Test func zigZagAlternatesEveryHalfTooth() throws {
        let shape = try #require(CutMark.shape(band: band, style: .zigZag, toothHeight: 10, toothRange: 20, seed: 1))
        #expect(shape.first.count == 11)
        #expect(shape.first.prefix(3) == [CGPoint(x: 0, y: 50), CGPoint(x: 10, y: 40), CGPoint(x: 20, y: 50)])
        #expect(shape.second.prefix(2) == [CGPoint(x: 0, y: 70), CGPoint(x: 10, y: 80)])
        #expect(shape.first.last?.x == 100)
    }

    @Test func edgesStayInsideTheBand() throws {
        for style in [CutMarkStyle.zigZag, .wave, .torn] {
            let shape = try #require(CutMark.shape(band: band, style: style, toothHeight: 12, toothRange: 20, seed: 7))
            for p in shape.first + shape.second {
                #expect(band.insetBy(dx: -0.001, dy: -0.001).contains(p), "\(style) \(p)")
            }
            #expect(shape.first.first?.x == 0 && shape.first.last?.x == 100)
        }
    }

    @Test func tornEdgesRepeatForTheSameSeed() throws {
        let a = try #require(CutMark.shape(band: band, style: .torn, toothHeight: 12, toothRange: 10, seed: 42))
        let b = try #require(CutMark.shape(band: band, style: .torn, toothHeight: 12, toothRange: 10, seed: 42))
        let c = try #require(CutMark.shape(band: band, style: .torn, toothHeight: 12, toothRange: 10, seed: 43))
        #expect(a.first == b.first && a.second == b.second)
        #expect(a.first != c.first || a.second != c.second)
    }

    @Test func teethAreAtMostHalfTheBand() throws {
        let thin = CGRect(x: 0, y: 0, width: 50, height: 10)
        let shape = try #require(CutMark.shape(band: thin, style: .line, toothHeight: 12, toothRange: 20, seed: 1))
        #expect(shape.first[0].y == 5 && shape.second[0].y == 5)
    }

    @Test func noneHasNoShape() {
        #expect(CutMark.shape(band: band, style: .none, toothHeight: 12, toothRange: 20, seed: 1) == nil)
    }

    @Test func spansTheWholeImageAndOnlyMovesUpAndDown() {
        let doc = EditorDocument(image: TestImage.solid(width: 120, height: 100, .white), scale: 1, title: "test")
        let mark = Annotation(kind: .cutMark, start: CGPoint(x: 30, y: 20), end: CGPoint(x: 40, y: 50))
        doc.add(mark)
        #expect(doc.annotations[0].bounds == CGRect(x: 0, y: 20, width: 120, height: 30))
        doc.move([mark.id], by: CGVector(dx: 15, dy: 5))
        #expect(doc.annotations[0].bounds == CGRect(x: 0, y: 25, width: 120, height: 30))
        #expect(Handle.handles(for: doc.annotations[0]) == [.top, .bottom])
        #expect(doc.annotations[0].hitTest(CGPoint(x: 110, y: 30), scale: 1, tolerance: 4))
        #expect(!doc.annotations[0].hitTest(CGPoint(x: 110, y: 70), scale: 1, tolerance: 4))
    }

    @Test func changingTheTeethKeepsTheGap() {
        var mark = Annotation(kind: .cutMark, start: CGPoint(x: 0, y: 20), end: CGPoint(x: 100, y: 54))
        mark.style.toothHeight = 12
        let taller = mark.withToothHeight(16, scale: 1)
        #expect(taller.bounds == CGRect(x: 0, y: 16, width: 100, height: 42))
        #expect(taller.style.toothHeight == 16)
    }

    @Test func drawsTheGapTransparentOrFilled() throws {
        let base = TestImage.solid(width: 60, height: 60, .blue)
        var mark = Annotation(kind: .cutMark, start: CGPoint(x: 0, y: 10), end: CGPoint(x: 60, y: 50))
        mark.style.cutMarkStyle = .line
        mark.style.shadow = false
        mark.style.toothHeight = 10
        let clear = try #require(AnnotationRenderer.flatten(base: base, annotations: [mark], scale: 1))
        #expect(TestImage.pixel(clear, 30, 30).a == 0)
        #expect(TestImage.pixel(clear, 30, 15).isClose(to: .blue))
        mark.style.fillColor = .white
        mark.style.lineWidth = 2
        let filled = try #require(AnnotationRenderer.flatten(base: base, annotations: [mark], scale: 1))
        #expect(TestImage.pixel(filled, 30, 30).isClose(to: .white))
        // The line along the edges is DimGray.
        #expect(TestImage.pixel(filled, 30, 20).isClose(to: RGBA(r: 105, g: 105, b: 105, a: 255), tolerance: 12))
    }

    @Test func theShadowDarkensTheGapAtItsEdges() throws {
        let base = TestImage.solid(width: 60, height: 60, .blue)
        var mark = Annotation(kind: .cutMark, start: CGPoint(x: 0, y: 0), end: CGPoint(x: 60, y: 60))
        mark.style.cutMarkStyle = .line
        mark.style.fillColor = .white
        mark.style.toothHeight = 10
        let image = try #require(AnnotationRenderer.flatten(base: base, annotations: [mark], scale: 1))
        let nearEdge = TestImage.pixel(image, 30, 11)
        let middle = TestImage.pixel(image, 30, 30)
        #expect(Int(nearEdge.r) < Int(middle.r) - 20)
        #expect(middle.isClose(to: .white, tolerance: 10))
    }

    @Test func oldRememberedStylesStillLoad() throws {
        let json = #"{"lineColor":{"red":1,"green":0,"blue":0,"alpha":1},"fillColor":{"red":0,"green":0,"blue":0,"alpha":0},"lineWidth":4,"shadow":false,"fontSize":15,"bold":false,"italic":false,"arrowHeads":"end","highlightMode":"text","obfuscateMode":"pixelate","pixelSize":5,"blurRadius":6,"magnification":2}"#
        let style = try JSONDecoder().decode(AnnotationStyle.self, from: Data(json.utf8))
        #expect(style.lineWidth == 4 && !style.shadow)
        #expect(style.cutMarkStyle == .torn && style.toothHeight == 12 && style.toothRange == 20)
    }
}
