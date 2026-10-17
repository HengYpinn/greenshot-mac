// Greenshot for Mac (Community) - an unofficial macOS port of Greenshot
// Copyright (C) 2026 Greenshot for Mac (Community) contributors
// SPDX-License-Identifier: GPL-3.0-or-later

import Foundation
import Testing
@testable import GreenshotCore

/// The host manifests and the origin check (upstream `ExtensionOriginPolicyTests`), always in a temporary home folder:
/// nothing is written to the browsers of the Mac running the tests.
struct BrowserHostManifestTests {
    private final class Home {
        let url: URL

        init() throws {
            url = FileManager.default.temporaryDirectory.appendingPathComponent("gs-browser-home-\(UUID().uuidString)", isDirectory: true)
            try FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)
        }

        deinit { try? FileManager.default.removeItem(at: url) }

        /// An executable file to point a manifest at.
        func program(_ name: String) throws -> String {
            let file = url.appendingPathComponent(name)
            try Data("#!/bin/sh\n".utf8).write(to: file)
            try FileManager.default.setAttributes([.posixPermissions: 0o755], ofItemAtPath: file.path)
            return file.path
        }

        func folder(_ relative: String) throws {
            try FileManager.default.createDirectory(at: url.appendingPathComponent("Library/Application Support/\(relative)"),
                                                    withIntermediateDirectories: true)
        }
    }

    private func browser(_ id: String) throws -> BrowserTarget {
        try #require(BrowserHostManifest.browsers.first { $0.id == id })
    }

    private func object(_ data: Data) throws -> [String: Any] {
        try #require(try JSONSerialization.jsonObject(with: data) as? [String: Any])
    }

    // MARK: Origin policy

    @Test(arguments: ["chrome-extension://phnpiifkcghdmpcgjilfkdlaidfjjjea/", "chrome-extension://phnpiifkcghdmpcgjilfkdlaidfjjjea",
                      "CHROME-EXTENSION://PHNPIIFKCGHDMPCGJILFKDLAIDFJJJEA/", "companion@greenshot-mac.github.io"])
    func builtInExtensionsAreAllowedWithoutManifests(_ origin: String) {
        #expect(BrowserOriginPolicy.isAllowed(origin))
    }

    @Test(arguments: [nil, "", "chrome-extension://aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa/", "moz-extension://0b1c2d3e-0000-0000-0000-000000000000/",
                      "other@example.com", "chrome-extension://*/", "COMPANION@greenshot-mac.github.io",
                      // Upstream's official ids are not this extension
                      "chrome-extension://knldjmfmopnpolahpmmgbagdohdnhkik/", "greenshot@getgreenshot.org"] as [String?])
    func unknownOriginsAreRefused(_ origin: String?) {
        #expect(!BrowserOriginPolicy.isAllowed(origin))
    }

    @Test func installedManifestsAddExtensionsAndChangesArePickedUp() throws {
        let home = try Home()
        let gate = BrowserOriginGate(home: home.url)
        let developer = "chrome-extension://bbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbb/"
        #expect(!gate.isAllowed(developer))

        let chrome = try browser("chrome")
        try BrowserHostManifest.install(for: chrome, home: home.url, hostPath: try home.program("host"))
        var manifest = try object(try Data(contentsOf: chrome.manifestURL(home: home.url)))
        manifest["allowed_origins"] = [BrowserOriginPolicy.chromeOrigin, developer]
        try JSONSerialization.data(withJSONObject: manifest).write(to: chrome.manifestURL(home: home.url))
        #expect(gate.isAllowed(developer))
        #expect(gate.isAllowed(BrowserOriginPolicy.chromeOrigin))

        try BrowserHostManifest.remove(for: chrome, home: home.url)
        #expect(!gate.isAllowed(developer))
    }

    @Test func aBrokenManifestOnlyAllowsTheBuiltInExtensions() throws {
        let home = try Home()
        let firefox = try browser("firefox")
        try FileManager.default.createDirectory(at: firefox.manifestURL(home: home.url).deletingLastPathComponent(), withIntermediateDirectories: true)
        try Data("{ not json".utf8).write(to: firefox.manifestURL(home: home.url))
        let gate = BrowserOriginGate(home: home.url)
        #expect(gate.allowedByManifests().isEmpty)
        #expect(gate.isAllowed(BrowserOriginPolicy.firefoxExtensionID))
        #expect(!gate.isAllowed("other@example.com"))
        #expect(BrowserHostManifest.state(of: firefox, home: home.url, hostPath: "/x") == .unreadable)
    }

    @Test func chromeIDComesFromTheExtensionsKey() throws {
        // The key in Extensions/Browser/manifest.json gives the id the policy and the host manifests allow
        let key = "MIIBIjANBgkqhkiG9w0BAQEFAAOCAQ8AMIIBCgKCAQEAzzFul0CvJRKJFjJNEAv59zwe13+WIf5e16sLRfWjLfxNLtNhXCbhb5xnIVVYq+WyzCDXoaNWljkI0RO4qPbU3FER5vEiCFD1ABSW6rtR03AYB+zekFH40Th3A8st/S8XtV5xa2aI3dlfUV5GbCD2is39VJ6+BIekX1dNpNRuaC2zl6q0FLtSoSVlg8pvNlmZcvowXuk4jeDM/ejN3L6hz0p9jittRW7o3rZysdOzlK6T779KhGoMkvnC7nbCwA9oMgp0Czq5qciJuyv0RhsJRsZwf5ZGV0uejl9n/y5ho9SrAVgo3DyvcGDFi73fZimMv2ore03FEO4SmTRsRDSe4QIDAQAB"
        #expect(BrowserOriginPolicy.chromeExtensionID(publicKeyBase64: key) == BrowserOriginPolicy.chromeExtensionID)
        // The digits 0-f are written a-p: an all-zero digest would be "aaaa…"
        let id = try #require(BrowserOriginPolicy.chromeExtensionID(publicKeyBase64: "AAAA"))
        #expect(id.count == 32)
        #expect(id.allSatisfy { ("a"..."p").contains($0) })
        #expect(BrowserOriginPolicy.chromeExtensionID(publicKeyBase64: "") == nil)
    }

    // MARK: Manifests

    @Test func chromiumAndFirefoxManifests() throws {
        let chromium = try object(BrowserHostManifest.json(family: .chromium, hostPath: "/Applications/G.app/Contents/Helpers/greenshot-native-host"))
        #expect(chromium["name"] as? String == "io.github.greenshot_mac.host")
        #expect(chromium["path"] as? String == "/Applications/G.app/Contents/Helpers/greenshot-native-host")
        #expect(chromium["type"] as? String == "stdio")
        #expect(chromium["allowed_origins"] as? [String] == ["chrome-extension://phnpiifkcghdmpcgjilfkdlaidfjjjea/"])
        #expect(chromium["allowed_extensions"] == nil)

        let firefox = try object(BrowserHostManifest.json(family: .firefox, hostPath: "/h"))
        #expect(firefox["allowed_extensions"] as? [String] == ["companion@greenshot-mac.github.io"])
        #expect(firefox["allowed_origins"] == nil)
        // The host name follows the browsers' rule: lower-case letters, digits, "_" and "."
        #expect(BrowserHostManifest.hostName.allSatisfy { $0.isLowercase || $0.isNumber || $0 == "_" || $0 == "." })
    }

    @Test func manifestsGoIntoEachBrowsersFolder() throws {
        let home = URL(fileURLWithPath: "/Users/me")
        #expect(try browser("chrome").manifestURL(home: home).path
                == "/Users/me/Library/Application Support/Google/Chrome/NativeMessagingHosts/io.github.greenshot_mac.host.json")
        #expect(try browser("edge").manifestURL(home: home).path
                == "/Users/me/Library/Application Support/Microsoft Edge/NativeMessagingHosts/io.github.greenshot_mac.host.json")
        #expect(try browser("firefox").manifestURL(home: home).path
                == "/Users/me/Library/Application Support/Mozilla/NativeMessagingHosts/io.github.greenshot_mac.host.json")
        #expect(try browser("brave").manifestURL(home: home).path
                == "/Users/me/Library/Application Support/BraveSoftware/Brave-Browser/NativeMessagingHosts/io.github.greenshot_mac.host.json")
    }

    @Test func installKeepsOtherExtensionsAndRemoveDeletes() throws {
        let home = try Home()
        let host = try home.program("host")
        let chrome = try browser("chrome")
        #expect(BrowserHostManifest.state(of: chrome, home: home.url, hostPath: host) == .notInstalled)
        try BrowserHostManifest.install(for: chrome, home: home.url, hostPath: host)
        #expect(BrowserHostManifest.state(of: chrome, home: home.url, hostPath: host) == .installed)

        // A developer's extension added by hand, and an entry of the wrong kind
        let url = chrome.manifestURL(home: home.url)
        var manifest = try object(try Data(contentsOf: url))
        manifest["allowed_origins"] = [BrowserOriginPolicy.chromeOrigin, "chrome-extension://cccccccccccccccccccccccccccccccc/",
                                       "someone@example.com"]
        try JSONSerialization.data(withJSONObject: manifest).write(to: url)
        try BrowserHostManifest.install(for: chrome, home: home.url, hostPath: host)
        let contents = try #require(BrowserHostManifest.read(url))
        #expect(contents.allowed == [BrowserOriginPolicy.chromeOrigin, "chrome-extension://cccccccccccccccccccccccccccccccc/"])

        try BrowserHostManifest.remove(for: chrome, home: home.url)
        #expect(BrowserHostManifest.state(of: chrome, home: home.url, hostPath: host) == .notInstalled)
        try BrowserHostManifest.remove(for: chrome, home: home.url)
    }

    @Test func statesOfManifestsPointingElsewhere() throws {
        let home = try Home()
        let host = try home.program("host")
        let otherCopy = try home.program("other-host")
        let edge = try browser("edge")
        try BrowserHostManifest.install(for: edge, home: home.url, hostPath: otherCopy)
        #expect(BrowserHostManifest.state(of: edge, home: home.url, hostPath: host) == .otherCopy(otherCopy))
        let gone = home.url.appendingPathComponent("moved/greenshot-native-host").path
        try BrowserHostManifest.install(for: edge, home: home.url, hostPath: gone)
        #expect(BrowserHostManifest.state(of: edge, home: home.url, hostPath: host) == .stale(gone))
    }

    @Test func refreshRewritesOnlyManifestsOfAMissingHost() throws {
        let home = try Home()
        let host = try home.program("host")
        let otherCopy = try home.program("other-host")
        let gone = home.url.appendingPathComponent("moved/greenshot-native-host").path
        let chrome = try browser("chrome")
        let edge = try browser("edge")
        try BrowserHostManifest.install(for: chrome, home: home.url, hostPath: gone)
        try BrowserHostManifest.install(for: edge, home: home.url, hostPath: otherCopy)

        let rewritten = BrowserHostManifest.refreshStale(home: home.url, hostPath: host)
        #expect(rewritten.map(\.id) == ["chrome"])
        #expect(BrowserHostManifest.state(of: chrome, home: home.url, hostPath: host) == .installed)
        #expect(BrowserHostManifest.state(of: edge, home: home.url, hostPath: host) == .otherCopy(otherCopy))
    }

    @Test func browsersArePresentByTheirFolderOrTheirApp() throws {
        let home = try Home()
        let chrome = try browser("chrome")
        let firefox = try browser("firefox")
        #expect(!BrowserHostManifest.isPresent(chrome, home: home.url))
        try home.folder("Google/Chrome")
        #expect(BrowserHostManifest.isPresent(chrome, home: home.url))
        #expect(BrowserHostManifest.isPresent(firefox, home: home.url) { $0 == "org.mozilla.firefoxdeveloperedition" })
    }
}
