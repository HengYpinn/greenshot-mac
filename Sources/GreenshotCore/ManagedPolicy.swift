// Greenshot for Mac (Community) - an unofficial macOS port of Greenshot
// Copyright (C) 2026 Greenshot for Mac (Community) contributors
// Based on Greenshot, Copyright (C) 2007-2026 Thomas Braun, Jens Klingen, Robin Krom
// SPDX-License-Identifier: GPL-3.0-or-later

import Foundation

// Settings an administrator sets with a configuration profile: the Mac's greenshot-fixed.ini and greenshot-defaults.ini
// (upstream `GreenshotMain.cs` `AddConstantsFile`, `AddDefaultsFile`; Dapplo.Ini's `IsConstant`). A setting is addressed by
// its name in the settings JSON with the prefix "Greenshot.": `Greenshot.outputFormat`, `Greenshot.jira.url`, or a group
// as a dictionary, `Greenshot.printing = {footer = true}`, which sets the members given and no others.

/// Where managed values come from: the app's user defaults (configuration profiles, /Library/Preferences), or in tests
/// and snapshots a dictionary (`ManagedValues`).
public protocol ManagedValueSource {
    /// The keys starting with `prefix` the source can list. A profile's keys may be missing here; every known setting
    /// name is asked for with `value(forKey:)` as well.
    func keys(withPrefix prefix: String) -> [String]
    func value(forKey key: String) -> Any?
    /// True when a configuration profile forces the key (`UserDefaults.objectIsForced(forKey:)`).
    func isForced(forKey key: String) -> Bool
}

/// The app's user defaults: values a configuration profile forces (in /Library/Managed Preferences) are locked, the
/// others (/Library/Preferences/<bundle id>.plist, `defaults write`) are defaults.
public struct UserDefaultsManagedSource: ManagedValueSource {
    private let defaults: UserDefaults

    public init(_ defaults: UserDefaults) {
        self.defaults = defaults
    }

    public func keys(withPrefix prefix: String) -> [String] {
        defaults.dictionaryRepresentation().keys.filter { $0.hasPrefix(prefix) }
    }

    public func value(forKey key: String) -> Any? {
        defaults.object(forKey: key)
    }

    public func isForced(forKey key: String) -> Bool {
        defaults.objectIsForced(forKey: key)
    }
}

/// Managed values from dictionaries, as a profile would give them: for the tests and the snapshots (there is no MDM
/// there).
public struct ManagedValues: ManagedValueSource {
    public var forced: [String: Any]
    public var unforced: [String: Any]

    public init(forced: [String: Any] = [:], unforced: [String: Any] = [:]) {
        self.forced = forced
        self.unforced = unforced
    }

    public func keys(withPrefix prefix: String) -> [String] {
        (Array(forced.keys) + Array(unforced.keys)).filter { $0.hasPrefix(prefix) }
    }

    public func value(forKey key: String) -> Any? {
        forced[key] ?? unforced[key]
    }

    public func isForced(forKey key: String) -> Bool {
        forced[key] != nil
    }
}

/// What an administrator set: the locked values (a profile forces them), the defaults, and what was ignored.
///
/// The settings keep two values (`SettingsStore`): what the user stored, and what is in effect, `effective(_:)`. Locked
/// values are put over the stored ones on every load and change and are never saved, so the user's own values come back
/// when the profile is removed. Defaults fill in what the stored settings don't have yet (a first start, a setting added
/// by an update), like upstream's greenshot-defaults.ini; after that they are the user's.
public struct ManagedPolicy: Equatable, Sendable {
    /// Every managed key starts with it.
    public static let keyPrefix = "Greenshot."
    /// A dictionary of default values, the profile's greenshot-defaults.ini.
    public static let defaultsKey = "Greenshot.defaults"
    /// The tooltip of a locked control.
    public static let lockedHelp = "Set by your organisation"

