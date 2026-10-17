// Greenshot for Mac (Community) - an unofficial macOS port of Greenshot
// Copyright (C) 2026 Greenshot for Mac (Community) contributors
// Based on Greenshot, Copyright (C) 2007-2026 Thomas Braun, Jens Klingen, Robin Krom
// SPDX-License-Identifier: GPL-3.0-or-later

// greenshot-cli: the command line of Greenshot for Mac (upstream src/greenshot-proxy/main_cli.c). It lives in the app
// bundle (Contents/Helpers) and forwards its arguments unchanged to the running app (connection source "cli", text
// replies), starting the app when it isn't running, and prints what comes back. Parsing, checks and output are the
// app's (IPCCommandLine); only --help and --version are answered here, so they work without the app.

import Darwin
import Foundation
import GreenshotCore

let arguments = Array(CommandLine.arguments.dropFirst())
let executable = IPCEndpoint.currentExecutablePath
let endpoint = IPCEndpoint.forExecutable(executable)

func write(_ data: Data, to handle: FileHandle) {
    guard !data.isEmpty else { return }
    handle.write(data)
}

/// An error of the tool itself; with --json, stdout gets a result document too (main_cli.c `Fail`).
func fail(json: Bool, code: Int32, _ message: String) -> Never {
    write(Data((message + "\n").utf8), to: .standardError)
    if json {
        let document = IPCJSON.text(["status": .string("error"), "exit_code": .number(Double(code)), "stderr": .string(message)])
        write(Data((document + "\n").utf8), to: .standardOutput)
    }
    exit(code)
}

var version: String {
    guard let bundle = endpoint.appBundlePath,
          let value = IPCEndpoint.infoDictionary(ofBundle: bundle)?["CFBundleShortVersionString"] as? String else { return "development build" }
    return value
}

/// Starts the app: the bundle this tool belongs to (`open -g`: in the background), or for a bare `swift build` the
/// GreenshotMac next to it, in a session of its own so it outlives the terminal.
func launchApp() -> Bool {
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
/// running), then waits up to 10 seconds for its socket.
func connectOrStartApp() -> IPCClient? {
    if let client = try? IPCClient.connect(to: endpoint.socketPath) { return client }
    let lock = IPCFileLock.wait(endpoint.coldStartLockURL, timeout: 8)
    defer { lock?.release() }
    // Another client may have started the app while this one waited
    if let client = IPCClient.connect(to: endpoint.socketPath, waitingUpTo: 1) { return client }
    guard launchApp() else { return nil }
    return IPCClient.connect(to: endpoint.socketPath, waitingUpTo: 10, interval: 0.25)
}

let first = arguments.first?.lowercased()
if first == nil || first == "--help" || first == "-h" {
    let usage = IPCCommandLine.cliUsage(installedPath: endpoint.appBundlePath == nil ? nil : executable)
    write(Data(usage.utf8), to: .standardOutput)
    exit(IPCExitCode.ok)
}
if first == "--version" || first == "-v" {
    write(Data("greenshot-cli \(version) (Greenshot for Mac (Community))\n".utf8), to: .standardOutput)
    exit(IPCExitCode.ok)
}

let json = arguments.contains { $0.caseInsensitiveCompare("--json") == .orderedSame }
let connection: IPCClient
if let client = try? IPCClient.connect(to: endpoint.socketPath) {
    connection = client
} else if !IPCClient.startsApp(for: arguments) {
    // --exit and --reload: nothing to do when the app isn't running
    exit(IPCExitCode.ok)
} else if let client = connectOrStartApp() {
    connection = client
} else {
    fail(json: json, code: IPCExitCode.unavailable, "Error: Greenshot for Mac is not running and could not be started.")
}

do {
    try connection.send(.hello(source: .cli, replyFormat: .text, client: "greenshot-cli", clientVersion: version))
    try connection.send(.commandLine(arguments, cwd: FileManager.default.currentDirectoryPath))
} catch {
    fail(json: json, code: IPCExitCode.failure, "Error: failed to send the command to Greenshot for Mac.")
}
let code = connection.receiveTextReply(stdout: { write($0, to: .standardOutput) }, stderr: { write($0, to: .standardError) })
connection.close()
exit(code)
