// Greenshot for Mac (Community) - an unofficial macOS port of Greenshot
// Copyright (C) 2026 Greenshot for Mac (Community) contributors
// Based on Greenshot, Copyright (C) 2007-2026 Thomas Braun, Jens Klingen, Robin Krom
// SPDX-License-Identifier: GPL-3.0-or-later

import Carbon.HIToolbox
import Foundation

/// The hotkeys of the settings with what registering them did, for Self-Service › Hotkeys (upstream
/// `HotkeySectionViewModel.RefreshGreenshotHotkeys`: Registered / Not Registered / Disabled).
public struct HotkeyStatusRow: Equatable, Identifiable, Sendable {
    public enum State: Equatable, Sendable {
        case registered
        /// macOS refused it: another app has its first key.
        case refused
        case notSet
        /// Not registered yet (e.g. while a shortcut is being recorded in Settings).
        case unknown
    }

    public var id: String
    public var name: String
    public var keys: String?
    public var state: State
    /// The macOS screenshot shortcut with the same keys, which macOS handles first.
    public var systemConflict: String?

    public init(id: String, name: String, keys: String?, state: State, systemConflict: String? = nil) {
        self.id = id
        self.name = name
        self.keys = keys
        self.state = state
        self.systemConflict = systemConflict
    }
}

public enum HotkeyStatus {
    /// The hotkeys in the order of Settings › General, with their names (upstream's tray menu names).
    public static func slots(_ hotkeys: HotkeySettings) -> [(id: String, name: String, combo: KeyCombo?)] {
        [("region", String(localized: "Capture region"), hotkeys.region),
         ("window", String(localized: "Capture window"), hotkeys.window),
         ("fullScreen", String(localized: "Capture full screen"), hotkeys.fullScreen),
         ("lastRegion", String(localized: "Capture last region"), hotkeys.lastRegion),
         ("text", String(localized: "Capture text"), hotkeys.text),
         ("recordVideo", String(localized: "Start or stop recording"), hotkeys.recordVideo),
         ("clipboard", String(localized: "Open image from clipboard"), hotkeys.clipboard)]
    }

    /// `registered`: the hotkeys of the last registration (nil: none yet); `refused`: those macOS refused.
    public static func rows(_ hotkeys: HotkeySettings, registered: [KeyCombo]?, refused: [KeyCombo],
                            systemShortcuts: [SystemScreenshotShortcut]) -> [HotkeyStatusRow] {
        slots(hotkeys).map { slot in
            guard let combo = slot.combo else {
                return HotkeyStatusRow(id: slot.id, name: slot.name, keys: nil, state: .notSet)
            }
            let state: HotkeyStatusRow.State
            if refused.contains(combo) {
                state = .refused
            } else if registered?.contains(combo) == true {
                state = .registered
            } else {
                state = .unknown
            }
            let conflict = systemShortcuts.first { $0.enabled && $0.combo.firstChord == combo.firstChord }
            return HotkeyStatusRow(id: slot.id, name: slot.name, keys: combo.displayString, state: state,
                                   systemConflict: conflict?.name)
        }
    }
}

/// A screenshot shortcut of macOS (System Settings › Keyboard › Keyboard Shortcuts › Screenshots), from the
/// `AppleSymbolicHotKeys` of `com.apple.symbolichotkeys`: the Mac's version of upstream's "the Print key opens the
/// Snipping Tool" check. macOS handles these before any app.
public struct SystemScreenshotShortcut: Equatable, Sendable {
    public var id: Int
    public var name: String
    public var combo: KeyCombo
    public var enabled: Bool

    public init(id: Int, name: String, combo: KeyCombo, enabled: Bool) {
        self.id = id
        self.name = name
        self.combo = combo
        self.enabled = enabled
    }

    /// The screenshot shortcuts with the keys macOS gives them when nobody changed them.
    public static let defaults: [SystemScreenshotShortcut] = {
        let shiftCommand = KeyCombo.shift | KeyCombo.command
        let controlShiftCommand = KeyCombo.control | shiftCommand
        return [
            .init(id: 28, name: String(localized: "Save picture of screen as a file"), combo: KeyCombo(keyCode: UInt32(kVK_ANSI_3), modifiers: shiftCommand), enabled: true),
            .init(id: 29, name: String(localized: "Copy picture of screen to the clipboard"), combo: KeyCombo(keyCode: UInt32(kVK_ANSI_3), modifiers: controlShiftCommand), enabled: true),
            .init(id: 30, name: String(localized: "Save picture of selected area as a file"), combo: KeyCombo(keyCode: UInt32(kVK_ANSI_4), modifiers: shiftCommand), enabled: true),
            .init(id: 31, name: String(localized: "Copy picture of selected area to the clipboard"), combo: KeyCombo(keyCode: UInt32(kVK_ANSI_4), modifiers: controlShiftCommand), enabled: true),
            .init(id: 184, name: String(localized: "Screenshot and recording options"), combo: KeyCombo(keyCode: UInt32(kVK_ANSI_5), modifiers: shiftCommand), enabled: true),
        ]
    }()

