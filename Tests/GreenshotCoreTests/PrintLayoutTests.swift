// SPDX-License-Identifier: GPL-3.0-or-later

import CoreGraphics
import Foundation
import Testing
@testable import GreenshotCore

struct PrintLayoutTests {
    private let page = CGSize(width: 500, height: 800)

    private func options(shrink: Bool = false, enlarge: Bool = false, rotate: Bool = false, center: Bool = false) -> PrintSettings {
        var o = PrintSettings()
        o.allowShrink = shrink
        o.allowEnlarge = enlarge
        o.allowRotate = rotate
        o.center = center
        return o
    }

    @Test func noFlagsKeepsTheSizeInTheTopLeftCorner() {
        let layout = PrintLayout.layout(image: CGSize(width: 1000, height: 400), page: page, footer: nil, options: options())
        #expect(layout.imageRect == CGRect(x: 0, y: 0, width: 1000, height: 400))
        #expect(!layout.rotated && layout.footerOrigin == nil)
    }

    @Test func shrinkFitsABigImageButNeverEnlarges() {
        let big = PrintLayout.layout(image: CGSize(width: 1000, height: 400), page: page, footer: nil, options: options(shrink: true))
        #expect(big.imageRect == CGRect(x: 0, y: 0, width: 500, height: 200))
        let small = PrintLayout.layout(image: CGSize(width: 100, height: 50), page: page, footer: nil, options: options(shrink: true))
        #expect(small.imageRect.size == CGSize(width: 100, height: 50))
    }

    @Test func enlargeFillsThePageButNeverShrinks() {
        let small = PrintLayout.layout(image: CGSize(width: 100, height: 50), page: page, footer: nil, options: options(enlarge: true))
        #expect(small.imageRect.size == CGSize(width: 500, height: 250))
        let big = PrintLayout.layout(image: CGSize(width: 1000, height: 400), page: page, footer: nil, options: options(enlarge: true))
        #expect(big.imageRect.size == CGSize(width: 1000, height: 400))
    }

    @Test func rotateTurnsAWideImageOnAPortraitPage() {
        let layout = PrintLayout.layout(image: CGSize(width: 1000, height: 400), page: page, footer: nil,
                                        options: options(shrink: true, rotate: true))
        #expect(layout.rotated)
        // Rotated it is 400 × 1000, shrunk to 320 × 800, and goes to the top right like upstream.
        #expect(layout.imageRect == CGRect(x: 180, y: 0, width: 320, height: 800))
        let tall = PrintLayout.layout(image: CGSize(width: 300, height: 400), page: page, footer: nil, options: options(rotate: true))
        #expect(!tall.rotated)
    }

    @Test func centerAndFooter() {
        let footer = CGSize(width: 100, height: 20)
        let layout = PrintLayout.layout(image: CGSize(width: 100, height: 100), page: page, footer: footer, options: options(center: true))
        // The footer takes 20 points off the bottom; the image is centred in the rest.
        #expect(layout.imageRect == CGRect(x: 200, y: 340, width: 100, height: 100))
        #expect(layout.footerOrigin == CGPoint(x: 200, y: 780))
    }

    @Test func footerPatternFillsWithoutMakingTheTitleFilenameSafe() {
        var s = PrintSettings()
        s.footerPattern = "${capturetime:d\"yyyy-MM-dd\"} - ${title}"
        let context = FilenamePattern.Context(captureTime: Date(timeIntervalSince1970: 0), title: "a/b: c",
                                              locale: Locale(identifier: "en_US_POSIX"), timeZone: TimeZone(identifier: "UTC")!)
        #expect(FilenamePattern.fill(s.footerPattern, context: context, filenameSafe: false) == "1970-01-01 - a/b: c")
    }

    @Test func colorsInvertGrayscaleAndMonochrome() {
        let image = TestImage.make(width: 2, height: 1) { x, _ in x == 0 ? RGBA(r: 200, g: 200, b: 200, a: 255) : .red }
        var o = PrintSettings()
        #expect(PrintColors.apply(image, options: o) === image)
        o.inverted = true
        #expect(TestImage.pixel(PrintColors.apply(image, options: o), 1, 0).isClose(to: RGBA(r: 0, g: 255, b: 255, a: 255)))
        o.inverted = false
        o.grayscale = true
        let gray = TestImage.pixel(PrintColors.apply(image, options: o), 1, 0)
        #expect(gray.r == gray.g && gray.g == gray.b && gray.isClose(to: RGBA(r: 76, g: 76, b: 76, a: 255)))
        o.grayscale = false
        o.monochrome = true
        o.monochromeThreshold = 127
        let mono = PrintColors.apply(image, options: o)
        #expect(TestImage.pixel(mono, 0, 0) == .white)
        #expect(TestImage.pixel(mono, 1, 0) == .black)
    }
}
