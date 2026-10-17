// SPDX-License-Identifier: GPL-3.0-or-later

import CoreGraphics
import Foundation
import Testing
@testable import GreenshotCore

/// The admin policy (`ManagedPolicy`). There is no MDM in a test: forced values come from `ManagedValues`, like a
/// configuration profile would give them; the defaults path also runs through a real `UserDefaults` suite.
struct ManagedPolicyTests {
    private func policy(forced: [String: Any] = [:], unforced: [String: Any] = [:]) -> ManagedPolicy {
        ManagedPolicy(source: ManagedValues(forced: forced, unforced: unforced))
    }

    // MARK: Locked values

    @Test func forcedValueWinsAndTheUsersValueStaysStored() {
        let p = policy(forced: ["Greenshot.outputFormat": "jpg", "Greenshot.jpegQuality": 85])
        var stored = AppSettings()
        stored.outputFormat = .bmp
        let effective = p.effective(stored)
        #expect(effective.outputFormat == .jpg)
        #expect(effective.jpegQuality == 85)
        #expect(stored.outputFormat == .bmp)
        #expect(p.isLocked("outputFormat"))
        #expect(!p.isLocked("filenamePattern"))
        #expect(p.problems.isEmpty)
    }

    @Test func editsOfLockedValuesAreDropped() {
        let p = policy(forced: ["Greenshot.outputFormat": "jpg"])
        var stored = AppSettings()
        stored.outputFormat = .bmp
        let effective = p.effective(stored)
        var changed = effective
        changed.outputFormat = .gif
        changed.filenamePattern = "shot"
        let newStored = p.stored(afterEditing: changed, effective: effective, stored: stored)
        #expect(newStored.outputFormat == .bmp)
        #expect(newStored.filenamePattern == "shot")
        let newEffective = p.effective(newStored)
        #expect(newEffective.outputFormat == .jpg)
        #expect(newEffective.filenamePattern == "shot")
    }

    @Test func onlyEditedValuesReachTheStoredSettings() {
        // A destination the policy took out stays stored, for when the profile is removed.
        let p = policy(forced: ["Greenshot.excludeDestinations": ["jira"]])
        var stored = AppSettings()
        stored.destinations = [.clipboard, .jira]
        let effective = p.effective(stored)
        #expect(effective.destinations == [.clipboard])
        var changed = effective
        changed.zoomerEnabled = false
        let newStored = p.stored(afterEditing: changed, effective: effective, stored: stored)
        #expect(newStored.destinations == [.clipboard, .jira])
        #expect(!newStored.zoomerEnabled)
    }

    @Test func withoutAPolicyAnEditIsStoredAsItIs() {
        let p = ManagedPolicy()
        var changed = AppSettings()
        changed.jpegQuality = 50
        let stored = p.stored(afterEditing: changed, effective: AppSettings(), stored: AppSettings())
        #expect(stored == changed)
        #expect(p.isEmpty)
    }

    @Test func membersByDottedKeyOrGroupDictionary() {
        let p = policy(forced: ["Greenshot.printing.footer": false, "Greenshot.email": ["to": "team@example.com"]])
        var stored = AppSettings()
        stored.email.cc = "me@example.com"
        stored.printing.center = false
        let e = p.effective(stored)
        #expect(!e.printing.footer)
        #expect(!e.printing.center)
        #expect(e.email.to == "team@example.com")
        #expect(e.email.cc == "me@example.com")
        #expect(p.isLocked("printing.footer"))
        #expect(!p.isLocked("printing.center"))
        #expect(p.isLocked("email.to"))
        #expect(!p.isLocked("email.cc"))
        // A control that writes the whole group counts as locked.
        #expect(p.isLocked("printing"))
    }

    @Test func aDottedKeyWinsOverItsGroupDictionary() {
        let p = policy(forced: ["Greenshot.printing": ["footer": true, "center": false], "Greenshot.printing.footer": false])
        let e = p.effective(AppSettings())
        #expect(!e.printing.footer)
        #expect(!e.printing.center)
    }

    @Test func wrongTypesAreIgnoredAndReported() {
        let p = policy(forced: ["Greenshot.jpegQuality": "high", "Greenshot.captureMousePointer": 1,
                                "Greenshot.lastUpdateCheck": Date(), "Greenshot.printing.footer": "maybe"])
        #expect(p.forced.isEmpty)
        #expect(p.problems.count == 4)
        let e = p.effective(AppSettings())
        #expect(e.jpegQuality == 80)
        #expect(e.captureMousePointer)
        #expect(!p.isLocked("jpegQuality"))
    }

