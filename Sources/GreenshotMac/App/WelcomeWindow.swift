// Greenshot for Mac (Community) - an unofficial macOS port of Greenshot
// Copyright (C) 2026 Greenshot for Mac (Community) contributors
// Based on Greenshot, Copyright (C) 2007-2026 Thomas Braun, Jens Klingen, Robin Krom
// SPDX-License-Identifier: GPL-3.0-or-later

import AppKit
import GreenshotCore
import SwiftUI

/// The welcome window: port of upstream `Greenshot/Views/WelcomeWindow.xaml(.cs)` (docs/welcome-window.md). A thank
/// you, the basics with the user's own hotkeys, the setup checks with their fixes, and a tip. Shown once at the start
/// (`welcomeShown`), and from Help › Welcome Guide. Upstream's step about old Imgur uploads has no Mac counterpart.
@MainActor
final class WelcomeModel: ObservableObject {
    enum Step: Int, CaseIterable {
        case welcome, basics, setup, done
    }

    @Published private(set) var step = Step.welcome
    @Published private(set) var tipIndex: Int
    let tips: [String]
    let basics: [WelcomeContent.Basic]
    let setup: SetupModel
    var openSettings: () -> Void = {}
    var close: () -> Void = {}
    /// The settings for the first page's language row (L10N-INFRA, APP-043); nil: no row.
    var languageStore: SettingsStore?
    /// The language row's "Relaunch in …": the welcome comes back after the relaunch, in the new language.
    var relaunchForLanguage: () -> Void = {}

    init(basics: [WelcomeContent.Basic], setup: SetupModel, tips: [String], tipIndex: Int? = nil) {
        self.basics = basics
        self.setup = setup
        self.tips = tips
        // A random tip when the window opens.
        self.tipIndex = tipIndex ?? Int.random(in: 0..<max(1, tips.count))
    }

    var tip: String { WelcomeContent.tip(tips, at: tipIndex) }
    var isLast: Bool { step == Step.allCases.last }

    func show(_ newStep: Step) {
        step = newStep
        if newStep == .setup { setup.refresh() }
    }

    func next() {
        if isLast {
            close()
        } else if let following = Step(rawValue: step.rawValue + 1) {
            show(following)
        }
    }

    func back() {
        if let previous = Step(rawValue: step.rawValue - 1) { show(previous) }
    }

    func anotherTip() {
        tipIndex += 1
    }
}

struct WelcomeView: View {
    @ObservedObject var model: WelcomeModel
    private let app = AppInfo.name

    var body: some View {
        VStack(spacing: 16) {
            HStack(spacing: 14) {
                Image(nsImage: NSApp.applicationIconImage ?? NSImage()).resizable().frame(width: 64, height: 64)
                VStack(alignment: .leading, spacing: 4) {
                    Text(WelcomeContent.title(app)).font(.title.weight(.semibold))
                    Text(WelcomeContent.thanks(app)).foregroundStyle(.secondary).fixedSize(horizontal: false, vertical: true)
                }
                Spacer(minLength: 0)
            }
            ZStack(alignment: .topLeading) {
                RoundedRectangle(cornerRadius: 10).fill(Color(nsColor: .controlBackgroundColor))
                RoundedRectangle(cornerRadius: 10).stroke(Color(nsColor: .separatorColor))
                ScrollView {
                    stepView.padding(18).frame(maxWidth: .infinity, alignment: .leading)
                }
            }
            .frame(height: 330)
            HStack {
                HStack(spacing: 7) {
                    ForEach(WelcomeModel.Step.allCases, id: \.rawValue) { step in
                        Circle().fill(step == model.step ? Color.accentColor : Color(nsColor: .tertiaryLabelColor))
                            .frame(width: 8, height: 8)
                    }
                }
                Spacer()
                if model.step != .welcome {
                    Button("Back") { model.back() }
                }
                Button(model.isLast ? "Let's Go!" : "Next") { model.next() }
                    .keyboardShortcut(.defaultAction)
            }
        }
        .padding(22)
        .frame(width: 620)
    }

