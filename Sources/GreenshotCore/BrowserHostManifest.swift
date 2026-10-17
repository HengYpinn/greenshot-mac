// Greenshot for Mac (Community) - an unofficial macOS port of Greenshot
// Copyright (C) 2026 Greenshot for Mac (Community) contributors
// Based on Greenshot, Copyright (C) 2007-2026 Thomas Braun, Jens Klingen, Robin Krom
// SPDX-License-Identifier: GPL-3.0-or-later

import Foundation

/// A browser the native messaging host can be registered for. Chromium browsers read `allowed_origins`, Firefox
/// `allowed_extensions` (upstream: `org.greenshot.proxy.json` and `org.greenshot.proxy-firefox.json`, registered by the
/// installer's `browser-extension.iss`; on the Mac the manifest is a file in the browser's own folder).
public struct BrowserTarget: Equatable, Sendable, Identifiable {
    public enum Family: String, Sendable {
        case chromium, firefox
    }

    /// A short name for logs and tests ("chrome", "edge-beta", "firefox").
    public var id: String
    public var name: String
    public var family: Family
    /// The browser's folder in `~/Library/Application Support`.
    public var supportFolder: String
    /// Its apps (any channel that shares the folder).
    public var bundleIdentifiers: [String]

    public init(id: String, name: String, family: Family, supportFolder: String, bundleIdentifiers: [String]) {
        self.id = id
        self.name = name
        self.family = family
        self.supportFolder = supportFolder
        self.bundleIdentifiers = bundleIdentifiers
    }

    public func supportURL(home: URL) -> URL {
        home.appendingPathComponent("Library/Application Support", isDirectory: true)
            .appendingPathComponent(supportFolder, isDirectory: true)
    }

    /// `~/Library/Application Support/<browser>/NativeMessagingHosts/io.github.greenshot_mac.host.json`.
    public func manifestURL(home: URL) -> URL {
        supportURL(home: home).appendingPathComponent("NativeMessagingHosts", isDirectory: true)
            .appendingPathComponent(BrowserHostManifest.fileName)
    }
}

/// The native messaging host manifests: what they contain, where they go, and what is installed.
public enum BrowserHostManifest {
    /// The host's name (only lower-case letters, digits, `_` and `.` are allowed; background.js connects to it).
    public static let hostName = "io.github.greenshot_mac.host"
    public static let fileName = hostName + ".json"
    public static let hostDescription = "Greenshot for Mac (Community): imports captures of its browser extension"
    /// The host's executable in the app bundle.
    public static let executableName = "greenshot-native-host"

    /// The browsers whose folders are documented (Chrome, Edge and their channels, Chromium, Brave, Vivaldi; Firefox's
    /// folder serves every Firefox channel).
    public static let browsers: [BrowserTarget] = [
        BrowserTarget(id: "chrome", name: "Google Chrome", family: .chromium, supportFolder: "Google/Chrome",
                      bundleIdentifiers: ["com.google.Chrome"]),
        BrowserTarget(id: "chrome-beta", name: "Google Chrome Beta", family: .chromium, supportFolder: "Google/Chrome Beta",
                      bundleIdentifiers: ["com.google.Chrome.beta"]),
        BrowserTarget(id: "chrome-dev", name: "Google Chrome Dev", family: .chromium, supportFolder: "Google/Chrome Dev",
                      bundleIdentifiers: ["com.google.Chrome.dev"]),
        BrowserTarget(id: "chrome-canary", name: "Google Chrome Canary", family: .chromium, supportFolder: "Google/Chrome Canary",
                      bundleIdentifiers: ["com.google.Chrome.canary"]),
        BrowserTarget(id: "edge", name: "Microsoft Edge", family: .chromium, supportFolder: "Microsoft Edge",
                      bundleIdentifiers: ["com.microsoft.edgemac"]),
        BrowserTarget(id: "edge-beta", name: "Microsoft Edge Beta", family: .chromium, supportFolder: "Microsoft Edge Beta",
                      bundleIdentifiers: ["com.microsoft.edgemac.Beta"]),
        BrowserTarget(id: "edge-dev", name: "Microsoft Edge Dev", family: .chromium, supportFolder: "Microsoft Edge Dev",
                      bundleIdentifiers: ["com.microsoft.edgemac.Dev"]),
        BrowserTarget(id: "edge-canary", name: "Microsoft Edge Canary", family: .chromium, supportFolder: "Microsoft Edge Canary",
                      bundleIdentifiers: ["com.microsoft.edgemac.Canary"]),
        BrowserTarget(id: "chromium", name: "Chromium", family: .chromium, supportFolder: "Chromium",
                      bundleIdentifiers: ["org.chromium.Chromium"]),
        BrowserTarget(id: "brave", name: "Brave", family: .chromium, supportFolder: "BraveSoftware/Brave-Browser",
                      bundleIdentifiers: ["com.brave.Browser"]),
        BrowserTarget(id: "vivaldi", name: "Vivaldi", family: .chromium, supportFolder: "Vivaldi",
                      bundleIdentifiers: ["com.vivaldi.Vivaldi"]),
        BrowserTarget(id: "firefox", name: "Firefox", family: .firefox, supportFolder: "Mozilla",
                      bundleIdentifiers: ["org.mozilla.firefox", "org.mozilla.firefoxdeveloperedition", "org.mozilla.nightly"]),
    ]