    @Test func textsAreReadAsNumbersSwitchesAndLists() {
        let p = policy(forced: ["Greenshot.jpegQuality": "85", "Greenshot.zoomerEnabled": "false",
                                "Greenshot.zoomerOpacity": "0.5", "Greenshot.excludeDestinations": "Box, dropbox",
                                "Greenshot.filenamePattern": "a,b"])
        let e = p.effective(AppSettings())
        #expect(e.jpegQuality == 85)
        #expect(!e.zoomerEnabled)
        #expect(e.zoomerOpacity == 0.5)
        #expect(e.excludeDestinations == ["Box", "dropbox"])
        #expect(e.filenamePattern == "a,b")
        #expect(p.problems.isEmpty)
    }

    @Test func unknownKeysAreReported() {
        let p = policy(forced: ["Greenshot.outputFormatt": "jpg", "Greenshot.printing.colour": true])
        #expect(p.forced.isEmpty)
        #expect(p.problems.count == 2)
    }

    @Test func anEmptyTextClearsAHotkey() {
        let shiftCommand = KeyCombo.shift | KeyCombo.command
        let p = policy(forced: ["Greenshot.hotkeys.region": "",
                                "Greenshot.hotkeys.clipboard": ["keyCode": 9, "modifiers": Int(shiftCommand)]])
        let e = p.effective(AppSettings())
        let expected = KeyCombo(keyCode: 9, modifiers: shiftCommand)
        #expect(e.hotkeys.region == nil)
        #expect(e.hotkeys.clipboard == expected)
        #expect(e.hotkeys.window == .defaultWindow)
        #expect(p.isLocked("hotkeys.region"))
        #expect(p.problems.isEmpty)
    }

    @Test func aWholeValueOfAStructIsReplacedNotMerged() {
        let p = policy(forced: ["Greenshot.defaultEditorSize": ["width": 800, "height": 600]])
        let e = p.effective(AppSettings())
        #expect(e.defaultEditorSize == CaptureSize(width: 800, height: 600))
        let partial = policy(forced: ["Greenshot.defaultEditorSize": ["width": 800]])
        #expect(partial.forced.isEmpty)
        #expect(partial.problems.count == 1)
    }

    // MARK: Defaults

    @Test func defaultsFillOnlyWhatTheStoredSettingsLack() throws {
        let p = policy(forced: ["Greenshot.defaults": ["outputFormat": "jpg", "printing": ["footer": false], "welcomeShown": true]])
        var settings = AppSettings()
        settings.outputFormat = .bmp
        let full = try JSONEncoder().encode(settings)
        var object = try #require(try JSONSerialization.jsonObject(with: full) as? [String: Any])
        object["outputFormat"] = nil
        var printing = try #require(object["printing"] as? [String: Any])
        printing["footer"] = nil
        object["printing"] = printing
        let stored = try JSONSerialization.data(withJSONObject: object)
        let loaded = p.loaded(AppSettings(), storedJSON: stored)
        #expect(loaded.outputFormat == .jpg)
        #expect(!loaded.printing.footer)
        #expect(!loaded.welcomeShown)
        #expect(!p.isLocked("outputFormat"))
        #expect(p.forced.isEmpty)
    }

    @Test func everyDefaultAppliesAtTheFirstStart() {
        let p = policy(forced: ["Greenshot.defaults": ["outputFormat": "jpg", "welcomeShown": true]])
        let loaded = p.loaded(AppSettings(), storedJSON: nil)
        #expect(loaded.outputFormat == .jpg)
        #expect(loaded.welcomeShown)
    }

    @Test func plainKeysThatAreNotForcedAreDefaults() throws {
        let name = "greenshot-tests-managed-\(UUID().uuidString)"
        let defaults = try #require(UserDefaults(suiteName: name))
        defer { defaults.removePersistentDomain(forName: name) }
        defaults.set("jpg", forKey: "Greenshot.outputFormat")
        defaults.set(["footer": false], forKey: "Greenshot.printing")
        let p = ManagedPolicy(source: UserDefaultsManagedSource(defaults))
        #expect(p.forced.isEmpty)
        #expect(p.defaults["outputFormat"] != nil)
        #expect(p.defaults["printing.footer"] != nil)
        let loaded = p.loaded(AppSettings(), storedJSON: nil)
        #expect(loaded.outputFormat == .jpg)
        #expect(!loaded.printing.footer)
    }

    @Test func aLockedValueBeatsADefault() {
        let p = policy(forced: ["Greenshot.outputFormat": "png"], unforced: ["Greenshot.outputFormat": "jpg"])
        let e = p.effective(p.loaded(AppSettings(), storedJSON: nil))
        #expect(e.outputFormat == .png)
    }

    // MARK: Destinations

