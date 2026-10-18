// Greenshot for Mac (Community) - an unofficial macOS port of Greenshot
// Copyright (C) 2026 Greenshot for Mac (Community) contributors
// Based on Greenshot, Copyright (C) 2007-2026 Thomas Braun, Jens Klingen, Robin Krom
// SPDX-License-Identifier: GPL-3.0-or-later

import CoreGraphics
import Foundation
import Testing
@testable import GreenshotCore

/// Area and grayscale highlights change the image outside their area, once for all highlights of a mode (upstream
/// `DrawableContainerList.Draw`, 4b3d9dee; `GrayscaleFilter { Invert = true }`).
struct InvertedHighlightTests {
    static let gray = RGBA(r: 200, g: 200, b: 200, a: 255)
    static let base = TestImage.solid(width: 100, height: 60, gray)

    static func highlight(_ mode: HighlightMode, _ x: CGFloat, _ y: CGFloat, _ width: CGFloat, _ height: CGFloat,
                          brightness: Double = 0.9, blur: Double = 3) -> Annotation {
        var style = AnnotationStyle.defaults(for: .highlight)
        style.highlightMode = mode
        style.brightness = brightness
        style.blurRadius = blur
        return Annotation(kind: .highlight, start: CGPoint(x: x, y: y), end: CGPoint(x: x + width, y: y + height), style: style)
    }

    static func filled(_ color: RGBAColor, _ x: CGFloat, _ y: CGFloat) -> Annotation {
        Annotation(kind: .rectangle, start: CGPoint(x: x, y: y), end: CGPoint(x: x + 10, y: y + 10),
                   style: AnnotationStyle(lineColor: .clear, fillColor: color, lineWidth: 0, shadow: false))
    }

    static func render(_ annotations: [Annotation], on base: CGImage = base, hiding: UUID? = nil) throws -> CGImage {
        try #require(AnnotationRenderer.flatten(base: base, annotations: annotations, scale: 1, hiding: hiding))
    }

    static func isGrey(_ p: RGBA) -> Bool {
        abs(Int(p.r) - Int(p.g)) < 8 && abs(Int(p.g) - Int(p.b)) < 8
    }

    @Test func twoAreaHighlightsDimTheOutsideOnceAndBothAreasStayBright() throws {
        let first = Self.highlight(.area, 10, 10, 20, 20)
        let second = Self.highlight(.area, 50, 10, 20, 20)
        let single = try Self.render([first])
        let both = try Self.render([first, second])
        #expect(TestImage.pixel(both, 20, 20) == Self.gray)
        #expect(TestImage.pixel(both, 60, 20) == Self.gray)
        // Outside both: dimmed once, as with one highlight (200 - 25.5).
        let outside = TestImage.pixel(both, 5, 50)
        #expect(outside == TestImage.pixel(single, 5, 50))
        #expect(outside.isClose(to: RGBA(r: 174, g: 174, b: 174, a: 255), tolerance: 3))
    }

    @Test func overlappingAreasStayBrightWhereTheyOverlap() throws {
        let image = try Self.render([Self.highlight(.area, 10, 10, 30, 30), Self.highlight(.area, 30, 30, 30, 20)])
        #expect(TestImage.pixel(image, 35, 35) == Self.gray)
        #expect(TestImage.pixel(image, 15, 15) == Self.gray)
        #expect(TestImage.pixel(image, 55, 45) == Self.gray)
        #expect(TestImage.pixel(image, 90, 5) != Self.gray)
    }

    @Test func theFirstHighlightsStyleIsUsed() throws {
        let image = try Self.render([Self.highlight(.area, 10, 10, 20, 20, brightness: 0.5),
                                     Self.highlight(.area, 50, 10, 20, 20, brightness: 0.9)])
        // 200 - 127.5 at 0.5.
        #expect(TestImage.pixel(image, 5, 50).isClose(to: RGBA(r: 72, g: 72, b: 72, a: 255), tolerance: 3))
    }

    @Test func theGrayscaleHighlightGreysTheOutside() throws {
        let red = TestImage.solid(width: 100, height: 60, .red)
        let image = try Self.render([Self.highlight(.grayscale, 10, 10, 20, 20), Self.highlight(.grayscale, 50, 10, 20, 20)],
                                    on: red)
        #expect(TestImage.pixel(image, 20, 20).isClose(to: .red))
        #expect(TestImage.pixel(image, 60, 20).isClose(to: .red))
        #expect(Self.isGrey(TestImage.pixel(image, 5, 50)))
        #expect(Self.isGrey(TestImage.pixel(image, 40, 20)))
    }

    @Test func areaAndGrayscaleHighlightsAreSeparateGroups() throws {
        let red = TestImage.solid(width: 100, height: 60, .red)
        let image = try Self.render([Self.highlight(.area, 10, 10, 20, 20), Self.highlight(.grayscale, 50, 10, 20, 20)],
                                    on: red)
        // The area highlight's area is outside the grayscale one: grey, not dimmed. The grayscale one's area is outside
        // the area highlight: red, dimmed.
        let inArea = TestImage.pixel(image, 20, 20)
        #expect(Self.isGrey(inArea))
        let inGrayscale = TestImage.pixel(image, 60, 20)
        #expect(inGrayscale.r > 200)
        #expect(inGrayscale.r < 250)
        #expect(inGrayscale.g < 10)
    }

