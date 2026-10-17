// Greenshot for Mac (Community) - an unofficial macOS port of Greenshot
// Copyright (C) 2026 Greenshot for Mac (Community) contributors
// Based on Greenshot, Copyright (C) 2007-2026 Thomas Braun, Jens Klingen, Robin Krom
// SPDX-License-Identifier: GPL-3.0-or-later
// Owned by L10N-INFRA after the wave 5 prep.

import AppKit
import GreenshotCore

/// The language of the app's texts, decided before the first text is looked up (upstream `--language`, `Language`,
/// `GreenshotApplication.cs` and `Texts.Load`; docs/translations.md). macOS picks the localization of a process once,
/// at its first lookup, so a chosen language is applied by setting `AppleLanguages` in the argument domain first, and a
/// later change needs a relaunch (`AppRelaunch`).
@MainActor
enum LanguageStartup {
    /// What this start uses (`LanguageChoice.decide`).
    private(set) static var choice = LanguageChoice(pack: nil, source: .macOS)
    /// What macOS alone would choose from the app's languages (System Settings › General › Language & Region ›
    /// Applications, else the preferred languages), for "Same as macOS (…)"; nil when the app has no translations (a
    /// development build without `scripts/l10n/stage-dev.sh`).
    private(set) static var macOSChoice: LanguagePack?
    /// The `.lproj` folders the app has.
    private(set) static var shipped: [String] = []
    /// The `language` setting this start began with (upstream's code, "" for macOS's choice; a --language value kept
    /// in the settings counts): Settings offers a relaunch only after it changed.
    private(set) static var startSetting = ""
    private static let log = Log("Language")

    /// The language in use: the localization macOS loaded, English when there is none.
    static var current: LanguagePack {
        Bundle.main.preferredLocalizations.first.flatMap(LanguagePacks.pack(lproj:)) ?? LanguagePacks.english
    }

    /// main.swift, first line: reads --language, the stored `language` and the profile, and sets the argument domain.
    /// Must run before anything looks up a text or asks for `Bundle.main.preferredLocalizations`; nothing here may look
    /// up a localized text (the settings' defaults are data, never localized).
    static func apply(arguments: [String] = CommandLine.arguments) {
        let options = IPCCommandLine.scanStartup(Array(arguments.dropFirst()))
        let launch = AppLaunchOptions.parse(arguments: arguments, environment: ProcessInfo.processInfo.environment)
        let policy = ManagedPolicy(source: UserDefaultsManagedSource(.standard))
        let setting = storedLanguage(file: launch.settingsFile, policy: policy)
        choice = LanguageChoice.decide(commandLine: options.language, setting: setting,
                                       lockedByProfile: policy.isLocked("language"), snapshot: options.snapshot)
        // The snapshots use settings of their own, without a language.
        startSetting = options.snapshot ? "" : (choice.saveToSettings ?? LanguagePacks.resolve(setting)?.ietf ?? "")
        shipped = shippedLocalizations()
        var domain = UserDefaults.standard.volatileDomain(forName: UserDefaults.argumentDomain)
        // A developer's `-AppleLanguages (de)` wins over the setting (not over --language or a profile).
        let developerLanguages = domain["AppleLanguages"] != nil && choice.source == .setting
        let preferences = UserDefaults.standard.stringArray(forKey: "AppleLanguages") ?? Locale.preferredLanguages
        macOSChoice = shipped.isEmpty ? nil
            : Bundle.preferredLocalizations(from: shipped, forPreferences: preferences).first.flatMap(LanguagePacks.pack(lproj:))
        let override = developerLanguages ? nil : choice.pack
        let effective = override.flatMap { shipped.contains($0.lproj) ? $0 : nil } ?? macOSChoice
        for (key, value) in LanguageChoice.argumentDomainValues(override: override, effective: effective) {
            // Text direction given on the command line (pseudo right to left for testing) stays.
            if key != "AppleLanguages", domain[key] != nil { continue }
            domain[key] = value
        }
        UserDefaults.standard.setVolatileDomain(domain, forName: UserDefaults.argumentDomain)
    }

    /// AppDelegate, after `startLogging()`: keeps the --language value in the settings (upstream "and save the
    /// configuration") and logs the choice.
    static func saveCommandLineChoice(into store: SettingsStore) {
        for problem in choice.problems { log.warn(problem) }
        log.info("Texts in \(current.ietf) (\(choice.source.rawValue)); the app has \(shipped.count) languages")
        guard let value = choice.saveToSettings, !store.isLocked(\.language), store.value.language != value else { return }
        store.update { $0.language = value }
    }

    /// The `language` setting in effect, read without side effects: `SettingsStore` reads (and may move aside) the
    /// settings only later.
    private static func storedLanguage(file: URL?, policy: ManagedPolicy) -> String {
        let read: (settings: AppSettings, json: Data?)?
        do {
            read = try file.map(SettingsStorage.reload(fromFile:)) ?? SettingsStorage.reload(from: .standard)
        } catch {
            read = nil
        }
        let stored = read.map { policy.loaded($0.settings, storedJSON: $0.json) } ?? policy.loaded(AppSettings(), storedJSON: nil)
        return policy.effective(stored).language
    }

    /// The localizations in Contents/Resources (or next to a development build, `scripts/l10n/stage-dev.sh`).
    private static func shippedLocalizations() -> [String] {
        guard let resources = Bundle.main.resourceURL else { return [] }
        return LanguagePacks.all.map(\.lproj).filter {
            FileManager.default.fileExists(atPath: resources.appendingPathComponent("\($0).lproj").path)
        }
    }
}