    @Test func excludedDestinationsByMacAndUpstreamNames() {
        var s = AppSettings()
        s.excludeDestinations = ["FileNoDialog", "EMail", "Windows10OCR", "Office Plugin", "zxing", "fileAs", "nonsense"]
        let expected: Set<CaptureDestination> = [.file, .email, .ocr, .word, .excel, .powerpoint, .outlook, .notes, .qrCode, .fileAs]
        #expect(s.excludedDestinations == expected)
        #expect(s.unknownExcludedDestinationNames == ["nonsense"])
        #expect(s.isDestinationExcluded(.notes))
        #expect(!s.isDestinationExcluded(.clipboard))
        let p = policy(forced: ["Greenshot.excludeDestinations": ["jira", "nonsense"]])
        #expect(p.problems.count == 1)
    }

    @Test func excludedDestinationsLeaveTheConfiguredOnes() {
        var s = AppSettings()
        s.destinations = [.jira]
        s.excludeDestinations = ["jira"]
        s.removeExcludedDestinations()
        #expect(s.destinations == [.picker])
        s.destinations = [.jira]
        s.excludeDestinations = ["Jira Plugin", "Picker"]
        s.removeExcludedDestinations()
        #expect(s.destinations == [.editor])
    }

    // MARK: Key paths and the table

    @Test func keyPathsHaveNames() {
        #expect(ManagedSettingKeys.name(for: \AppSettings.outputFormat) == "outputFormat")
        #expect(ManagedSettingKeys.name(for: \AppSettings.printing.footer) == "printing.footer")
        #expect(ManagedSettingKeys.name(for: \AppSettings.video.frameRate) == "video.frameRate")
        // HotkeysSection builds its key paths like this.
        let appended: AnyKeyPath = (\AppSettings.hotkeys).appending(path: \HotkeySettings.recordVideo)
        #expect(ManagedSettingKeys.name(for: appended) == "hotkeys.recordVideo")
        let p = policy(forced: ["Greenshot.hotkeys.region": ""])
        let region: AnyKeyPath = (\AppSettings.hotkeys).appending(path: \HotkeySettings.region)
        #expect(p.isLocked(region))
        #expect(!p.isLocked(\AppSettings.hotkeys.window))
    }

    @Test func theTableHasEverySetting() throws {
        var settings = AppSettings()
        settings.lastCapturedRegion = CGRect(x: 1, y: 2, width: 3, height: 4)
        settings.fixedCaptureSize = CaptureSize(width: 10, height: 20)
        settings.lastUpdateCheck = Date(timeIntervalSince1970: 0)
        settings.lastSavedFile = "/tmp/a.png"
        settings.video.maximumSize = CaptureSize(width: 1280, height: 720)
        let object = try #require(SettingsJSON.object(settings))
        var missing: [String] = []
        for key in object.keys.sorted() {
            if !ManagedSettingKeys.contains(key) { missing.append(key) }
            guard ManagedSettingKeys.isGroup(key) else { continue }
            let members = try #require(object[key] as? [String: Any])
            for member in members.keys.sorted() where !ManagedSettingKeys.contains(key + "." + member) {
                missing.append(key + "." + member)
            }
        }
        #expect(missing == [], "Add these to ManagedSettingKeys (Settings+Managed.swift)")
        let names = ManagedSettingKeys.names
        #expect(Set(names).count == names.count)
        let unresolved = names.filter { SettingsJSON.value(at: $0, in: object) == nil }
        #expect(unresolved == [])
    }

    // MARK: The sample profile

    @Test func theSampleProfileHasNoProblems() throws {
        let root = URL(fileURLWithPath: #filePath).deletingLastPathComponent().deletingLastPathComponent().deletingLastPathComponent()
        let file = root.appendingPathComponent("docs/admin/GreenshotMac.mobileconfig")
        let data = try Data(contentsOf: file)
        let plist = try #require(try PropertyListSerialization.propertyList(from: data, format: nil) as? [String: Any])
        let payloads = try #require(plist["PayloadContent"] as? [[String: Any]])
        let payload = try #require(payloads.first { ($0["PayloadType"] as? String) == "com.apple.ManagedClient.preferences" })
        let domains = try #require(payload["PayloadContent"] as? [String: Any])
        let domain = try #require(domains["io.github.greenshot-mac.GreenshotMac"] as? [String: Any])
        let forced = try #require(domain["Forced"] as? [[String: Any]])
        let values = try #require(forced.first?["mcx_preference_settings"] as? [String: Any])
        #expect(!values.isEmpty)
        let p = ManagedPolicy(source: ManagedValues(forced: values))
        #expect(p.problems == [])
        let e = p.effective(p.loaded(AppSettings(), storedJSON: nil))
        #expect(e.hideExpertSettings)
        #expect(e.isDestinationExcluded(.dropbox))
        #expect(e.outputFormat == .jpg)
        #expect(e.jira.login == .serverToken)
        #expect(e.hotkeys.lastRegion == nil)
        #expect(e.hotkeys.region == .defaultRegion)
        #expect(!e.captureMousePointer)
        #expect(p.isLocked("updateCheckIntervalDays"))
        #expect(!p.isLocked("captureMousePointer"))
    }
}
