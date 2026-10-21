// Greenshot for Mac (Community) - an unofficial macOS port of Greenshot
// Copyright (C) 2026 Greenshot for Mac (Community) contributors
// Based on Greenshot, Copyright (C) 2007-2026 Thomas Braun, Jens Klingen, Robin Krom
// SPDX-License-Identifier: GPL-3.0-or-later

import Foundation

/// What the app knows about itself and the Mac, gathered by the app (`SystemInfo`) and turned into text here, so the
/// texts are tested with fixed values. Upstream `Greenshot.Base/Core/EnvironmentInfo.cs` and the System section of
/// the Self-Service window (`SystemInfoSectionViewModel.cs`).
public struct EnvironmentSnapshot: Equatable, Sendable {
    public struct Screen: Equatable, Sendable {
        public var name: String
        /// Size in points.
        public var width: Int
        public var height: Int
        public var scale: Double
        public var refreshRate: Int
        /// The extended dynamic range headroom now and at most (1 = SDR only).
        public var edrNow: Double
        public var edrPotential: Double
        public var colorSpace: String
        public var isMain: Bool

        public init(name: String, width: Int, height: Int, scale: Double, refreshRate: Int = 0, edrNow: Double = 1,
                    edrPotential: Double = 1, colorSpace: String = "", isMain: Bool = false) {
            self.name = name
            self.width = width
            self.height = height
            self.scale = scale
            self.refreshRate = refreshRate
            self.edrNow = edrNow
            self.edrPotential = edrPotential
            self.colorSpace = colorSpace
            self.isMain = isMain
        }
    }

    public var appName: String
    public var version: String
    public var build: String
    /// "Apple silicon" or "Intel".
    public var architecture: String
    /// An Intel build running on Apple silicon (Rosetta).
    public var translated = false
    /// "Version 27.0 (Build 27A100)", from `ProcessInfo.operatingSystemVersionString`.
    public var osVersion: String
    /// "Mac15,3" (`hw.model`).
    public var model = ""
    /// "Apple M3" (`machdep.cpu.brand_string`).
    public var chip = ""
    public var physicalMemory: UInt64 = 0
    /// Memory of the app as Activity Monitor shows it (`phys_footprint`), and the most it used (`ru_maxrss`).
    public var appMemory: UInt64?
    public var peakMemory: UInt64?
    public var threads: Int?
    public var launched: Date?
    public var now: Date
    public var timeZone: TimeZone = .current
    public var locale = ""
    /// "nominal", "fair", "serious", "critical".
    public var thermalState = ""
    public var lowPowerMode = false
    public var screens: [Screen] = []

    public init(appName: String, version: String, build: String, architecture: String, osVersion: String, now: Date) {
        self.appName = appName
        self.version = version
        self.build = build
        self.architecture = architecture
        self.osVersion = osVersion
        self.now = now
    }
}

/// The texts of the diagnostics: the environment (upstream `EnvironmentToString`), the report of an error (upstream
/// `BuildReport`), the settings that differ from the defaults with everything personal left out.
public enum DiagnosticReport {
    /// "Software version: ...", "Time: ...", "OS: ...", "Hardware: ...", "Screens: ...", "Locale: ...", one per line or
    /// separated by ", " (the first entry of the log).
    public static func environmentText(_ snapshot: EnvironmentSnapshot, newline: Bool) -> String {
        var lines: [String] = []
        let translated = snapshot.translated ? " under Rosetta" : ""
        lines.append("Software version: \(snapshot.appName) \(snapshot.version) (build \(snapshot.build), \(snapshot.architecture)\(translated))")
        lines.append("Time: \(time(snapshot.now, in: snapshot.timeZone))")
        lines.append("OS: macOS \(snapshot.osVersion)")
        let hardware = [snapshot.model, snapshot.chip, snapshot.physicalMemory > 0 ? "\(byteCount(snapshot.physicalMemory)) memory" : ""]
            .filter { !$0.isEmpty }
        if !hardware.isEmpty { lines.append("Hardware: " + hardware.joined(separator: ", ")) }
        if !snapshot.screens.isEmpty {
            lines.append("Screens: " + snapshot.screens.map(screenText).joined(separator: "; "))
        }
        if !snapshot.locale.isEmpty { lines.append("Locale: \(snapshot.locale)") }
        return lines.joined(separator: newline ? "\n" : ", ")
    }

