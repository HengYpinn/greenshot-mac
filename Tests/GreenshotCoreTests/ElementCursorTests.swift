// Greenshot for Mac (Community) - an unofficial macOS port of Greenshot
// Copyright (C) 2026 Greenshot for Mac (Community) contributors
// Based on Greenshot, Copyright (C) 2007-2026 Thomas Braun, Jens Klingen, Robin Krom
// SPDX-License-Identifier: GPL-3.0-or-later

import CoreGraphics
import Foundation
import Testing
@testable import GreenshotCore

/// The captured mouse pointer as an element (upstream `CursorContainer`, `Surface.AddCursorContainer`).
struct ElementCursorTests {
    /// A red 16 × 24 pixel pointer, 2 pixels per point.
    private func pointer(at origin: CGPoint, scale: CGFloat = 2) -> CapturedPointer {
        CapturedPointer(image: TestImage.solid(width: 16, height: 24, .red), scale: scale, hotSpot: CGPoint(x: 2, y: 2),
                        origin: origin)
    }

    @Test func thePointerSitsWhereItWasCaptured() throws {
        let element = try #require(Annotation.pointer(pointer(at: CGPoint(x: 100, y: 50)), documentScale: 2,
                                                      imageSize: CGSize(width: 400, height: 200)))
        #expect(element.kind == .cursor)
        #expect(element.bounds == CGRect(x: 100, y: 50, width: 16, height: 24))
        #expect(!element.style.shadow)
        #expect(Handle.handles(for: element) == Handle.boxHandles)
    }

    @Test func aPointerOfAnotherScaleKeepsItsPointSize() throws {
        let element = try #require(Annotation.pointer(pointer(at: .zero, scale: 1), documentScale: 2,
                                                      imageSize: CGSize(width: 400, height: 200)))
        #expect(element.bounds.size == CGSize(width: 32, height: 48))
    }

    @Test func aPointerOutsideTheCaptureIsLeftOut() {
        let size = CGSize(width: 400, height: 200)
        #expect(Annotation.pointer(pointer(at: CGPoint(x: 500, y: 20)), documentScale: 2, imageSize: size) == nil)
        // Partly on the capture: kept, like upstream.
        #expect(Annotation.pointer(pointer(at: CGPoint(x: 390, y: -10)), documentScale: 2, imageSize: size) != nil)
    }

    @Test func itIsPartOfTheOpenedCaptureWithoutAnUndoStep() throws {
        let doc = EditorDocument(image: TestImage.solid(width: 400, height: 200, .white), scale: 2, title: "test")
        #expect(doc.addPointer(nil) == nil)
        let id = try #require(doc.addPointer(pointer(at: CGPoint(x: 100, y: 50))))
        #expect(doc.annotations.map(\.id) == [id])
        #expect(!doc.canUndo)
        let image = doc.flattened()
        #expect(TestImage.pixel(image, 108, 60) == .red)
        #expect(TestImage.pixel(image, 120, 60) == .white)
    }

    @Test func resetSizeGivesThePointerItsSizeBack() throws {
        var element = try #require(Annotation.pointer(pointer(at: CGPoint(x: 10, y: 10)), documentScale: 2,
                                                      imageSize: CGSize(width: 400, height: 200)))
        element.end = CGPoint(x: 200, y: 150)
        #expect(element.hasDefaultSize)
        let size = try #require(element.defaultSize(documentScale: 2))
        #expect(size == CGSize(width: 16, height: 24))
    }
}
