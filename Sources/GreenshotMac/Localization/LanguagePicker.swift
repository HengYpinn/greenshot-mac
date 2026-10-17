// Greenshot for Mac (Community) - an unofficial macOS port of Greenshot
// Copyright (C) 2026 Greenshot for Mac (Community) contributors
// Based on Greenshot, Copyright (C) 2007-2026 Thomas Braun, Jens Klingen, Robin Krom
// SPDX-License-Identifier: GPL-3.0-or-later

import AppKit
import GreenshotCore
import SwiftUI

/// The choice of the app's language (upstream `SettingsViewModel.SupportedLanguages`/`SelectedLanguage` and
/// `LanguageWindow`): "Same as macOS" or one of the packs by its name. The setting takes effect after a relaunch.
@MainActor
enum LanguageOptions {
    /// The pack the setting asks for: the setting's, else macOS's choice, else (a build without translations) the one
    /// in use.
    static func wanted(_ setting: String) -> LanguagePack {
        LanguagePacks.resolve(setting) ?? LanguageStartup.macOSChoice ?? LanguageStartup.current
    }

    /// The setting changed since the start and asks for another language than the one in use: a relaunch shows it.
    static func needsRelaunch(_ setting: String) -> Bool {
        let code = LanguagePacks.resolve(setting)?.ietf ?? ""
        return code != LanguageStartup.startSetting && wanted(setting).lproj != LanguageStartup.current.lproj
    }

    /// The picker's value of the setting: upstream's code, "" for macOS's choice.
    static func selection(store: SettingsStore, changed: @escaping () -> Void = {}) -> Binding<String> {
        Binding(get: { LanguagePacks.resolve(store.value.language)?.ietf ?? "" },
                set: { newValue in
                    guard newValue != (LanguagePacks.resolve(store.value.language)?.ietf ?? "") else { return }
                    store.update { $0.language = newValue }
                    changed()
                })
    }

    /// The name of macOS's choice, for "Same as macOS (…)".
    static var macOSName: String {
        (LanguageStartup.macOSChoice ?? LanguagePacks.english).description
    }

    /// Asks whether to relaunch now, after the language changed in Settings.
    static func askToRelaunch(store: SettingsStore) {
        guard needsRelaunch(store.value.language) else { return }
        let alert = NSAlert()
        let name = wanted(store.value.language).description
        alert.messageText = String(localized: "Relaunch \(AppInfo.name) in \(name)?")
        alert.informativeText = String(localized: "The new language shows after a relaunch. Unsaved screenshots are asked about first.")
        alert.addButton(withTitle: String(localized: "Relaunch Now"))
        alert.addButton(withTitle: String(localized: "Later"))
        if alert.runModal() == .alertFirstButtonReturn { AppRelaunch.relaunch() }
    }
}

/// The Language row of Settings › General (upstream SettingsWindow.xaml `settings_language`).
struct LanguagePicker: View {
    @ObservedObject var store: SettingsStore

    var body: some View {
        Picker("Language", selection: LanguageOptions.selection(store: store) { [store] in
            // After SwiftUI finished the change, like the other confirmations of Settings.
            DispatchQueue.main.async { LanguageOptions.askToRelaunch(store: store) }
        }) {
            Text("Same as macOS (\(LanguageOptions.macOSName))").tag("")
            Divider()
            ForEach(LanguagePacks.byName, id: \.ietf) { pack in
                Text(verbatim: pack.description).tag(pack.ietf)
            }
        }
        .help("The language of Greenshot's texts. Texts that Greenshot for Windows has no translation of stay English.")
        .managed(\.language)
        if LanguageOptions.needsRelaunch(store.value.language) {
            HStack {
                Text("The new language shows after a relaunch.").font(.caption).foregroundStyle(.secondary)
                Spacer()
                Button("Relaunch Now") { AppRelaunch.relaunch() }
            }
        }
    }
}

/// The language row on the first page of the welcome at the first start (upstream `LanguageWindow`, shown when
/// `Language` is empty): a relaunch shows the welcome again in the new language.
struct WelcomeLanguageRow: View {
    @ObservedObject var store: SettingsStore
    let onRelaunch: () -> Void

    var body: some View {
        HStack(spacing: 10) {
            Label("Language", systemImage: "globe")
            Picker("Language", selection: LanguageOptions.selection(store: store)) {
                Text("Same as macOS (\(LanguageOptions.macOSName))").tag("")
                Divider()
                ForEach(LanguagePacks.byName, id: \.ietf) { pack in
                    Text(verbatim: pack.description).tag(pack.ietf)
                }
            }
            .labelsHidden()
            .frame(width: 240)
            if LanguageOptions.needsRelaunch(store.value.language) {
                Button("Relaunch in \(LanguageOptions.wanted(store.value.language).description)") { onRelaunch() }
            }
            Spacer(minLength: 0)
        }
    }
}
