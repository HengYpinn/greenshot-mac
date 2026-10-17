// Greenshot for Mac (Community) - an unofficial macOS port of Greenshot
// Copyright (C) 2026 Greenshot for Mac (Community) contributors
// SPDX-License-Identifier: GPL-3.0-or-later

import Foundation
import Testing
@testable import GreenshotCore

/// Extensions/Browser and the app agree: the host name the extension connects to, its ids, and the files it names.
struct BrowserExtensionPackageTests {
    private static let folder = URL(fileURLWithPath: #filePath).deletingLastPathComponent().deletingLastPathComponent()
        .deletingLastPathComponent().appendingPathComponent("Extensions/Browser", isDirectory: true)

    private func manifest() throws -> [String: Any] {
        let data = try Data(contentsOf: Self.folder.appendingPathComponent("manifest.json"))
        return try #require(try JSONSerialization.jsonObject(with: data) as? [String: Any])
    }

    private func text(_ path: String) throws -> String {
        try String(contentsOf: Self.folder.appendingPathComponent(path), encoding: .utf8)
    }

    @Test func idsMatchThePolicy() throws {
        let manifest = try manifest()
        let key = try #require(manifest["key"] as? String)
        let id = BrowserOriginPolicy.chromeExtensionID(publicKeyBase64: key)
        #expect(id == BrowserOriginPolicy.chromeExtensionID)
        let settings = try #require(manifest["browser_specific_settings"] as? [String: Any])
        let gecko = try #require(settings["gecko"] as? [String: Any])
        #expect(gecko["id"] as? String == BrowserOriginPolicy.firefoxExtensionID)
        #expect(manifest["manifest_version"] as? Int == 3)
        // Review S-N4: activeTab and tabs are enough; no access to every site (Firefox needs 126 for captureVisibleTab
        // with activeTab)
        #expect(manifest["host_permissions"] == nil)
        #expect(manifest["permissions"] as? [String] == ["activeTab", "tabs", "nativeMessaging", "storage"])
        #expect(gecko["strict_min_version"] as? String == "126.0")
        let description = try #require(manifest["description"] as? String)
        // Chrome's limit for the description
        #expect(description.count <= 132)
    }

    @Test func theBackgroundScriptConnectsToOurHost() throws {
        let script = try text("background.js")
        #expect(script.contains("const NATIVE_HOST_NAME = \"\(BrowserHostManifest.hostName)\";"))
        #expect(!script.contains("org.greenshot.proxy"))
        for command in BrowserCommand.all {
            #expect(script.contains("command: \"\(command)\""))
        }
    }

    @Test func everyReferencedFileExists() throws {
        let manifest = try manifest()
        var files: [String] = []
        if let icons = manifest["icons"] as? [String: String] { files += icons.values }
        if let background = manifest["background"] as? [String: Any] {
            if let worker = background["service_worker"] as? String { files.append(worker) }
            files += background["scripts"] as? [String] ?? []
        }
        if let action = manifest["action"] as? [String: Any], let popup = action["default_popup"] as? String { files.append(popup) }
        if let options = manifest["options_ui"] as? [String: Any], let page = options["page"] as? String { files.append(page) }
        // What the pages load, relative to their folders
        files += ["popup/popup.css", "popup/popup.js", "icons/g.svg", "options/options.js"]
        for file in files {
            #expect(FileManager.default.fileExists(atPath: Self.folder.appendingPathComponent(file).path), "\(file) is missing")
        }
        let popup = try text("popup/popup.html")
        #expect(popup.contains("data=\"../icons/g.svg\""))
        #expect(!popup.contains("data=\"..\\icons"))
    }

    @Test func everySourceFileCarriesTheLicenseAndCredit() throws {
        for path in ["background.js", "popup/popup.js", "popup/popup.css", "popup/popup.html", "options/options.js", "options/options.html"] {
            let source = try text(path)
            #expect(source.contains("SPDX-License-Identifier: GPL-3.0-or-later"), "\(path)")
            #expect(source.contains("Thomas Braun, Jens Klingen, Robin Krom"), "\(path)")
        }
    }
}
