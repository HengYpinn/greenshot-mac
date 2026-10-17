// Greenshot for Mac (Community) - an unofficial macOS port of Greenshot
// Copyright (C) 2026 Greenshot for Mac (Community) contributors
// SPDX-License-Identifier: GPL-3.0-or-later

import Darwin
import Foundation
import Testing
@testable import GreenshotCore

/// Upstream `NamedPipeIpcTests`: a real socket in a temporary folder, the test process on both ends.
@Suite(.serialized)
struct IPCServerTests {
    private struct Failure: Error {}

    private func makeServer(configure: (inout IPCServer.Configuration) -> Void = { _ in }) throws -> IPCServer {
        let path = FileManager.default.temporaryDirectory.appendingPathComponent("gs-\(UUID().uuidString.prefix(8)).ipc").path
        var configuration = IPCServer.Configuration(socketPath: path)
        configuration.helloTimeout = 5
        configure(&configuration)
        let dispatcher = IPCDispatcher()
        dispatcher.table.register(IPCCommand.version) { _ in .ok("Greenshot for Mac version 9.9", extra: ["version": .string("9.9")]) }
        dispatcher.table.register(IPCCommand.openFile) { context in
            context.stream("opening \(context.envelope.files.count)", to: .stdout)
            return .ok("Opened \(context.envelope.files.count) file(s).")
        }
        dispatcher.table.register(IPCCommand.reloadConfig) { _ in throw Failure() }
        dispatcher.table.register(IPCCommand.exit) { _ in nil }
        dispatcher.table.register(IPCCommand.firstLaunch) { context in
            for index in 0..<64 { context.stream(String(repeating: "x", count: 65_536) + "\(index)", to: .stdout) }
            return .ok()
        }
        let server = IPCServer(configuration: configuration, dispatcher: dispatcher)
        try server.start()
        return server
    }

    private func connect(_ server: IPCServer, format: IPCReplyFormat = .text, source: IPCSource = .cli) throws -> IPCClient {
        let client = try IPCClient.connect(to: server.configuration.socketPath)
        client.setReadTimeout(5)
        try client.send(.hello(source: source, replyFormat: format, client: "tests", clientVersion: "1"))
        return client
    }

    /// Text reply of one command line: stdout, stderr, exit code.
    private func run(_ argv: [String], on server: IPCServer) throws -> (out: String, err: String, code: Int32) {
        let client = try connect(server)
        defer { client.close() }
        try client.send(.commandLine(argv, cwd: "/tmp"))
        var out = Data()
        var err = Data()
        let code = client.receiveTextReply(stdout: { out.append($0) }, stderr: { err.append($0) })
        return (String(decoding: out, as: UTF8.self), String(decoding: err, as: UTF8.self), code)
    }

    private func nextObject(_ client: IPCClient) throws -> JSONObject {
        guard let frame = try client.readFrame(), let object = IPCJSON.parseObject(frame) else { throw Failure() }
        return object
    }

    private func waitUntil(_ condition: () -> Bool) -> Bool {
        for _ in 0..<100 {
            if condition() { return true }
            usleep(50_000)
        }
        return condition()
    }

    @Test func endToEndCommandLine() throws {
        let server = try makeServer()
        defer { server.stop() }
        let version = try run(["--version"], on: server)
        #expect(version.out == "Greenshot for Mac version 9.9\n")
        #expect(version.code == 0)
        let open = try run(["a.png", "b.png"], on: server)
        #expect(open.out == "opening 2\nOpened 2 file(s).\n")
        let usage = try run(["--bogus"], on: server)
        #expect(usage.code == 2)
        #expect(usage.err.contains("unrecognized option '--bogus'"))
    }

    @Test func replyAlwaysEndsWithExactlyOneExitFrame() throws {
        let server = try makeServer()
        defer { server.stop() }
        let failing = try run(["--reload"], on: server)
        #expect(failing.code == 1)
        #expect(failing.err.contains("Greenshot failed to handle the command"))
        let silent = try run(["--exit"], on: server)
        #expect(silent.code == 0)
        #expect(silent.out.isEmpty)

        // Two requests on one connection: each ends with its own exit frame
        let client = try connect(server)
        defer { client.close() }
        try client.send(.commandLine(["--version"], cwd: nil))
        try client.send(.commandLine(["--exit"], cwd: nil))
        let first = client.receiveTextReply(stdout: { _ in }, stderr: { _ in })
        let second = client.receiveTextReply(stdout: { _ in }, stderr: { _ in })
        #expect(first == 0)
        #expect(second == 0)
    }

    @Test func jsonRequestPrintsOneDocument() throws {
        let server = try makeServer()
        defer { server.stop() }
        let client = try connect(server)
        defer { client.close() }
        var envelope = IPCEnvelope(command: IPCCommand.version)
        envelope.json = true
        try client.send(envelope)
        var out = Data()
        let code = client.receiveTextReply(stdout: { out.append($0) }, stderr: { _ in })
        #expect(code == 0)
        let document = try #require(IPCJSON.parseObject(out))
        #expect(document["version"] == .string("9.9"))
    }

