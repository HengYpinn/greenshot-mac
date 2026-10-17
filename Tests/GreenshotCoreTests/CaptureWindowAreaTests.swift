// Greenshot for Mac (Community) - an unofficial macOS port of Greenshot
// Copyright (C) 2026 Greenshot for Mac (Community) contributors
// SPDX-License-Identifier: GPL-3.0-or-later

import CoreGraphics
import Testing
@testable import GreenshotCore

/// The window mode's areas inside a window (CAP-073, upstream `WindowCaptureTool` for beta testers).
struct CaptureWindowAreaTests {
    private let windowFrame = CGRect(x: 100, y: 100, width: 800, height: 600)
    private let sidebar = WindowArea(frame: CGRect(x: 100, y: 150, width: 200, height: 550), role: "AXGroup", name: "group “Sidebar”")

    /// A window with a toolbar, a sidebar holding a list, and a content area holding a wrapper around a web area.
    private var window: WindowArea {
        let list = WindowArea(frame: CGRect(x: 110, y: 200, width: 180, height: 300), role: "AXOutline")
        var sidebar = self.sidebar
        sidebar.children = [list]
        let web = WindowArea(frame: CGRect(x: 300, y: 150, width: 600, height: 550), role: "AXWebArea",
                             children: [WindowArea(frame: CGRect(x: 320, y: 170, width: 400, height: 200), role: "AXGroup")])
        let wrapper = WindowArea(frame: web.frame, role: "AXScrollArea", children: [web])
        let toolbar = WindowArea(frame: CGRect(x: 100, y: 100, width: 800, height: 50), role: "AXToolbar")
        return WindowArea(frame: windowFrame, role: "AXWindow", children: [toolbar, sidebar, wrapper])
    }

    @Test func theDeepestAreaUnderTheMouseComesFirst() {
        let chain = WindowAreas.chain(at: CGPoint(x: 150, y: 300), in: window)
        #expect(chain.map(\.role) == ["AXOutline", "AXGroup", "AXWindow"])
        // The sidebar's neighbours aren't part of it.
        #expect(!chain.contains { $0.role == "AXToolbar" })
    }

    @Test func choicesGoFromTheSmallestAreaToTheWindow() {
        let (choices, deepest) = WindowAreas.selectable(at: CGPoint(x: 150, y: 300), in: window, window: windowFrame, scale: 1)
        #expect(choices.map(\.rect) == [CGRect(x: 110, y: 200, width: 180, height: 300), sidebar.frame, windowFrame])
        #expect(choices.last?.area == nil)
        #expect(deepest?.role == "AXOutline")
    }

    @Test func aWrapperWithTheSameFrameIsOneChoice() {
        // In the web area but outside its group: web area and its scroll area wrapper have the same frame.
        let (choices, _) = WindowAreas.selectable(at: CGPoint(x: 850, y: 650), in: window, window: windowFrame, scale: 1)
        #expect(choices.count == 2)
        #expect(choices.first?.area?.role == "AXWebArea")
    }

    @Test func smallAreasAreSkippedByTheirPixels() {
        // 50 points high: 50 pixels on a normal display, 100 on a Retina display.
        let point = CGPoint(x: 500, y: 120)
        let normal = WindowAreas.selectable(at: point, in: window, window: windowFrame, scale: 1).choices
        let retina = WindowAreas.selectable(at: point, in: window, window: windowFrame, scale: 2).choices
        #expect(normal.map(\.rect) == [windowFrame])
        #expect(retina.map(\.rect) == [CGRect(x: 100, y: 100, width: 800, height: 50), windowFrame])
    }

    @Test func areasAreCutToTheVisiblePartOfTheWindow() {
        // The window goes past the right edge of the screen at 600.
        let visible = CGRect(x: 100, y: 100, width: 500, height: 600)
        let (choices, _) = WindowAreas.selectable(at: CGPoint(x: 500, y: 250), in: window, window: visible, scale: 1)
        #expect(choices.first?.rect == CGRect(x: 320, y: 170, width: 280, height: 200))
        #expect(choices.last?.rect == visible)
    }

