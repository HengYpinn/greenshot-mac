// SPDX-License-Identifier: GPL-3.0-or-later

import Foundation
import Testing
@testable import GreenshotCore

struct SettingsPaneTests {
    @Test func upstreamTabNames() {
        #expect(SettingsPane(name: "general") == .general)
        #expect(SettingsPane(name: "Capture") == .capture)
        #expect(SettingsPane(name: " OUTPUT ") == .output)
        #expect(SettingsPane(name: "destination") == .destinations)
        #expect(SettingsPane(name: "destinations") == .destinations)
        #expect(SettingsPane(name: "editor") == .editor)
        #expect(SettingsPane(name: "print") == .printer)
        #expect(SettingsPane(name: "printer") == .printer)
        #expect(SettingsPane(name: "expert") == .expert)
        #expect(SettingsPane(name: "ExpertSettings") == .expert)
    }

    @Test func tabsWithoutAMacTab() {
        #expect(SettingsPane(name: "plugins") == nil)
        #expect(SettingsPane(name: "recipes") == nil)
        #expect(SettingsPane(name: "") == nil)
    }

    @Test func numberedLikeTheWindowsTabs() {
        #expect(SettingsPane.allCases.map(\.rawValue) == Array(0...6))
        #expect(SettingsPane.expert.rawValue == 6)
    }
}

struct AppLaunchOptionsTests {
    @Test func settingsFolderFromTheArguments() {
        let options = AppLaunchOptions.parse(arguments: ["GreenshotMac", "--settings-dir", "/tmp/gs"], environment: [:])
        #expect(options.settingsDirectory?.path == "/tmp/gs")
        #expect(options.settingsFile?.path == "/tmp/gs/settings.json")
        let joined = AppLaunchOptions.parse(arguments: ["GreenshotMac", "--settings-dir=/tmp/other"], environment: [:])
        #expect(joined.settingsDirectory?.path == "/tmp/other")
    }

    @Test func environmentAndPrecedence() {
        let env = [AppLaunchOptions.settingsDirectoryVariable: "/tmp/env"]
        #expect(AppLaunchOptions.parse(arguments: ["GreenshotMac"], environment: env).settingsDirectory?.path == "/tmp/env")
        #expect(AppLaunchOptions.parse(arguments: ["GreenshotMac", "--settings-dir", "/tmp/arg"], environment: env)
            .settingsDirectory?.path == "/tmp/arg")
    }

    @Test func missingValuesAndTilde() {
        #expect(AppLaunchOptions.parse(arguments: ["GreenshotMac", "--settings-dir"], environment: [:]).settingsDirectory == nil)
        #expect(AppLaunchOptions.parse(arguments: ["GreenshotMac"], environment: [:]) == AppLaunchOptions())
        #expect(AppLaunchOptions.parse(arguments: ["GreenshotMac", "--settings-dir="], environment: [:]).settingsDirectory == nil)
        let home = FileManager.default.homeDirectoryForCurrentUser.standardizedFileURL.path
        #expect(AppLaunchOptions.parse(arguments: ["x", "--settings-dir", "~/gs"], environment: [:]).settingsDirectory?.path == home + "/gs")
    }
}

struct SettingsFileTests {
    @Test func roundTripThroughAFile() throws {
        let folder = FileManager.default.temporaryDirectory.appendingPathComponent("gs-settings-\(UUID().uuidString)")
        defer { try? FileManager.default.removeItem(at: folder) }
        let file = folder.appendingPathComponent("settings.json")
        var settings = AppSettings()
        settings.theme = .dark
        settings.leftClickAction = .captureRegion
        settings.maxMenuItemLength = 40
        try SettingsStorage.save(settings, toFile: file)
        #expect(SettingsStorage.load(fromFile: file) == settings)
    }

    @Test func missingOrBrokenFileGivesDefaults() throws {
        let folder = FileManager.default.temporaryDirectory.appendingPathComponent("gs-settings-\(UUID().uuidString)")
        defer { try? FileManager.default.removeItem(at: folder) }
        let file = folder.appendingPathComponent("settings.json")
        #expect(SettingsStorage.load(fromFile: file) == AppSettings())
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        try Data("not json".utf8).write(to: file)
        #expect(SettingsStorage.load(fromFile: file) == AppSettings())
    }
}