    @Test func connectionWithoutHelloIsRejected() throws {
        let server = try makeServer()
        defer { server.stop() }
        let client = try IPCClient.connect(to: server.configuration.socketPath)
        client.setReadTimeout(5)
        defer { client.close() }
        try client.send(IPCEnvelope(command: IPCCommand.exit, source: "cli"))
        let object = try nextObject(client)
        #expect(object["status"] == .string("error"))
        #expect(object.ipcString("stderr")?.contains("first message must be HELLO") == true)
        #expect(try client.readFrame() == nil)
    }

    @Test func unknownSourceOrReplyFormatIsRejected() throws {
        let server = try makeServer()
        defer { server.stop() }
        let foreign = try connect(server, format: .text, source: .nativeMessaging)
        defer { foreign.close() }
        let code = foreign.receiveTextReply(stdout: { _ in }, stderr: { _ in })
        #expect(code == 1)

        let client = try IPCClient.connect(to: server.configuration.socketPath)
        client.setReadTimeout(5)
        defer { client.close() }
        var hello = IPCEnvelope.hello(source: .cli, replyFormat: .json, client: "tests", clientVersion: "1")
        hello.replyFormat = "xml"
        try client.send(hello)
        let rejection = try nextObject(client)
        #expect(IPCJSON.text(rejection).contains("unknown reply format"))
    }

    @Test func repeatedHelloClosesTheConnection() throws {
        let server = try makeServer()
        defer { server.stop() }
        let client = try connect(server)
        defer { client.close() }
        try client.send(.hello(source: .cli, replyFormat: .text, client: "tests", clientVersion: "1"))
        var err = Data()
        let code = client.receiveTextReply(stdout: { _ in }, stderr: { err.append($0) })
        #expect(code == 1)
        #expect(String(decoding: err, as: UTF8.self).contains("HELLO is only allowed as the first message"))
    }

    @Test func sourceIsBoundFromHelloNotFromLaterEnvelopes() throws {
        let server = try makeServer()
        defer { server.stop() }
        let seen = SourceRecorder()
        server.dispatcher.table.register(IPCCommand.about) { context in
            seen.record(context.source, claimed: context.envelope.source)
            return .ok()
        }
        let client = try connect(server)
        defer { client.close() }
        try client.send(IPCEnvelope(command: IPCCommand.about, source: "native_messaging"))
        _ = client.receiveTextReply(stdout: { _ in }, stderr: { _ in })
        #expect(seen.source == .cli)
        #expect(seen.claimed == "cli")
    }

    @Test func verifierDecidesBeforeAnyRequest() throws {
        let server = try makeServer { $0.verifier = { _, source in source == .cli ? "not one of ours" : nil } }
        defer { server.stop() }
        let client = try connect(server)
        defer { client.close() }
        var err = Data()
        let code = client.receiveTextReply(stdout: { _ in }, stderr: { err.append($0) })
        #expect(code == 1)
        #expect(String(decoding: err, as: UTF8.self).contains("[SECURITY] Connection rejected: not one of ours"))
    }

    @Test func peerIsThisProcess() throws {
        let recorder = PeerRecorder()
        let server = try makeServer { configuration in
            configuration.verifier = { peer, _ in
                recorder.record(peer)
                return nil
            }
        }
        defer { server.stop() }
        _ = try run(["--version"], on: server)
        let peer = try #require(recorder.peer)
        #expect(peer.uid == geteuid())
        #expect(peer.pid == getpid())
        #expect(peer.auditToken?.count == MemoryLayout<audit_token_t>.size)
    }

    @Test func watchConnectionGetsEventsAndTheShutdown() throws {
        let server = try makeServer()
        defer { server.stop() }
        let client = try connect(server, format: .json)
        defer { client.close() }
        try client.send(IPCEnvelope(command: IPCCommand.watch))
        let watching = try nextObject(client)
        #expect(watching["watching"] == .bool(true))

        server.broadcast(["event": .string("tools_changed")])
        let event = try nextObject(client)
        #expect(event["event"] == .string("tools_changed"))

        server.notifyShutdown(reason: IPCServer.shutdownReasonExit)
        let shutdown = try nextObject(client)
        #expect(shutdown["event"] == .string("shutdown"))
        #expect(shutdown["reason"] == .string("exit"))
        #expect(shutdown["greenshot_running"] == .bool(false))
    }

    @Test func oversizedFrameClosesTheConnection() throws {
        let server = try makeServer()
        defer { server.stop() }
        let client = try connect(server)
        defer { client.close() }
        try IPCFrameIO.writeAll(client.fd, Data([0xFF, 0xFF, 0xFF, 0x7F]))
        #expect(try client.readFrame() == nil)
        #expect(waitUntil { server.connectionCount == 0 })
    }

