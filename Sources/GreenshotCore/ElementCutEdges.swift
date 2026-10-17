// Greenshot for Mac (Community) - an unofficial macOS port of Greenshot
// Copyright (C) 2026 Greenshot for Mac (Community) contributors
// Based on Greenshot, Copyright (C) 2007-2026 Thomas Braun, Jens Klingen, Robin Krom
// SPDX-License-Identifier: GPL-3.0-or-later

import Foundation

/// What a cut mark or torn edge element keeps besides its style (upstream `CutMarkContainer` and `TornEdgeContainer`
/// private fields `_shadowDarkness`, `_shadowSize`, `_shadowOffsetX`, `_shadowOffsetY`, `_edges`, `_margins`): the
/// shadow's own settings, and for torn edges which sides are torn and the room outside of them for the shadow.
public struct CutEdgeLayout: Codable, Equatable, Sendable {
    /// How dark the shadow is, 0...1 (upstream `TornEdgeEffect.Darkness`, 0.6).
    public var shadowDarkness: Double
    /// How soft the shadow is, points, 1...20 (upstream `ShadowSize`, 7).
    public var shadowSize: Int
    /// How far the shadow is moved, points, -20...20 (upstream `ShadowOffset`, -1, -1).
    public var shadowOffsetX: Int
    public var shadowOffsetY: Int
    /// Torn edges: which sides are torn (upstream `_edges`: top, right, bottom, left).
    public var top: Bool
    public var right: Bool
    public var bottom: Bool
    public var left: Bool
    /// Torn edges: the room for the shadow outside of each side, image pixels; the canvas was made bigger by it
    /// (upstream `_margins`).
    public var marginTop: Int
    public var marginRight: Int
    public var marginBottom: Int
    public var marginLeft: Int

    public init(shadowDarkness: Double = 0.6, shadowSize: Int = 7, shadowOffsetX: Int = -1, shadowOffsetY: Int = -1,
                top: Bool = true, right: Bool = true, bottom: Bool = true, left: Bool = true,
                marginTop: Int = 0, marginRight: Int = 0, marginBottom: Int = 0, marginLeft: Int = 0) {
        self.shadowDarkness = shadowDarkness
        self.shadowSize = shadowSize
        self.shadowOffsetX = shadowOffsetX
        self.shadowOffsetY = shadowOffsetY
        self.top = top
        self.right = right
        self.bottom = bottom
        self.left = left
        self.marginTop = marginTop
        self.marginRight = marginRight
        self.marginBottom = marginBottom
        self.marginLeft = marginLeft
    }

    enum CodingKeys: String, CodingKey {
        case shadowDarkness, shadowSize, shadowOffsetX, shadowOffsetY, top, right, bottom, left
        case marginTop, marginRight, marginBottom, marginLeft
    }

    /// Every value falls back to its default, and values are limited to what the editor offers: element files and
    /// pasted elements can come from anywhere.
    public init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        let d = CutEdgeLayout()
        func value<T: Decodable>(_ key: CodingKeys, _ fallback: T) -> T {
            (try? c.decodeIfPresent(T.self, forKey: key)) ?? fallback
        }
        func limited(_ number: Int, _ range: ClosedRange<Int>) -> Int { min(max(number, range.lowerBound), range.upperBound) }
        let darkness = value(.shadowDarkness, d.shadowDarkness)
        shadowDarkness = darkness.isFinite ? min(max(darkness, 0), 1) : d.shadowDarkness
        shadowSize = limited(value(.shadowSize, d.shadowSize), 1...20)
        shadowOffsetX = limited(value(.shadowOffsetX, d.shadowOffsetX), -20...20)
        shadowOffsetY = limited(value(.shadowOffsetY, d.shadowOffsetY), -20...20)
        top = value(.top, d.top)
        right = value(.right, d.right)
        bottom = value(.bottom, d.bottom)
        left = value(.left, d.left)
        marginTop = limited(value(.marginTop, d.marginTop), 0...4000)
        marginRight = limited(value(.marginRight, d.marginRight), 0...4000)
        marginBottom = limited(value(.marginBottom, d.marginBottom), 0...4000)
        marginLeft = limited(value(.marginLeft, d.marginLeft), 0...4000)
    }
}
