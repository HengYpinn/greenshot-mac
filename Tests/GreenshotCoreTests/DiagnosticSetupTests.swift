// Greenshot for Mac (Community) - an unofficial macOS port of Greenshot
// Copyright (C) 2026 Greenshot for Mac (Community) contributors
// SPDX-License-Identifier: GPL-3.0-or-later

import Carbon.HIToolbox
import Foundation
import Testing
@testable import GreenshotCore

/// "Your setup" (upstream `SetupSectionViewModelTests.cs`), the screenshot shortcuts of macOS and other capture apps.
struct DiagnosticSetupTests {
    /// `AppleSymbolicHotKeys` as `defaults export com.apple.symbolichotkeys` gives it on a Mac where nobody changed the
    /// screenshot shortcuts (60, 61, 164 and 15 are real entries; 28-31 and 184 are missing), plus two changes in the
    /// same shape: ⇧⌘4 switched off, and the options moved to ⌃⇧⌘5.
    static var symbolicHotKeys: [String: Any] {
        let json = """
            {"60": {"enabled": true, "value": {"type": "standard", "parameters": [32, 49, 262144]}},
             "61": {"enabled": true, "value": {"type": "standard", "parameters": [32, 49, 786432]}},
             "164": {"enabled": false, "value": {"type": "standard", "parameters": [65535, 65535, 0]}},
             "15": {"enabled": false},
             "30": {"enabled": false, "value": {"type": "standard", "parameters": [52, 21, 1179648]}},
             "184": {"enabled": true, "value": {"type": "standard", "parameters": [53, 23, 1441792]}}}
            """
        return (try? JSONSerialization.jsonObject(with: Data(json.utf8))) as? [String: Any] ?? [:]
    }

    @Test func missingEntriesAreTheDefaultsAndSwitchedOn() {
        let shortcuts = SystemScreenshotShortcut.read(symbolicHotKeys: [:])
        #expect(shortcuts == SystemScreenshotShortcut.defaults)
        let allOn = shortcuts.allSatisfy { $0.enabled }
        #expect(allOn)
        #expect(shortcuts.map(\.combo.displayString) == ["⇧⌘3", "⌃⇧⌘3", "⇧⌘4", "⌃⇧⌘4", "⇧⌘5"])
        #expect(SystemScreenshotShortcut.read(symbolicHotKeys: nil) == SystemScreenshotShortcut.defaults)
    }

    @Test func readsChangedAndSwitchedOffShortcuts() throws {
        let shortcuts = SystemScreenshotShortcut.read(symbolicHotKeys: Self.symbolicHotKeys)
        let area = try #require(shortcuts.first { $0.id == 30 })
        #expect(!area.enabled)
        let options = try #require(shortcuts.first { $0.id == 184 })
        #expect(options.enabled)
        #expect(options.combo.displayString == "⌃⇧⌘5")
        let screen = try #require(shortcuts.first { $0.id == 28 })
        #expect(screen.enabled)
    }

    @Test func eventFlagsBecomeCarbonModifiers() {
        let shiftCommand = SystemScreenshotShortcut.carbonModifiers(eventFlags: 1_179_648)
        let expectedShiftCommand: UInt32 = KeyCombo.shift | KeyCombo.command
        #expect(shiftCommand == expectedShiftCommand)
        let control = SystemScreenshotShortcut.carbonModifiers(eventFlags: 262_144)
        #expect(control == KeyCombo.control)
        let controlOption = SystemScreenshotShortcut.carbonModifiers(eventFlags: 786_432)
        let expectedControlOption: UInt32 = KeyCombo.control | KeyCombo.option
        #expect(controlOption == expectedControlOption)
    }

    @Test func conflictsOnlyWithSwitchedOnShortcutsOfTheSameKeys() {
        let shortcuts = SystemScreenshotShortcut.read(symbolicHotKeys: Self.symbolicHotKeys)
        let shiftCommand4 = KeyCombo(keyCode: UInt32(kVK_ANSI_4), modifiers: KeyCombo.shift | KeyCombo.command)
        let shiftCommand3 = KeyCombo(keyCode: UInt32(kVK_ANSI_3), modifiers: KeyCombo.shift | KeyCombo.command)
        // ⇧⌘4 is switched off on this Mac, ⇧⌘3 is on.
        #expect(SystemScreenshotShortcut.conflicts(shortcuts, with: [shiftCommand4]).isEmpty)
        #expect(SystemScreenshotShortcut.conflicts(shortcuts, with: [shiftCommand3]).map(\.id) == [28])
        #expect(SystemScreenshotShortcut.conflicts(shortcuts, with: [.defaultRegion, .defaultWindow]).isEmpty)
        // A hotkey of two steps conflicts with its first step.
        let sequence = KeyCombo(keyCode: UInt32(kVK_ANSI_3), modifiers: KeyCombo.shift | KeyCombo.command,
                                followingChords: [KeyChord(keyCode: UInt32(kVK_ANSI_C), modifiers: 0)])
        #expect(SystemScreenshotShortcut.conflicts(shortcuts, with: [sequence]).map(\.id) == [28])
    }

