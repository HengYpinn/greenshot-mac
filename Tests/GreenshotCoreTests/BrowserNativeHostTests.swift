// Greenshot for Mac (Community) - an unofficial macOS port of Greenshot
// Copyright (C) 2026 Greenshot for Mac (Community) contributors
// SPDX-License-Identifier: GPL-3.0-or-later

import Darwin
import Foundation
import Testing
@testable import GreenshotCore

/// The native messaging host (upstream `GreenshotProxyIntegrationTests`, in-process): the browser's stdin and stdout are
/// pipes, the app is a real `IPCServer` on a temporary socket. Everything that blocks (the relay, reading a pipe) runs
/// on a thread of its own, never on the test's concurrency threads, which the server's handlers need.
@Suite(.serialized)
struct BrowserNativeHostTests {
    /// The origins the server saw, with their source.
    private final class Recorder: @unchecked Sendable {
        private let lock = NSLock()
        private var seen: [(IPCSource, String?)] = []

        func record(_ source: IPCSource, _ origin: String?) {
            lock.lock()
            seen.append((source, origin))
            lock.unlock()
        }

        var all: [(IPCSource, String?)] {
            lock.lock()
            defer { lock.unlock() }
            return seen
        }
    }

    /// stdin and stdout of the host. Each end is closed once (a closed number may already belong to another file).
    private final class Pipes {
        private(set) var input: [Int32] = [-1, -1]
        private(set) var output: [Int32] = [-1, -1]

        init() {
            _ = pipe(&input)
            _ = pipe(&output)
        }

        /// The browser closes its end of stdin.
        func closeInputWriter() {
            if input[1] >= 0 { close(input[1]) }
            input[1] = -1
        }

        func closeAll() {
            closeInputWriter()
            for fd in [input[0], output[0], output[1]] where fd >= 0 { close(fd) }
            input[0] = -1
            output = [-1, -1]
        }
    }

    private func makeServer(_ recorder: Recorder) throws -> IPCServer {
        let path = FileManager.default.temporaryDirectory.appendingPathComponent("gs-nh-\(UUID().uuidString.prefix(8)).ipc").path
        var configuration = IPCServer.Configuration(socketPath: path)
        configuration.acceptedSources = [.nativeMessaging]
        configuration.helloTimeout = 5
        let dispatcher = IPCDispatcher()
        dispatcher.table.register(BrowserCommand.handshake, sources: [.nativeMessaging]) { context in
            recorder.record(context.source, context.origin)
            return BrowserReplies.handshake(version: "9.9")
        }
        let server = IPCServer(configuration: configuration, dispatcher: dispatcher)
        try server.start()
        return server
    }

    /// Runs `body` on a new thread and waits for it without holding a concurrency thread.
    private func onOwnThread<T: Sendable>(_ body: @escaping @Sendable () -> T) async -> T {
        await withCheckedContinuation { continuation in
            let thread = Thread { continuation.resume(returning: body()) }
            thread.start()
        }
    }

    private func readFrame(_ fd: Int32) async -> JSONObject? {
        let data = await onOwnThread { try? IPCFrameIO.readFrame(fd, minimum: 2, deadline: Date().addingTimeInterval(5)) }
        return data.flatMap { IPCJSON.parseObject($0) }
    }

    private func write(_ json: String, to fd: Int32) throws {
        try IPCFrameIO.writeFrame(fd, Data(json.utf8))
    }

    // MARK: Arguments

    @Test func originsOfTheBrowsersArguments() {
        let host = "/Applications/G.app/Contents/Helpers/greenshot-native-host"
        #expect(BrowserNativeHost.extensionOrigin(arguments: [host, "chrome-extension://abcdef/"]) == "chrome-extension://abcdef/")
        // Chrome on Windows adds the parent window
        #expect(BrowserNativeHost.extensionOrigin(arguments: [host, "chrome-extension://abcdef/", "--parent-window=0"]) == "chrome-extension://abcdef/")
        // Firefox: the manifest's path and the add-on id
        let manifest = "/Users/me/Library/Application Support/Mozilla/NativeMessagingHosts/io.github.greenshot_mac.host.json"
        #expect(BrowserNativeHost.extensionOrigin(arguments: [host, manifest, "companion@greenshot-mac.github.io"]) == "companion@greenshot-mac.github.io")
        #expect(BrowserNativeHost.extensionOrigin(arguments: [host, manifest, "{0b1c2d3e-0000-0000-0000-000000000000}"]) == "{0b1c2d3e-0000-0000-0000-000000000000}")
        // Anything else isn't a browser
        #expect(BrowserNativeHost.extensionOrigin(arguments: [host]) == nil)
        #expect(BrowserNativeHost.extensionOrigin(arguments: [host, "--help"]) == nil)
        #expect(BrowserNativeHost.extensionOrigin(arguments: [host, manifest, "plain-id"]) == nil)
        #expect(BrowserNativeHost.extensionOrigin(arguments: [host, "file.txt", "a@b"]) == nil)
        #expect(BrowserNativeHost.extensionOrigin(arguments: [host, manifest, "a@b", "extra"]) == nil)
    }

