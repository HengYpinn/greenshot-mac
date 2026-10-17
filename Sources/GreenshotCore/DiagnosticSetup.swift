// Greenshot for Mac (Community) - an unofficial macOS port of Greenshot
// Copyright (C) 2026 Greenshot for Mac (Community) contributors
// Based on Greenshot, Copyright (C) 2007-2026 Thomas Braun, Jens Klingen, Robin Krom
// SPDX-License-Identifier: GPL-3.0-or-later

import Foundation

/// What "Your setup" knows (upstream `Greenshot/SelfService/ViewModels/SetupSectionViewModel.cs`, also step 3 of the
/// welcome window): gathered by the app, turned into lines here.
public struct SetupFacts: Equatable, Sendable {
    public enum Version: Equatable, Sendable {
        case checking
        case checked(UpdateCheck.Outcome)
    }

    public enum LoginItem: Equatable, Sendable { case on, off, needsApproval }

    public var appName: String
    public var currentVersion: String
    public var version: Version = .checking
    public var canRecordScreen = true
    /// Switched off in Settings › General.
    public var menuBarIconSwitchedOff = false
    /// The icon is on a screen (not behind the notch, not hidden by macOS); nil when unknown.
    public var menuBarIconVisible: Bool?
    public var hotkeyCount = 0
    /// "Capture region (⌃⌥⌘4)" for each hotkey macOS refused.
    public var refusedHotkeys: [String] = []
    /// "⇧⌘4 (Save picture of selected area as a file)" for each macOS screenshot shortcut with the keys of a hotkey.
    public var systemShortcutConflicts: [String] = []
    public var loginItem = LoginItem.off

    public init(appName: String, currentVersion: String) {
        self.appName = appName
        self.currentVersion = currentVersion
    }
}

/// One line of "Your setup": ✓ when fine, else what's wrong with a button to fix it (upstream `setup_*` texts).
public struct SetupLine: Equatable, Identifiable, Sendable {
    public enum State: Equatable, Sendable { case ok, problem, pending }

    public enum Fix: Equatable, Sendable {
        case download(URL)
        case openScreenRecordingSettings
        case showMenuBarIcon
        case openMenuBarSettings
        case registerHotkeys
        case openKeyboardShortcuts
        case openLoginItems
    }

    public var id: String
    public var state: State
    public var text: String
    public var fix: Fix?
    public var fixTitle: String?

    public init(id: String, state: State, text: String, fix: Fix? = nil, fixTitle: String? = nil) {
        self.id = id
        self.state = state
        self.text = text
        self.fix = fix
        self.fixTitle = fixTitle
    }
}

public enum SetupCheck {
    public static func lines(_ facts: SetupFacts) -> [SetupLine] {
        let app = facts.appName
        var lines: [SetupLine] = [versionLine(facts)]
        lines.append(facts.canRecordScreen
            ? SetupLine(id: "screen", state: .ok, text: "\(app) may record the screen, so it can take screenshots.")
            : SetupLine(id: "screen", state: .problem,
                        text: "macOS doesn't let \(app) record the screen yet. Screenshots need this permission: turn on \(app) under Privacy & Security › Screen & System Audio Recording.",
                        fix: .openScreenRecordingSettings, fixTitle: "Open System Settings"))
        if facts.menuBarIconSwitchedOff {
            lines.append(SetupLine(id: "icon", state: .problem,
                                   text: "The menu bar icon is switched off in Settings › General. Its menu is the way to most of \(app).",
                                   fix: .showMenuBarIcon, fixTitle: "Show It"))
        } else if facts.menuBarIconVisible == false {
            lines.append(SetupLine(id: "icon", state: .problem,
                                   text: "macOS hides the \(app) icon, behind the notch or in the menu bar settings. ⌘-drag it further right, or allow it in System Settings › Menu Bar.",
                                   fix: .openMenuBarSettings, fixTitle: "Open Menu Bar Settings"))
        } else {
            lines.append(SetupLine(id: "icon", state: .ok, text: "The \(app) icon is shown in the menu bar."))
        }
        if !facts.refusedHotkeys.isEmpty {
            lines.append(SetupLine(id: "hotkeys", state: .problem,
                                   text: "macOS refused these hotkeys, another app may use them: \(facts.refusedHotkeys.joined(separator: ", ")).",
                                   fix: .registerHotkeys, fixTitle: "Register Again"))
        } else if facts.hotkeyCount > 0 {
            lines.append(SetupLine(id: "hotkeys", state: .ok,
                                   text: facts.hotkeyCount == 1 ? "Your hotkey works." : "Your \(facts.hotkeyCount) hotkeys work."))
        }
        if facts.systemShortcutConflicts.isEmpty {
            if facts.hotkeyCount > 0 {
                lines.append(SetupLine(id: "system", state: .ok, text: "The screenshot shortcuts of macOS don't use your hotkeys."))
            }
        } else {
            lines.append(SetupLine(id: "system", state: .problem,
                                   text: "macOS uses \(facts.systemShortcutConflicts.joined(separator: ", ")) for its own screenshots and gets the keys first. Turn them off under Keyboard Shortcuts › Screenshots, or choose other hotkeys.",
                                   fix: .openKeyboardShortcuts, fixTitle: "Open Keyboard Shortcuts"))
        }
        if facts.loginItem == .needsApproval {
            lines.append(SetupLine(id: "login", state: .problem,
                                   text: "\(app) should open at login, but macOS waits for you to allow it under Login Items & Extensions.",
                                   fix: .openLoginItems, fixTitle: "Open Login Items"))
        }
        return lines
    }

    private static func versionLine(_ facts: SetupFacts) -> SetupLine {
        let app = facts.appName
        switch facts.version {
        case .checking:
            return SetupLine(id: "version", state: .pending, text: "\(app) is checking for a newer version…")
        case .checked(.failed):
            return SetupLine(id: "version", state: .pending, text: "\(app) couldn't check for a newer version right now.")
        case .checked(.upToDate):
            return SetupLine(id: "version", state: .ok, text: "You have the latest version of \(app), \(facts.currentVersion).")
        case .checked(.newer(let release)):
            return SetupLine(id: "version", state: .problem,
                             text: "\(app) \(release.version) is available, you have \(facts.currentVersion).",
                             fix: .download(release.pageURL), fixTitle: "Download It")
        }
    }

    /// The number shown next to the section (upstream `UpdateBadge`).
    public static func problemCount(_ lines: [SetupLine]) -> Int {
        lines.filter { $0.state == .problem }.count
    }
}
