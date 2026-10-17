// Greenshot for Mac (Community) - an unofficial macOS port of Greenshot
// Copyright (C) 2026 Greenshot for Mac (Community) contributors
// Based on Greenshot, Copyright (C) 2007-2026 Thomas Braun, Jens Klingen, Robin Krom
// SPDX-License-Identifier: GPL-3.0-or-later

import Darwin
import Foundation
import GreenshotCore

/// A failure talking to the app, in words for the AI tool (upstream `GreenshotConnectionException`).
struct GreenshotConnectionError: LocalizedError {
    var message: String

    var errorDescription: String? { message }
}

/// What greenshot-mcp knows about the running app (upstream `GreenshotState`): the user quit it, so nothing starts it
/// again until it runs.
final class GreenshotState: @unchecked Sendable {
    static let shared = GreenshotState()
    private let lock = NSLock()
    private var closedByUser = false

    var isClosedByUser: Bool { lock.withLock { closedByUser } }

    /// The reason of the app's `shutdown` event: "exit" is the user quitting.
    func shuttingDown(reason: String?) {
        let reason = (reason ?? "exit").lowercased()
        lock.withLock { closedByUser = reason == IPCServer.shutdownReasonExit }
    }

    func connected() {
        lock.withLock { closedByUser = false }
    }
}

/// One request to the running app over its automation socket (upstream `Greenshot.Mcp/GreenshotConnection.cs`): HELLO
/// with the source `mcp`, the request, then frames until the final reply. Blocking socket I/O runs on its own queue, never
/// on the cooperative threads; a cancelled call closes its connection.
final class GreenshotConnection: @unchecked Sendable {
    let endpoint: IPCEndpoint
    let executable: String
    let version: String
    private let queue = DispatchQueue(label: "greenshot-mcp requests", attributes: .concurrent)

    init(endpoint: IPCEndpoint, executable: String, version: String) {
        self.endpoint = endpoint
        self.executable = executable
        self.version = version
    }

    /// Sends `request` and returns the app's final reply, with streamed text in `streamed_stdout` / `streamed_stderr`.
    /// `startApp`: start the app when it isn't running (tool calls; background requests never do).
    func send(_ request: JSONObject, client: String?, startApp: Bool = true) async throws -> JSONObject {
        let holder = ClientHolder()
        return try await withTaskCancellationHandler {
            try await withCheckedThrowingContinuation { continuation in
                queue.async {
                    continuation.resume(with: Result { try self.sendBlocking(request, client: client, startApp: startApp, holder: holder) })
                }
            }
        } onCancel: {
            holder.cancel()
        }
    }

    /// The blocking part of `send`, also for greenshot-mcp's own threads (the tool sync, with a `readTimeout` so a hung app
    /// doesn't stop it for good, MC-L6).
    func sendBlocking(_ request: JSONObject, client: String?, startApp: Bool, holder: ClientHolder = ClientHolder(),
                      readTimeout: TimeInterval = 0) throws -> JSONObject {
        let connection = try connect(startApp: startApp && !GreenshotState.shared.isClosedByUser, holder: holder)
        guard holder.set(connection) else {
            connection.close()
            throw CancellationError()
        }
        // The holder lets go before the descriptor is closed: a late cancellation can't shut another socket (MC-L1)
        defer {
            holder.finish()
            connection.close()
        }
        if readTimeout > 0 { connection.setReadTimeout(readTimeout) }
        try sendHello(connection, client: client)
        var message = request
        message["version"] = .number(Double(ipcProtocolVersion))
        message["source"] = .string(IPCSource.mcp.rawValue)
        try connection.send(object: message)
        var streamedStdout: [String] = []
        var streamedStderr: [String] = []
        while true {
            let frame: JSONObject?
            do {
                frame = try connection.readObject(maximum: IPCFrame.maximumReplyLength)
            } catch IPCIOError.invalidLength(let length) {
                throw GreenshotConnectionError(message: "Greenshot for Mac sent an invalid reply length (\(length)).")
            } catch IPCIOError.invalidJSON {
                throw GreenshotConnectionError(message: "Greenshot for Mac sent a reply which is not a JSON object.")
            } catch {
                if holder.isCancelled { throw CancellationError() }
                throw GreenshotConnectionError(message: "Greenshot for Mac closed the connection in the middle of a reply.")
            }
            guard var frame else {
                if holder.isCancelled { throw CancellationError() }
                throw GreenshotConnectionError(message: "Greenshot for Mac closed the connection without a reply.")
            }
            if let event = frame["event"]?.stringValue {
                // The app's own messages can arrive on any connection
                if event.lowercased() == "shutdown" {
                    GreenshotState.shared.shuttingDown(reason: frame["reason"]?.stringValue)
                    throw GreenshotConnectionError(message: "Greenshot for Mac is quitting, the request was not finished.")
                }
                continue
            }
            if let stream = frame["stream"]?.stringValue {
                let text = frame["text"]?.stringValue ?? ""
                if stream.lowercased() == "stderr" { streamedStderr.append(text) } else { streamedStdout.append(text) }
                continue
            }
            if !streamedStdout.isEmpty { frame["streamed_stdout"] = .string(streamedStdout.joined(separator: "\n")) }
            if !streamedStderr.isEmpty { frame["streamed_stderr"] = .string(streamedStderr.joined(separator: "\n")) }
            return frame
        }
    }