    @Test func withoutAreasTheWindowIsTheOnlyChoice() {
        let (choices, deepest) = WindowAreas.selectable(at: CGPoint(x: 150, y: 300), in: nil, window: windowFrame, scale: 1)
        #expect(choices == [SelectableArea(rect: windowFrame, area: nil)])
        #expect(deepest == nil)
    }

    @Test func pruningDropsSmallAreasAndStopsAtTheDepth() {
        let icon = WindowArea(frame: CGRect(x: 120, y: 210, width: 20, height: 20), role: "AXImage")
        var tree = window
        tree.children[1].children[0].children = [icon]
        // Ten nested levels, each 10 points smaller than the one around it.
        var nested = WindowArea(frame: CGRect(x: 300, y: 300, width: 300, height: 300), role: "AXGroup")
        for level in 1..<10 {
            let inset = CGFloat(level) * 10
            nested = WindowArea(frame: CGRect(x: 300 - inset, y: 300 - inset, width: 300 + 2 * inset, height: 300 + 2 * inset),
                                role: "AXGroup", children: [nested])
        }
        tree.children.append(nested)
        // On a Retina display: the toolbar (50 points high) stays, the icon (20 points, 40 pixels) goes.
        let pruned = WindowAreas.pruned(tree, scale: 2)
        #expect(pruned.children.count == 4)
        #expect(pruned.children[1].children[0].children.isEmpty)
        var depth = 0
        var current = pruned.children[3]
        while let next = current.children.first {
            depth += 1
            current = next
        }
        #expect(depth == WindowAreas.maximumDepth - 1)
    }

    @Test func wrappersDontCountAsLevels() {
        #expect(!WindowAreas.countsAsLevel(CGRect(x: 0, y: 0, width: 100, height: 100),
                                           parent: CGRect(x: 0.2, y: 0, width: 100, height: 100)))
        #expect(WindowAreas.countsAsLevel(CGRect(x: 0, y: 0, width: 90, height: 100), parent: CGRect(x: 0, y: 0, width: 100, height: 100)))
        #expect(WindowAreas.countsAsLevel(CGRect(x: 0, y: 0, width: 90, height: 100), parent: nil))
    }

    @Test func anEmptyWebAreaIsFound() {
        let empty = WindowArea(frame: windowFrame, role: "AXWindow",
                               children: [WindowArea(frame: windowFrame, role: "AXWebArea")])
        #expect(empty.hasEmptyWebArea)
        #expect(!window.hasEmptyWebArea)
        #expect(window.count == 7)
    }

    @Test func pageUpAndDownStepThroughTheChoices() {
        var level = WindowAreaLevel()
        let list = window.children[1].children[0]
        #expect(level.resolve(deepest: list, count: 3) == 0)
        level.step(by: 1)
        #expect(level.resolve(deepest: list, count: 3) == 1)
        level.step(by: 1)
        level.step(by: 1)
        // Up to the window, not past it.
        #expect(level.resolve(deepest: list, count: 3) == 2)
        level.step(by: -1)
        level.step(by: -1)
        level.step(by: -1)
        #expect(level.resolve(deepest: list, count: 3) == 0)
    }

    @Test func anotherAreaUnderTheMouseStartsWithTheSmallest() {
        var level = WindowAreaLevel()
        let list = window.children[1].children[0]
        _ = level.resolve(deepest: list, count: 3)
        level.step(by: 2)
        #expect(level.resolve(deepest: list, count: 3) == 2)
        #expect(level.resolve(deepest: window.children[0], count: 2) == 0)
        level.step(by: 1)
        level.reset()
        #expect(level.resolve(deepest: window.children[0], count: 2) == 0)
    }
}