    /// One screen: "Built-in Retina Display 1512x982 pt @2x, 120 Hz, HDR (EDR 1.0 of 16.0), main".
    public static func screenText(_ screen: EnvironmentSnapshot.Screen) -> String {
        var parts = ["\(screen.name) \(screen.width)x\(screen.height) pt @\(number(screen.scale))x"]
        if screen.refreshRate > 0 { parts.append("\(screen.refreshRate) Hz") }
        if screen.edrPotential > 1 {
            parts.append("HDR (EDR \(String(format: "%.1f", screen.edrNow)) of \(String(format: "%.1f", screen.edrPotential)))")
        }
        if !screen.colorSpace.isEmpty { parts.append(screen.colorSpace) }
        if screen.isMain { parts.append("main") }
        return parts.joined(separator: ", ")
    }

    /// The memory and process lines of Self-Service › System and of "Copy System Info".
    public static func processText(_ snapshot: EnvironmentSnapshot) -> [String] {
        var lines: [String] = []
        if let memory = snapshot.appMemory {
            let peak = snapshot.peakMemory.map { " (peak \(byteCount($0)))" } ?? ""
            lines.append("App memory: \(byteCount(memory))\(peak)")
        }
        if snapshot.physicalMemory > 0 { lines.append("Physical memory: \(byteCount(snapshot.physicalMemory))") }
        if let threads = snapshot.threads { lines.append("Threads: \(threads)") }
        if let launched = snapshot.launched {
            lines.append("Running for: \(duration(snapshot.now.timeIntervalSince(launched)))")
        }
        if !snapshot.thermalState.isEmpty { lines.append("Thermal state: \(snapshot.thermalState)") }
        lines.append("Low Power Mode: \(snapshot.lowPowerMode ? "on" : "off")")
        return lines
    }

    /// "Copy System Info" (upstream `SystemInfoSectionViewModel.EnvironmentReport`).
    public static func systemReport(_ snapshot: EnvironmentSnapshot) -> String {
        """
        === \(snapshot.appName) System Diagnostics ===
        \(environmentText(snapshot, newline: true))

        === Memory and Process ===
        \(processText(snapshot).joined(separator: "\n"))
        """
    }

    /// The report of an error (upstream `EnvironmentInfo.BuildReport`): the environment, the error with its stack, and
    /// the settings that differ from the defaults.
    public static func bugReport(environment: EnvironmentSnapshot, crash: CrashDetails, settings: AppSettings,
                                 home: String = NSHomeDirectory()) -> String {
        var text = environmentText(environment, newline: true) + "\n\n"
        text += crash.reportText(home: home) + "\n\n"
        let dump = settingsDump(settings)
        text += "Configuration dump (settings that differ from the defaults):\n"
        text += dump.isEmpty ? "(none)" : dump.joined(separator: "\n")
        return text + "\n"
    }

    // MARK: Settings

    /// Key paths whose values can be personal or secret: shown as `<set>`.
    static let hiddenKeyParts = ["key", "secret", "token", "password", "email", "url", "user", "account", "clientid",
                                 "folder", "file", "path", "host", "title", "subject"]
    static let hiddenKeys: Set<String> = ["to", "cc", "bcc"]
    /// The settings whose text is one of a few values (an enum's raw value, a language code), by their last key (array
    /// indices left out): the only text that is shown as it is. The text of any other key, e.g. the search pattern of
    /// the text obfuscation or the space name of a recent Confluence page, can be a name and is shown as its length.
    static let shownTextKeys: Set<String> = [
        "arrowHeads", "clipboardContent", "clipboardFormats", "cutMarkStyle", "cutOutMarkStyle", "destinations",
        "doubleClickAction", "effect", "fixedCaptureAnchor", "format", "highlightMode", "horizontalAlignment",
        "leftClickAction", "login", "notificationLevel", "obfuscateMode", "ocrLanguage", "outlookEmailFormat",
        "outputFormat", "pageSize", "powerpointSlideLayout", "scaling", "scope", "screenCaptureMode", "theme", "unit",
        "uploadFormat", "verticalAlignment",
    ]

