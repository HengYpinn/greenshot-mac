// Greenshot for Mac (Community) - an unofficial macOS port of Greenshot
// Copyright (C) 2026 Greenshot for Mac (Community) contributors
// Based on Greenshot, Copyright (C) 2007-2026 Thomas Braun, Jens Klingen, Robin Krom
// SPDX-License-Identifier: GPL-3.0-or-later

import Foundation
import Testing
@testable import GreenshotCore

/// The colour, line width and shadow shortcuts of the selection (upstream `Surface.ProcessCmdKey`).
struct ElementShortcutsTests {
    @Test func digitsPickUpstreamsColours() {
        #expect(ElementShortcuts.color(digit: 0, line: false) == .clear)
        #expect(ElementShortcuts.color(digit: 0, line: true) == RGBAColor(red: 1, green: 165 / 255, blue: 0))
        #expect(ElementShortcuts.color(digit: 1, line: false) == .red)
        // .NET Green and Gray are half bright.
        #expect(ElementShortcuts.color(digit: 2, line: true) == RGBAColor(red: 0, green: 128 / 255, blue: 0))
        #expect(ElementShortcuts.color(digit: 8, line: false) == RGBAColor(red: 128 / 255, green: 128 / 255, blue: 128 / 255))
        let rest = (3...9).compactMap { ElementShortcuts.color(digit: $0, line: false) }
        #expect(rest == [.blue, RGBAColor(red: 0, green: 1, blue: 1), RGBAColor(red: 1, green: 0, blue: 1), .yellow, .black,
                         RGBAColor(red: 128 / 255, green: 128 / 255, blue: 128 / 255), .white])
        #expect(ElementShortcuts.color(digit: 10, line: false) == nil)
    }

    @Test func lineWidthStaysBetweenZeroAndTheMaximum() {
        #expect(ElementShortcuts.lineWidth(2, changedBy: 1) == 3)
        #expect(ElementShortcuts.lineWidth(2, changedBy: -5) == 0)
        #expect(ElementShortcuts.lineWidth(98, changedBy: 5) == 100)
        // A width in between (from an older version) goes to whole points.
        #expect(ElementShortcuts.lineWidth(2.4, changedBy: 1) == 3)
    }

    @Test func onlyElementsWithTheFieldChange() {
        // Upstream `HasField`: lines, arrows and freehand drawings have no fill; every element has a shadow but SVG and
        // pointer elements, which have no fields at all.
        #expect(!AnnotationKind.line.has(.fillColor) && !AnnotationKind.arrow.has(.fillColor) && !AnnotationKind.freehand.has(.fillColor))
        #expect(AnnotationKind.rectangle.has(.fillColor) && AnnotationKind.counter.has(.fillColor) && AnnotationKind.highlight.has(.fillColor))
        #expect(!AnnotationKind.highlight.has(.lineColor) && !AnnotationKind.image.has(.lineWidth))
        #expect(AnnotationKind.text.has(.lineWidth))
        let withShadow = AnnotationKind.kinds(with: .shadow)
        #expect(withShadow == Set(AnnotationKind.allCases).subtracting([.svg, .cursor]))
        for property in AnnotationStyleProperty.allCases {
            #expect(!AnnotationKind.svg.has(property))
            #expect(!AnnotationKind.cursor.has(property))
            #expect(AnnotationKind.tornEdge.has(property))
        }
        #expect(AnnotationKind.cutEdgeKinds == [.cutMark, .tornEdge])
    }

    @Test func copyingAPropertyLeavesTheOthers() {
        var target = AnnotationStyle.defaults(for: .rectangle)
        var source = AnnotationStyle.defaults(for: .ellipse)
        source.lineColor = .blue
        source.lineWidth = 9
        target.copy(.lineColor, from: source)
        #expect(target.lineColor == .blue && target.lineWidth == 2)
        target.copy(.lineWidth, from: source)
        #expect(target.lineWidth == 9)
    }
}
