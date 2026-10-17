// Greenshot for Mac (Community) - an unofficial macOS port of Greenshot
// Copyright (C) 2026 Greenshot for Mac (Community) contributors
// Based on Greenshot, Copyright (C) 2007-2026 Thomas Braun, Jens Klingen, Robin Krom
// SPDX-License-Identifier: GPL-3.0-or-later

import AppKit
import GreenshotCore

/// The browser registration of this copy of the app: where its native messaging host is, which browsers have our host
/// manifest, installing and removing it (upstream: the installer's `includes\browser-extension.iss` and the self-service
/// debug page; on the Mac the user clicks Install), and the extension's folder for "Load unpacked".
struct BrowserIntegration {
    /// One browser's line in Settings.
    struct Row: Identifiable, Equatable {
        var browser: BrowserTarget
        var state: BrowserHostManifest.State
        var id: String { browser.id }
    }

    /// The user's home folder (manifests go to its Library/Application Support).
    var home: URL
    /// The host executable; nil when it isn't there (a build without it).
    var hostPath: String?
    /// The extension's files: in the app bundle, or the repository's Extensions/Browser for a bare build.
    var extensionSource: URL?
    var appInstalled: (String) -> Bool

    private static let log = Log("Browser")

    static var current: BrowserIntegration {
        BrowserIntegration(home: FileManager.default.homeDirectoryForCurrentUser, hostPath: installedHostPath,
                           extensionSource: bundledExtension,
                           appInstalled: { NSWorkspace.shared.urlForApplication(withBundleIdentifier: $0) != nil })
    }

    /// `Contents/Helpers/greenshot-native-host` of the app bundle, or the one next to a bare build's executable.
    static var installedHostPath: String? {
        let executable = IPCEndpoint.currentExecutablePath
        let path: String
        if let bundle = IPCPeerPolicy.appBundle(ofExecutable: executable) {
            path = ((bundle as NSString).appendingPathComponent("Contents/Helpers") as NSString)
                .appendingPathComponent(BrowserHostManifest.executableName)
        } else {
            path = ((executable as NSString).deletingLastPathComponent as NSString).appendingPathComponent(BrowserHostManifest.executableName)
        }
        return FileManager.default.isExecutableFile(atPath: path) ? path : nil
    }

    /// `Contents/Resources/BrowserExtension` (build-app.sh copies Extensions/Browser there), else the repository's.
    static var bundledExtension: URL? {
        let fileManager = FileManager.default
        if let resources = Bundle.main.resourceURL?.appendingPathComponent("BrowserExtension", isDirectory: true),
           fileManager.fileExists(atPath: resources.appendingPathComponent("manifest.json").path) {
            return resources
        }
        // Sources/GreenshotMac/Browser/BrowserIntegration.swift → the repository
        let repository = URL(fileURLWithPath: #filePath).deletingLastPathComponent().deletingLastPathComponent()
            .deletingLastPathComponent().deletingLastPathComponent()
        let folder = repository.appendingPathComponent("Extensions/Browser", isDirectory: true)
        return fileManager.fileExists(atPath: folder.appendingPathComponent("manifest.json").path) ? folder : nil
    }

    /// The browsers on this Mac, and those with our manifest although the browser seems gone.
    func rows() -> [Row] {
        BrowserHostManifest.browsers.compactMap { browser in
            let state = BrowserHostManifest.state(of: browser, home: home, hostPath: hostPath ?? "")
            guard state != .notInstalled || BrowserHostManifest.isPresent(browser, home: home, appInstalled: appInstalled) else { return nil }
            return Row(browser: browser, state: state)
        }
    }

    /// Registers the host for every browser in `rows()`. Returns the browsers it couldn't write for.
    func installAll() -> [String] {
        guard let hostPath else { return BrowserHostManifest.browsers.map(\.name) }
        var failed: [String] = []
        for row in rows() {
            do {
                try BrowserHostManifest.install(for: row.browser, home: home, hostPath: hostPath)
            } catch {
                Self.log.error("The native messaging host couldn't be registered for \(row.browser.name)", error: error)
                failed.append(row.browser.name)
            }
        }
        Self.log.info("Native messaging host registered for \(rows().filter { $0.state == .installed }.count) browser(s)")
        return failed
    }

    /// Removes our manifest from every browser.
    func removeAll() -> [String] {
        var failed: [String] = []
        for browser in BrowserHostManifest.browsers {
            do {
                try BrowserHostManifest.remove(for: browser, home: home)
            } catch {
                Self.log.error("The native messaging host couldn't be removed for \(browser.name)", error: error)
                failed.append(browser.name)
            }
        }
        Self.log.info("Native messaging host registrations removed")
        return failed
    }

    /// At launch, from an app bundle only: manifests that point to a host that is gone (the app was moved) point to this
    /// one again. Manifests of another copy that still exists stay as they are; a bare build never writes.
    @MainActor
    static func refreshInstalledManifests() {
        guard Snapshots.requestedFolder == nil, IPCPeerPolicy.appBundle(ofExecutable: IPCEndpoint.currentExecutablePath) != nil,
              let hostPath = installedHostPath else { return }
        let home = FileManager.default.homeDirectoryForCurrentUser
        DispatchQueue.global(qos: .utility).async {
            let rewritten = BrowserHostManifest.refreshStale(home: home, hostPath: hostPath)
            if !rewritten.isEmpty {
                log.info("Native messaging host registration updated for \(rewritten.map(\.name).joined(separator: ", ")) (the app moved)")
            }
        }
    }

    /// Copies the extension to `~/Library/Application Support/<bundle id>/BrowserExtension` (a place that stays when the
    /// app is moved or updated) and shows it in Finder, for the browsers' "Load unpacked".
    @MainActor
    func revealExtensionFolder() throws -> URL {
        guard let extensionSource else { throw CocoaError(.fileNoSuchFile) }
        let target = AutomationStartup.endpoint.supportFolder.appendingPathComponent("BrowserExtension", isDirectory: true)
        let fileManager = FileManager.default
        try fileManager.createDirectory(at: target.deletingLastPathComponent(), withIntermediateDirectories: true)
        if fileManager.fileExists(atPath: target.path) { try fileManager.removeItem(at: target) }
        try fileManager.copyItem(at: extensionSource, to: target)
        NSWorkspace.shared.activateFileViewerSelecting([target])
        return target
    }
}
