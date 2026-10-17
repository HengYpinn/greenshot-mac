// Greenshot for Mac (Community) - an unofficial macOS port of Greenshot
// Copyright (C) 2026 Greenshot for Mac (Community) contributors
// Based on Greenshot, Copyright (C) 2007-2026 Thomas Braun, Jens Klingen, Robin Krom
// SPDX-License-Identifier: GPL-3.0-or-later

import CoreGraphics
import Foundation
import Testing
@testable import GreenshotCore

/// The shared shadow of cut marks and torn edges (upstream `CutShadow`, commit 9f6726c0).
struct CutShadowTests {
    let base = TestImage.solid(width: 300, height: 300, .white)

    /// A cut mark with straight edges and a transparent gap: rows 100..<160, or columns 100..<160 when `vertical`.
    private func mark(vertical: Bool = false, _ change: (inout Annotation) -> Void = { _ in }) -> Annotation {
        var a = vertical
            ? Annotation(kind: .cutMark, start: CGPoint(x: 90, y: 0), end: CGPoint(x: 170, y: 300))
            : Annotation(kind: .cutMark, start: CGPoint(x: 0, y: 90), end: CGPoint(x: 300, y: 170))
        a.verticalCut = vertical
        a.seed = 1
        a.style.cutMarkStyle = .line
        a.style.toothHeight = 10
        a.style.fillColor = .clear
        change(&a)
        return a
    }

    private func render(_ annotations: [Annotation]) throws -> CGImage {
        try #require(AnnotationRenderer.flatten(base: base, annotations: annotations, scale: 1))
    }

    /// The biggest difference of a color or alpha value between the two images, on a grid of every third pixel.
    private func difference(_ a: CGImage, _ b: CGImage) -> Int {
        var worst = 0
        for y in stride(from: 0, to: 300, by: 3) {
            for x in stride(from: 0, to: 300, by: 3) {
                let p = TestImage.pixel(a, x, y)
                let q = TestImage.pixel(b, x, y)
                let channels = [Int(p.r) - Int(q.r), Int(p.g) - Int(q.g), Int(p.b) - Int(q.b), Int(p.a) - Int(q.a)]
                worst = max(worst, channels.map(abs).max() ?? 0)
            }
        }
        return worst
    }

    @Test func twoCutsOfTheSameGapLookLikeOne() throws {
        let one = mark()
        let single = try render([one])
        let twice = try render([one, one.withNewID()])
        // The second has the whole gap, the first none of it: the shadow is there once, as with one cut.
        #expect(difference(single, twice) <= 2)
        let nearEdge = TestImage.pixel(twice, 150, 101)
        #expect(nearEdge.a > 40)
    }

    @Test func anotherGapCastsNoShadow() throws {
        // The vertical cut is drawn last: where the gaps cross, its shadow is the one that shows.
        let image = try render([mark(), mark(vertical: true)])
        // In the vertical gap next to the image on its left: the image casts a shadow.
        let besideTheImage = TestImage.pixel(image, 101, 50)
        #expect(besideTheImage.a > 40)
        // Where the two gaps cross, left of it is the other gap, not the image: no shadow comes from there.
        let besideTheOtherGap = TestImage.pixel(image, 101, 130)
        #expect(besideTheOtherGap.a < 10)
    }

    @Test func aCutIsAloneWithoutOthers() throws {
        let one = mark()
        let cuts = CutShadow([one, Annotation(kind: .rectangle, start: .zero, end: CGPoint(x: 10, y: 10))],
                             canvas: CGRect(x: 0, y: 0, width: 300, height: 300), scale: 1)
        #expect(cuts.cuts.count == 1)
        #expect(cuts.isAlone(one.id))
        // A cut mark that cuts nothing (style None) is no cut.
        let none = mark(vertical: true) { $0.style.cutMarkStyle = .none }
        let withNone = CutShadow([one, none], canvas: CGRect(x: 0, y: 0, width: 300, height: 300), scale: 1)
        #expect(withNone.isAlone(one.id))
    }

    @Test func theLineAlongAnEdgeDoesNotShowInAnotherGap() throws {
        let lined = mark { $0.style.lineWidth = 4; $0.style.lineColor = .blue; $0.style.shadow = false }
        let image = try render([mark(vertical: true) { $0.style.shadow = false }, lined])
        // Along the image the line shows, inside the vertical gap it doesn't.
        let onTheImage = TestImage.pixel(image, 50, 100)
        let inTheGap = TestImage.pixel(image, 130, 100)
        #expect(onTheImage.isClose(to: .blue, tolerance: 20))
        #expect(inTheGap.a == 0)
    }

    @Test func cutsThatAreNotDrawnStillShareTheShadow() throws {
        // Apply to the Image draws only the chosen cuts, with the ones that stay elements cutting the image too.
        let vertical = mark(vertical: true)
        let horizontal = mark()
        let alone = try render([horizontal])
        let shared = try #require(AnnotationRenderer.flatten(base: base, annotations: [horizontal], scale: 1,
                                                             cutElements: [vertical, horizontal]))
        // Below the vertical gap, where the two cross: the image above casts a shadow, the other gap doesn't.
        let withImageAbove = TestImage.pixel(alone, 130, 101)
        let withGapAbove = TestImage.pixel(shared, 130, 101)
        #expect(withImageAbove.a > 40)
        #expect(withGapAbove.a < 10)
    }
}
