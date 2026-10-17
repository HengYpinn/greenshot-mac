// Greenshot for Mac (Community) - an unofficial macOS port of Greenshot
// Copyright (C) 2026 Greenshot for Mac (Community) contributors
// Based on Greenshot, Copyright (C) 2007-2026 Thomas Braun, Jens Klingen, Robin Krom
// SPDX-License-Identifier: GPL-3.0-or-later

import Foundation

/// Where the frames of a reply go: a connection of the server. Writes must not block the caller.
public protocol IPCFrameWriter: AnyObject, Sendable {
    func write(frame payload: Data)
}

/// A request and its reply (upstream `IpcRequestContext`). Handlers reply with JSON-shaped objects: streamed chunks and
/// one final reply. JSON connections get them as they are; text connections (greenshot-cli) get text frames, 'O' and
/// 'E' with UTF-8 text and exactly one 'X' with the exit code per request, also when the handler failed. With `--json`
/// the final reply goes out as one 'O' document. The app's own callers (links, AppleScript, ...) have no writer: they
/// read `finalReply`.
public final class IPCReplyContext: @unchecked Sendable {
    /// Shared by a request and the contexts derived from it (`with(envelope:)`), so the final reply is sent once.
    private final class State: @unchecked Sendable {
        let lock = NSLock()
        var completed = false
        var finalReply: IPCReply?
        var streamed: [(IPCStream, String)] = []
    }

    public let envelope: IPCEnvelope
    public let source: IPCSource
    /// The origin from the connection's HELLO (native messaging, wave 4).
    public let origin: String?
    public let peer: IPCPeer?
    public let usesTextFrames: Bool
    private let writer: IPCFrameWriter?
    private let state: State
    private let log = Log("IPC")

    public convenience init(envelope: IPCEnvelope, source: IPCSource, writer: IPCFrameWriter? = nil, usesTextFrames: Bool = false,
                origin: String? = nil, peer: IPCPeer? = nil) {
        self.init(envelope: envelope, source: source, writer: writer, usesTextFrames: usesTextFrames, origin: origin, peer: peer,
                  state: State())
    }

    private init(envelope: IPCEnvelope, source: IPCSource, writer: IPCFrameWriter?, usesTextFrames: Bool, origin: String?,
                 peer: IPCPeer?, state: State) {
        self.envelope = envelope
        self.source = source
        self.writer = writer
        self.usesTextFrames = usesTextFrames
        self.origin = origin
        self.peer = peer
        self.state = state
    }

    /// The same connection and reply with another envelope (e.g. the command parsed from a command line).
    public func with(envelope: IPCEnvelope) -> IPCReplyContext {
        IPCReplyContext(envelope: envelope, source: source, writer: writer, usesTextFrames: usesTextFrames, origin: origin,
                        peer: peer, state: state)
    }

    /// The final reply was sent (text connections: the exit frame).
    public var isCompleted: Bool {
        state.lock.lock()
        defer { state.lock.unlock() }
        return state.completed
    }

    /// The final reply, for the app's own callers.
    public var finalReply: IPCReply? {
        state.lock.lock()
        defer { state.lock.unlock() }
        return state.finalReply
    }

    /// The chunks streamed so far (for the app's own callers and tests).
    public var streamedText: [(IPCStream, String)] {
        state.lock.lock()
        defer { state.lock.unlock() }
        return state.streamed
    }

    /// Streams a chunk of output before the final reply (upstream `{"stream": ..., "text": ...}`).
    public func stream(_ text: String, to stream: IPCStream) {
        state.lock.lock()
        let completed = state.completed
        if !completed { state.streamed.append((stream, text)) }
        state.lock.unlock()
        guard !completed else { return }
        if usesTextFrames {
            if let frame = IPCTextFrame.text(text, to: stream) { writer?.write(frame: frame.payload) }
        } else {
            writer?.write(frame: IPCJSON.data(["stream": .string(stream.rawValue), "text": .string(text)]))
        }
    }

    /// Sends the final reply; a second one is ignored.
    public func reply(_ reply: IPCReply) {
        state.lock.lock()
        if state.completed {
            state.lock.unlock()
            log.warn("Ignoring an additional final reply for a request that already completed.")
            return
        }
        state.completed = true
        state.finalReply = reply
        state.lock.unlock()

        guard let writer else { return }
        guard usesTextFrames else {
            writer.write(frame: IPCJSON.data(reply.jsonObject))
            return
        }
        if envelope.json {
            // --json: the reply object is the result document
            writer.write(frame: IPCTextFrame.stdout(Data((IPCJSON.text(reply.jsonObject) + "\n").utf8)).payload)
        } else {
            if let frame = IPCTextFrame.text(reply.stdout, to: .stdout) { writer.write(frame: frame.payload) }
            if let frame = IPCTextFrame.text(reply.stderr, to: .stderr) { writer.write(frame: frame.payload) }
        }
        var exitCode = reply.exitCode
        if exitCode == IPCExitCode.ok, reply.isError { exitCode = IPCExitCode.failure }
        writer.write(frame: IPCTextFrame.exit(exitCode).payload)
    }

    /// Text connections: the exit frame, unless the reply was completed already (commands without a reply). Nothing for
    /// JSON connections.
    public func complete(exitCode: Int32 = IPCExitCode.ok) {
        state.lock.lock()
        let send = !state.completed && usesTextFrames
        if usesTextFrames { state.completed = true }
        state.lock.unlock()
        if send { writer?.write(frame: IPCTextFrame.exit(exitCode).payload) }
    }

    /// A message outside the request-reply flow (an event, a rejection): JSON as it is, or on a text connection its
    /// `stderr` text.
    public func send(_ object: JSONObject) {
        guard let writer else { return }
        if usesTextFrames {
            if let frame = IPCTextFrame.text(object.ipcString("stderr"), to: .stderr) { writer.write(frame: frame.payload) }
        } else {
            writer.write(frame: IPCJSON.data(object))
        }
    }
}
