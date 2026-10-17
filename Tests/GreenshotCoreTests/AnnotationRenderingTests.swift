// Greenshot for Mac (Community) - an unofficial macOS port of Greenshot
// Copyright (C) 2026 Greenshot for Mac (Community) contributors
// Based on Greenshot, Copyright (C) 2007-2026 Thomas Braun, Jens Klingen, Robin Krom
// SPDX-License-Identifier: GPL-3.0-or-later

import CoreGraphics
import Foundation
import Testing
@testable import GreenshotCore

/// The text element's frame, the area highlight's brightness and the cut-edge previews.
struct AnnotationRenderingTests {
    func render(_ annotations: [Annotation], base: CGImage = TestImage.solid(width: 100, height: 60, .white)) throws -> CGImage {
        try #require(AnnotationRenderer.flatten(base: base, annotations: annotations, scale: 1))
    }

    func text(_ change: (inout AnnotationStyle) -> Void) -> Annotation {
        var style = AnnotationStyle.defaults(for: .text)
        style.shadow = false
        change(&style)
        return Annotation(kind: .text, start: CGPoint(x: 10, y: 10), end: CGPoint(x: 90, y: 50), text: "", style: style)
    }

    @Test func aTextElementHasAFrameOfItsLineWidth() throws {
        // Upstream `TextContainer` draws its box like a rectangle: a 2 px frame in the text colour by default.
        #expect(AnnotationStyle.defaults(for: .text).lineWidth == 2)
        let framed = try render([text { _ in }])
        #expect(TestImage.pixel(framed, 10, 30).isClose(to: .red, tolerance: 40))
        #expect(TestImage.pixel(framed, 50, 30) == .white)
        let frameless = try render([text { $0.lineWidth = 0 }])
        #expect(TestImage.pixel(frameless, 10, 30) == .white)
    }

    @Test func theTextMovesInByHalfTheFrame() {
        let thin = text { $0.lineWidth = 0 }
        let thick = text { $0.lineWidth = 10 }
        #expect(AnnotationRenderer.textRect(for: thin, scale: 1) == CGRect(x: 12, y: 12, width: 76, height: 36))
        #expect(AnnotationRenderer.textRect(for: thick, scale: 1) == CGRect(x: 17, y: 17, width: 66, height: 26))
    }

    @Test func aFilledTextBoxCastsTheShadowNotItsText() throws {
        // Upstream draws the text's shadow only without a fill; the box's shadow is there either way.
        var a = text { $0.lineWidth = 0; $0.fillColor = .white; $0.shadow = true; $0.fontSize = 30 }
        a.text = "W"
        let image = try render([a], base: TestImage.solid(width: 100, height: 60, RGBA(r: 0, g: 0, b: 255, a: 255)))
        // Below and right of the box, the image is darker (shadow); inside, nothing is grey except the letter.
        let outside = TestImage.pixel(image, 91, 52)
        #expect(outside.b < 250)
    }

    @Test func theAreaHighlightDarkensByItsBrightness() throws {
        let base = TestImage.solid(width: 100, height: 60, RGBA(r: 200, g: 200, b: 200, a: 255))
        func outside(_ brightness: Double) throws -> RGBA {
            var style = AnnotationStyle.defaults(for: .highlight)
            style.highlightMode = .area
            style.brightness = brightness
            let a = Annotation(kind: .highlight, start: CGPoint(x: 40, y: 20), end: CGPoint(x: 60, y: 40), style: style)
            let image = try render([a], base: base)
            #expect(TestImage.pixel(image, 50, 30) == RGBA(r: 200, g: 200, b: 200, a: 255))
            return TestImage.pixel(image, 5, 5)
        }
        // Upstream adds brightness − 1 to each channel: 200 − 25.5 at 0.9, 200 − 127.5 at 0.5.
        #expect(try outside(0.9).isClose(to: RGBA(r: 174, g: 174, b: 174, a: 255), tolerance: 3))
        #expect(try outside(0.5).isClose(to: RGBA(r: 72, g: 72, b: 72, a: 255), tolerance: 3))
        #expect(try outside(1).isClose(to: RGBA(r: 200, g: 200, b: 200, a: 255), tolerance: 2))
    }

    @Test func theAreaHighlightUsesUpstreamsDefaults() {
        let style = AnnotationStyle.defaults(for: .highlight)
        #expect(style.brightness == 0.9 && style.blurRadius == 3)
        // Styles remembered before the brightness existed load with the default.
        let json = #"{"lineColor":{"red":1,"green":0,"blue":0,"alpha":1},"lineWidth":4}"#
        #expect((try? JSONDecoder().decode(AnnotationStyle.self, from: Data(json.utf8)))?.brightness == 0.9)
    }

    @Test func cutEdgePreviewsShowTheirStyle() throws {
        var pictures: [Data] = []
        for style in CutMarkStyle.allCases {
            let image = try #require(CutMark.previewImage(style))
            #expect(image.width == 32 && image.height == 32)
            // A transparent border, the parts in steel blue.
            #expect(TestImage.pixel(image, 1, 1).a == 0)
            #expect(TestImage.pixel(image, 16, 5).isClose(to: RGBA(r: 70, g: 130, b: 180, a: 255), tolerance: 2))
            pictures.append(try ImageExporter.data(for: image, format: .png))
        }
        // None is solid; the others show the gap's checkerboard in the middle, each with its own edges.
        let none = try #require(CutMark.previewImage(.none))
        #expect(TestImage.pixel(none, 16, 16).isClose(to: RGBA(r: 70, g: 130, b: 180, a: 255), tolerance: 2))
        let line = try #require(CutMark.previewImage(.line))
        #expect(TestImage.pixel(line, 16, 14).b > 180 && TestImage.pixel(line, 16, 14).r > 180)
        #expect(Set(pictures).count == CutMarkStyle.allCases.count)
    }
}
