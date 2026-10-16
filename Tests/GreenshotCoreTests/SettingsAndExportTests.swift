// SPDX-License-Identifier: GPL-3.0-or-later

import Carbon.HIToolbox
import CoreGraphics
import Foundation
import ImageIO
import Testing
@testable import GreenshotCore

struct SettingsTests {
    @Test func defaultsMatchUpstream() {
        let s = AppSettings()
        #expect(s.destinations == [.picker])
        #expect(s.captureMousePointer && !s.interactiveWindowCapture && !s.playCameraSound)
        #expect(s.captureDelayMilliseconds == 100)
        #expect(s.filenamePattern == "${capturetime:d\"yyyy-MM-dd HH_mm_ss\"}-${title}")
        #expect(s.outputFormat == .png && s.jpegQuality == 80 && s.copyPathToClipboard)
        #expect(s.recentEmoji == "🙂")
    }

    @Test func roundTrip() throws {
        var s = AppSettings()
        s.destinations = [.editor, .clipboard]
        s.lastCapturedRegion = CGRect(x: 1, y: 2, width: 3, height: 4)
        s.editorStyles["arrow"] = AnnotationStyle(lineColor: .blue)
        s.recentEmoji = "👍"
        let decoded = try JSONDecoder().decode(AppSettings.self, from: JSONEncoder().encode(s))
        #expect(decoded == s)
    }

    @Test func missingOrBrokenValuesFallBackToDefaults() throws {
        let json = #"{"captureDelayMilliseconds": "soon", "zoomerEnabled": false}"#
        let decoded = try JSONDecoder().decode(AppSettings.self, from: Data(json.utf8))
        #expect(decoded.captureDelayMilliseconds == 100)
        #expect(!decoded.zoomerEnabled)
        #expect(decoded.hotkeys.region == .defaultRegion)
        #expect(decoded.recentEmoji == "🙂")
    }

    @Test func aClearedHotkeyStaysCleared() throws {
        var s = AppSettings()
        s.hotkeys.region = nil
        let decoded = try JSONDecoder().decode(AppSettings.self, from: JSONEncoder().encode(s))
        #expect(decoded.hotkeys.region == nil)
        #expect(decoded.hotkeys.window == .defaultWindow)
    }

    @Test func storedInUserDefaults() throws {
        let defaults = try #require(UserDefaults(suiteName: "greenshot-mac-tests-\(UUID().uuidString)"))
        var s = AppSettings()
        s.outputFolder = "~/Pictures/Screenshots"
        SettingsStorage.save(s, to: defaults)
        #expect(SettingsStorage.load(from: defaults).outputFolder == "~/Pictures/Screenshots")
        #expect(SettingsStorage.load(from: defaults).outputFolderURL.path.hasSuffix("/Pictures/Screenshots"))
    }

    @Test func turningOnADestinationTurnsOffTheMenu() {
        var s = AppSettings()
        s.setDestination(.clipboard, on: true)
        #expect(s.destinations == [.clipboard])
        s.setDestination(.file, on: true)
        s.setDestination(.file, on: true)
        #expect(s.destinations == [.clipboard, .file])
    }

    @Test func theMenuExcludesTheOthersAndComesBackWhenNothingIsLeft() {
        var s = AppSettings()
        s.setDestination(.clipboard, on: true)
        s.setDestination(.picker, on: true)
        #expect(s.destinations == [.picker])
        s.setDestination(.clipboard, on: true)
        s.setDestination(.clipboard, on: false)
        #expect(s.destinations == [.picker])
        s.setDestination(.picker, on: false)
        #expect(s.destinations == [.picker])
    }

    @Test func rememberedStylesPerKind() {
        var s = AppSettings()
        #expect(s.style(for: .counter) == .defaults(for: .counter))
        s.editorStyles["counter"] = AnnotationStyle(fillColor: .blue)
        #expect(s.style(for: .counter).fillColor == .blue)
    }
}

struct KeyComboTests {
    @Test func displayString() {
        #expect(KeyCombo.defaultRegion.displayString == "⌃⌥⌘4")
        #expect(KeyCombo(keyCode: UInt32(kVK_F13), modifiers: 0).displayString == "F13")
    }

    @Test func plainKeysNeedAModifier() {
        #expect(KeyCombo(keyCode: UInt32(kVK_F13), modifiers: 0).isValidGlobalShortcut)
        #expect(!KeyCombo(keyCode: UInt32(kVK_ANSI_A), modifiers: KeyCombo.shift).isValidGlobalShortcut)
        #expect(KeyCombo(keyCode: UInt32(kVK_ANSI_A), modifiers: KeyCombo.option).isValidGlobalShortcut)
    }
}

struct ImageExporterTests {
    let image = TestImage.make(width: 40, height: 20) { x, _ in x < 20 ? .red : .blue }

    @Test func pngKeepsSizeAndPixels() throws {
        let data = try ImageExporter.data(for: image, format: .png)
        let decoded = try #require(CGImageSourceCreateWithData(data as CFData, nil).flatMap { CGImageSourceCreateImageAtIndex($0, 0, nil) })
        #expect(decoded.width == 40 && decoded.height == 20)
        #expect(TestImage.pixel(decoded, 30, 10) == .blue)
    }

    @Test func jpegIsJpeg() throws {
        let data = try ImageExporter.data(for: image, format: .jpg, quality: 50)
        #expect(data.prefix(2) == Data([0xFF, 0xD8]))
    }

    @Test func writeCreatesFolders() throws {
        let folder = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: folder) }
        let url = folder.appendingPathComponent("2026/shot.png")
        try ImageExporter.write(image, to: url, format: .png)
        #expect(FileManager.default.fileExists(atPath: url.path))
    }

    @Test func formatFromExtension() {
        #expect(ImageFormat(fileExtension: "JPEG") == .jpg)
        #expect(ImageFormat(fileExtension: "tif") == .tiff)
        #expect(ImageFormat(fileExtension: "webp") == nil)
    }
}