struct AppSettingsMenuBarDecodingTests {
    @Test func brokenValuesFallBackToDefaults() throws {
        let json = #"""
            {"leftClickAction": "fly", "doubleClickAction": 3, "hideMenuBarIcon": "yes", "thumbnailPreview": null,
             "maxMenuItemLength": "x", "theme": "purple", "checkForUnstable": "maybe"}
            """#
        let decoded = try JSONDecoder().decode(AppSettings.self, from: Data(json.utf8))
        let d = AppSettings()
        #expect(decoded.leftClickAction == d.leftClickAction && decoded.doubleClickAction == d.doubleClickAction)
        #expect(decoded.hideMenuBarIcon == d.hideMenuBarIcon && decoded.thumbnailPreview == d.thumbnailPreview)
        #expect(decoded.maxMenuItemLength == d.maxMenuItemLength && decoded.theme == d.theme)
        #expect(decoded.checkForUnstable == d.checkForUnstable)
    }

    @Test func validValuesRoundTrip() throws {
        var s = AppSettings()
        s.leftClickAction = .openEmptyEditor
        s.doubleClickAction = .doNothing
        s.hideMenuBarIcon = true
        s.thumbnailPreview = false
        s.maxMenuItemLength = 60
        s.theme = .light
        s.checkForUnstable = true
        let decoded = try JSONDecoder().decode(AppSettings.self, from: JSONEncoder().encode(s))
        #expect(decoded == s)
    }
}

struct BrokenSettingsFileTests {
    @Test func aBrokenFileIsMovedAsideNotOverwritten() throws {
        let folder = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString, isDirectory: true)
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: folder) }
        let file = folder.appendingPathComponent("settings.json")
        try Data("{ \"jpegQuality\": 50, oops".utf8).write(to: file)
        var aside: URL?
        let settings = SettingsStorage.load(fromFile: file) { aside = $0 }
        #expect(settings == AppSettings())
        #expect(aside?.lastPathComponent == "settings.json.bad")
        #expect(!FileManager.default.fileExists(atPath: file.path))
        #expect(try String(contentsOf: folder.appendingPathComponent("settings.json.bad"), encoding: .utf8).contains("oops"))
    }

    @Test func aMissingFileGivesTheDefaultsWithoutAnythingMoved() {
        var moved = false
        let file = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString + ".json")
        #expect(SettingsStorage.load(fromFile: file) { _ in moved = true } == AppSettings())
        #expect(!moved)
    }
}

struct SelfServiceSectionTests {
    @Test func upstreamSectionIds() {
        #expect(SelfServiceSection(name: "system") == .system)
        #expect(SelfServiceSection(name: " Setup ") == .setup)
        #expect(SelfServiceSection(name: "FILES") == .files)
        #expect(SelfServiceSection(name: "clipboard") == .clipboard)
        #expect(SelfServiceSection(name: "hotkeys") == .hotkeys)
        #expect(SelfServiceSection(name: "checksum") == .integrity)
        #expect(SelfServiceSection(name: "integrity") == .integrity)
        #expect(SelfServiceSection(name: "imgur") == nil)
        #expect(SelfServiceSection(name: "debug_integration") == nil)
    }

    @Test func keysOfTheWindow() {
        #expect(SelfServiceSection(key: "1") == .system)
        #expect(SelfServiceSection(key: "E") == .system)
        #expect(SelfServiceSection(key: "2") == .setup)
        #expect(SelfServiceSection(key: "l") == .files)
        #expect(SelfServiceSection(key: "i") == .files)
        #expect(SelfServiceSection(key: "c") == .clipboard)
        #expect(SelfServiceSection(key: "h") == .hotkeys)
        #expect(SelfServiceSection(key: "v") == .integrity)
        #expect(SelfServiceSection(key: "6") == .integrity)
        #expect(SelfServiceSection(key: "x") == nil)
    }
}
