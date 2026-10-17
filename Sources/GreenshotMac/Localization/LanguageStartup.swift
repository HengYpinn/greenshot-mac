// Greenshot for Mac (Community) - an unofficial macOS port of Greenshot
// Copyright (C) 2026 Greenshot for Mac (Community) contributors
// Based on Greenshot, Copyright (C) 2007-2026 Thomas Braun, Jens Klingen, Robin Krom
// SPDX-License-Identifier: GPL-3.0-or-later
// Owned by L10N-INFRA after the wave 5 prep.

import AppKit
import GreenshotCore

/// The language of the app's texts, decided before the first text is looked up (upstream `--language`, `Language`).
/// Filled in by the L10N-INFRA package.
@MainActor
enum LanguageStartup {
    /// main.swift, first line: reads --language, the stored `language` and the profile, and sets the argument domain.
    /// Must run before anything looks up a text or asks for `Bundle.main.preferredLocalizations`.
    static func apply(arguments: [String] = CommandLine.arguments) {}

    /// AppDelegate, after `startLogging()`: keeps the --language value in the settings (upstream "and save the
    /// configuration").
    static func saveCommandLineChoice(into store: SettingsStore) {}
}