    @Test func contendersByBundleIdentifierOrName() {
        let cleanShot = CaptureAppContender.known[0]
        #expect(cleanShot.matches(bundleIdentifier: "pl.maketheweb.cleanshotx", name: nil))
        #expect(cleanShot.matches(bundleIdentifier: "pl.maketheweb.CleanShotX.setapp", name: "CleanShot X"))
        #expect(!cleanShot.matches(bundleIdentifier: "com.apple.Safari", name: "Safari"))
        let snagit = CaptureAppContender.known.first { $0.name == "Snagit" }
        #expect(snagit?.matches(bundleIdentifier: "com.TechSmith.Snagit2024", name: nil) == true)
        #expect(snagit?.matches(bundleIdentifier: nil, name: "Snagit 2025") == true)
    }

    // MARK: Hotkey rows

    @Test func hotkeyRowsSayWhatRegisteringDid() {
        var hotkeys = HotkeySettings()
        hotkeys.text = KeyCombo(keyCode: UInt32(kVK_ANSI_3), modifiers: KeyCombo.shift | KeyCombo.command)
        let registered = [KeyCombo.defaultRegion, .defaultWindow, .defaultFullScreen, .defaultLastRegion]
        let rows = HotkeyStatus.rows(hotkeys, registered: registered, refused: [.defaultWindow],
                                     systemShortcuts: SystemScreenshotShortcut.defaults)
        #expect(rows.map(\.id) == ["region", "window", "fullScreen", "lastRegion", "text", "recordVideo", "clipboard"])
        #expect(rows[0].state == .registered)
        #expect(rows[0].keys == "⌃⌥⌘4")
        #expect(rows[1].state == .refused)
        // Not in the registration (e.g. while a shortcut is being recorded).
        #expect(rows[4].state == .unknown)
        #expect(rows[4].systemConflict == "Save picture of screen as a file")
        #expect(rows[5].state == .notSet)
        #expect(rows[5].keys == nil)
        let none = HotkeyStatus.rows(hotkeys, registered: nil, refused: [], systemShortcuts: [])
        #expect(none[0].state == .unknown)
    }

    // MARK: Setup lines

    private var facts: SetupFacts {
        var facts = SetupFacts(appName: "Greenshot for Mac", currentVersion: "1.4.0")
        facts.version = .checked(.upToDate(latest: "1.4.0"))
        facts.hotkeyCount = 4
        facts.menuBarIconVisible = true
        return facts
    }

    @Test func everythingFineHasNoProblems() {
        let lines = SetupCheck.lines(facts)
        #expect(lines.map(\.id) == ["version", "screen", "icon", "hotkeys", "system"])
        let allOK = lines.allSatisfy { $0.state == .ok }
        #expect(allOK)
        #expect(SetupCheck.problemCount(lines) == 0)
        #expect(lines[0].text == "You have the latest version of Greenshot for Mac, 1.4.0.")
    }

    @Test func eachProblemHasItsFix() {
        var facts = self.facts
        let page = URL(string: "https://github.com/HengYpinn/greenshot-mac/releases/tag/v1.5.0")!
        facts.version = .checked(.newer(UpdateCheck.Release(version: "1.5.0", pageURL: page)))
        facts.canRecordScreen = false
        facts.menuBarIconSwitchedOff = true
        facts.refusedHotkeys = ["Capture window (⌃⌥⌘5)"]
        facts.systemShortcutConflicts = ["⇧⌘4 (Save picture of selected area as a file)"]
        facts.loginItem = .needsApproval
        let lines = SetupCheck.lines(facts)
        #expect(SetupCheck.problemCount(lines) == 6)
        #expect(lines.map(\.fix) == [.download(page), .openScreenRecordingSettings, .showMenuBarIcon, .registerHotkeys,
                                     .openKeyboardShortcuts, .openLoginItems])
        #expect(lines[0].text == "Greenshot for Mac 1.5.0 is available, you have 1.4.0.")
        let allFixable = lines.allSatisfy { $0.fixTitle != nil }
        #expect(allFixable)
    }

    @Test func hiddenIconAndUnknownVersion() {
        var facts = self.facts
        facts.menuBarIconVisible = false
        facts.version = .checked(.failed)
        let lines = SetupCheck.lines(facts)
        #expect(lines[0].state == .pending)
        #expect(lines[2].fix == .openMenuBarSettings)
        facts.version = .checking
        facts.menuBarIconVisible = nil
        let unknown = SetupCheck.lines(facts)
        #expect(unknown[0].text == "Greenshot for Mac is checking for a newer version…")
        #expect(unknown[2].state == .ok)
    }

    @Test func noHotkeysNoHotkeyLines() {
        var facts = self.facts
        facts.hotkeyCount = 0
        #expect(SetupCheck.lines(facts).map(\.id) == ["version", "screen", "icon"])
    }
}