    /// The locked values that passed the check, by setting path ("outputFormat", "printing.footer"), as JSON text.
    public private(set) var forced: [String: String] = [:]
    /// The defaults that passed the check, the same way.
    public private(set) var defaults: [String: String] = [:]
    /// The managed values that were ignored, each with why (names only, never the values).
    public private(set) var problems: [String] = []

    /// Nothing managed.
    public init() {}

    /// Reads and checks every managed value of `source`.
    public init(source: ManagedValueSource) {
        let prefix = Self.keyPrefix
        var keys = Set(source.keys(withPrefix: prefix))
        keys.formUnion(ManagedSettingKeys.names.map { prefix + $0 })
        keys.insert(Self.defaultsKey)
        var forcedLeaves: [(String, Any)] = []
        var defaultLeaves: [(String, Any)] = []
        var defaultsDictionaryLeaves: [(String, Any)] = []
        // Sorted, so a dotted key ("Greenshot.printing.footer") comes after its group's dictionary and wins.
        for key in keys.sorted() {
            guard let raw = source.value(forKey: key) else { continue }
            if key == Self.defaultsKey {
                guard let dictionary = raw as? [String: Any] else {
                    problems.append("defaults: not a dictionary")
                    continue
                }
                for name in dictionary.keys.sorted() {
                    Self.leaves(name, dictionary[name] as Any, into: &defaultsDictionaryLeaves)
                }
                continue
            }
            let name = String(key.dropFirst(prefix.count))
            if source.isForced(forKey: key) {
                Self.leaves(name, raw, into: &forcedLeaves)
            } else {
                Self.leaves(name, raw, into: &defaultLeaves)
            }
        }
        // Plain keys that aren't forced win over the profile's defaults dictionary.
        for (path, value) in defaultsDictionaryLeaves + defaultLeaves {
            switch Self.check(path, value) {
            case .success(let json): defaults[path] = json
            case .failure(let problem): problems.append("defaults.\(path): \(problem.text)")
            }
        }
        for (path, value) in forcedLeaves {
            switch Self.check(path, value) {
            case .success(let json): forced[path] = json
            case .failure(let problem): problems.append("\(path): \(problem.text)")
            }
        }
        let unknown = effective(loaded(AppSettings(), storedJSON: nil)).unknownExcludedDestinationNames
        if !unknown.isEmpty {
            problems.append("excludeDestinations: unknown \(unknown.joined(separator: ", "))")
        }
    }

    public var isEmpty: Bool { forced.isEmpty && defaults.isEmpty && problems.isEmpty }

    /// Whether the setting at `path` (or a member of it, or the group it belongs to) is locked.
    public func isLocked(_ path: String) -> Bool {
        forced.keys.contains { locked in
            locked == path || locked.hasPrefix(path + ".") || path.hasPrefix(locked + ".")
        }
    }

    /// Whether the setting at `keyPath` is locked; false for a key path `ManagedSettingKeys` doesn't know.
    public func isLocked(_ keyPath: AnyKeyPath) -> Bool {
        guard !forced.isEmpty, let name = ManagedSettingKeys.name(for: keyPath) else { return false }
        return isLocked(name)
    }

    /// For the log: which settings are locked and which have defaults, by name.
    public var summary: String {
        var parts: [String] = []
        if !forced.isEmpty { parts.append("locked: " + forced.keys.sorted().joined(separator: ", ")) }
        if !defaults.isEmpty { parts.append("defaults: " + defaults.keys.sorted().joined(separator: ", ")) }
        return parts.isEmpty ? "none" : parts.joined(separator: "; ")
    }

    // MARK: Applying

