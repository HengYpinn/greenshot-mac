// Greenshot for Mac (Community) - an unofficial macOS port of Greenshot
// Copyright (C) 2026 Greenshot for Mac (Community) contributors
// SPDX-License-Identifier: GPL-3.0-or-later

import CoreGraphics
import Testing
@testable import GreenshotCore

/// The fixed-size mode (upstream `FixedSizeCaptureTool`).
struct CaptureFixedSizeTests {
    let size = CaptureSize(width: 100, height: 50)

    @Test(arguments: [
        (FixedCaptureAnchor.topLeft, CGRect(x: 200, y: 100, width: 100, height: 50)),
        (.topRight, CGRect(x: 101, y: 100, width: 100, height: 50)),
        (.bottomRight, CGRect(x: 101, y: 51, width: 100, height: 50)),
        (.bottomLeft, CGRect(x: 200, y: 51, width: 100, height: 50)),
        (.center, CGRect(x: 150, y: 75, width: 100, height: 50)),
    ])
    func placesTheMousePixelAtTheAnchor(anchor: FixedCaptureAnchor, expected: CGRect) {
        #expect(FixedSizeCapture.place(cursor: CGPoint(x: 200.4, y: 100.7), size: size, anchor: anchor, scale: 1) == expected)
    }

    @Test func sizesArePixelsOnRetina() {
        // 100 × 50 pixels are 50 × 25 points at 2×; the corner pixel under the mouse belongs to the area.
        let rect = FixedSizeCapture.place(cursor: CGPoint(x: 10.3, y: 20.6), size: size, anchor: .bottomRight, scale: 2)
        #expect(rect == CGRect(x: -39.5, y: -4, width: 50, height: 25))
        #expect(Geometry.pixelRect(for: rect.offsetBy(dx: 100, dy: 100), scale: 2).size == CGSize(width: 100, height: 50))
    }

    @Test func snapsTheNearestEdgeWithinTheDistance() {
        let window = CGRect(x: 300, y: 200, width: 400, height: 300)
        // The left edge is 6 pt from the window's left edge, the bottom 4 pt above its bottom edge.
        let rect = CGRect(x: 306, y: 446, width: 100, height: 50)
        #expect(FixedSizeCapture.snap(rect, to: [window], distance: 10) == CGRect(x: 300, y: 450, width: 100, height: 50))
        // Too far away: unchanged.
        let far = CGRect(x: 330, y: 420, width: 100, height: 50)
        #expect(FixedSizeCapture.snap(far, to: [window], distance: 10) == far)
    }

    @Test func keepsTheAreaOnTheDisplayWithTheMouse() {
        let monitor = CGRect(x: 0, y: 0, width: 1280, height: 800)
        let selection = FixedSizeCapture.selection(cursor: CGPoint(x: 1250, y: 790), size: size, anchor: .topLeft, scale: 1,
                                                   monitor: monitor, desktop: monitor, snapTargets: [], snapping: false)
        #expect(selection == CGRect(x: 1180, y: 750, width: 100, height: 50))
        // A size larger than the display is cut off at the desktop's edges.
        let huge = FixedSizeCapture.selection(cursor: CGPoint(x: 100, y: 100), size: CaptureSize(width: 3000, height: 100),
                                              anchor: .topLeft, scale: 1, monitor: monitor, desktop: monitor, snapTargets: [],
                                              snapping: false)
        #expect(huge == CGRect(x: 100, y: 100, width: 1180, height: 100))
    }

    @Test func snappingIsOffWithOption() {
        let monitor = CGRect(x: 0, y: 0, width: 1280, height: 800)
        let window = CGRect(x: 103, y: 103, width: 500, height: 500)
        let snapped = FixedSizeCapture.selection(cursor: CGPoint(x: 100, y: 100), size: size, anchor: .topLeft, scale: 1,
                                                 monitor: monitor, desktop: monitor, snapTargets: [window], snapping: true)
        #expect(snapped.origin == CGPoint(x: 103, y: 103))
        let free = FixedSizeCapture.selection(cursor: CGPoint(x: 100, y: 100), size: size, anchor: .topLeft, scale: 1,
                                              monitor: monitor, desktop: monitor, snapTargets: [window], snapping: false)
        #expect(free.origin == CGPoint(x: 100, y: 100))
    }

    @Test func recentSizesNewestFirstDeduplicatedAtMostFive() {
        var recent: [CaptureSize] = []
        for width in [10, 20, 30, 40, 50, 60] { recent = FixedSizeCapture.remember(CaptureSize(width: width, height: 1), in: recent) }
        #expect(recent.map(\.width) == [60, 50, 40, 30, 20])
        recent = FixedSizeCapture.remember(CaptureSize(width: 30, height: 1), in: recent)
        #expect(recent.map(\.width) == [30, 60, 50, 40, 20])
        #expect(FixedSizeCapture.remember(CaptureSize(width: 0, height: 0), in: recent) == recent)
    }

