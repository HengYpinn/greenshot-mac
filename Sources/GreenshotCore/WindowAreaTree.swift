// Greenshot for Mac (Community) - an unofficial macOS port of Greenshot
// Copyright (C) 2026 Greenshot for Mac (Community) contributors
// Based on Greenshot, Copyright (C) 2007-2026 Thomas Braun, Jens Klingen, Robin Krom
// SPDX-License-Identifier: GPL-3.0-or-later

import CoreGraphics
import Foundation

/// An area inside a window, like a sidebar, a toolbar or a part of a web page, as the Accessibility API describes it
/// (upstream `UiAutomationArea`, read by `Greenshot.Base/Capturing/WindowCaptureTool.cs`). Frames in Quartz global points.
public struct WindowArea: Equatable, Sendable {
    public var frame: CGRect
    /// The accessibility role, e.g. "AXGroup".
    public var role: String
    /// What it is called, for the window details (D): the role's description and the title, e.g. "group “Sidebar”".
    public var name: String
    public var children: [WindowArea]

    public init(frame: CGRect, role: String, name: String = "", children: [WindowArea] = []) {
        self.frame = frame
        self.role = role
        self.name = name
        self.children = children
    }

    /// Any `AXWebArea` in the tree that has nothing inside: the browser doesn't show its web content to the
    /// Accessibility API yet.
    public var hasEmptyWebArea: Bool {
        (role == "AXWebArea" && children.isEmpty) || children.contains { $0.hasEmptyWebArea }
    }

    /// The number of areas in the tree, this one included.
    public var count: Int { 1 + children.reduce(0) { $0 + $1.count } }
}

/// One choice of the window mode under the mouse: an area, or the window itself (`area` nil).
public struct SelectableArea: Equatable, Sendable {
    public var rect: CGRect
    public var area: WindowArea?

    public init(rect: CGRect, area: WindowArea?) {
        self.rect = rect
        self.area = area
    }
}

/// The rules of the window mode's areas (upstream `WindowCaptureTool`: `MinimumAreaSize`, `MaximumAreaDepth`,
/// `GetSelectableAreas`).
public enum WindowAreas {
    /// Smaller areas (a word, an icon) are rarely what the user wants to capture: an area needs this many pixels of the
    /// display in width and in height (upstream `MinimumAreaSize`, 64 pixels; 32 points on a Retina display).
    public static let minimumPixels: CGFloat = 64
    /// The levels below the window, counted without the elements that only wrap another one (upstream
    /// `MaximumAreaDepth`).
    public static let maximumDepth = 8
    /// Reading the areas shows the turning mark only when it takes longer than this (upstream `BusyMarkDelay`).
    public static let busyMarkDelay: TimeInterval = 0.2

    /// Big enough to be an area on a display with `scale` pixels per point.
    public static func isLargeEnough(_ frame: CGRect, scale: CGFloat) -> Bool {
        frame.width * scale >= minimumPixels && frame.height * scale >= minimumPixels
    }

    /// An element with the same frame as the one around it only wraps it and isn't a level of its own.
    public static func countsAsLevel(_ frame: CGRect, parent: CGRect?) -> Bool {
        guard let parent else { return true }
        return !(abs(frame.minX - parent.minX) < 0.5 && abs(frame.minY - parent.minY) < 0.5
                 && abs(frame.width - parent.width) < 0.5 && abs(frame.height - parent.height) < 0.5)
    }

    /// The tree as the window mode uses it: areas under the minimum left out with everything inside them, and nothing
    /// deeper than `maximumDepth` levels below the window. The window (`root`) itself always stays.
    public static func pruned(_ root: WindowArea, scale: CGFloat) -> WindowArea {
        var root = root
        root.children = root.children.compactMap { prune($0, parent: root.frame, depth: 0, scale: scale) }
        return root
    }

    private static func prune(_ area: WindowArea, parent: CGRect, depth: Int, scale: CGFloat) -> WindowArea? {
        guard isLargeEnough(area.frame, scale: scale) else { return nil }
        let level = countsAsLevel(area.frame, parent: parent) ? depth + 1 : depth
        var area = area
        let frame = area.frame
        area.children = level >= maximumDepth ? [] : area.children.compactMap { prune($0, parent: frame, depth: level, scale: scale) }
        return area
    }

    /// The areas under `point`, the deepest first, ending with `root`. Where children overlap, the smallest one under
    /// the mouse is the deeper one.
    public static func chain(at point: CGPoint, in root: WindowArea) -> [WindowArea] {
        var chain = [root]
        var current = root
        while let next = current.children.filter({ $0.frame.contains(point) })
            .min(by: { $0.frame.width * $0.frame.height < $1.frame.width * $1.frame.height }) {
            chain.append(next)
            current = next
        }
        return chain.reversed()
    }

    /// The rectangles to choose from at `point`, the smallest first and the window last (upstream
    /// `GetSelectableAreas`): each area cut to `window` (the visible part of the window), areas under the minimum
    /// skipped, and a rectangle that is the same as the one inside it only once. Also the deepest area under the mouse,
    /// which decides when the level starts again (`WindowAreaLevel`).
    public static func selectable(at point: CGPoint, in root: WindowArea?, window: CGRect,
                                  scale: CGFloat) -> (choices: [SelectableArea], deepest: WindowArea?) {
        var choices: [SelectableArea] = []
        var deepest: WindowArea?
        if let root {
            // The last one is the window's own element: the window takes its place.
            for area in chain(at: point, in: root).dropLast() {
                if deepest == nil { deepest = area }
                guard isLargeEnough(area.frame, scale: scale) else { continue }
                let rect = area.frame.intersection(window)
                guard !rect.isNull, !rect.isEmpty, choices.last?.rect != rect else { continue }
                choices.append(SelectableArea(rect: rect, area: area))
            }
        }
        if choices.last?.rect != window { choices.append(SelectableArea(rect: window, area: nil)) }
        return (choices, deepest)
    }
}

/// Which of the window mode's choices is selected: 0 is the smallest area under the mouse, PgUp one larger, PgDn one
/// smaller; another area under the mouse starts at 0 again (upstream `WindowCaptureTool._areaLevel`).
public struct WindowAreaLevel: Equatable, Sendable {
    private struct Key: Equatable, Sendable {
        var frame: CGRect
        var role: String
    }

    public private(set) var level = 0
    private var deepest: Key?

    public init() {}

    /// The level for `count` choices whose deepest area is `deepest`.
    public mutating func resolve(deepest area: WindowArea?, count: Int) -> Int {
        let key = area.map { Key(frame: $0.frame, role: $0.role) }
        if key != deepest {
            deepest = key
            level = 0
        }
        level = min(level, max(count - 1, 0))
        return level
    }

    /// PgUp (+1) or PgDn (−1); the next `resolve` keeps it within the choices.
    public mutating func step(by change: Int) {
        level = max(0, level + change)
    }

    /// Another window: start with its smallest area.
    public mutating func reset() {
        level = 0
        deepest = nil
    }
}
