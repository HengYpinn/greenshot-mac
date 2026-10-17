// Greenshot for Mac (Community) - an unofficial macOS port of Greenshot
// Copyright (C) 2026 Greenshot for Mac (Community) contributors
// Based on Greenshot, Copyright (C) 2007-2026 Thomas Braun, Jens Klingen, Robin Krom
// SPDX-License-Identifier: GPL-3.0-or-later

import Foundation
import Testing
@testable import GreenshotCore

/// How greenshot-mcp reaches the app: only the app it belongs to, and a cancelled call doesn't start it.
@Suite struct MCPConnectionTests {
    private func folder() throws -> URL {
        let url = FileManager.default.temporaryDirectory.appendingPathComponent("mcp-connection-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)
        return url
    }

    @Test func theAppOfABundle() throws {
        let root = try folder()
        defer { try? FileManager.default.removeItem(at: root) }
        let bundle = root.appendingPathComponent("Greenshot.app")
        try FileManager.default.createDirectory(at: bundle.appendingPathComponent("Contents/Helpers"), withIntermediateDirectories: true)
        let plist: [String: Any] = ["CFBundleIdentifier": "test.greenshot.connection", "CFBundleExecutable": "Greenshot Mac"]
        try PropertyListSerialization.data(fromPropertyList: plist, format: .xml, options: 0)
            .write(to: bundle.appendingPathComponent("Contents/Info.plist"))
        let helper = bundle.appendingPathComponent("Contents/Helpers/greenshot-mcp").path
        let endpoint = IPCEndpoint.forExecutable(helper, temporaryFolder: root.path, applicationSupport: root)
        let app = bundle.appendingPathComponent("Contents/MacOS/Greenshot Mac").path
        #expect(IPCAppLauncher.appExecutable(endpoint: endpoint, executable: helper) == app)
        #expect(IPCAppLauncher.isApp(processPath: app, uid: 501, endpoint: endpoint, executable: helper, currentUser: 501))
        // Another user's process, another program, or the same app in another copy
        #expect(!IPCAppLauncher.isApp(processPath: app, uid: 502, endpoint: endpoint, executable: helper, currentUser: 501))
        #expect(!IPCAppLauncher.isApp(processPath: "/usr/bin/nc", uid: 501, endpoint: endpoint, executable: helper, currentUser: 501))
        #expect(!IPCAppLauncher.isApp(processPath: "/Applications/Greenshot.app/Contents/MacOS/Greenshot Mac", uid: 501,
                                      endpoint: endpoint, executable: helper, currentUser: 501))
        #expect(!IPCAppLauncher.isApp(processPath: nil, uid: 501, endpoint: endpoint, executable: helper, currentUser: 501))
    }

    @Test func theAppOfABareBuild() {
        let helper = "/work/.build/debug/greenshot-mcp"
        let endpoint = IPCEndpoint(bundleIdentifier: nil, appBundlePath: nil, temporaryFolder: "/tmp", applicationSupport: URL(fileURLWithPath: "/tmp"))
        #expect(IPCAppLauncher.appExecutable(endpoint: endpoint, executable: helper) == "/work/.build/debug/GreenshotMac")
        #expect(IPCAppLauncher.isApp(processPath: "/work/.build/debug/GreenshotMac", uid: 7, endpoint: endpoint, executable: helper,
                                     currentUser: 7))
        #expect(!IPCAppLauncher.isApp(processPath: "/work/.build/debug/greenshot-cli", uid: 7, endpoint: endpoint, executable: helper,
                                      currentUser: 7))
    }

    @Test func thisProcessIsNotTheApp() async throws {
        let root = try folder()
        defer { try? FileManager.default.removeItem(at: root) }
        let path = "/tmp/gsmac-peer-\(getpid()).sock"
        defer { unlink(path) }
        let listener = try IPCSocket.listen(at: path)
        defer { close(listener) }
        let endpoint = IPCEndpoint(bundleIdentifier: "test.peer", appBundlePath: nil, temporaryFolder: root.path, applicationSupport: root)
        let isApp = try await offPool { () -> Bool in
            let client = try IPCClient.connect(to: path)
            defer { client.close() }
            return IPCAppLauncher.isAppPeer(client, endpoint: endpoint, executable: root.appendingPathComponent("greenshot-mcp").path)
        }
        // A program of the user listening on the app's socket isn't the app
        #expect(!isApp)
    }

    @Test func aCancelledCallDoesNotStartTheApp() async throws {
        let root = try folder()
        defer { try? FileManager.default.removeItem(at: root) }
        // A bare build whose "GreenshotMac" only leaves a mark when it is started
        let marker = root.appendingPathComponent("started")
        let app = root.appendingPathComponent("GreenshotMac")
        try "#!/bin/sh\ntouch '\(marker.path)'\n".write(to: app, atomically: true, encoding: .utf8)
        try FileManager.default.setAttributes([.posixPermissions: 0o755], ofItemAtPath: app.path)
        let endpoint = IPCEndpoint(bundleIdentifier: "test.cancelled.\(getpid())", appBundlePath: nil, temporaryFolder: root.path,
                                   applicationSupport: root)
        try FileManager.default.createDirectory(at: endpoint.supportFolder, withIntermediateDirectories: true)
        let executable = root.appendingPathComponent("greenshot-mcp").path
        let (connected, seconds) = try await offPool { () -> (Bool, TimeInterval) in
            let start = Date()
            let client = IPCAppLauncher.connectOrStart(endpoint: endpoint, executable: executable, timeout: 20, shouldStop: { true })
            client?.close()
            return (client != nil, Date().timeIntervalSince(start))
        }
        #expect(!connected)
        #expect(seconds < 5)
        try await offPool { usleep(300_000) }
        #expect(!FileManager.default.fileExists(atPath: marker.path))
    }

    @Test func waitingForTheSocketStops() async throws {
        let (client, seconds) = try await offPool { () -> (IPCClient?, TimeInterval) in
            let start = Date()
            let client = IPCClient.connect(to: "/tmp/gsmac-none-\(getpid()).sock", waitingUpTo: 10, shouldStop: { Date().timeIntervalSince(start) > 0.2 })
            return (client, Date().timeIntervalSince(start))
        }
        #expect(client == nil)
        #expect(seconds < 3)
    }
}