    @Test func helloLargerThanItsCapClosesTheConnection() throws {
        let server = try makeServer()
        defer { server.stop() }
        let client = try IPCClient.connect(to: server.configuration.socketPath)
        client.setReadTimeout(5)
        defer { client.close() }
        var hello = IPCEnvelope.hello(source: .cli, replyFormat: .text, client: "tests", clientVersion: "1")
        hello.extra = ["padding": .string(String(repeating: "x", count: IPCFrame.maximumHelloLength))]
        // The server closes after the length prefix, maybe while the rest is still being written
        _ = try? client.send(hello)
        let next = try? client.readFrame()
        #expect(next == nil)
        #expect(waitUntil { server.connectionCount == 0 })
    }

    @Test func slowHelloIsClosedAtItsDeadline() throws {
        let server = try makeServer { $0.helloTimeout = 0.5 }
        defer { server.stop() }
        let client = try IPCClient.connect(to: server.configuration.socketPath)
        defer { client.close() }
        let frame = IPCFrame.encode(IPCJSON.data(IPCEnvelope.hello(source: .cli, replyFormat: .text, client: "tests",
                                                                   clientVersion: "1").jsonObject))
        // A byte every 100 ms: more than the deadline in all, never a pause as long as it
        let fd = client.fd
        let trickle = Thread {
            for byte in frame.prefix(30) {
                var value = byte
                if Darwin.write(fd, &value, 1) != 1 { return }
                usleep(100_000)
            }
        }
        let started = Date()
        trickle.start()
        #expect(waitUntil { server.connectionCount == 1 })
        #expect(waitUntil { server.connectionCount == 0 })
        // Closed at the deadline, long before the 3 seconds of trickling end
        let elapsed = Date().timeIntervalSince(started)
        #expect(elapsed < 2)
    }

    @Test func largeRequestAfterHelloIsRead() throws {
        let server = try makeServer()
        defer { server.stop() }
        let client = try connect(server)
        defer { client.close() }
        var envelope = IPCEnvelope(command: IPCCommand.version)
        envelope.extra = ["padding": .string(String(repeating: "y", count: 300_000))]
        try client.send(envelope)
        var out = Data()
        let code = client.receiveTextReply(stdout: { out.append($0) }, stderr: { _ in })
        #expect(code == 0)
        #expect(String(decoding: out, as: UTF8.self).contains("9.9"))
    }

    @Test func clientClosingEarlyDoesNotHurtTheServer() throws {
        let server = try makeServer()
        defer { server.stop() }
        for _ in 0..<5 {
            let client = try connect(server)
            try client.send(.commandLine(["a.png"], cwd: nil))
            client.close()
        }
        #expect(waitUntil { server.connectionCount == 0 })
        let version = try run(["--version"], on: server)
        #expect(version.code == 0)
    }

    @Test func clientThatDoesNotReadIsDisconnected() throws {
        let server = try makeServer { $0.writeTimeout = 0.5 }
        defer { server.stop() }
        let client = try connect(server)
        defer { client.close() }
        // FIRST_LAUNCH streams 4 MB here, far more than the socket buffers
        try client.send(IPCEnvelope(command: IPCCommand.firstLaunch))
        #expect(waitUntil { server.connectionCount == 0 })
    }

    @Test func connectionsAreLimited() throws {
        let server = try makeServer { $0.maxConnections = 2 }
        defer { server.stop() }
        let first = try IPCClient.connect(to: server.configuration.socketPath)
        let second = try IPCClient.connect(to: server.configuration.socketPath)
        #expect(waitUntil { server.connectionCount == 2 })
        let third = try IPCClient.connect(to: server.configuration.socketPath)
        third.setReadTimeout(5)
        #expect(try third.readFrame() == nil)
        [first, second, third].forEach { $0.close() }
    }

    @Test func stopRemovesTheSocketAndRebindRestoresIt() throws {
        let server = try makeServer()
        let path = server.configuration.socketPath
        #expect(FileManager.default.fileExists(atPath: path))
        #expect(!server.rebindIfNeeded())
        unlink(path)
        #expect(server.rebindIfNeeded())
        let version = try run(["--version"], on: server)
        #expect(version.code == 0)
        server.stop()
        #expect(!FileManager.default.fileExists(atPath: path))
    }
}

private final class SourceRecorder: @unchecked Sendable {
    private let lock = NSLock()
    private(set) var source: IPCSource?
    private(set) var claimed: String?

    func record(_ source: IPCSource, claimed: String?) {
        lock.lock()
        self.source = source
        self.claimed = claimed
        lock.unlock()
    }
}

private final class PeerRecorder: @unchecked Sendable {
    private let lock = NSLock()
    private var recorded: IPCPeer?

    var peer: IPCPeer? {
        lock.lock()
        defer { lock.unlock() }
        return recorded
    }

    func record(_ peer: IPCPeer) {
        lock.lock()
        recorded = peer
        lock.unlock()
    }
}
