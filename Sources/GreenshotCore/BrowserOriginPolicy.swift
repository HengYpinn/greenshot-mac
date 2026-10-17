// Greenshot for Mac (Community) - an unofficial macOS port of Greenshot
// Copyright (C) 2026 Greenshot for Mac (Community) contributors
// Based on Greenshot, Copyright (C) 2007-2026 Thomas Braun, Jens Klingen, Robin Krom
// SPDX-License-Identifier: GPL-3.0-or-later

import CryptoKit
import Foundation

/// Which browser extensions may talk to the app through the native messaging host (upstream
/// `Ipc/BrowserExtension/ExtensionOriginPolicy.cs`, docs/greenshot-proxy-and-integration.md §2.1). A browser starts the
/// host only for the extensions its host manifest lists, and the host passes the caller's origin on in HELLO; the app
/// checks it against the same lists, so a manifest registered elsewhere that points at the host doesn't open the app to
/// other extensions. Allowed: the Mac extension's own ids, plus what our installed host manifests allow (a developer's
/// extension id added to one of them works without a restart).
public enum BrowserOriginPolicy {
    /// The Chromium id of Extensions/Browser, fixed by the public key in its manifest (`"key"`).
    public static let chromeExtensionID = "phnpiifkcghdmpcgjilfkdlaidfjjjea"
    /// The Firefox add-on id (manifest `browser_specific_settings.gecko.id`).
    public static let firefoxExtensionID = "companion@greenshot-mac.github.io"

    /// `allowed_origins` of a Chromium host manifest.
    public static var chromeOrigin: String { "chrome-extension://\(chromeExtensionID)/" }
    public static var builtInOrigins: [String] { [chromeOrigin, firefoxExtensionID] }

    /// True when `origin` (Chromium: `chrome-extension://<id>/`, Firefox: the add-on id) is a built-in one or in `extra`.
    public static func isAllowed(_ origin: String?, extra: [String] = []) -> Bool {
        guard let normalized = normalize(origin) else { return false }
        return (builtInOrigins + extra).contains { normalize($0) == normalized }
    }

    /// Chromium origins compared case-insensitively with a trailing slash, Firefox ids exactly; a wildcard never
    /// matches, as in the browsers' manifests.
    public static func normalize(_ origin: String?) -> String? {
        guard var text = origin?.trimmingCharacters(in: .whitespacesAndNewlines), !text.isEmpty, !text.contains("*") else { return nil }
        if text.lowercased().hasPrefix("chrome-extension://") {
            text = text.lowercased()
            if !text.hasSuffix("/") { text += "/" }
        }
        return text
    }

    /// The id Chromium gives an extension with this public key (`"key"` in manifest.json, base64 DER): the first 128 bits
    /// of its SHA-256 as hex digits, 0-f written a-p.
    public static func chromeExtensionID(publicKeyBase64: String) -> String? {
        guard let key = Data(base64Encoded: publicKeyBase64.filter { !$0.isWhitespace }), !key.isEmpty else { return nil }
        let letters = Array("abcdefghijklmnop")
        var id = ""
        for byte in SHA256.hash(data: key).prefix(16) {
            id.append(letters[Int(byte >> 4)])
            id.append(letters[Int(byte & 0x0F)])
        }
        return id
    }
}

/// `BrowserOriginPolicy` with the lists of the installed host manifests, read again only when one of the files changed
/// (TAB_CHANGED comes with every page the user opens).
public final class BrowserOriginGate: @unchecked Sendable {
    private let home: URL
    private let lock = NSLock()
    private var stamp: [String: Date] = [:]
    private var extra: [String] = []
    private var loaded = false

    /// `home`: the user's home folder (a test passes a temporary one).
    public init(home: URL = FileManager.default.homeDirectoryForCurrentUser) {
        self.home = home
    }

    public func isAllowed(_ origin: String?) -> Bool {
        BrowserOriginPolicy.isAllowed(origin, extra: allowedByManifests())
    }

    /// The `allowed_origins` / `allowed_extensions` of our manifests in every browser's folder.
    public func allowedByManifests() -> [String] {
        let files = BrowserHostManifest.browsers.map { $0.manifestURL(home: home) }
        var current: [String: Date] = [:]
        for file in files {
            if let date = (try? file.resourceValues(forKeys: [.contentModificationDateKey]))?.contentModificationDate {
                current[file.path] = date
            }
        }
        lock.lock()
        defer { lock.unlock() }
        if loaded, current == stamp { return extra }
        var origins: [String] = []
        for file in files where current[file.path] != nil {
            for origin in BrowserHostManifest.read(file)?.allowed ?? [] where !origins.contains(origin) {
                origins.append(origin)
            }
        }
        stamp = current
        extra = origins
        loaded = true
        return origins
    }
}
