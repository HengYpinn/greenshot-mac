// Greenshot for Mac (Community) - an unofficial macOS port of Greenshot
// Copyright (C) 2026 Greenshot for Mac (Community) contributors
// Based on Greenshot, Copyright (C) 2007-2026 Thomas Braun, Jens Klingen, Robin Krom
// SPDX-License-Identifier: GPL-3.0-or-later

import Foundation
import Testing
@testable import GreenshotCore

/// The colours last picked (upstream `ColorPickerWindow.AddToRecentColors`: newest first, no doubles, 12 at most).
struct RecentColorsTests {
    static func gray(_ level: Int) -> RGBAColor {
        let value = Double(level) / 255
        return RGBAColor(red: value, green: value, blue: value)
    }

    @Test func theNewestComesFirst() {
        var list: [RGBAColor] = []
        list = RecentColors.remember(.red, in: list)
        list = RecentColors.remember(.blue, in: list)
        #expect(list == [.blue, .red])
    }

    @Test func aColorUsedAgainMovesToTheFront() {
        let list = RecentColors.remember(.red, in: [.blue, .red, .yellow])
        #expect(list == [.red, .blue, .yellow])
    }

    @Test func colorsThatDifferLessThanAStepAreTheSame() {
        // A colour well gives the colour back with a little noise.
        let noisy = RGBAColor(red: 0.999_999, green: 0.000_001, blue: 0)
        let list = RecentColors.remember(noisy, in: [.blue, .red])
        #expect(list.count == 2)
        #expect(list.first == noisy)
    }

    @Test func atMostTwelveAreKept() {
        var list: [RGBAColor] = []
        for level in 0..<20 { list = RecentColors.remember(Self.gray(level * 10), in: list) }
        #expect(list.count == RecentColors.limit)
        #expect(RecentColors.limit == 12)
        #expect(list.first == Self.gray(190))
        #expect(list.last == Self.gray(80))
    }

    @Test func alphaIsKeptButTransparentIsNot() {
        let halfRed = RGBAColor(red: 1, green: 0, blue: 0, alpha: 0.5)
        let list = RecentColors.remember(halfRed, in: [.red])
        #expect(list == [halfRed, .red])
        #expect(RecentColors.remember(.clear, in: list) == list)
        #expect(RecentColors.cleaned([.clear, .red, .red, .blue]) == [.red, .blue])
    }

    @Test func colorsAreNamedByTheirHexValue() {
        #expect(RecentColors.name(of: .red) == "#FF0000")
        #expect(RecentColors.name(of: RGBAColor(red: 0, green: 0.5, blue: 1, alpha: 0.5)) == "#0080FF80")
        // Values outside 0–1 from a hand-edited file are clamped.
        #expect(RecentColors.name(of: RGBAColor(red: 2, green: -1, blue: .nan)) == "#FF0000")
    }

    @Test func theListIsKeptInTheSettings() throws {
        var settings = AppSettings()
        #expect(settings.recentColors.isEmpty)
        settings.recentColors = RecentColors.remember(.yellow, in: settings.recentColors)
        let data = try JSONEncoder().encode(settings)
        let loaded = try JSONDecoder().decode(AppSettings.self, from: data)
        #expect(loaded.recentColors == [.yellow])
    }
}

/// Colours of wells that may still change count once their well kept them for a moment, each well on its own.
struct RecentColorPicksTests {
    final class Well {}

    @Test func aColorCountsOnceItsWellKeptItForAMoment() {
        let well = Well()
        var picks = RecentColorPicks()
        picks.pick(.red, from: ObjectIdentifier(well), at: 10)
        #expect(picks.settled(at: 10.5, after: 1).isEmpty)
        #expect(picks.settled(at: 11, after: 1) == [.red])
        #expect(picks.isEmpty)
    }

    @Test func aNewerPickInTheSameWellReplacesTheOlder() {
        let well = Well()
        var picks = RecentColorPicks()
        picks.pick(.red, from: ObjectIdentifier(well), at: 10)
        picks.pick(.blue, from: ObjectIdentifier(well), at: 10.6)
        #expect(picks.settled(at: 11, after: 1).isEmpty)
        #expect(picks.settled(at: 11.6, after: 1) == [.blue])
    }

    @Test func aPickInAnotherWellDoesNotDropTheFirst() {
        let line = Well()
        let fill = Well()
        var picks = RecentColorPicks()
        picks.pick(.red, from: ObjectIdentifier(line), at: 10)
        picks.pick(.blue, from: ObjectIdentifier(fill), at: 10.4)
        #expect(picks.settled(at: 11, after: 1) == [.red])
        #expect(picks.settled(at: 11.4, after: 1) == [.blue])
    }

    @Test func settledColorsComeOldestFirst() {
        let line = Well()
        let fill = Well()
        var picks = RecentColorPicks()
        picks.pick(.yellow, from: ObjectIdentifier(fill), at: 10.2)
        picks.pick(.red, from: ObjectIdentifier(line), at: 10)
        // Remembered in this order, the newest (yellow) ends up first in the recent colours.
        let settled = picks.settled(at: 20, after: 1)
        #expect(settled == [.red, .yellow])
        let recent = settled.reduce([RGBAColor]()) { RecentColors.remember($1, in: $0) }
        #expect(recent == [.yellow, .red])
    }
}
