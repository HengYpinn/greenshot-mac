// Greenshot for Mac (Community) - an unofficial macOS port of Greenshot
// Copyright (C) 2026 Greenshot for Mac (Community) contributors
// Based on Greenshot, Copyright (C) 2007-2026 Thomas Braun, Jens Klingen, Robin Krom
// SPDX-License-Identifier: GPL-3.0-or-later

import Foundation

/// Why the settings could not be read again; the settings in use stay as they are.
public struct SettingsReloadError: Error, Equatable, CustomStringConvertible {
    public let description: String

    public init(_ description: String) {
        self.description = description
    }
}

extension SettingsStorage {
    /// The settings read again from the file of `--settings-dir`, for `greenshot-cli --reload` (upstream's RELOAD
    /// command), with the JSON as read (for the managed defaults). Unlike at the start (`load(fromFile:movedAside:)`), a
    /// file that can't be read or isn't valid JSON is left where it is (the user is probably still editing it) and the
    /// error says what is wrong. A missing file gives the defaults, like at the start.
    public static func reload(fromFile url: URL) throws -> (settings: AppSettings, json: Data?) {
        guard FileManager.default.fileExists(atPath: url.path) else { return (AppSettings(), nil) }
        let data: Data
        do {
            data = try Data(contentsOf: url)
        } catch {
            throw SettingsReloadError("\(url.lastPathComponent) could not be read: \(reason(of: error))")
        }
        do {
            return (try JSONDecoder().decode(AppSettings.self, from: data), data)
        } catch {
            throw SettingsReloadError("\(url.lastPathComponent) is not valid settings JSON: \(reason(of: error))")
        }
    }

    /// The settings read again from the user defaults, like `reload(fromFile:)`: none stored gives the defaults,
    /// stored settings that can't be decoded are an error.
    public static func reload(from defaults: UserDefaults) throws -> (settings: AppSettings, json: Data?) {
        guard let stored = defaults.object(forKey: key) else { return (AppSettings(), nil) }
        guard let data = stored as? Data else {
            throw SettingsReloadError("The settings in the user defaults (\(key)) are not settings data")
        }
        do {
            return (try JSONDecoder().decode(AppSettings.self, from: data), data)
        } catch {
            throw SettingsReloadError("The settings in the user defaults (\(key)) are not valid settings JSON: \(reason(of: error))")
        }
    }

    /// What the parser says, e.g. "Unexpected character 'x' around line 3, column 5.", rather than only "not valid JSON".
    private static func reason(of error: Error) -> String {
        if case DecodingError.dataCorrupted(let context) = error {
            if let underlying = context.underlyingError as NSError?,
               let detail = underlying.userInfo["NSDebugDescription"] as? String, !detail.isEmpty {
                return detail
            }
            return context.debugDescription
        }
        if case DecodingError.typeMismatch(_, let context) = error { return context.debugDescription }
        return error.localizedDescription
    }
}
