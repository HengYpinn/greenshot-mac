// Greenshot for Mac (Community) - an unofficial macOS port of Greenshot
// Copyright (C) 2026 Greenshot for Mac (Community) contributors
// SPDX-License-Identifier: GPL-3.0-or-later

import Darwin
import Foundation
import Testing
@testable import GreenshotCore

/// Upstream `NamedPipeIpcTests`: a real socket in a temporary folder, the test process on both ends. The server runs
/// its handlers as tasks on the cooperative pool, so the tests never block a pool thread while they wait for an answer:
/// replies are read with `offPool` and polling sleeps with `Task.sleep`.
@Suite(.serialized)
struct IPCServerTests {
    private struct Failure: Error {}

    /// How long a client waits for a frame: only a guard against a hang. A reply needs a pool thread for its handler,
    /// and while the whole test run starts that may take seconds to come free (CI runners have 3).
    private static let readTimeout: TimeInterval = 30

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
        client.setReadTimeout(Self.readTimeout)
        try client.send(.hello(source: source, replyFormat: format, client: "tests", clientVersion: "1"))
        return client
    }

    /// The text reply to the request sent last, up to its exit frame: stdout, stderr, exit code.
    private func textReply(_ client: IPCClient) async throws -> (out: Data, err: Data, code: Int32) {
        try await offPool {
            var out = Data()
            var err = Data()
            let code = client.receiveTextReply(stdout: { out.append($0) }, stderr: { err.append($0) })
            return (out, err, code)
        }
    }

    /// Text reply of one command line: stdout, stderr, exit code.
    private func run(_ argv: [String], on server: IPCServer) async throws -> (out: String, err: String, code: Int32) {
        let client = try connect(server)
        defer { client.close() }
        try client.send(.commandLine(argv, cwd: "/tmp"))
        let reply = try await textReply(client)
        return (String(decoding: reply.out, as: UTF8.self), String(decoding: reply.err, as: UTF8.self), reply.code)
    }

    private func readFrame(_ client: IPCClient) async throws -> Data? {
        try await offPool { try client.readFrame() }
    }

    private func nextObject(_ client: IPCClient) async throws -> JSONObject {
        guard let frame = try await readFrame(client), let object = IPCJSON.parseObject(frame) else { throw Failure() }
        return object
    }

    /// Polls about 5 seconds, giving the thread back between checks (a handler may need it).
    private func waitUntil(_ condition: () -> Bool) async -> Bool {
        for _ in 0..<100 {
            if condition() { return true }
            try? await Task.sleep(for: .milliseconds(50))
        }
        return condition()
    }

    /// Polls 5 seconds, blocking: only in `offPool`, for what the server's own threads do.
    private static func pollBlocking(_ condition: () -> Bool) -> Bool {
        for _ in 0..<100 {
            if condition() { return true }
            usleep(50_000)
        }
        return condition()
    }

    @Test func endToEndCommandLine() async throws {
        let server = try makeServer()
        defer { server.stop() }
        let version = try await run(["--version"], on: server)
        #expect(version.out == "Greenshot for Mac version 9.9\n")
        #expect(version.code == 0)
        let open = try await run(["a.png", "b.png"], on: server)
        #expect(open.out == "opening 2\nOpened 2 file(s).\n")
        let usage = try await run(["--bogus"], on: server)
        #expect(usage.code == 2)
        #expect(usage.err.contains("unrecognized option '--bogus'"))
    }

    @Test func replyAlwaysEndsWithExactlyOneExitFrame() async throws {
        let server = try makeServer()
        defer { server.stop() }
        let failing = try await run(["--reload"], on: server)
        #expect(failing.code == 1)
        #expect(failing.err.contains("Greenshot failed to handle the command"))
        let silent = try await run(["--exit"], on: server)
        #expect(silent.code == 0)
        #expect(silent.out.isEmpty)

        // Two requests on one connection: each ends with its own exit frame
        let client = try connect(server)
        defer { client.close() }
        try client.send(.commandLine(["--version"], cwd: nil))
        try client.send(.commandLine(["--exit"], cwd: nil))
        let first = try await textReply(client).code
        let second = try await textReply(client).code
        #expect(first == 0)
        #expect(second == 0)
    }

    @Test func jsonRequestPrintsOneDocument() async throws {
        let server = try makeServer()
        defer { server.stop() }
        let client = try connect(server)
        defer { client.close() }
        var envelope = IPCEnvelope(command: IPCCommand.version)
        envelope.json = true
        try client.send(envelope)
        let reply = try await textReply(client)
        #expect(reply.code == 0)
        let document = try #require(IPCJSON.parseObject(reply.out))
        #expect(document["version"] == .string("9.9"))
    }

    @Test func connectionWithoutHelloIsRejected() async throws {
        let server = try makeServer()
        defer { server.stop() }
        let client = try IPCClient.connect(to: server.configuration.socketPath)
        client.setReadTimeout(Self.readTimeout)
        defer { client.close() }
        try client.send(IPCEnvelope(command: IPCCommand.exit, source: "cli"))
        let object = try await nextObject(client)
        #expect(object["status"] == .string("error"))
        #expect(object.ipcString("stderr")?.contains("first message must be HELLO") == true)
        let next = try await readFrame(client)
        #expect(next == nil)
    }

    @Test func unknownSourceOrReplyFormatIsRejected() async throws {
        let server = try makeServer()
        defer { server.stop() }
        let foreign = try connect(server, format: .text, source: .nativeMessaging)
        defer { foreign.close() }
        let code = try await textReply(foreign).code
        #expect(code == 1)

        let client = try IPCClient.connect(to: server.configuration.socketPath)
        client.setReadTimeout(Self.readTimeout)
        defer { client.close() }
        var hello = IPCEnvelope.hello(source: .cli, replyFormat: .json, client: "tests", clientVersion: "1")
        hello.replyFormat = "xml"
        try client.send(hello)
        let rejection = try await nextObject(client)
        #expect(IPCJSON.text(rejection).contains("unknown reply format"))
    }

    @Test func repeatedHelloClosesTheConnection() async throws {
        let server = try makeServer()
        defer { server.stop() }
        let client = try connect(server)
        defer { client.close() }
        try client.send(.hello(source: .cli, replyFormat: .text, client: "tests", clientVersion: "1"))
        let reply = try await textReply(client)
        #expect(reply.code == 1)
        #expect(String(decoding: reply.err, as: UTF8.self).contains("HELLO is only allowed as the first message"))
    }

    @Test func sourceIsBoundFromHelloNotFromLaterEnvelopes() async throws {
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
        _ = try await textReply(client)
        #expect(seen.source == .cli)
        #expect(seen.claimed == "cli")
    }

    @Test func verifierDecidesBeforeAnyRequest() async throws {
        let server = try makeServer { $0.verifier = { _, source in source == .cli ? "not one of ours" : nil } }
        defer { server.stop() }
        let client = try connect(server)
        defer { client.close() }
        let reply = try await textReply(client)
        #expect(reply.code == 1)
        #expect(String(decoding: reply.err, as: UTF8.self).contains("[SECURITY] Connection rejected: not one of ours"))
    }

    @Test func verificationAndHandlersRunOffTheMainThread() async throws {
        let threads = ThreadRecorder()
        let server = try makeServer { configuration in
            configuration.verifier = { _, _ in
                threads.record(Thread.isMainThread)
                return nil
            }
        }
        defer { server.stop() }
        server.dispatcher.table.register(IPCCommand.about) { _ in
            threads.record(Thread.isMainThread)
            return .ok()
        }
        _ = try await run(["greenshotmac://about"], on: server)
        #expect(threads.values == [false, false])
    }

    @Test func peerIsThisProcess() async throws {
        let recorder = PeerRecorder()
        let server = try makeServer { configuration in
            configuration.verifier = { peer, _ in
                recorder.record(peer)
                return nil
            }
        }
        defer { server.stop() }
        _ = try await run(["--version"], on: server)
        let peer = try #require(recorder.peer)
        #expect(peer.uid == geteuid())
        #expect(peer.pid == getpid())
        #expect(peer.auditToken?.count == MemoryLayout<audit_token_t>.size)
    }

    @Test func watchConnectionGetsEventsAndTheShutdown() async throws {
        let server = try makeServer()
        defer { server.stop() }
        let client = try connect(server, format: .json)
        defer { client.close() }
        try client.send(IPCEnvelope(command: IPCCommand.watch))
        let watching = try await nextObject(client)
        #expect(watching["watching"] == .bool(true))

        server.broadcast(["event": .string("tools_changed")])
        let event = try await nextObject(client)
        #expect(event["event"] == .string("tools_changed"))

        // notifyShutdown waits (up to a second) for the message to go out
        try await offPool { server.notifyShutdown(reason: IPCServer.shutdownReasonExit) }
        let shutdown = try await nextObject(client)
        #expect(shutdown["event"] == .string("shutdown"))
        #expect(shutdown["reason"] == .string("exit"))
        #expect(shutdown["greenshot_running"] == .bool(false))
    }

    @Test func oversizedFrameClosesTheConnection() async throws {
        let server = try makeServer()
        defer { server.stop() }
        let client = try connect(server)
        defer { client.close() }
        try IPCFrameIO.writeAll(client.fd, Data([0xFF, 0xFF, 0xFF, 0x7F]))
        let next = try await readFrame(client)
        #expect(next == nil)
        #expect(await waitUntil { server.connectionCount == 0 })
    }

    @Test func helloLargerThanItsCapClosesTheConnection() async throws {
        let server = try makeServer()
        defer { server.stop() }
        let client = try IPCClient.connect(to: server.configuration.socketPath)
        client.setReadTimeout(Self.readTimeout)
        defer { client.close() }
        var hello = IPCEnvelope.hello(source: .cli, replyFormat: .text, client: "tests", clientVersion: "1")
        hello.extra = ["padding": .string(String(repeating: "x", count: IPCFrame.maximumHelloLength))]
        // The server closes after the length prefix, maybe while the rest is still being written
        _ = try? await offPool { [hello] in try client.send(hello) }
        let next = try? await readFrame(client)
        #expect(next == nil)
        #expect(await waitUntil { server.connectionCount == 0 })
    }

    @Test func slowHelloIsClosedAtItsDeadline() async throws {
        let server = try makeServer { $0.helloTimeout = 0.5 }
        defer { server.stop() }
        let client = try IPCClient.connect(to: server.configuration.socketPath)
        defer { client.close() }
        let frame = IPCFrame.encode(IPCJSON.data(IPCEnvelope.hello(source: .cli, replyFormat: .text, client: "tests",
                                                                   clientVersion: "1").jsonObject))
        // A byte every 100 ms: more than the deadline in all, never a pause as long as it
        let trickle = TrickleWriter(fd: client.fd, bytes: Array(frame.prefix(30)), pause: 100_000)
        // Watched from a thread of its own, so the time measured is the server's (its connection thread enforces the
        // deadline), not how long this test waits for a pool thread
        let watched = try await offPool { () -> (opened: Bool, closed: Bool, elapsed: TimeInterval) in
            let started = Date()
            trickle.start()
            let opened = Self.pollBlocking { server.connectionCount == 1 }
            let closed = Self.pollBlocking { server.connectionCount == 0 }
            return (opened, closed, Date().timeIntervalSince(started))
        }
        #expect(watched.opened)
        #expect(watched.closed)
        // Closed at the deadline, long before the 3 seconds of trickling end
        #expect(watched.elapsed < 2)
        // The writer ends before the descriptor is closed (it would write into the next test's socket)
        try await offPool { trickle.stop() }
    }

    @Test func largeRequestAfterHelloIsRead() async throws {
        let server = try makeServer()
        defer { server.stop() }
        let client = try connect(server)
        defer { client.close() }
        var envelope = IPCEnvelope(command: IPCCommand.version)
        envelope.extra = ["padding": .string(String(repeating: "y", count: 300_000))]
        // More than the socket buffers: the write waits for the server to read
        try await offPool { [envelope] in try client.send(envelope) }
        let reply = try await textReply(client)
        #expect(reply.code == 0)
        #expect(String(decoding: reply.out, as: UTF8.self).contains("9.9"))
    }

    @Test func clientClosingEarlyDoesNotHurtTheServer() async throws {
        let server = try makeServer()
        defer { server.stop() }
        for _ in 0..<5 {
            let client = try connect(server)
            try client.send(.commandLine(["a.png"], cwd: nil))
            client.close()
        }
        #expect(await waitUntil { server.connectionCount == 0 })
        let version = try await run(["--version"], on: server)
        #expect(version.code == 0)
    }

    @Test func clientThatDoesNotReadIsDisconnected() async throws {
        let server = try makeServer { $0.writeTimeout = 0.5 }
        defer { server.stop() }
        let client = try connect(server)
        defer { client.close() }
        // FIRST_LAUNCH streams 4 MB here, far more than the socket buffers
        try client.send(IPCEnvelope(command: IPCCommand.firstLaunch))
        #expect(await waitUntil { server.connectionCount == 0 })
    }

    /// The app forgets the browser extension's tab when its connection ends: the server says which identified
    /// connection ended, and which program was behind it. A connection without HELLO isn't reported.
    @Test func theEndOfAnIdentifiedConnectionIsReported() async throws {
        let ended = EndRecorder()
        let server = try makeServer {
            $0.acceptedSources = [.cli, .nativeMessaging]
            $0.connectionEnded = { source, peer in ended.record(source, pid: peer.pid) }
        }
        defer { server.stop() }
        let anonymous = try IPCClient.connect(to: server.configuration.socketPath)
        #expect(await waitUntil { server.connectionCount == 1 })
        anonymous.close()
        #expect(await waitUntil { server.connectionCount == 0 })
        let client = try connect(server, format: .json, source: .nativeMessaging)
        client.close()
        #expect(await waitUntil { server.connectionCount == 0 })
        let recorded = ended.values
        #expect(recorded.map(\.source) == [.nativeMessaging])
        #expect(recorded.map(\.pid) == [getpid()])
    }

    @Test func connectionsAreLimited() async throws {
        let server = try makeServer { $0.maxConnections = 2 }
        defer { server.stop() }
        let first = try IPCClient.connect(to: server.configuration.socketPath)
        let second = try IPCClient.connect(to: server.configuration.socketPath)
        #expect(await waitUntil { server.connectionCount == 2 })
        let third = try IPCClient.connect(to: server.configuration.socketPath)
        third.setReadTimeout(Self.readTimeout)
        let refused = try await readFrame(third)
        #expect(refused == nil)
        [first, second, third].forEach { $0.close() }
    }

    @Test func stopRemovesTheSocketAndRebindRestoresIt() async throws {
        let server = try makeServer()
        let path = server.configuration.socketPath
        #expect(FileManager.default.fileExists(atPath: path))
        #expect(!server.rebindIfNeeded())
        unlink(path)
        #expect(server.rebindIfNeeded())
        let version = try await run(["--version"], on: server)
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

private final class ThreadRecorder: @unchecked Sendable {
    private let lock = NSLock()
    private var recorded: [Bool] = []

    var values: [Bool] {
        lock.lock()
        defer { lock.unlock() }
        return recorded
    }

    func record(_ isMain: Bool) {
        lock.lock()
        recorded.append(isMain)
        lock.unlock()
    }
}

private final class EndRecorder: @unchecked Sendable {
    private let lock = NSLock()
    private var recorded: [(source: IPCSource, pid: pid_t)] = []

    var values: [(source: IPCSource, pid: pid_t)] {
        lock.lock()
        defer { lock.unlock() }
        return recorded
    }

    func record(_ source: IPCSource, pid: pid_t) {
        lock.lock()
        recorded.append((source, pid))
        lock.unlock()
    }
}