    /// The settings read from storage with the defaults filled in where `storedJSON` (what was read) has no value.
    public func loaded(_ settings: AppSettings, storedJSON: Data?) -> AppSettings {
        guard !defaults.isEmpty else { return settings }
        let stored = storedJSON.flatMap { try? JSONSerialization.jsonObject(with: $0) as? [String: Any] } ?? [:]
        guard var object = SettingsJSON.object(settings) else { return settings }
        var filled = false
        for (path, json) in defaults where SettingsJSON.value(at: path, in: stored) == nil {
            SettingsJSON.set(SettingsJSON.parse(json), at: path, in: &object)
            filled = true
        }
        return filled ? (SettingsJSON.settings(object) ?? settings) : settings
    }

    /// The settings in effect: `stored` with the locked values, without excluded destinations.
    public func effective(_ stored: AppSettings) -> AppSettings {
        var result = stored
        if !forced.isEmpty, var object = SettingsJSON.object(stored) {
            for (path, json) in forced {
                SettingsJSON.set(SettingsJSON.parse(json), at: path, in: &object)
            }
            result = SettingsJSON.settings(object) ?? stored
        }
        result.removeExcludedDestinations()
        return result
    }

    /// What to store after the settings in effect, `previous`, were changed to `changed`: the stored settings with the
    /// values that changed, except the locked ones. A value that only differs because the policy put it there (a locked
    /// value, a destination it removed) keeps what the user stored.
    public func stored(afterEditing changed: AppSettings, effective previous: AppSettings, stored: AppSettings) -> AppSettings {
        if forced.isEmpty && previous == stored { return changed }
        guard let new = SettingsJSON.object(changed), let old = SettingsJSON.object(previous),
              var result = SettingsJSON.object(stored) else { return stored }
        for path in SettingsJSON.leafPaths(new, old) where !isLocked(path) {
            let newValue = SettingsJSON.value(at: path, in: new)
            if SettingsJSON.text(newValue) != SettingsJSON.text(SettingsJSON.value(at: path, in: old)) {
                SettingsJSON.set(newValue, at: path, in: &result)
            }
        }
        return SettingsJSON.settings(result) ?? stored
    }

    // MARK: Checking

    struct Problem: Error {
        let text: String
    }

    /// Splits a managed value into settings: a dictionary for a group into its members, anything else is one value.
    private static func leaves(_ path: String, _ value: Any, into result: inout [(String, Any)]) {
        if ManagedSettingKeys.isGroup(path), let dictionary = value as? [String: Any] {
            for member in dictionary.keys.sorted() {
                leaves(path + "." + member, dictionary[member] as Any, into: &result)
            }
        } else {
            result.append((path, value))
        }
    }

    /// The value as JSON text if the settings take it: it is put into the default settings, decoded with their tolerant
    /// decoders and encoded again, and must come out the same. A text is also tried as a switch ("true"), a number and a
    /// comma-separated list; an empty text clears an optional setting, like a hotkey.
    static func check(_ path: String, _ value: Any) -> Result<String, Problem> {
        guard ManagedSettingKeys.contains(path) else { return .failure(Problem(text: "not a setting")) }
        guard let json = SettingsJSON.compatible(value) else {
            return .failure(Problem(text: "a date or data can't be a setting"))
        }
        for candidate in candidates(json) {
            guard var object = SettingsJSON.defaultObject else { break }
            SettingsJSON.set(candidate, at: path, in: &object)
            guard let decoded = SettingsJSON.settings(object), let encoded = SettingsJSON.object(decoded) else { continue }
            let result = SettingsJSON.value(at: path, in: encoded)
            let resultText = SettingsJSON.text(result)
            if let text = SettingsJSON.text(candidate), text == resultText { return .success(text) }
            if (candidate as? String)?.isEmpty == true, result == nil || result is NSNull,
               let null = SettingsJSON.text(NSNull()) {
                return .success(null)
            }
        }
        return .failure(Problem(text: "a value of the wrong type"))
    }

