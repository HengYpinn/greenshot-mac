// Greenshot for Mac (Community) - an unofficial macOS port of Greenshot
// Copyright (C) 2026 Greenshot for Mac (Community) contributors
// Based on Greenshot, Copyright (C) 2007-2026 Thomas Braun, Jens Klingen, Robin Krom
// SPDX-License-Identifier: GPL-3.0-or-later

import Foundation

/// The tabs of Settings, numbered like the window's tabs, found by upstream's names for them
/// (`Greenshot/Settings/Views/SettingsWindow.xaml.cs` `SelectTab`, used by `greenshot://settings?tab=`).
public enum SettingsPane: Int, CaseIterable, Sendable {
    case general, capture, output, destinations, editor, printer, expert

    /// Upstream's tab names and their aliases, any case; nil for a name without a tab here (plugins, recipes).
    public init?(name: String) {
        switch name.trimmingCharacters(in: .whitespacesAndNewlines).lowercased() {
        case "general": self = .general
        case "capture": self = .capture
        case "output": self = .output
        case "destination", "destinations": self = .destinations
        case "editor": self = .editor
        case "printer", "print": self = .printer
        case "expert", "expertsettings": self = .expert
        default: return nil
        }
    }
}

/// What the app was started with: the Mac's stand-in for upstream's `--ini-directory` (`GreenshotCommandLine.cs`),
/// a folder for the settings file instead of the user defaults.
public struct AppLaunchOptions: Equatable, Sendable {
    public static let settingsDirectoryArgument = "--settings-dir"
    public static let settingsDirectoryVariable = "GREENSHOT_MAC_SETTINGS_DIR"
    public static let settingsFileName = "settings.json"

    public var settingsDirectory: URL?

    public init(settingsDirectory: URL? = nil) {
        self.settingsDirectory = settingsDirectory
    }

    /// `--settings-dir <folder>` or `--settings-dir=<folder>`; else the environment variable. `~` is expanded, a
    /// relative path is taken from the current folder.
    public static func parse(arguments: [String], environment: [String: String]) -> AppLaunchOptions {
        var path: String?
        for (index, argument) in arguments.enumerated() {
            if argument == settingsDirectoryArgument, index + 1 < arguments.count {
                path = arguments[index + 1]
            } else if argument.hasPrefix(settingsDirectoryArgument + "=") {
                path = String(argument.dropFirst(settingsDirectoryArgument.count + 1))
            }
        }
        if path?.isEmpty ?? true { path = environment[settingsDirectoryVariable] }
        guard let path, !path.isEmpty else { return AppLaunchOptions() }
        let expanded = (path as NSString).expandingTildeInPath
        return AppLaunchOptions(settingsDirectory: URL(fileURLWithPath: expanded, isDirectory: true).standardizedFileURL)
    }

    /// The settings file in the settings folder, if one was given.
    public var settingsFile: URL? {
        settingsDirectory?.appendingPathComponent(Self.settingsFileName)
    }
}

extension SettingsStorage {
    /// The settings from a JSON file; the defaults when the file is missing or broken (single values fall back like
    /// they do from the user defaults). A file that isn't JSON at all is renamed to `<name>.bad` first, so the next save
    /// doesn't overwrite what the user wrote; `movedAside` then names it.
    public static func load(fromFile url: URL, movedAside: ((URL) -> Void)? = nil) -> AppSettings {
        guard let data = try? Data(contentsOf: url) else { return AppSettings() }
        if let settings = try? JSONDecoder().decode(AppSettings.self, from: data) { return settings }
        let aside = url.appendingPathExtension("bad")
        try? FileManager.default.removeItem(at: aside)
        if (try? FileManager.default.moveItem(at: url, to: aside)) != nil { movedAside?(aside) }
        return AppSettings()
    }

    /// Writes the settings as readable JSON, creating the folder when needed.
    public static func save(_ settings: AppSettings, toFile url: URL) throws {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        let data = try encoder.encode(settings)
        try FileManager.default.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
        try data.write(to: url, options: .atomic)
    }
}