    /// The members of an installed manifest that matter.
    public struct Contents: Equatable, Sendable {
        public var path: String
        public var allowed: [String]
    }

    /// A browser's registration.
    public enum State: Equatable, Sendable {
        case notInstalled
        /// Points to this host.
        case installed
        /// Points to the host of another copy of the app that still exists.
        case otherCopy(String)
        /// Points to a program that is gone (the app was moved or deleted).
        case stale(String)
        /// Not a manifest we can read.
        case unreadable
    }

    /// The members the extension's family reads its list from.
    public static func allowedKey(_ family: BrowserTarget.Family) -> String {
        family == .chromium ? "allowed_origins" : "allowed_extensions"
    }

    /// Our own entry in a family's list.
    public static func ownOrigin(_ family: BrowserTarget.Family) -> String {
        family == .chromium ? BrowserOriginPolicy.chromeOrigin : BrowserOriginPolicy.firefoxExtensionID
    }

    /// The manifest's JSON: `name`, `description`, `path`, `type` "stdio" and the list of allowed extensions, ours first,
    /// then `keeping` (entries of a manifest being replaced, e.g. a developer's extension), without duplicates.
    public static func json(family: BrowserTarget.Family, hostPath: String, keeping: [String] = []) -> Data {
        var allowed = [ownOrigin(family)]
        for entry in keeping where BrowserOriginPolicy.normalize(entry) != nil && belongs(entry, to: family) {
            if !allowed.contains(where: { BrowserOriginPolicy.normalize($0) == BrowserOriginPolicy.normalize(entry) }) {
                allowed.append(entry)
            }
        }
        let object: [String: Any] = ["name": hostName, "description": hostDescription, "path": hostPath, "type": "stdio",
                                     allowedKey(family): allowed]
        let options: JSONSerialization.WritingOptions = [.prettyPrinted, .sortedKeys, .withoutEscapingSlashes]
        let data = (try? JSONSerialization.data(withJSONObject: object, options: options)) ?? Data()
        return data + Data("\n".utf8)
    }

    /// Chromium lists only hold `chrome-extension://` origins, Firefox lists only add-on ids.
    private static func belongs(_ entry: String, to family: BrowserTarget.Family) -> Bool {
        entry.lowercased().hasPrefix("chrome-extension://") == (family == .chromium)
    }

    /// An installed manifest's path and list; nil when the file is missing or isn't one of ours.
    public static func read(_ url: URL) -> Contents? {
        guard let data = try? Data(contentsOf: url),
              let object = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              (object["name"] as? String) == hostName, let path = object["path"] as? String else { return nil }
        let lists = ["allowed_origins", "allowed_extensions"].compactMap { object[$0] as? [Any] }
        let allowed = lists.flatMap { $0.compactMap { $0 as? String } }
        return Contents(path: path, allowed: allowed)
    }

    public static func state(of browser: BrowserTarget, home: URL, hostPath: String) -> State {
        let url = browser.manifestURL(home: home)
        guard FileManager.default.fileExists(atPath: url.path) else { return .notInstalled }
        guard let contents = read(url) else { return .unreadable }
        if samePath(contents.path, hostPath) { return .installed }
        return FileManager.default.isExecutableFile(atPath: contents.path) ? .otherCopy(contents.path) : .stale(contents.path)
    }

    /// Whether the browser is on this Mac: its folder exists (it ran once) or `appInstalled` finds one of its apps.
    public static func isPresent(_ browser: BrowserTarget, home: URL, appInstalled: (String) -> Bool = { _ in false }) -> Bool {
        var isFolder: ObjCBool = false
        if FileManager.default.fileExists(atPath: browser.supportURL(home: home).path, isDirectory: &isFolder), isFolder.boolValue {
            return true
        }
        return browser.bundleIdentifiers.contains(where: appInstalled)
    }

    /// Writes the manifest for `browser`, keeping the other extensions an existing one allows.
    public static func install(for browser: BrowserTarget, home: URL, hostPath: String) throws {
        let url = browser.manifestURL(home: home)
        let keeping = read(url)?.allowed ?? []
        try FileManager.default.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
        try json(family: browser.family, hostPath: hostPath, keeping: keeping).write(to: url, options: .atomic)
    }

    /// Deletes our manifest for `browser`, if there is one.
    public static func remove(for browser: BrowserTarget, home: URL) throws {
        let url = browser.manifestURL(home: home)
        guard FileManager.default.fileExists(atPath: url.path) else { return }
        try FileManager.default.removeItem(at: url)
    }

    /// At launch: rewrites the manifests that point to a program that is gone (the app moved), never one that points to
    /// another copy that still exists. Returns the browsers it rewrote.
    @discardableResult
    public static func refreshStale(home: URL, hostPath: String) -> [BrowserTarget] {
        var rewritten: [BrowserTarget] = []
        for browser in browsers {
            guard case .stale = state(of: browser, home: home, hostPath: hostPath) else { continue }
            if (try? install(for: browser, home: home, hostPath: hostPath)) != nil { rewritten.append(browser) }
        }
        return rewritten
    }

    private static func samePath(_ first: String, _ second: String) -> Bool {
        (first as NSString).standardizingPath == (second as NSString).standardizingPath
            || IPCEndpoint.realPath(first) == IPCEndpoint.realPath(second)
    }
}
