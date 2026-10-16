// SPDX-License-Identifier: GPL-3.0-or-later

import CoreGraphics
import Foundation
import Testing
@testable import GreenshotCore

struct ImageEffectsTests {
    let white = TestImage.solid(width: 40, height: 30, .white)

    func apply(_ effect: ImageEffect, to image: CGImage? = nil, scale: CGFloat = 1, seed: UInt64 = 1) throws -> EffectResult {
        try #require(ImageEffects.apply(effect, to: image ?? white, scale: scale, seed: seed))
    }

    func bytes(_ image: CGImage) -> Data? {
        image.dataProvider?.data as Data?
    }

    @Test func borderGrowsTheImageByTheLineOnEachSide() throws {
        let result = try apply(.border)
        #expect(result.image.width == 44 && result.image.height == 34)
        #expect(result.offset == CGVector(dx: 2, dy: 2))
        #expect(TestImage.pixel(result.image, 1, 17) == .black)
        #expect(TestImage.pixel(result.image, 22, 1) == .black)
        #expect(TestImage.pixel(result.image, 22, 17) == .white)
        let retina = try apply(.border, scale: 2)
        #expect(retina.image.width == 48 && retina.offset == CGVector(dx: 4, dy: 4))
    }

    @Test func dropShadowFallsToTheBottomRight() throws {
        let result = try apply(.dropShadow)
        // Upstream: 7 px on every side, the image at 5, 5.
        #expect(result.image.width == 54 && result.image.height == 44)
        #expect(result.offset == CGVector(dx: 5, dy: 5))
        #expect(TestImage.pixel(result.image, 25, 20) == .white)
        let belowRight = TestImage.pixel(result.image, 45, 30)
        let aboveLeft = TestImage.pixel(result.image, 2, 2)
        #expect(belowRight.a > 60 && belowRight.r == 0)
        #expect(aboveLeft.a < belowRight.a / 4)
    }

    @Test func tornEdgesCutTheBorderAndAddAShadow() throws {
        let base = TestImage.solid(width: 200, height: 150, .white)
        let result = try apply(.tornEdge, to: base)
        #expect(result.image.width == 214 && result.image.height == 164)
        #expect(result.offset == CGVector(dx: 5, dy: 5))
        // The first row of the image is always torn off; the middle stays.
        #expect(TestImage.pixel(result.image, 5, 5) != .white)
        #expect(TestImage.pixel(result.image, 105, 5) != .white)
        #expect(TestImage.pixel(result.image, 105, 80) == .white)
    }

    @Test func theSameSeedTearsTheSameEdges() throws {
        let base = TestImage.solid(width: 120, height: 90, .white)
        let first = try apply(.tornEdge, to: base, seed: 7)
        let again = try apply(.tornEdge, to: base, seed: 7)
        let other = try apply(.tornEdge, to: base, seed: 8)
        #expect(bytes(first.image) == bytes(again.image))
        #expect(bytes(first.image) != bytes(other.image))
    }

    @Test func grayscaleUsesUpstreamsWeights() throws {
        let red = TestImage.solid(width: 4, height: 4, .red)
        let result = try apply(.grayscale, to: red)
        #expect(TestImage.pixel(result.image, 1, 1) == RGBA(r: 77, g: 77, b: 77, a: 255))
        #expect(result.offset == .zero && result.image.width == 4)
    }

    @Test func invertKeepsTransparency() throws {
        let image = TestImage.make(width: 4, height: 1) { x, _ in
            [RGBA.white, .red, RGBA(r: 0, g: 0, b: 0, a: 0), RGBA(r: 128, g: 128, b: 128, a: 255)][x]
        }
        let result = try apply(.invert, to: image)
        #expect(TestImage.pixel(result.image, 0, 0) == .black)
        #expect(TestImage.pixel(result.image, 1, 0) == RGBA(r: 0, g: 255, b: 255, a: 255))
        #expect(TestImage.pixel(result.image, 2, 0).a == 0)
        #expect(TestImage.pixel(result.image, 3, 0) == RGBA(r: 127, g: 127, b: 127, a: 255))
    }

    @Test func anEffectIsOneUndoStepAndMovesTheElements() {
        let doc = EditorDocument(image: white, scale: 1, title: "test", isModified: false)
        let arrow = Annotation(kind: .arrow, start: CGPoint(x: 5, y: 5), end: CGPoint(x: 20, y: 20))
        doc.change { doc.add(arrow) }
        doc.change { #expect(doc.apply(.border)) }
        #expect(doc.imageSize == CGSize(width: 44, height: 34))
        #expect(doc.annotations[0].start == CGPoint(x: 7, y: 7))
        doc.undo()
        #expect(doc.imageSize == CGSize(width: 40, height: 30))
        #expect(doc.annotations[0].start == CGPoint(x: 5, y: 5))
        doc.redo()
        #expect(doc.imageSize == CGSize(width: 44, height: 34))
    }

    @Test func anEffectThatKeepsTheSizeStillLeavesAnUndoStep() {
        let doc = EditorDocument(image: white, scale: 1, title: "test", isModified: false)
        doc.change { doc.apply(.grayscale) }
        #expect(doc.canUndo && doc.isModified)
    }
}
