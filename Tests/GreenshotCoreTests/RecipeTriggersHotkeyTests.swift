// Greenshot for Mac (Community) - an unofficial macOS port of Greenshot
// Copyright (C) 2026 Greenshot for Mac (Community) contributors
// Based on Greenshot, Copyright (C) 2007-2026 Thomas Braun, Jens Klingen, Robin Krom
// SPDX-License-Identifier: GPL-3.0-or-later

import Foundation
@testable import GreenshotCore
import Testing

/// Recipe hotkeys next to the app's (RCP-061): the app's win, then the earlier recipe hotkey.
struct RecipeTriggersHotkeyTests {
    static func hotkey(_ name: String, _ text: String) throws -> NamedHotkey {
        let combo = try #require(RecipeHotkeyText.parse(text))
        return NamedHotkey(name: name, combo: combo)
    }

    @Test func distinctHotkeysAreKept() throws {
        let app = try Self.hotkey("Capture region", "Ctrl + Alt + 4")
        let recipes = [try Self.hotkey("Recipe A", "Ctrl + Shift + J"), try Self.hotkey("Recipe B", "Ctrl + K, C")]
        let resolved = RecipeHotkeyClashes.resolve(recipes, taken: [app])
        #expect(resolved.kept == [0, 1])
        #expect(resolved.clashes.isEmpty)
    }

    @Test func theAppsHotkeyWins() throws {
        let app = try Self.hotkey("Capture region", "Ctrl + Shift + J")
        let resolved = RecipeHotkeyClashes.resolve([try Self.hotkey("Recipe A", "Ctrl + Shift + J")], taken: [app])
        #expect(resolved.kept.isEmpty)
        let clash = try #require(resolved.clashes.first)
        #expect(clash.name == "Recipe A")
        #expect(clash.problem.contains("Capture region"))
    }

    @Test func theEarlierRecipeWins() throws {
        let recipes = [try Self.hotkey("Recipe A", "Ctrl + Shift + J"), try Self.hotkey("Recipe B", "Ctrl + Shift + J")]
        let resolved = RecipeHotkeyClashes.resolve(recipes, taken: [])
        #expect(resolved.kept == [0])
        #expect(resolved.clashes.map(\.name) == ["Recipe B"])
    }

    @Test func aSequenceStartingWithAnotherHotkeyNeverFires() throws {
        let app = try Self.hotkey("Capture text", "Ctrl + K")
        let resolved = RecipeHotkeyClashes.resolve([try Self.hotkey("Recipe A", "Ctrl + K, C")], taken: [app])
        #expect(resolved.kept.isEmpty)
        #expect(resolved.clashes.count == 1)
    }

    @Test func aHotkeyThatBeginsAnotherOneTakesItsKeys() throws {
        let app = try Self.hotkey("Capture text", "Ctrl + K, C")
        let resolved = RecipeHotkeyClashes.resolve([try Self.hotkey("Recipe A", "Ctrl + K")], taken: [app])
        #expect(resolved.kept.isEmpty)
        let clash = try #require(resolved.clashes.first)
        #expect(clash.problem.contains("beginning of “Capture text”"))
    }

    @Test func eitherSideClashesWithOneSide() throws {
        let app = try Self.hotkey("Capture region", "Ctrl (L) + Shift + J")
        let resolved = RecipeHotkeyClashes.resolve([try Self.hotkey("Recipe A", "Ctrl + Shift + J")], taken: [app])
        #expect(resolved.kept.isEmpty)
    }

    @Test func oppositeSidesDontClash() throws {
        let app = try Self.hotkey("Capture region", "Ctrl (L) + Shift + J")
        let resolved = RecipeHotkeyClashes.resolve([try Self.hotkey("Recipe A", "Ctrl (R) + Shift + J")], taken: [app])
        #expect(resolved.kept == [0])
    }

    @Test func aKeptRecipeHotkeyBlocksLaterOnes() throws {
        let recipes = [try Self.hotkey("Recipe A", "Ctrl + K, C"), try Self.hotkey("Recipe B", "Ctrl + K")]
        let resolved = RecipeHotkeyClashes.resolve(recipes, taken: [])
        #expect(resolved.kept == [0])
        let clash = try #require(resolved.clashes.first)
        #expect(clash.text.hasPrefix("Recipe B ("))
    }
}