    /// The settings that differ from the defaults, one `key.path = value` per line, sorted. Numbers and switches are
    /// shown; the words of `shownTextKeys` like "jpg" or "showMenu" too; any other text only as its length, and the
    /// text of keys that can hold a name, an address, a path or a secret only as `<set>`. The keys of dictionaries (the
    /// path of a recipe file, the id of a custom recipe) are the user's data too: numbered `<key 1>`, `<key 2>` ... in
    /// their sorted order. Keychain values are never in the settings.
    public static func settingsDump(_ settings: AppSettings) -> [String] {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.sortedKeys]
        guard let current = try? encoder.encode(settings), let defaults = try? encoder.encode(AppSettings()),
              let currentObject = try? JSONSerialization.jsonObject(with: current),
              let defaultObject = try? JSONSerialization.jsonObject(with: defaults) else { return [] }
        let dictionaries = dictionaryPaths(in: settings)
        var currentLeaves: [String: Leaf] = [:]
        var defaultLeaves: [String: Leaf] = [:]
        flatten(currentObject, path: "", shownPath: "", dictionaries: dictionaries, into: &currentLeaves)
        flatten(defaultObject, path: "", shownPath: "", dictionaries: dictionaries, into: &defaultLeaves)
        return currentLeaves.keys.sorted().compactMap { path in
            guard let leaf = currentLeaves[path] else { return nil }
            if let original = defaultLeaves[path], isEqual(leaf.value, original.value) { return nil }
            return "\(leaf.shownPath) = \(describe(leaf.value, path: path, shownPath: leaf.shownPath))"
        }
    }

    /// A value of the settings and its key path as the dump shows it, with the keys of dictionaries numbered.
    private struct Leaf {
        var value: Any
        var shownPath: String
    }

    private static func flatten(_ object: Any, path: String, shownPath: String, dictionaries: Set<String>,
                                into leaves: inout [String: Leaf]) {
        func joined(_ base: String, _ key: String) -> String { base.isEmpty ? key : "\(base).\(key)" }
        if let dictionary = object as? [String: Any] {
            if dictionary.isEmpty { leaves[path] = Leaf(value: "{}", shownPath: shownPath) }
            let numbered = dictionaries.contains(path)
            for (number, entry) in dictionary.sorted(by: { $0.key < $1.key }).enumerated() {
                flatten(entry.value, path: joined(path, entry.key),
                        shownPath: joined(shownPath, numbered ? "<key \(number + 1)>" : entry.key),
                        dictionaries: dictionaries, into: &leaves)
            }
        } else if let array = object as? [Any] {
            if array.isEmpty { leaves[path] = Leaf(value: "[]", shownPath: shownPath) }
            for (index, value) in array.enumerated() {
                flatten(value, path: "\(path)[\(index)]", shownPath: "\(shownPath)[\(index)]",
                        dictionaries: dictionaries, into: &leaves)
            }
        } else {
            leaves[path] = Leaf(value: object, shownPath: shownPath)
        }
    }

    /// The key paths of the dictionaries in `value` (`recipes.unloadedRecipes`, `editorStyles`), as the JSON of the
    /// settings has them. Their keys are data, not names of settings; in JSON a dictionary looks like any other object,
    /// so they are found by reflection, and a new dictionary setting is covered without a list to keep up to date.
    static func dictionaryPaths(in value: Any, path: String = "") -> Set<String> {
        let mirror = Mirror(reflecting: value)
        func joined(_ key: String) -> String { path.isEmpty ? key : "\(path).\(key)" }
        switch mirror.displayStyle {
        case .dictionary:
            var paths: Set<String> = [path]
            for entry in mirror.children {
                // An entry is a (key, value) pair.
                let pair = Array(Mirror(reflecting: entry.value).children)
                guard pair.count == 2 else { continue }
                paths.formUnion(dictionaryPaths(in: pair[1].value, path: joined("\(pair[0].value)")))
            }
            return paths
        case .optional:
            return mirror.children.first.map { dictionaryPaths(in: $0.value, path: path) } ?? []
        case .collection:
            var paths: Set<String> = []
            for (index, element) in mirror.children.enumerated() {
                paths.formUnion(dictionaryPaths(in: element.value, path: "\(path)[\(index)]"))
            }
            return paths
        case .struct:
            var paths: Set<String> = []
            for child in mirror.children {
                guard let label = child.label else { continue }
                paths.formUnion(dictionaryPaths(in: child.value, path: joined(label)))
            }
            return paths
        default:
            return []
        }
    }

    private static func isEqual(_ a: Any, _ b: Any) -> Bool {
        if let a = a as? NSObject, let b = b as? NSObject { return a.isEqual(b) }
        return false
    }

    /// `path` has the keys of dictionaries as they are, so a key like "upload.apiToken" still hides its value; the name
    /// of the setting comes from `shownPath`, so a dictionary key is never taken for one of `shownTextKeys`.
    private static func describe(_ value: Any, path: String, shownPath: String) -> String {
        let lowered = path.lowercased()
        let key = shownPath.split(separator: ".").last.map { String($0.split(separator: "[").first ?? "") } ?? shownPath
        let lastKey = key.lowercased()
        if let string = value as? String {
            if string == "{}" || string == "[]" { return string }
            if hiddenKeys.contains(lastKey) || hiddenKeyParts.contains(where: lowered.contains) {
                return string.isEmpty ? "\"\"" : "<set>"
            }
            if string.isEmpty { return "\"\"" }
            return shownTextKeys.contains(key) && isWord(string) ? "\"\(string)\"" : "<text, \(string.count) characters>"
        }
        if value is NSNull { return "null" }
        if let number = value as? NSNumber {
            if CFGetTypeID(number) == CFBooleanGetTypeID() { return number.boolValue ? "true" : "false" }
            return number.stringValue
        }
        return "<value>"
    }

    /// An enum raw value or a short word: a letter, then letters, digits, "_", "-" or ".", up to 32 characters.
    static func isWord(_ text: String) -> Bool {
        guard let first = text.unicodeScalars.first, text.count <= 32, CharacterSet.letters.contains(first),
              text.unicodeScalars.allSatisfy({ $0.isASCII }) else { return false }
        let allowed = CharacterSet.alphanumerics.union(CharacterSet(charactersIn: "_-."))
        return text.unicodeScalars.allSatisfy(allowed.contains)
    }

    // MARK: Formatting

    /// The home folder written as "~", so reports don't carry the user's name. Only the whole path is replaced: with
    /// home /Users/alex, "/Users/alexandra/x" and "/Volumes/Backup/Users/alex" stay as they are.
    public static func abbreviatingHome(_ text: String, home: String = NSHomeDirectory()) -> String {
        var home = home
        while home.count > 1, home.hasSuffix("/") { home.removeLast() }
        guard !home.isEmpty, home != "/" else { return text }
        // Not inside a longer name before it; after it not a name going on ("alex-old", "alex.backup"), though a full
        // stop that ends a sentence is no name.
        let pattern = #"(?<![\w.-])"# + NSRegularExpression.escapedPattern(for: home) + #"(?![\w-]|\.[\w-])"#
        return text.replacingOccurrences(of: pattern, with: "~", options: .regularExpression)
    }

    /// 1536 bytes as "1.5 KB", 3 GB as "3.0 GB" (upstream `FormatBytes`).
    public static func byteCount(_ bytes: UInt64) -> String {
        let value = Double(bytes)
        if bytes >= 1 << 30 { return String(format: "%.1f GB", value / Double(1 << 30)) }
        if bytes >= 1 << 20 { return String(format: "%.1f MB", value / Double(1 << 20)) }
        if bytes >= 1 << 10 { return String(format: "%.1f KB", value / Double(1 << 10)) }
        return "\(bytes) B"
    }

    /// "2d 03h 04m 05s" (upstream's uptime).
    public static func duration(_ seconds: TimeInterval) -> String {
        let total = max(0, Int(seconds))
        let days = total / 86_400
        let hours = total / 3_600 % 24
        let minutes = total / 60 % 60
        return String(format: "%dd %02dh %02dm %02ds", days, hours, minutes, total % 60)
    }

    /// "2026-10-17 12:00:00 +0800" (upstream `yyyy-MM-dd HH:mm:ss zzz`).
    public static func time(_ date: Date, in timeZone: TimeZone = .current) -> String {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.timeZone = timeZone
        formatter.dateFormat = "yyyy-MM-dd HH:mm:ss Z"
        return formatter.string(from: date)
    }

    private static func number(_ value: Double) -> String {
        value == value.rounded() ? String(Int(value)) : String(format: "%.2g", value)
    }
}