    @ViewBuilder private var stepView: some View {
        switch model.step {
        case .welcome:
            VStack(alignment: .leading, spacing: 12) {
                Text(WelcomeContent.intro(app)).font(.title3).fixedSize(horizontal: false, vertical: true)
                Text("Press Next to begin, or Esc to close this window at any time.").foregroundStyle(.secondary)
                if let store = model.languageStore {
                    Divider()
                    WelcomeLanguageRow(store: store) { model.relaunchForLanguage() }
                }
            }
        case .basics:
            VStack(alignment: .leading, spacing: 12) {
                Text(WelcomeContent.basicsTitle).font(.title3.weight(.semibold))
                if model.basics.isEmpty {
                    Text(WelcomeContent.noHotkeys)
                }
                ForEach(model.basics, id: \.keys) { basic in
                    HStack(spacing: 12) {
                        Text(basic.keys).font(.system(.body, design: .monospaced).weight(.semibold))
                            .padding(.horizontal, 8).padding(.vertical, 3)
                            .background(RoundedRectangle(cornerRadius: 5).fill(Color(nsColor: .quaternaryLabelColor).opacity(0.4)))
                            .frame(width: 110, alignment: .leading)
                        Text(basic.text)
                    }
                }
                Text(WelcomeContent.basicsMenu(app)).fixedSize(horizontal: false, vertical: true)
                Text(WelcomeContent.basicsAfter).foregroundStyle(.secondary).fixedSize(horizontal: false, vertical: true)
            }
        case .setup:
            VStack(alignment: .leading, spacing: 12) {
                Text(WelcomeContent.setupTitle).font(.title3.weight(.semibold))
                Text(WelcomeContent.setupSubtitle(app)).foregroundStyle(.secondary)
                SetupChecksView(model: model.setup)
                Divider()
                LoginSwitch(model: model.setup)
            }
        case .done:
            VStack(alignment: .leading, spacing: 12) {
                Text(WelcomeContent.doneTitle).font(.title3.weight(.semibold))
                Text(WelcomeContent.done(app)).fixedSize(horizontal: false, vertical: true)
                Button("Open Settings") { model.openSettings() }
                VStack(alignment: .leading, spacing: 6) {
                    Label(WelcomeContent.tipTitle, systemImage: "lightbulb").font(.headline)
                    Text(model.tip).fixedSize(horizontal: false, vertical: true)
                    HStack {
                        Spacer()
                        Button("Another Tip") { model.anotherTip() }
                    }
                }
                .padding(12)
                .background(RoundedRectangle(cornerRadius: 8).fill(Color.accentColor.opacity(0.08)))
            }
        }
    }
}

@MainActor
final class WelcomeWindowController: DiagnosticsWindowController {
    let model: WelcomeModel
    private static var current: WelcomeWindowController?
    private static let log = Log("Welcome")

    init(model: WelcomeModel) {
        self.model = model
        super.init(title: WelcomeContent.title(AppInfo.name), content: WelcomeView(model: model),
                   size: NSSize(width: 620, height: 520), resizable: false)
        model.close = { [weak self] in self?.close() }
    }

    required init?(coder: NSCoder) {
        fatalError("not used")
    }

    /// Shows the welcome, or brings it to the front when it's open already (upstream `ShowWelcome`). On the first
    /// launch "Open at login" starts ticked and is applied when the window closes.
    static func show(app: AppDelegate, firstLaunch: Bool) {
        if let current, current.isOpen {
            current.present()
            return
        }
        let setup = SetupModel(app: app, firstWelcome: firstLaunch)
        let tips = WelcomeContent.tips(appName: AppInfo.name, showsCaptures: NotificationService.showsCaptures)
        let model = WelcomeModel(basics: WelcomeContent.basics(app.settings.value.hotkeys), setup: setup, tips: tips)
        model.openSettings = { [weak app] in app?.showSettings(nil) }
        // Upstream shows its language window at the first start while `Language` is empty (GreenshotShell.cs:225-230).
        let settings = app.settings
        if firstLaunch, settings.value.language.isEmpty, !settings.isLocked(\.language), LanguagePacks.all.count > 1 {
            model.languageStore = settings
            model.relaunchForLanguage = {
                settings.update { $0.welcomeShown = false }
                AppRelaunch.relaunch()
            }
        }
        let controller = WelcomeWindowController(model: model)
        current = controller
        log.info(firstLaunch ? "Showing the welcome at the first start" : "Showing the welcome")
        controller.present()
    }

    /// Back from System Settings: the checks again (upstream `OnActivated`).
    override func didBecomeKey() {
        if model.step == .setup { model.setup.refresh() }
    }

    override func didClose() {
        model.setup.applyPendingLogin()
        if Self.current === self { Self.current = nil }
    }
}
