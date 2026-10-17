// Greenshot for Mac (Community) - an unofficial macOS port of Greenshot
// Copyright (C) 2026 Greenshot for Mac (Community) contributors
// Based on Greenshot, Copyright (C) 2007-2026 Thomas Braun, Jens Klingen, Robin Krom
// SPDX-License-Identifier: GPL-3.0-or-later

import Darwin
import Foundation

/// A connection to the app's automation socket, for greenshot-cli and a second start of the app (upstream
/// `greenshot-proxy/pipe_utils.c`, `protocol.c`, `Ipc/NamedPipeClient.cs`).
public final class IPCClient {
    public let fd: Int32
    private var closed = false

    private init(fd: Int32) {
        self.fd = fd
    }

    deinit { close() }

    /// Connects once; throws when nothing listens.
    public static func connect(to path: String) throws -> IPCClient {
        IPCClient(fd: try IPCSocket.connect(to: path))
    }

    /// Tries to connect until `timeout` passes (upstream `ConnectToGreenshotPipe`): the app may still be starting.
    public static func connect(to path: String, waitingUpTo timeout: TimeInterval, interval: TimeInterval = 0.1) -> IPCClient? {
        let deadline = Date().addingTimeInterval(timeout)
        while true {
            if let client = try? connect(to: path) { return client }
            if Date() >= deadline { return nil }
            usleep(useconds_t(max(0.01, interval) * 1_000_000))
        }
    }

    public func send(_ envelope: IPCEnvelope) throws {
        try IPCFrameIO.writeFrame(fd, IPCJSON.data(envelope.jsonObject))
    }

    /// The next frame; nil when the app closed the connection.
    public func readFrame() throws -> Data? {
        try IPCFrameIO.readFrame(fd, minimum: 1)
    }

    /// The next frame up to `maximum` bytes (greenshot-mcp: `IPCFrame.maximumReplyLength` for captures); nil when the app
    /// closed the connection.
    public func readFrame(maximum: Int) throws -> Data? {
        try IPCFrameIO.readFrame(fd, minimum: 1, maximum: maximum)
    }

    /// The next frame as a JSON object; nil when the app closed the connection. Throws for a frame that isn't one.
    public func readObject(maximum: Int = IPCFrame.maximumLength) throws -> JSONObject? {
        guard let payload = try readFrame(maximum: maximum) else { return nil }
        guard let object = IPCJSON.parseObject(payload) else { throw IPCIOError.invalidJSON }
        return object
    }

    /// Sends a JSON object as one frame (greenshot-mcp builds its requests as objects).
    public func send(object: JSONObject) throws {
        try IPCFrameIO.writeFrame(fd, IPCJSON.data(object))
    }

    /// 0 waits forever.
    public func setReadTimeout(_ seconds: TimeInterval) {
        IPCSocket.setTimeout(fd, option: SO_RCVTIMEO, seconds: seconds)
    }

    public func close() {
        guard !closed else { return }
        closed = true
        Darwin.close(fd)
    }

    /// Reads text frames until the exit frame and returns its code (upstream `ReceiveTextReply`); 'O' and 'E' go to
    /// `stdout` and `stderr`. A broken connection or frame writes its message to `stderr` and gives 1.
    public func receiveTextReply(stdout: (Data) -> Void, stderr: (Data) -> Void) -> Int32 {
        Self.readTextReply(next: { try self.readFrame() }, stdout: stdout, stderr: stderr)
    }

    public static let closedEarlyMessage = "Error: the connection to Greenshot was closed before a result was received.\n"
    public static let invalidResponseMessage = "Error: received an invalid response from Greenshot.\n"

    public static func readTextReply(next: () throws -> Data?, stdout: (Data) -> Void, stderr: (Data) -> Void) -> Int32 {
        while true {
            let payload: Data?
            do {
                payload = try next()
            } catch IPCIOError.invalidLength {
                stderr(Data(invalidResponseMessage.utf8))
                return IPCExitCode.failure
            } catch {
                stderr(Data(closedEarlyMessage.utf8))
                return IPCExitCode.failure
            }
            guard let payload else {
                stderr(Data(closedEarlyMessage.utf8))
                return IPCExitCode.failure
            }
            switch IPCTextFrame(payload: payload) {
            case .stdout(let text): stdout(text)
            case .stderr(let text): stderr(text)
            case .exit(let code): return code
            case nil:
                stderr(Data(invalidResponseMessage.utf8))
                return IPCExitCode.failure
            }
        }
    }

    /// `--exit` and `--reload` have nothing to do when the app isn't running, so they don't start it (upstream
    /// Greenshot.exe's behaviour for them).
    public static func startsApp(for argv: [String]) -> Bool {
        guard let first = argv.first else { return true }
        return !["--exit", "--reload"].contains(first.lowercased())
    }
}
