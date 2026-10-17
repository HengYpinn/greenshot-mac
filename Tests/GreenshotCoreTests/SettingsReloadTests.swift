// SPDX-License-Identifier: GPL-3.0-or-later

import Foundation
import Testing
@testable import GreenshotCore

/// `greenshot-cli --reload` reads the settings again: a settings file with a mistake must change nothing and stay where
/// it is (`SettingsStorage.reload`), unlike at the start, where it is moved aside.
struct SettingsReloadTests {
    private func folder() throws -> URL {
        let url = FileManager.default.temporaryDirectory.appendingPathComponent("greenshot-reload-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)
        return url
    }

    @Test func aFileWithAMistakeIsAnErrorAndStaysWhereItIs() throws {
        let dir = try folder()
        defer { try? FileManager.default.removeItem(at: dir) }
        let file = dir.appendingPathComponent("settings.json")
        let text = "{\n  \"outputFormat\": \"jpg\",\n  \"jpegQuality\": 85,,\n}\n"
        try Data(text.utf8).write(to: file)
        var failure: SettingsReloadError?
        do {
            _ = try SettingsStorage.reload(fromFile: file)
        } catch let error as SettingsReloadError {
            failure = error
        }
        let error = try #require(failure)
        #expect(error.description.contains("settings.json"))
        let kept = try String(contentsOf: file, encoding: .utf8)
        #expect(kept == text)
        let aside = file.appendingPathExtension("bad")
        #expect(!FileManager.default.fileExists(atPath: aside.path))
    }

    @Test func jsonThatIsNotAnObjectIsAnError() throws {
        let dir = try folder()
        defer { try? FileManager.default.removeItem(at: dir) }
        let file = dir.appendingPathComponent("settings.json")
        try Data("[1, 2]".utf8).write(to: file)
        #expect(throws: SettingsReloadError.self) { try SettingsStorage.reload(fromFile: file) }
    }

    @Test func aGoodFileIsReadWithItsJSON() throws {
        let dir = try folder()
        defer { try? FileManager.default.removeItem(at: dir) }
        let file = dir.appendingPathComponent("settings.json")
        var settings = AppSettings()
        settings.outputFormat = .jpg
        try SettingsStorage.save(settings, toFile: file)
        let reloaded = try SettingsStorage.reload(fromFile: file)
        #expect(reloaded.settings == settings)
        #expect(reloaded.json != nil)
    }

    @Test func aMissingFileGivesTheDefaults() throws {
        let dir = try folder()
        defer { try? FileManager.default.removeItem(at: dir) }
        let reloaded = try SettingsStorage.reload(fromFile: dir.appendingPathComponent("settings.json"))
        #expect(reloaded.settings == AppSettings())
        #expect(reloaded.json == nil)
    }

    @Test func userDefaultsThatCantBeDecodedAreAnError() throws {
        let name = "greenshot-tests-reload-\(UUID().uuidString)"
        let defaults = try #require(UserDefaults(suiteName: name))
        defer { defaults.removePersistentDomain(forName: name) }
        let none = try SettingsStorage.reload(from: defaults)
        #expect(none.settings == AppSettings())
        defaults.set(Data("not json".utf8), forKey: SettingsStorage.key)
        #expect(throws: SettingsReloadError.self) { try SettingsStorage.reload(from: defaults) }
        defaults.set("a text", forKey: SettingsStorage.key)
        #expect(throws: SettingsReloadError.self) { try SettingsStorage.reload(from: defaults) }
        var settings = AppSettings()
        settings.jpegQuality = 60
        SettingsStorage.save(settings, to: defaults)
        let reloaded = try SettingsStorage.reload(from: defaults)
        #expect(reloaded.settings.jpegQuality == 60)
    }
}