    @Test func sizeListSkipsRecentSizesThatAreConfigured() {
        let configured = [CaptureSize(width: 640, height: 480), CaptureSize(width: 800, height: 600)]
        let recent = [CaptureSize(width: 412, height: 300), CaptureSize(width: 640, height: 480)]
        let entries = FixedSizeCapture.sizes(configured: configured, recent: recent)
        #expect(entries.map(\.size.width) == [640, 800, 412])
        #expect(entries.map(\.isRecent) == [false, false, true])
    }

    @Test func stepsWrapAround() {
        #expect(FixedSizeCapture.step(0, by: -1, count: 5) == 4)
        #expect(FixedSizeCapture.step(4, by: 1, count: 5) == 0)
        #expect(FixedSizeCapture.step(2, by: 1, count: 0) == 0)
    }

    @Test func parsesASizeList() {
        let sizes = FixedSizeCapture.parseSizes("640x480, 800 X 600\n1280×720; nonsense, 0x5")
        #expect(sizes == [CaptureSize(width: 640, height: 480), CaptureSize(width: 800, height: 600), CaptureSize(width: 1280, height: 720)])
        #expect(CaptureSize("32x32")?.displayString == "32×32")
        #expect(CaptureSize("32") == nil)
    }
}

/// The text mode (upstream `TextCaptureTool`).
struct CaptureTextSelectionTests {
    func line(_ words: [(String, CGFloat)], y: CGFloat, height: CGFloat = 10) -> RecognizedLine {
        let recognized = words.map { RecognizedWord(text: $0.0, bounds: CGRect(x: $0.1, y: y, width: 20, height: height)) }
        let bounds = recognized.map(\.bounds).reduce(CGRect.null) { $0.union($1) }
        return RecognizedLine(text: words.map(\.0).joined(separator: " "), bounds: bounds, words: recognized)
    }

    @Test func selectsWordsAcrossLinesInReadingOrder() {
        let second = line([("three", 0), ("four", 30), ("five", 60)], y: 20)
        let first = line([("one", 0), ("two", 30)], y: 0)
        // The drag goes from the right of the first line to the middle of the second.
        let rect = Geometry.rect(from: CGPoint(x: 45, y: 25), to: CGPoint(x: 35, y: 5))
        #expect(TextCaptureSelection.text(in: rect, lines: [second, first]) == "two\nfour")
        let wide = CGRect(x: 0, y: 0, width: 100, height: 30)
        #expect(TextCaptureSelection.text(in: wide, lines: [second, first]) == "one two\nthree four five")
    }

    @Test func linesOnOneRowReadLeftToRight() {
        let right = line([("right", 300)], y: 2)
        let left = line([("left", 0)], y: 0)
        let below = line([("below", 0)], y: 30)
        #expect(TextCaptureSelection.readingOrder([below, right, left]).map(\.text) == ["left", "right", "below"])
    }

    @Test func lineUnderTheMouse() {
        let first = line([("one", 0), ("two", 30)], y: 0)
        let second = line([("three", 0)], y: 20)
        #expect(TextCaptureSelection.line(at: CGPoint(x: 35, y: 5), in: [first, second])?.text == "one two")
        #expect(TextCaptureSelection.line(at: CGPoint(x: 35, y: 15), in: [first, second]) == nil)
        #expect(TextCaptureSelection.text(in: CGRect(x: 200, y: 200, width: 10, height: 10), lines: [first, second]).isEmpty)
    }

    @Test func pixelsOfADisplayBecomeGlobalPoints() {
        let lines = [line([("word", 40)], y: 100)]
        let global = TextCaptureSelection.global(lines, scale: 2, origin: CGPoint(x: -1440, y: 0))
        #expect(global[0].words[0].bounds == CGRect(x: -1420, y: 50, width: 10, height: 5))
        #expect(global[0].bounds == global[0].words[0].bounds)
    }
}

/// What the full screen hotkey captures (upstream `ScreenCaptureMode`).
struct CaptureScreenChoiceTests {
    let frames = [CGRect(x: 0, y: 0, width: 1440, height: 900), CGRect(x: 1440, y: -200, width: 1920, height: 1080)]

    @Test func autoTakesTheDisplayWithTheMouse() {
        #expect(CaptureScreenChoice.screens(for: .auto, screenNumber: 1, mouse: CGPoint(x: 2000, y: 100), frames: frames) == [1])
        #expect(CaptureScreenChoice.screens(for: .auto, screenNumber: 1, mouse: CGPoint(x: 10, y: 10), frames: frames) == [0])
        // Off every display (in a gap): the nearest one.
        #expect(CaptureScreenChoice.screens(for: .auto, screenNumber: 1, mouse: CGPoint(x: 100, y: 950), frames: frames) == [0])
    }