    /// A connection that stays open for the app's events (WATCH), without starting the app. Nil: the app isn't running,
    /// or it doesn't know WATCH (`isRunning` true).
    func openWatch() -> (connection: IPCClient?, isRunning: Bool) {
        guard let connection = try? IPCClient.connect(to: endpoint.socketPath) else { return (nil, false) }
        guard isGreenshot(connection) else {
            connection.close()
            return (nil, false)
        }
        do {
            try sendHello(connection, client: "greenshot-mcp")
            try connection.send(object: ["version": .number(Double(ipcProtocolVersion)), "command": .string(IPCCommand.watch),
                                         "source": .string(IPCSource.mcp.rawValue)])
            // The handshake has a time limit (MC-L6); the events then come whenever they come
            connection.setReadTimeout(10)
            if let reply = try connection.readObject(), reply["watching"]?.boolValue == true {
                connection.setReadTimeout(0)
                return (connection, true)
            }
        } catch {
            // Treated like an app without WATCH
        }
        connection.close()
        return (nil, true)
    }

    private func sendHello(_ connection: IPCClient, client: String?) throws {
        let origin = client.flatMap { $0.trimmingCharacters(in: .whitespaces).isEmpty ? nil : $0 } ?? "AI tool"
        try connection.send(.hello(source: .mcp, replyFormat: .json, client: "greenshot-mcp", clientVersion: version, origin: origin))
    }

    /// Connects; starts the app from its bundle when allowed. A development build (no bundle) never starts the app: start
    /// GreenshotMac first (upstream: a Debug greenshot-mcp can't start Greenshot either).
    private func connect(startApp: Bool, holder: ClientHolder) throws -> IPCClient {
        if let client = try? IPCClient.connect(to: endpoint.socketPath) { return try verified(client) }
        guard startApp, endpoint.appBundlePath != nil else {
            if GreenshotState.shared.isClosedByUser {
                throw GreenshotConnectionError(message: "Greenshot for Mac was closed by the user. Ask the user to start Greenshot for Mac to use these tools.")
            }
            throw GreenshotConnectionError(message: "Greenshot for Mac is not running. Please start Greenshot for Mac and try again.")
        }
        // A cancelled call doesn't start the app or keep waiting for it (MC-L8)
        guard let client = IPCAppLauncher.connectOrStart(endpoint: endpoint, executable: executable, timeout: 20,
                                                         shouldStop: { holder.isCancelled }) else {
            if holder.isCancelled { throw CancellationError() }
            throw GreenshotConnectionError(message: "Greenshot for Mac was started, but did not accept the connection in time. Please try again.")
        }
        return try verified(client)
    }

    private func verified(_ client: IPCClient) throws -> IPCClient {
        guard isGreenshot(client) else {
            client.close()
            throw GreenshotConnectionError(message: "The program listening on Greenshot for Mac's socket isn't Greenshot for Mac, so nothing was sent to it.")
        }
        return client
    }

    /// The app on the other end of the socket (security review note): the GreenshotMac this greenshot-mcp belongs to.
    func isGreenshot(_ client: IPCClient) -> Bool {
        IPCAppLauncher.isAppPeer(client, endpoint: endpoint, executable: executable)
    }
}

/// The connection of a running request, so a cancellation can close it (and end its blocking read). The shutdown runs
/// under the lock and only while the connection is set: `finish()` lets go before the descriptor is closed, so a late
/// cancellation can't hit a descriptor number another connection got meanwhile (MC-L1).
final class ClientHolder: @unchecked Sendable {
    private let lock = NSLock()
    private var client: IPCClient?
    private var cancelled = false

    var isCancelled: Bool { lock.withLock { cancelled } }

    /// False when the call was cancelled already (the caller closes the connection).
    func set(_ client: IPCClient) -> Bool {
        lock.withLock {
            guard !cancelled else { return false }
            self.client = client
            return true
        }
    }

    func finish() {
        lock.withLock { client = nil }
    }

    func cancel() {
        lock.withLock {
            cancelled = true
            if let client { Darwin.shutdown(client.fd, SHUT_RDWR) }
        }
    }
}
