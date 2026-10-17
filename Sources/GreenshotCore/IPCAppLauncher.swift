// Greenshot for Mac (Community) - an unofficial macOS port of Greenshot
// Copyright (C) 2026 Greenshot for Mac (Community) contributors
// Based on Greenshot, Copyright (C) 2007-2026 Thomas Braun, Jens Klingen, Robin Krom
// SPDX-License-Identifier: GPL-3.0-or-later
// Owned by MCP after the wave 4 prep (moved here from greenshot-cli/main.swift).

import Darwin
import Foundation

/// Starts the app for its helpers (greenshot-cli, greenshot-mcp) and connects to it (upstream greenshot-proxy
/// `ConnectOrColdStart`). The browser extension's native messaging host never starts the app (upstream ADR 003).
public enum IPCAppLauncher {
    /// Starts the app: the bundle `executable` belongs to (`open -g`: in the background), or for a bare `swift build` the
    /// GreenshotMac next to it, in a session of its own so it outlives the terminal.
    public static func launch(endpoint: IPCEndpoint, executable: String) -> Bool {
        if let bundle = endpoint.appBundlePath {
            let open = Process()
            open.executableURL = URL(fileURLWithPath: "/usr/bin/open")
            open.arguments = ["-g", "-a", bundle, "--args", "--background"]
            open.standardOutput = FileHandle.nullDevice
            open.standardError = FileHandle.nullDevice
            do {
                try open.run()
            } catch {
                return false
            }
            open.waitUntilExit()
            return open.terminationStatus == 0
        }
        let app = ((executable as NSString).deletingLastPathComponent as NSString).appendingPathComponent("GreenshotMac")
        guard FileManager.default.isExecutableFile(atPath: app) else { return false }
        var attributes: posix_spawnattr_t?
        posix_spawnattr_init(&attributes)
        posix_spawnattr_setflags(&attributes, Int16(POSIX_SPAWN_SETSID))
        var actions: posix_spawn_file_actions_t?
        posix_spawn_file_actions_init(&actions)
        for fd in [STDIN_FILENO, STDOUT_FILENO, STDERR_FILENO] {
            posix_spawn_file_actions_addopen(&actions, fd, "/dev/null", fd == STDIN_FILENO ? O_RDONLY : O_WRONLY, 0)
        }
        defer {
            posix_spawn_file_actions_destroy(&actions)
            posix_spawnattr_destroy(&attributes)
        }
        var pid: pid_t = 0
        let argv: [UnsafeMutablePointer<CChar>?] = [strdup(app), strdup("--background"), nil]
        defer { argv.forEach { free($0) } }
        return posix_spawn(&pid, app, &actions, &attributes, argv, environ) == 0
    }

    /// Upstream `ConnectOrColdStart`: one client at a time starts the app (others wait for the lock and then find it
    /// running), then waits up to `timeout` seconds for its socket.
    public static func connectOrStart(endpoint: IPCEndpoint, executable: String, timeout: TimeInterval = 10) -> IPCClient? {
        if let client = try? IPCClient.connect(to: endpoint.socketPath) { return client }
        let lock = IPCFileLock.wait(endpoint.coldStartLockURL, timeout: 8)
        defer { lock?.release() }
        // Another client may have started the app while this one waited
        if let client = IPCClient.connect(to: endpoint.socketPath, waitingUpTo: 1) { return client }
        guard launch(endpoint: endpoint, executable: executable) else { return nil }
        return IPCClient.connect(to: endpoint.socketPath, waitingUpTo: timeout, interval: 0.25)
    }
}
