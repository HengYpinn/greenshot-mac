// Greenshot for Mac (Community) - an unofficial macOS port of Greenshot
// Copyright (C) 2026 Greenshot for Mac (Community) contributors
// Based on Greenshot, Copyright (C) 2007-2026 Thomas Braun, Jens Klingen, Robin Krom
// SPDX-License-Identifier: GPL-3.0-or-later

import AppKit
import CoreGraphics
import Foundation
import Testing
@testable import GreenshotCore

/// Text alignment, font family and the counter start value.
struct TextOptionsTests {
    func style(_ h: HorizontalTextAlignment, _ v: VerticalTextAlignment) -> AnnotationStyle {
        var style = AnnotationStyle.defaults(for: .text)
        style.horizontalAlignment = h
        style.verticalAlignment = v
        style.shadow = false
        style.lineWidth = 0
        return style
    }

    @Test func centredByDefault() {
        let style = AnnotationStyle.defaults(for: .text)
        #expect(style.horizontalAlignment == .center && style.verticalAlignment == .center)
        #expect(AnnotationStyle.defaults(for: .speechBubble).verticalAlignment == .center)
    }

    @Test func verticalAlignmentPlacesTheText() {
        let rect = CGRect(x: 0, y: 0, width: 200, height: 100)
        let top = AnnotationRenderer.textFrame("Hi", style: style(.center, .top), in: rect, scale: 1)
        let middle = AnnotationRenderer.textFrame("Hi", style: style(.center, .center), in: rect, scale: 1)
        let bottom = AnnotationRenderer.textFrame("Hi", style: style(.center, .bottom), in: rect, scale: 1)
        #expect(top.minY == 0)
        #expect(middle.minY > 30 && middle.midY > 45 && middle.midY < 55)
        #expect(bottom.maxY >= 99 && bottom.maxY <= 101)
    }

    /// The column of the leftmost red pixel in row `y`.
    func leftmostInk(_ image: CGImage, row y: Int) -> Int? {
        (0..<image.width).first { TestImage.pixel(image, $0, y).g < 200 }
    }

    func rowsWithInk(_ image: CGImage) -> [Int] {
        (0..<image.height).filter { y in stride(from: 0, to: image.width, by: 1).contains { TestImage.pixel(image, $0, y).g < 200 } }
    }

    @Test func horizontalAlignmentMovesTheText() throws {
        let base = TestImage.solid(width: 200, height: 40, .white)
        func render(_ h: HorizontalTextAlignment) throws -> CGImage {
            let a = Annotation(kind: .text, start: .zero, end: CGPoint(x: 200, y: 40), text: "Hi", style: style(h, .center))
            return try #require(AnnotationRenderer.flatten(base: base, annotations: [a], scale: 1))
        }
        let left = try render(.left), center = try render(.center), right = try render(.right)
        let row = try #require(rowsWithInk(center).dropFirst(3).first)
        let l = try #require(leftmostInk(left, row: row))
        let c = try #require(leftmostInk(center, row: row))
        let r = try #require(leftmostInk(right, row: row))
        #expect(l < 10)
        #expect(c > 80 && c < 100)
        #expect(r > 170)
    }

    @Test func fontFamilyIsUsed() {
        var style = AnnotationStyle.defaults(for: .text)
        #expect(AnnotationRenderer.font(for: style, size: 12).familyName == NSFont.systemFont(ofSize: 12).familyName)
        style.fontFamily = "Courier"
        style.bold = true
        let font = AnnotationRenderer.font(for: style, size: 12)
        #expect(font.familyName == "Courier")
        #expect(font.fontDescriptor.symbolicTraits.contains(.bold))
        style.fontFamily = "No Such Font Family"
        #expect(AnnotationRenderer.font(for: style, size: 12).familyName == NSFont.systemFont(ofSize: 12).familyName)
    }

    @Test func countersStartAtTheStartValue() {
        let doc = EditorDocument(image: TestImage.solid(width: 50, height: 50, .white), scale: 1, title: "test", isModified: false)
        let a = Annotation(kind: .counter, start: .zero, end: CGPoint(x: 10, y: 10))
        let b = Annotation(kind: .counter, start: CGPoint(x: 20, y: 0), end: CGPoint(x: 30, y: 10))
        doc.add([a, b])
        #expect(doc.counterNumber(for: b.id) == 2)
        doc.change { doc.counterStart = 5 }
        #expect(doc.counterNumber(for: a.id) == 5 && doc.counterNumber(for: b.id) == 6)
        #expect(doc.isModified)
        doc.undo()
        #expect(doc.counterStart == 1)
    }

    @Test func theRenderedCounterShowsTheStartValue() throws {
        let base = TestImage.solid(width: 60, height: 60, .white)
        let counter = Annotation(kind: .counter, start: .zero, end: CGPoint(x: 60, y: 60))
        let one = try #require(AnnotationRenderer.flatten(base: base, annotations: [counter], scale: 1))
        let eight = try #require(AnnotationRenderer.flatten(base: base, annotations: [counter], scale: 1, counterStart: 8))
        let differs = (0..<60).contains { x in (0..<60).contains { y in TestImage.pixel(one, x, y) != TestImage.pixel(eight, x, y) } }
        #expect(differs)
    }
}
