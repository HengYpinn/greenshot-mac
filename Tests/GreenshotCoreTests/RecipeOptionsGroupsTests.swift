// Greenshot for Mac (Community) - an unofficial macOS port of Greenshot
// Copyright (C) 2026 Greenshot for Mac (Community) contributors
// Based on Greenshot, Copyright (C) 2007-2026 Thomas Braun, Jens Klingen, Robin Krom
// SPDX-License-Identifier: GPL-3.0-or-later

import Foundation
import Testing
@testable import GreenshotCore

/// Settings › Recipes (upstream SettingsViewModel.RecipeOptions, RecipeOptionGroupViewModel), the scope dialog and Quick
/// Settings › Automatic steps (TrayMenu.AddRecipeQuickSettings).
@MainActor
@Suite struct RecipeOptionsGroupsTests {
    static let destinations: [(designation: String, name: String)] = [("Clipboard", "Copy to clipboard"), ("EMail", "Email")]

    /// Two capture recipes with the standard BeforeDestination slot; the second has options of its own.
    func fixture() -> LibraryFixture {
        let region = ComposerFixture.recipe("region", slots: ["BeforeDestination"])
        var window = ComposerFixture.recipe("window", slots: ["BeforeDestination"])
        var frame = RecipeOption(key: "frame", type: .boolean, defaultValue: .bool(false))
        frame.label = "Frame"
        frame.quickSettings = true
        var size = RecipeOption(key: "size", type: .integer, defaultValue: .number(3))
        size.min = 1
        size.max = 9
        size.enabledWhen = "frame"
        var mode = RecipeOption(key: "mode", type: .enumeration, defaultValue: .string("a"))
        mode.choices = [RecipeOptionChoice(value: "a", label: "Mode A"), RecipeOptionChoice(value: "b")]
        mode.quickSettings = true
        mode.label = "Add a border"
        window.options = [frame, size, mode]
        return LibraryFixture(builtIns: [region, window])
    }

    @Test func groupsListTheAutomaticStepsThenTheRecipes() throws {
        let fixture = fixture()
        defer { fixture.cleanUp() }
        let groups = fixture.library.optionGroups(destinations: Self.destinations)
        #expect(groups.map(\.id) == ["ext_caption", "ext_border", "ext_dropshadow", "window"])
        let border = try #require(groups.first { $0.id == "ext_border" })
        #expect(border.isExtension)
        #expect(border.switchOption?.key == "enabled")
        #expect(!border.isOn)
        #expect(border.items.map(\.id) == ["width", "color"])
        #expect(border.items.first?.rangeText == "1 – 50")
        #expect(border.items.allSatisfy { !$0.isEditable })
        let window = try #require(groups.last)
        #expect(!window.isExtension)
        #expect(window.isOn)
        #expect(window.items.map(\.label) == ["Frame", "size", "Add a border"])
        // `size` waits for `frame`.
        #expect(window.items[1].isEditable == false)
        fixture.library.setOption(.bool(true), key: "frame", ownerId: "window")
        let after = try #require(fixture.library.optionGroups(destinations: Self.destinations).last)
        #expect(after.items[1].isEditable)
        #expect(fixture.box.settings.optionValues["window.frame"] == "True")
    }

    @Test func switchingAnAutomaticStepOnShowsItsOptions() throws {
        let fixture = fixture()
        defer { fixture.cleanUp() }
        fixture.library.setExtensionEnabled(true, id: "ext_border")
        fixture.library.setOption(.number(7), key: "width", ownerId: "ext_border")
        let border = try #require(fixture.library.optionGroups(destinations: Self.destinations).first { $0.id == "ext_border" })
        #expect(border.isOn)
        #expect(border.items.first?.text == "7")
        let editable = border.items.allSatisfy { $0.isEditable }
        #expect(editable)
        // Out of range is clamped, a default is not stored.
        fixture.library.setOption(.number(99), key: "width", ownerId: "ext_border")
        #expect(fixture.box.settings.optionValues["ext_border.width"] == "50")
        fixture.library.setOption(.number(2), key: "width", ownerId: "ext_border")
        #expect(fixture.box.settings.optionValues["ext_border.width"] == nil)
        fixture.library.resetOptions(recipeId: "ext_border")
        #expect(fixture.box.settings.optionValues.isEmpty)
    }