    /// The screenshot shortcuts as the user has them: `symbolicHotKeys` is the `AppleSymbolicHotKeys` dictionary
    /// (keys are the ids as text; `enabled`; `value.parameters` = [character, key code, NSEvent modifier flags]). A
    /// missing entry keeps the default, switched on.
    public static func read(symbolicHotKeys: [String: Any]?) -> [SystemScreenshotShortcut] {
        defaults.map { shortcut in
            guard let entry = symbolicHotKeys?[String(shortcut.id)] as? [String: Any] else { return shortcut }
            var result = shortcut
            if let enabled = entry["enabled"] as? NSNumber { result.enabled = enabled.boolValue }
            if let value = entry["value"] as? [String: Any], let parameters = value["parameters"] as? [NSNumber],
               parameters.count >= 3, parameters[1].intValue != 65_535 {
                result.combo = KeyCombo(keyCode: parameters[1].uint32Value,
                                        modifiers: carbonModifiers(eventFlags: parameters[2].uint64Value))
            }
            return result
        }
    }

    /// NSEvent modifier flags (shift 0x20000, control 0x40000, option 0x80000, command 0x100000) as Carbon flags.
    public static func carbonModifiers(eventFlags flags: UInt64) -> UInt32 {
        var result: UInt32 = 0
        if flags & 0x20000 != 0 { result |= KeyCombo.shift }
        if flags & 0x40000 != 0 { result |= KeyCombo.control }
        if flags & 0x80000 != 0 { result |= KeyCombo.option }
        if flags & 0x100000 != 0 { result |= KeyCombo.command }
        return result
    }

    /// The switched-on shortcuts whose keys are the first keys of one of `hotkeys`.
    public static func conflicts(_ shortcuts: [SystemScreenshotShortcut], with hotkeys: [KeyCombo]) -> [SystemScreenshotShortcut] {
        shortcuts.filter { shortcut in shortcut.enabled && hotkeys.contains { $0.firstChord == shortcut.combo.firstChord } }
    }
}

/// Other screenshot apps, which may take the same keys (upstream `HotkeySectionViewModel` "contenders": ShareX, Snagit,
/// Lightshot, PicPick, Dropbox). Found by bundle identifier or name among the running apps.
public struct CaptureAppContender: Equatable, Sendable {
    public var name: String
    public var bundlePrefixes: [String]
    public var note: String

    public init(name: String, bundlePrefixes: [String], note: String) {
        self.name = name
        self.bundlePrefixes = bundlePrefixes
        self.note = note
    }

    public static let known: [CaptureAppContender] = [
        .init(name: "CleanShot X", bundlePrefixes: ["pl.maketheweb.cleanshotx"], note: String(localized: "Screenshot app with its own global shortcuts")),
        .init(name: "Shottr", bundlePrefixes: ["cc.ffitch.shottr"], note: String(localized: "Screenshot app with its own global shortcuts")),
        .init(name: "Snagit", bundlePrefixes: ["com.TechSmith.Snagit"], note: String(localized: "TechSmith Snagit screen capture")),
        .init(name: "Lightshot", bundlePrefixes: ["com.skillbrains.lightshot"], note: String(localized: "Lightshot screenshot tool")),
        .init(name: "Monosnap", bundlePrefixes: ["com.monosnap"], note: String(localized: "Monosnap screenshot tool")),
        .init(name: "Dropbox", bundlePrefixes: ["com.getdropbox.dropbox"],
              note: String(localized: "\u{201C}Share screenshots using Dropbox\u{201D} takes the macOS screenshot keys")),
        .init(name: "Skitch", bundlePrefixes: ["com.skitch", "com.evernote.Skitch"], note: String(localized: "Skitch screenshot tool")),
        .init(name: "Xnapper", bundlePrefixes: ["com.xnapper"], note: String(localized: "Screenshot app with its own global shortcuts")),
        .init(name: "Flameshot", bundlePrefixes: ["org.flameshot"], note: String(localized: "Flameshot screenshot tool")),
        .init(name: "Zight", bundlePrefixes: ["com.linebreak.CloudAppMacOSX"], note: String(localized: "Zight (CloudApp) screen capture")),
    ]

    /// Whether one of `apps` (bundle identifier and name) is this contender.
    public func matches(bundleIdentifier: String?, name appName: String?) -> Bool {
        if let bundleIdentifier, bundlePrefixes.contains(where: { bundleIdentifier.lowercased().hasPrefix($0.lowercased()) }) {
            return true
        }
        guard let appName else { return false }
        return appName.range(of: name, options: .caseInsensitive) != nil
    }
}