    @Test func elementsBetweenTheHighlightsStayOnTop() throws {
        // Upstream draws the group's effect where its first highlight is: what comes before is dimmed, what comes
        // after (even before the second highlight) is not.
        let blue = RGBAColor(red: 0, green: 0, blue: 1)
        let red = RGBAColor(red: 1, green: 0, blue: 0)
        let image = try Self.render([Self.filled(blue, 80, 40), Self.highlight(.area, 10, 10, 20, 20, blur: 0),
                                     Self.filled(red, 40, 40), Self.highlight(.area, 50, 10, 20, 20, blur: 0)])
        #expect(TestImage.pixel(image, 45, 45) == .red)
        // 255 - 25.5 without blur.
        #expect(TestImage.pixel(image, 85, 45).isClose(to: RGBA(r: 0, g: 0, b: 229, a: 255), tolerance: 3))
    }

    @Test func aHighlightBeingHiddenIsLeftOut() throws {
        let first = Self.highlight(.area, 10, 10, 20, 20)
        let second = Self.highlight(.area, 50, 10, 20, 20)
        let image = try Self.render([first, second], hiding: first.id)
        #expect(TestImage.pixel(image, 20, 20) != Self.gray)
        #expect(TestImage.pixel(image, 60, 20) == Self.gray)
    }

    @Test func highlightsOffTheCanvasChangeNothing() throws {
        let image = try Self.render([Self.highlight(.grayscale, 200, 200, 20, 20)],
                                    on: TestImage.solid(width: 100, height: 60, .red))
        #expect(TestImage.pixel(image, 5, 5) == .red)
    }

    /// Upstream draws a group where the first of its highlights on the canvas is (`DrawingBounds.IntersectsWith`), in
    /// the style of the first highlight of the mode.
    @Test func theGroupIsDrawnAtTheFirstHighlightOnTheCanvas() throws {
        let red = RGBAColor(red: 1, green: 0, blue: 0)
        let image = try Self.render([Self.highlight(.area, 500, 500, 20, 20, brightness: 0.5, blur: 0),
                                     Self.filled(red, 40, 40),
                                     Self.highlight(.area, 10, 10, 20, 20, brightness: 0.9, blur: 0)])
        // The red box comes before the highlight on the canvas: it is darkened, by the first highlight's 0.5.
        #expect(TestImage.pixel(image, 45, 45).isClose(to: RGBA(r: 127, g: 0, b: 0, a: 255), tolerance: 3))
        #expect(TestImage.pixel(image, 20, 20) == Self.gray)
    }

    /// The changed canvas is kept between draws; what lies below the highlights changing must show.
    @Test func aChangeBelowTheHighlightsIsNotTakenFromTheLastDraw() throws {
        let colors = [RGBAColor(red: 1, green: 0, blue: 0), RGBAColor(red: 0, green: 0, blue: 1)]
        let grayscale = Self.highlight(.grayscale, 60, 10, 20, 20)
        var greys: [RGBA] = []
        for color in colors {
            let box = Self.filled(color, 10, 40)
            let first = try Self.render([box, grayscale])
            let again = try Self.render([box, grayscale])
            #expect(TestImage.pixel(first, 15, 45) == TestImage.pixel(again, 15, 45))
            greys.append(TestImage.pixel(again, 15, 45))
        }
        // Red and blue turn into different greys.
        #expect(greys[0] != greys[1])
    }

    @Test func anotherImageIsNotTakenFromTheLastDraw() throws {
        let grayscale = Self.highlight(.grayscale, 60, 10, 20, 20)
        let red = try Self.render([grayscale], on: TestImage.solid(width: 100, height: 60, .red))
        let blue = try Self.render([grayscale], on: TestImage.solid(width: 100, height: 60, .blue))
        #expect(TestImage.pixel(red, 5, 5) != TestImage.pixel(blue, 5, 5))
        #expect(TestImage.pixel(blue, 70, 20) == .blue)
    }

    @Test func movingAnElementAboveTheHighlightsKeepsTheEffect() throws {
        let blue = RGBAColor(red: 0, green: 0, blue: 1)
        let area = Self.highlight(.area, 10, 10, 20, 20, blur: 0)
        let near = try Self.render([area, Self.filled(blue, 40, 40)])
        let moved = try Self.render([area, Self.filled(blue, 70, 40)])
        // Where the box was, the darkened image shows again; the box is drawn on top, not darkened.
        #expect(TestImage.pixel(moved, 45, 45) == TestImage.pixel(near, 5, 50))
        #expect(TestImage.pixel(moved, 75, 45) == .blue)
    }
}