    /// The value, then for a text the other readings of it.
    private static func candidates(_ json: Any) -> [Any] {
        guard let text = json as? String else { return [json] }
        var result: [Any] = [json]
        let trimmed = text.trimmingCharacters(in: .whitespaces)
        switch trimmed.lowercased() {
        case "true", "yes": result.append(true)
        case "false", "no": result.append(false)
        default: break
        }
        if let number = Int(trimmed) { result.append(number) }
        if let number = Double(trimmed) { result.append(number) }
        let items = trimmed.split(separator: ",").map { $0.trimmingCharacters(in: .whitespaces) }.filter { !$0.isEmpty }
        if !trimmed.isEmpty { result.append(items) }
        return result
    }
}

/// The settings as a JSON object, to put managed values in by name and decode them with the settings' own decoders.
enum SettingsJSON {
    static func object(_ settings: AppSettings) -> [String: Any]? {
        guard let data = try? JSONEncoder().encode(settings) else { return nil }
        return (try? JSONSerialization.jsonObject(with: data)) as? [String: Any]
    }

    static func settings(_ object: [String: Any]) -> AppSettings? {
        guard let data = try? JSONSerialization.data(withJSONObject: object) else { return nil }
        return try? JSONDecoder().decode(AppSettings.self, from: data)
    }

    /// The default settings, the base of every check.
    static let defaultObject: [String: Any]? = object(AppSettings())

    static func value(at path: String, in object: [String: Any]) -> Any? {
        let parts = path.split(separator: ".").map(String.init)
        var current: Any? = object
        for part in parts {
            guard let dictionary = current as? [String: Any] else { return nil }
            current = dictionary[part]
        }
        return current
    }

    /// Puts `value` at `path`, making the dictionaries on the way; nil removes it.
    static func set(_ value: Any?, at path: String, in object: inout [String: Any]) {
        let parts = path.split(separator: ".").map(String.init)
        set(value, at: parts[...], in: &object)
    }

    private static func set(_ value: Any?, at parts: ArraySlice<String>, in object: inout [String: Any]) {
        guard let first = parts.first else { return }
        if parts.count == 1 {
            object[first] = value
            return
        }
        var child = object[first] as? [String: Any] ?? [:]
        set(value, at: parts.dropFirst(), in: &child)
        object[first] = child
    }

    /// The JSON text of a value, the same for equal values (keys sorted); nil for none.
    static func text(_ value: Any?) -> String? {
        guard let value, let data = try? JSONSerialization.data(withJSONObject: [value], options: [.sortedKeys]) else {
            return nil
        }
        return String(data: data, encoding: .utf8)
    }

    /// The value of `text()`.
    static func parse(_ text: String) -> Any? {
        guard let data = text.data(using: .utf8), let array = (try? JSONSerialization.jsonObject(with: data)) as? [Any] else {
            return nil
        }
        return array.first
    }

    /// A property list value as JSON: texts, numbers, switches, lists and dictionaries; nil for dates and data.
    static func compatible(_ value: Any) -> Any? {
        switch value {
        case let text as String: return text
        case let number as NSNumber: return number
        case let list as [Any]:
            var result: [Any] = []
            for item in list {
                guard let converted = compatible(item) else { return nil }
                result.append(converted)
            }
            return result
        case let dictionary as [String: Any]:
            var result: [String: Any] = [:]
            for (key, item) in dictionary {
                guard let converted = compatible(item) else { return nil }
                result[key] = converted
            }
            return result
        default: return nil
        }
    }

    /// The paths of the single settings in two settings objects: each top-level setting, and each member of a group.
    static func leafPaths(_ a: [String: Any], _ b: [String: Any]) -> [String] {
        var result: [String] = []
        for key in Set(a.keys).union(b.keys).sorted() {
            if ManagedSettingKeys.isGroup(key) {
                let membersA = (a[key] as? [String: Any]).map { Array($0.keys) } ?? []
                let membersB = (b[key] as? [String: Any]).map { Array($0.keys) } ?? []
                result += Set(membersA + membersB).sorted().map { key + "." + $0 }
            } else {
                result.append(key)
            }
        }
        return result
    }
}