    @Test func fullScreenTakesEveryDisplay() {
        #expect(CaptureScreenChoice.screens(for: .fullScreen, screenNumber: 2, mouse: .zero, frames: frames) == [0, 1])
    }

    @Test func fixedTakesTheNumberedDisplayOrTheOneWithTheMouse() {
        #expect(CaptureScreenChoice.screens(for: .fixed, screenNumber: 2, mouse: .zero, frames: frames) == [1])
        #expect(CaptureScreenChoice.screens(for: .fixed, screenNumber: 3, mouse: CGPoint(x: 1500, y: 0), frames: frames) == [1])
        #expect(CaptureScreenChoice.screens(for: .fixed, screenNumber: 1, mouse: .zero, frames: []) == [])
    }
}

/// The panels and the zoomer (upstream `PanelPlacement`, `ZoomerPlacement`, `SelectionPreviewOverlay`).
struct CapturePanelLayoutTests {
    let monitor = CGRect(x: 0, y: 0, width: 1280, height: 800)
    let size = CGSize(width: 200, height: 100)

    @Test func newPanelGoesToTheCornerFarthestFromTheMouse() {
        let box = CapturePanelPlacement.place(size: size, monitor: monitor, cursor: CGPoint(x: 100, y: 100), current: nil, avoid: [])
        #expect(box == CGRect(x: 1070, y: 690, width: 200, height: 100))
    }

    @Test func panelsAvoidEachOtherAndTheSelection() {
        let cursor = CGPoint(x: 100, y: 100)
        let first = CapturePanelPlacement.place(size: size, monitor: monitor, cursor: cursor, current: nil, avoid: [])
        let second = CapturePanelPlacement.place(size: size, monitor: monitor, cursor: cursor, current: nil, avoid: [first])
        #expect(!second.intersects(first))
        #expect(monitor.contains(second))
        let selection = CGRect(x: 1000, y: 0, width: 280, height: 800)
        let third = CapturePanelPlacement.place(size: size, monitor: monitor, cursor: cursor, current: nil, avoid: [], avoidLoosely: [selection])
        #expect(third == CGRect(x: 10, y: 690, width: 200, height: 100))
    }

    @Test func panelStaysUntilTheMouseComesClose() {
        let current = CGRect(x: 10, y: 10, width: 200, height: 100)
        let stays = CapturePanelPlacement.place(size: size, monitor: monitor, cursor: CGPoint(x: 600, y: 400), current: current, avoid: [])
        #expect(stays == current)
        let moves = CapturePanelPlacement.place(size: size, monitor: monitor, cursor: CGPoint(x: 50, y: 50), current: current, avoid: [])
        #expect(moves != current)
        // A panel that grows keeps the edges at its corner.
        let grown = CapturePanelPlacement.resize(CGRect(x: 1070, y: 690, width: 200, height: 100), to: CGSize(width: 260, height: 120), in: monitor)
        #expect(grown == CGRect(x: 1010, y: 670, width: 260, height: 120))
    }

    @Test func zoomerGoesBottomRightElseAnotherSide() {
        let zoomer = CGSize(width: 128, height: 128)
        #expect(CaptureZoomerPlacement.offset(cursor: CGPoint(x: 100, y: 100), current: nil, size: zoomer, monitor: monitor, avoid: [])
            == CGPoint(x: 24, y: 24))
        #expect(CaptureZoomerPlacement.offset(cursor: CGPoint(x: 1270, y: 790), current: nil, size: zoomer, monitor: monitor, avoid: [])
            == CGPoint(x: -152, y: -152))
        let panel = CGRect(x: 630, y: 430, width: 100, height: 100)
        #expect(CaptureZoomerPlacement.offset(cursor: CGPoint(x: 400, y: 100), current: nil, size: zoomer, monitor: monitor, avoid: [panel])
            == CGPoint(x: 24, y: 24))
        // Bottom right would cover the panel: bottom left.
        #expect(CaptureZoomerPlacement.offset(cursor: CGPoint(x: 600, y: 400), current: nil, size: zoomer, monitor: monitor, avoid: [panel])
            == CGPoint(x: -152, y: 24))
    }

    @Test func previewEnlargesByWholeFactorsAndReducesToFit() {
        let box = CGSize(width: 640, height: 400)
        #expect(SelectionPreviewLayout.scale(for: CGSize(width: 32, height: 32), fitting: box) == 12)
        #expect(SelectionPreviewLayout.scale(for: CGSize(width: 2560, height: 1600), fitting: box) == 0.25)
        #expect(SelectionPreviewLayout.percentText(4) == "400 %")
        #expect(SelectionPreviewLayout.percentText(0.25) == "25 %")
        #expect(SelectionPreviewLayout.percentText(0.025) == "2.5 %")
    }
}
