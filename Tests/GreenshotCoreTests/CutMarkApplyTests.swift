// Greenshot for Mac (Community) - an unofficial macOS port of Greenshot
// Copyright (C) 2026 Greenshot for Mac (Community) contributors
// Based on Greenshot, Copyright (C) 2007-2026 Thomas Braun, Jens Klingen, Robin Krom
// SPDX-License-Identifier: GPL-3.0-or-later

import CoreGraphics
import Foundation
import Testing
@testable import GreenshotCore

/// Upstream "Apply to the image" and "Cut edge settings…" of a cut mark (`Surface.ApplyElementToImage`,
/// `CutMarkContainer.AddContextMenuItems`).
struct CutMarkApplyTests {
    private func document() -> EditorDocument {
        EditorDocument(image: TestImage.solid(width: 100, height: 100, .white), scale: 1, title: "test")
    }

    private func mark(_ change: (inout AnnotationStyle) -> Void = { _ in }) -> Annotation {
        var style = AnnotationStyle.defaults(for: .cutMark)
        style.shadow = false
        style.cutMarkStyle = .line
        change(&style)
        var mark = Annotation(kind: .cutMark, start: CGPoint(x: 0, y: 30), end: CGPoint(x: 100, y: 70), style: style)
        mark.seed = 1
        return mark
    }

    @Test func applyingDrawsTheGapIntoTheImage() {
        let doc = document()
        let cut = mark()
        doc.add(cut)
        var applied = false
        doc.change { applied = doc.applyToImage([cut.id]) }
        #expect(applied)
        #expect(doc.annotations.isEmpty)
        // The gap is between the two edges, 12 pixels in from each side of the band.
        #expect(TestImage.pixel(doc.baseImage, 50, 50).a == 0)
        #expect(TestImage.pixel(doc.baseImage, 50, 10) == .white)
        #expect(TestImage.pixel(doc.baseImage, 50, 90) == .white)
        doc.undo()
        #expect(doc.annotations.map(\.id) == [cut.id])
        #expect(TestImage.pixel(doc.baseImage, 50, 50) == .white)
    }

    @Test func aFilledGapKeepsItsColor() {
        let doc = document()
        let cut = mark { $0.fillColor = .yellow }
        doc.add(cut)
        doc.change { doc.applyToImage([cut.id]) }
        #expect(TestImage.pixel(doc.baseImage, 50, 50) == .yellow)
    }

    @Test func theSettingsChangeOnlyTheMark() throws {
        let cut = mark()
        var settings = cut.cutEdgeSettings
        #expect(settings.toothHeight == 12)
        #expect(settings.shadowSize == 7)
        settings.toothHeight = 6
        settings.horizontalToothRange = 30
        settings.verticalToothRange = 8
        settings.shadow = true
        settings.shadowSize = 3
        settings.shadowOffsetX = 4
        settings.backgroundColor = .yellow
        // The sides are torn edges only.
        settings.top = false
        let changed = cut.applyingCutEdgeSettings(settings, scale: 1)
        #expect(changed.style.toothHeight == 6)
        #expect(changed.style.toothRange == 30)
        #expect(changed.style.shadow)
        #expect(changed.style.fillColor == .yellow)
        let layout = try #require(changed.cutEdges)
        #expect(layout.shadowSize == 3)
        #expect(layout.shadowOffsetX == 4)
        #expect(layout.top)
        // The band shrinks by the smaller teeth on both sides (12 - 6 = 6 pixels each), so the gap keeps its size.
        #expect(changed.bounds == CGRect(x: 0, y: 36, width: 100, height: 28))
    }

    @Test func aMarkAcrossColumnsTakesTheVerticalRange() {
        var cut = mark()
        cut.verticalCut = true
        var settings = cut.cutEdgeSettings
        settings.horizontalToothRange = 30
        settings.verticalToothRange = 8
        #expect(cut.applyingCutEdgeSettings(settings, scale: 1).style.toothRange == 8)
    }

    @Test func theShadowFollowsTheSettings() {
        func gapTop(shadow: CutEdgeLayout?) -> RGBA {
            let doc = document()
            var cut = mark { $0.shadow = true }
            cut.cutEdges = shadow
            doc.add(cut)
            // Just below the top edge of the gap (y 42), where the part above casts its shadow.
            return TestImage.pixel(doc.flattened(), 50, 43)
        }
        let standard = gapTop(shadow: nil)
        #expect(standard.a > 40)
        // A shadow that falls up (offset 10 down means 1 - 10 = 9 points up) leaves the top of the gap lighter.
        let up = gapTop(shadow: CutEdgeLayout(shadowSize: 1, shadowOffsetY: 10))
        #expect(up.a < standard.a)
    }
}
