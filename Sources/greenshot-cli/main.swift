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
} else if let client = IPCAppLauncher.connectOrStart(endpoint: endpoint, executable: executable) {
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
// On a terminal, escape sequences in what the app prints (a QR code's text, OCR, a window title) are made visible;
// a pipe, a file and --json get the exact bytes.
func output(_ data: Data, to handle: FileHandle, fd: Int32) {
    write(isatty(fd) != 0 && !json ? TerminalSafeText.sanitize(data) : data, to: handle)
}
let code = connection.receiveTextReply(stdout: { output($0, to: .standardOutput, fd: STDOUT_FILENO) },
                                       stderr: { output($0, to: .standardError, fd: STDERR_FILENO) })
connection.close()
exit(code)