    // MARK: Relay

    @Test func helloThenMessagesBothWays() async throws {
        let recorder = Recorder()
        let server = try makeServer(recorder)
        defer { server.stop() }
        let pipes = Pipes()
        defer { pipes.closeAll() }
        let socketPath = server.configuration.socketPath
        let (input, output) = (pipes.input[0], pipes.output[1])
        async let exitCode = onOwnThread {
            BrowserNativeHost.run(origin: "chrome-extension://abcdef/", socketPath: socketPath, clientVersion: "1",
                                  input: input, output: output)
        }

        try write(#"{"source":"cli","command":"HANDSHAKE","extension_version":"1.0.0","browser":"chrome"}"#, to: pipes.input[1])
        let reply = try #require(await readFrame(pipes.output[0]))
        #expect(reply["status"]?.stringValue == "ready")
        #expect(reply["greenshot_version"]?.stringValue == "9.9")

        // The browser closes the port: the relay ends
        pipes.closeInputWriter()
        let code = await exitCode
        #expect(code == 0)
        // The connection was announced as the browser's, whatever the message claimed
        let seen = recorder.all
        #expect(seen.count == 1)
        #expect(seen.first?.0 == .nativeMessaging)
        #expect(seen.first?.1 == "chrome-extension://abcdef/")
    }

    @Test func theAppClosingEndsTheRelay() async throws {
        let server = try makeServer(Recorder())
        let pipes = Pipes()
        defer { pipes.closeAll() }
        let socketPath = server.configuration.socketPath
        let (input, output) = (pipes.input[0], pipes.output[1])
        async let exitCode = onOwnThread {
            BrowserNativeHost.run(origin: "companion@greenshot-mac.github.io", socketPath: socketPath, clientVersion: "1",
                                  input: input, output: output)
        }
        try write(#"{"command":"HANDSHAKE"}"#, to: pipes.input[1])
        _ = await readFrame(pipes.output[0])

        // The app quits: watching clients hear it, then the connection ends, and so does the host
        server.notifyShutdown(reason: IPCServer.shutdownReasonExit, timeout: 1)
        server.stop()
        let code = await exitCode
        #expect(code == 0)
    }

    @Test func aBrokenFrameFromTheBrowserEndsTheRelay() async throws {
        let server = try makeServer(Recorder())
        defer { server.stop() }
        let pipes = Pipes()
        defer { pipes.closeAll() }
        let socketPath = server.configuration.socketPath
        let (input, output) = (pipes.input[0], pipes.output[1])
        async let exitCode = onOwnThread {
            BrowserNativeHost.run(origin: "chrome-extension://abcdef/", socketPath: socketPath, clientVersion: "1",
                                  input: input, output: output)
        }
        // A frame of one byte: shorter than any JSON object
        try IPCFrameIO.writeFrame(pipes.input[1], Data("x".utf8))
        let code = await exitCode
        #expect(code == 0)
    }

    @Test func offlineAnswerWhenTheAppIsNotRunning() async throws {
        let pipes = Pipes()
        defer { pipes.closeAll() }
        let missing = FileManager.default.temporaryDirectory.appendingPathComponent("gs-nh-missing-\(UUID().uuidString.prefix(8)).ipc").path
        let output = pipes.output[1]
        let code = await onOwnThread {
            BrowserNativeHost.run(origin: "chrome-extension://abcdef/", socketPath: missing, clientVersion: "1",
                                  input: STDIN_FILENO, output: output)
        }
        #expect(code == 0)
        let reply = try #require(await readFrame(pipes.output[0]))
        #expect(reply["status"]?.stringValue == "unavailable")
        #expect(reply["greenshot_running"]?.boolValue == false)
        #expect(reply["retry"]?.boolValue == true)
    }
}