    @Test func theScopeSaysWhereItIsUsed() throws {
        let fixture = fixture()
        defer { fixture.cleanUp() }
        let scope = try #require(fixture.library.extensionScope(id: "ext_border", destinations: Self.destinations))
        #expect(scope.captures.map(\.id) == ["region", "window"])
        #expect(scope.destinations.map(\.id) == ["Clipboard", "EMail"])
        #expect(scope.summary == "All captures → all destinations")
        #expect(scope.onlyDestinations.isEmpty)
        fixture.library.setExtensionScope(id: "ext_border", exceptRecipes: ["window"], onlyDestinations: ["EMail"])
        #expect(fixture.box.settings.optionValues["ext_border.exceptRecipes"] == "window")
        #expect(fixture.box.settings.optionValues["ext_border.onlyDestinations"] == "EMail")
        let changed = try #require(fixture.library.extensionScope(id: "ext_border", destinations: Self.destinations))
        #expect(changed.summary == "1 of 2 captures → Email")
        var none = changed
        none.captures = none.captures.map { RecipeScopeItem(id: $0.id, name: $0.name, isChecked: false) }
        none.destinations = none.destinations.map { RecipeScopeItem(id: $0.id, name: $0.name, isChecked: false) }
        #expect(none.summary == "No captures → ")
        #expect(!none.isValid)
        #expect(none.exceptRecipes == ["region", "window"])
        // An automatic step no recipe has a slot for has no "Used for".
        #expect(fixture.library.extensionScope(id: "nope", destinations: Self.destinations) == nil)
    }

    @Test func changedRecipesGroupByTheirAutomaticSteps() {
        let fixture = fixture()
        defer { fixture.cleanUp() }
        #expect(fixture.library.recipeChanges().isEmpty)
        fixture.library.setExtensionEnabled(true, id: "ext_border")
        fixture.library.setExtensionEnabled(true, id: "ext_caption")
        #expect(fixture.library.recipeChanges() == [RecipeChangeLine(extensions: "Caption, Border", recipes: "Capture region, Capture window")])
        fixture.library.setExtensionScope(id: "ext_caption", exceptRecipes: ["window"], onlyDestinations: [])
        #expect(fixture.library.recipeChanges() == [RecipeChangeLine(extensions: "Caption, Border", recipes: "Capture region"),
                                                    RecipeChangeLine(extensions: "Border", recipes: "Capture window")])
    }

    @Test func quickSettingsShowSwitchesAndChoices() {
        let fixture = fixture()
        defer { fixture.cleanUp() }
        fixture.library.setExtensionEnabled(true, id: "ext_border")
        let entries = fixture.library.quickSettings()
        #expect(entries.map(\.ownerId) == ["ext_caption", "ext_border", "ext_dropshadow", "window", "window"])
        // Two "Add a border" labels: the owner's name in front.
        let labels = entries.map(\.label)
        #expect(labels == ["Add a caption", "Border: Add a border", "Add a drop shadow", "Frame", "Capture window: Add a border"])
        #expect(entries[1].value == .bool(true))
        #expect(entries[4].option.type == .enumeration)
        #expect(RecipeQuickSetting.maximum == 6)
    }

    @Test func colorsAsText() throws {
        let red = try #require(RecipeOptionColor.parse("#FF0000"))
        #expect(RecipeOptionColor.format(red) == "#FF0000")
        let translucent = try #require(RecipeOptionColor.parse("#80112233"))
        #expect(RecipeOptionColor.format(translucent) == "#80112233")
        #expect(RecipeOptionColor.parse("red?") == nil)
    }

    @Test func destinationChoicesLeaveOutThePickerAndListExternalCommands() {
        var settings = AppSettings()
        settings.externalCommands = [ExternalCommand(name: "Paint", command: "/usr/bin/open", arguments: "{0}")]
        let choices = RecipeExtensionScope.destinationChoices(settings: settings)
        #expect(!choices.contains { $0.designation == "Picker" })
        #expect(choices.contains { $0.designation == "FileNoDialog" })
        #expect(choices.contains { $0.designation == "External Paint" && $0.name == "Paint (external command)" })
    }
}
