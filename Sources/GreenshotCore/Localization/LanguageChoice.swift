// Greenshot for Mac (Community) - an unofficial macOS port of Greenshot
// Copyright (C) 2026 Greenshot for Mac (Community) contributors
// Based on Greenshot, Copyright (C) 2007-2026 Thomas Braun, Jens Klingen, Robin Krom
// SPDX-License-Identifier: GPL-3.0-or-later

import Foundation

/// The language of the app's texts at the start (upstream `Texts.Load` with `ICoreConfiguration.Language` and
/// `GreenshotApplication`'s `--language`): a profile's locked value, else `--language`, else the `language` setting,
/// else macOS's choice (System Settings › General › Language & Region › Applications, else the preferred languages).
/// The app applies it by setting `AppleLanguages` in the argument domain before the first text is looked up.
public struct LanguageChoice: Equatable, Sendable {
    public enum Source: String, Equatable, Sendable {
        /// An administrator's configuration profile locks `language`.
        case managed
        /// `--language <code>` of this start.
        case commandLine
        /// The `language` setting.
        case setting
        /// Nothing chosen: macOS decides.
        case macOS
        /// `--snapshot` without `--language`: English, so the snapshots don't depend on the machine.
        case snapshot
    }

    /// The language to use; nil: as macOS chooses.
    public var pack: LanguagePack?
    public var source: Source
    /// The `--language` value to keep in the settings (upstream "and save the configuration"); "" for `system`.
    public var saveToSettings: String?
    /// What was ignored, for the log (English).
    public var problems: [String]

    public init(pack: LanguagePack?, source: Source, saveToSettings: String? = nil, problems: [String] = []) {
        self.pack = pack
        self.source = source
        self.saveToSettings = saveToSettings
        self.problems = problems
    }

    /// The choice for `--language` (`commandLine`, nil when not given), the `language` setting in effect (`setting`,
    /// with a profile's value) and whether a profile locks it.
    public static func decide(commandLine: String?, setting: String, lockedByProfile: Bool, snapshot: Bool) -> LanguageChoice {
        var problems: [String] = []
        let requested = commandLine?.trimmingCharacters(in: .whitespacesAndNewlines)
        let requestedPack = requested.flatMap(LanguagePacks.resolve)
        let requestsSystem = requested.map { $0.isEmpty || $0.lowercased() == LanguagePacks.systemCode } ?? false
        if let requested, requestedPack == nil, !requestsSystem {
            problems.append("--language \(requested) is ignored: no language pack has that code")
        }
        if snapshot {
            return LanguageChoice(pack: requestedPack ?? LanguagePacks.english, source: requestedPack == nil ? .snapshot : .commandLine,
                                  problems: problems)
        }
        if lockedByProfile {
            if requested != nil { problems.append("--language is ignored: the language is set by a configuration profile") }
            return fromSetting(setting, source: .managed, problems: problems)
        }
        if let requestedPack {
            return LanguageChoice(pack: requestedPack, source: .commandLine, saveToSettings: requestedPack.ietf, problems: problems)
        }
        if requestsSystem {
            return LanguageChoice(pack: nil, source: .macOS, saveToSettings: "", problems: problems)
        }
        return fromSetting(setting, source: .setting, problems: problems)
    }

    private static func fromSetting(_ setting: String, source: Source, problems: [String]) -> LanguageChoice {
        var problems = problems
        let trimmed = setting.trimmingCharacters(in: .whitespacesAndNewlines)
        if trimmed.isEmpty || trimmed.lowercased() == LanguagePacks.systemCode {
            return LanguageChoice(pack: nil, source: source == .managed ? .managed : .macOS, problems: problems)
        }
        guard let pack = LanguagePacks.resolve(trimmed) else {
            problems.append("The language setting \(trimmed) is ignored: no language pack has that code")
            return LanguageChoice(pack: nil, source: .macOS, problems: problems)
        }
        return LanguageChoice(pack: pack, source: source, problems: problems)
    }

    /// The argument-domain defaults that apply a choice: `AppleLanguages` for a chosen language (`override`), and
    /// `AppleTextDirection` when the language in use (`effective`, also macOS's own choice) is right to left — without
    /// it AppKit stays left to right even in an Arabic localization. (Not `NSForceRightToLeftWritingDirection`: that
    /// makes numbers and other left-to-right text right to left too, "621 × 941" turns into "941 × 621".)
    public static func argumentDomainValues(override: LanguagePack?, effective: LanguagePack?) -> [String: Any] {
        var values: [String: Any] = [:]
        if let override { values["AppleLanguages"] = [override.lproj] }
        if effective?.rightToLeft == true { values["AppleTextDirection"] = true }
        return values
    }
}
