// Greenshot for Mac (Community) - an unofficial macOS port of Greenshot
// Copyright (C) 2026 Greenshot for Mac (Community) contributors
// Based on Greenshot, Copyright (C) 2007-2026 Thomas Braun, Jens Klingen, Robin Krom
// SPDX-License-Identifier: GPL-3.0-or-later

import AppKit
import GreenshotCore
import SwiftUI

/// "Your setup": port of upstream `SetupSectionViewModel.cs`, the same checks in the Self-Service window and in step 3
/// of the welcome. The version is read once; the rest every time the window comes to the front (the user may come back
/// from System Settings).
@MainActor
final class SetupModel: ObservableObject {
    @Published private(set) var facts: SetupFacts
    @Published private(set) var lines: [SetupLine]
    @Published private(set) var loginOn: Bool
    @Published private(set) var loginError: String?
    /// The first welcome: "Open at login" starts on and is applied when the welcome closes (like the "start with
    /// Windows" option of Greenshot's installer, ticked by default). Nil: the switch changes the login item at once.
    private(set) var pendingLogin: Bool?
    private weak var app: AppDelegate?
    private let live: Bool
    private var versionRequested = false
    private let log = Log("Setup")

    init(app: AppDelegate, firstWelcome: Bool = false) {
        self.app = app
        live = true
        facts = SetupFacts(appName: AppInfo.name, currentVersion: UpdateChecker.currentVersion)
        lines = []
        loginOn = LaunchAtLogin.state != .off
        if firstWelcome, LaunchAtLogin.state == .off { pendingLogin = true }
        refresh()
    }

    /// Fixed facts (snapshots).
    init(sample: SetupFacts, loginOn: Bool) {
        live = false
        facts = sample
        lines = SetupCheck.lines(sample)
        self.loginOn = loginOn
    }

    var problemCount: Int { SetupCheck.problemCount(lines) }

    func refresh() {
        guard live, let app else { return }
        let settings = app.settings.value
        var facts = SetupFacts(appName: AppInfo.name, currentVersion: UpdateChecker.currentVersion)
        facts.version = self.facts.version
        facts.canRecordScreen = CGPreflightScreenCaptureAccess()
        facts.menuBarIconSwitchedOff = settings.hideMenuBarIcon
        facts.menuBarIconVisible = app.statusItemOnScreen
        let combos = HotkeyStatus.slots(settings.hotkeys).compactMap(\.combo)
        facts.hotkeyCount = combos.count
        if let registration = HotkeyDiagnostics.lastRegistration {
            facts.refusedHotkeys = registration.refused.filter(registration.combos.indices.contains).map { index in
                "\(registration.names[index]) (\(BidiText.isolatedLTR(registration.combos[index].displayString)))"
            }
        }
        let system = SystemShortcuts.read()
        facts.systemShortcutConflicts = SystemScreenshotShortcut.conflicts(system, with: combos).map {
            "\(BidiText.isolatedLTR($0.combo.displayString)) (\u{201C}\($0.name)\u{201D})"
        }
        switch LaunchAtLogin.state {
        case .on: facts.loginItem = .on
        case .off: facts.loginItem = .off
        case .needsApproval: facts.loginItem = .needsApproval
        }
        self.facts = facts
        lines = SetupCheck.lines(facts)
        loginOn = pendingLogin ?? (LaunchAtLogin.state != .off)
        if !versionRequested {
            versionRequested = true
            Task { @MainActor [weak self] in
                let outcome = await UpdateChecker.fetchLatest(unstable: settings.checkForUnstable)
                guard let self else { return }
                self.facts.version = .checked(outcome)
                self.lines = SetupCheck.lines(self.facts)
            }
        }
    }

    func perform(_ fix: SetupLine.Fix) {
        switch fix {
        case .download(let url):
            NSWorkspace.shared.open(url)
        case .openScreenRecordingSettings:
            NSWorkspace.shared.open(Permissions.screenCaptureSettingsURL)
        case .showMenuBarIcon:
            app?.settings.update { $0.hideMenuBarIcon = false }
        case .openMenuBarSettings:
            SystemSettings.open("com.apple.ControlCenter-Settings.extension")
        case .registerHotkeys:
            app?.reregisterHotkeys()
        case .openKeyboardShortcuts:
            SystemSettings.open("com.apple.Keyboard-Settings.extension")
        case .openLoginItems:
            LaunchAtLogin.openSystemSettings()
        }
        log.info("Setup fix: \(fix)")
        refresh()
    }

    func setLogin(_ on: Bool) {
        if pendingLogin != nil {
            pendingLogin = on
            loginOn = on
            return
        }
        let message = LaunchAtLogin.set(on)
        refresh()
        loginError = LaunchAtLogin.state == .needsApproval ? nil : message
    }

    /// Applies the choice of the first welcome, when it closes.
    func applyPendingLogin() {
        guard let pending = pendingLogin else { return }
        pendingLogin = nil
        guard pending else { return }
        if let problem = LaunchAtLogin.set(true) {
            ErrorPresenter.show(message: String(localized: "\(AppInfo.name) doesn't open at login yet"), detail: problem)
        }
    }
}

/// Opens a pane of System Settings, or System Settings when the pane isn't there (they move between macOS versions).
enum SystemSettings {
    @MainActor
    static func open(_ pane: String) {
        if let url = URL(string: "x-apple.systempreferences:\(pane)"), NSWorkspace.shared.open(url) { return }
        NSWorkspace.shared.open(URL(fileURLWithPath: "/System/Applications/System Settings.app"))
    }
}

/// The lines of "Your setup", each with ✓, ⚠ or a clock, and its button.
struct SetupChecksView: View {
    @ObservedObject var model: SetupModel

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            ForEach(model.lines) { line in
                HStack(alignment: .top, spacing: 10) {
                    icon(line.state).frame(width: 18)
                    Text(line.text).fixedSize(horizontal: false, vertical: true)
                        .frame(maxWidth: .infinity, alignment: .leading)
                    if let fix = line.fix, let title = line.fixTitle {
                        Button(title) { model.perform(fix) }
                    }
                }
            }
        }
    }

    @ViewBuilder private func icon(_ state: SetupLine.State) -> some View {
        switch state {
        case .ok: Image(systemName: "checkmark.circle.fill").foregroundStyle(.green)
        case .problem: Image(systemName: "exclamationmark.triangle.fill").foregroundStyle(.orange)
        case .pending: Image(systemName: "clock").foregroundStyle(.secondary)
        }
    }
}

/// The login switch below the checks (upstream "Launch Greenshot on startup").
struct LoginSwitch: View {
    @ObservedObject var model: SetupModel

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            Toggle("Open \(AppInfo.name) at login", isOn: Binding(get: { model.loginOn }, set: { model.setLogin($0) }))
            if let error = model.loginError {
                Text(error).font(.caption).foregroundStyle(.red)
            }
            if !LaunchAtLogin.isInApplicationsFolder {
                Text("Tip: move the app to your Applications folder first, so it keeps opening at login.")
                    .font(.caption).foregroundStyle(.secondary)
            }
        }
    }
}

struct SetupSectionView: View {
    @ObservedObject var model: SetupModel

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            SectionCard(title: String(localized: "Checks", comment: "The checks of the setup (a noun)")) {
                SetupChecksView(model: model)
            }
            SectionCard(title: String(localized: "Startup", comment: "Opening the app at login")) {
                LoginSwitch(model: model)
                Text("Then the hotkeys work right after you log in.").font(.caption).foregroundStyle(.secondary)
            }
        }
    }
}
