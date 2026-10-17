// Greenshot for Mac (Community) - an unofficial macOS port of Greenshot
// Copyright (C) 2026 Greenshot for Mac (Community) contributors
// Based on Greenshot, Copyright (C) 2007-2026 Thomas Braun, Jens Klingen, Robin Krom
// SPDX-License-Identifier: GPL-3.0-or-later

import Darwin
import Foundation

/// The app's automation server (upstream `Ipc/NamedPipeServer.cs`) on a per-user unix domain socket. Every connection
/// starts with HELLO, which names its source and reply format; the source is checked against the program behind the
/// connection and then overrides whatever later envelopes claim. Requests of a connection run one after the other; each
/// connection has its own thread (blocking I/O, never the cooperative thread pool) and a serial write queue, so a client
/// that doesn't read can't hold up the app. JSON connections can WATCH for events and get the shutdown message.
public final class IPCServer: @unchecked Sendable {
    public struct Configuration: Sendable {
        public var socketPath: String
        /// The sources a client may announce (the app's own callers dispatch in-process). Wave 4 adds
        /// `native_messaging` and `mcp`.
        public var acceptedSources: Set<IPCSource> = [.cli]
        public var maxConnections = 16
        /// How long a new connection may take to send HELLO.
        public var helloTimeout: TimeInterval = 10
        /// How long a frame may wait for the client to read it before the connection is closed (upstream
        /// `ReplyWriteTimeout`, 2 minutes).
        public var writeTimeout: TimeInterval = 120
        /// Upstream's 64 KB out buffer (macOS may give a unix socket less).
        public var sendBufferSize: Int32 = 64 * 1024
        /// Checks the program behind a connection for the source it announced: nil to accept, else the reason. Without
        /// a verifier every program of the user is accepted (tests).
        public var verifier: (@Sendable (IPCPeer, IPCSource) -> String?)?
        /// Only processes of this user may connect.
        public var allowedUID: uid_t = geteuid()

        public init(socketPath: String) {
            self.socketPath = socketPath
        }
    }

    public static let watchCommand = IPCCommand.watch
    /// Shutdown reasons (upstream `ShutdownReason*`): the user quits, or the session ends.
    public static let shutdownReasonExit = "exit"
    public static let shutdownReasonSessionEnd = "session_end"

    public let configuration: Configuration
    public let dispatcher: IPCDispatcher
    private let lock = NSLock()
    private var listenFD: Int32 = -1
    private var socketIdentity: [UInt64]?
    private var wakePipe: [Int32] = [-1, -1]
    private var running = false
    private var connections: [ObjectIdentifier: Connection] = [:]
    fileprivate let log = Log("IPC")

    public init(configuration: Configuration, dispatcher: IPCDispatcher) {
        self.configuration = configuration
        self.dispatcher = dispatcher
    }

    deinit { stop() }

    public var isRunning: Bool {
        lock.lock()
        defer { lock.unlock() }
        return running
    }

    public var connectionCount: Int {
        lock.lock()
        defer { lock.unlock() }
        return connections.count
    }

    /// Binds the socket (removing a stale one: only the instance holding the instance lock starts a server) and starts
    /// accepting connections.
    public func start() throws {
        lock.lock()
        defer { lock.unlock() }
        guard !running else { return }
        let fd = try IPCSocket.listen(at: configuration.socketPath)
        var pipeFDs: [Int32] = [-1, -1]
        guard pipe(&pipeFDs) == 0 else {
            close(fd)
            throw IPCSocket.Failure(call: "pipe", code: errno)
        }
        for end in pipeFDs { _ = fcntl(end, F_SETFD, FD_CLOEXEC) }
        _ = fcntl(pipeFDs[0], F_SETFL, O_NONBLOCK)
        listenFD = fd
        socketIdentity = IPCSocket.fileIdentity(configuration.socketPath)
        wakePipe = pipeFDs
        running = true
        let thread = Thread { [weak self] in self?.acceptLoop() }
        thread.name = "IPC accept"
        thread.start()
        log.info("Listening for automation requests")
    }

    /// Stops accepting, ends every connection and removes the socket file (when it is still ours).
    public func stop() {
        lock.lock()
        guard running else {
            lock.unlock()
            return
        }
        running = false
        let fd = listenFD
        listenFD = -1
        let identity = socketIdentity
        let open = Array(connections.values)
        lock.unlock()

        wake()
        if fd >= 0 { close(fd) }
        if let identity, IPCSocket.fileIdentity(configuration.socketPath) == identity { unlink(configuration.socketPath) }
        open.forEach { $0.shutDown() }
    }

    /// The socket file is gone or replaced (the system cleans temporary folders): listens at a new one. True when it did.
    @discardableResult
    public func rebindIfNeeded() -> Bool {
        lock.lock()
        let needed = running && IPCSocket.fileIdentity(configuration.socketPath) != socketIdentity
        lock.unlock()
        guard needed else { return false }
        do {
            let fd = try IPCSocket.listen(at: configuration.socketPath)
            lock.lock()
            let old = listenFD
            listenFD = fd
            socketIdentity = IPCSocket.fileIdentity(configuration.socketPath)
            lock.unlock()
            wake()
            if old >= 0 { close(old) }
            log.warn("The automation socket was removed; listening again")
            return true
        } catch {
            log.error("Could not listen for automation requests again", error: error)
            return false
        }
    }

    /// Sends an event (e.g. `{"event":"tools_changed"}`) to every watching JSON connection, without waiting for them.
    public func broadcast(_ event: JSONObject) {
        let payload = IPCJSON.data(event)
        for connection in snapshot() where connection.isWatching {
            connection.write(frame: payload)
        }
    }

    /// Tells every JSON connection that the app quits and why (upstream `NotifyShutdownAsync`), waiting at most
    /// `timeout` for the messages to go out.
    public func notifyShutdown(reason: String, timeout: TimeInterval = 1) {
        let identified = snapshot().filter(\.isJSONIdentified)
        guard !identified.isEmpty else { return }
        log.info("Telling \(identified.count) automation connection(s) that the app quits (\(reason)).")
        let payload = IPCJSON.data(["event": .string("shutdown"), "reason": .string(reason), "greenshot_running": .bool(false)])
        let group = DispatchGroup()
        for connection in identified {
            connection.write(frame: payload)
            group.enter()
            connection.afterPendingWrites { group.leave() }
        }
        _ = group.wait(timeout: .now() + timeout)
    }

    private func snapshot() -> [Connection] {
        lock.lock()
        defer { lock.unlock() }
        return Array(connections.values)
    }

    private func wake() {
        lock.lock()
        let fd = wakePipe[1]
        lock.unlock()
        guard fd >= 0 else { return }
        var byte: UInt8 = 1
        _ = write(fd, &byte, 1)
    }

    private func acceptLoop() {
        while true {
            lock.lock()
            let isRunning = running
            let fd = listenFD
            let wakeFD = wakePipe[0]
            lock.unlock()
            guard isRunning, fd >= 0 else { break }

            var fds = [pollfd(fd: fd, events: Int16(POLLIN), revents: 0), pollfd(fd: wakeFD, events: Int16(POLLIN), revents: 0)]
            let ready = poll(&fds, 2, -1)
            if ready < 0 {
                if errno == EINTR { continue }
                log.error("Waiting for automation connections failed: \(String(cString: strerror(errno)))")
                break
            }
            if fds[1].revents != 0 {
                var buffer = [UInt8](repeating: 0, count: 16)
                while read(wakeFD, &buffer, buffer.count) > 0 {}
                continue
            }
            guard fds[0].revents & Int16(POLLIN) != 0 else { continue }
            let client = accept(fd, nil, nil)
            guard client >= 0 else { continue }
            accepted(client)
        }
        lock.lock()
        let ends = wakePipe
        wakePipe = [-1, -1]
        lock.unlock()
        ends.filter { $0 >= 0 }.forEach { close($0) }
    }

    private func accepted(_ fd: Int32) {
        _ = fcntl(fd, F_SETFD, FD_CLOEXEC)
        IPCSocket.setNoSigPipe(fd)
        IPCSocket.setSendBuffer(fd, bytes: configuration.sendBufferSize)
        IPCSocket.setTimeout(fd, option: SO_SNDTIMEO, seconds: configuration.writeTimeout)
        IPCSocket.setTimeout(fd, option: SO_RCVTIMEO, seconds: configuration.helloTimeout)
        guard let peer = IPCSocket.peer(of: fd), peer.uid == configuration.allowedUID else {
            log.warn("[SECURITY] Automation connection of another user refused.")
            close(fd)
            return
        }
        lock.lock()
        guard connections.count < configuration.maxConnections else {
            lock.unlock()
            log.warn("Too many automation connections; one refused.")
            close(fd)
            return
        }
        let connection = Connection(fd: fd, peer: peer, server: self)
        connections[ObjectIdentifier(connection)] = connection
        lock.unlock()
        let thread = Thread { connection.run() }
        thread.name = "IPC connection"
        thread.start()
    }

    fileprivate func remove(_ connection: Connection) {
        lock.lock()
        connections.removeValue(forKey: ObjectIdentifier(connection))
        lock.unlock()
    }
}

/// One client connection: reads frames on its own thread, writes through a serial queue.
private final class Connection: IPCFrameWriter, @unchecked Sendable {
    private let fd: Int32
    private let peer: IPCPeer
    private let server: IPCServer
    private let writeQueue = DispatchQueue(label: "IPC connection writes")
    private let lock = NSLock()
    private var closed = false
    private var gone = false
    private var watching = false
    private var jsonIdentified = false

    init(fd: Int32, peer: IPCPeer, server: IPCServer) {
        self.fd = fd
        self.peer = peer
        self.server = server
    }

    var isWatching: Bool {
        lock.lock()
        defer { lock.unlock() }
        return watching && !closed
    }

    var isJSONIdentified: Bool {
        lock.lock()
        defer { lock.unlock() }
        return jsonIdentified && !closed
    }

    func write(frame payload: Data) {
        writeQueue.async { [self] in
            lock.lock()
            let skip = closed || gone
            lock.unlock()
            guard !skip else { return }
            do {
                try IPCFrameIO.writeFrame(fd, payload)
            } catch IPCIOError.timedOut {
                // The client does not read its replies: closing ends the waiting handler too
                server.log.warn("IPC client did not read its reply within \(Int(server.configuration.writeTimeout)) seconds, closing the connection.")
                markGone()
                shutDown()
            } catch {
                // Not an error: e.g. a second start only forwards its command and quits
                server.log.debug("The IPC client closed the connection; a reply is dropped.")
                markGone()
            }
        }
    }

    func afterPendingWrites(_ body: @escaping @Sendable () -> Void) {
        writeQueue.async(execute: body)
    }

    private func markGone() {
        lock.lock()
        gone = true
        lock.unlock()
    }

    /// Unblocks the reader (the thread then closes the connection).
    func shutDown() {
        lock.lock()
        if !closed { Darwin.shutdown(fd, SHUT_RDWR) }
        lock.unlock()
    }

    func run() {
        defer {
            server.remove(self)
            // Let queued frames go out (each write is bounded by SO_SNDTIMEO), then close; later writes see `closed`.
            writeQueue.sync {
                lock.lock()
                closed = true
                Darwin.close(fd)
                lock.unlock()
            }
        }
        var source: IPCSource?
        var origin: String?
        var textFrames = false
        let configuration = server.configuration
        let log = server.log

        while true {
            let payload: Data?
            do {
                payload = try IPCFrameIO.readFrame(fd, minimum: IPCFrame.minimumJSONLength)
            } catch IPCIOError.invalidLength(let length) {
                log.warn("[SECURITY] Invalid or oversized payload received on the automation socket: \(length) bytes. Closing connection.")
                return
            } catch IPCIOError.timedOut {
                log.warn("[SECURITY] Automation connection closed: no HELLO within \(Int(configuration.helloTimeout)) seconds.")
                return
            } catch {
                log.debug("Automation connection ended: \(error)")
                return
            }
            guard let payload else { return }
            guard let object = IPCJSON.parseObject(payload) else {
                log.warn("[SECURITY] Automation connection closed: a frame isn't a JSON object.")
                reject("[SECURITY] Connection rejected: frames must be JSON objects.", text: textFrames)
                return
            }
            var envelope = IPCEnvelope(json: object)

            guard let bound = source else {
                // The first frame must be HELLO, announcing a known source
                guard envelope.isHello, let claimed = IPCSource(name: envelope.source), configuration.acceptedSources.contains(claimed) else {
                    log.warn("[SECURITY] Automation connection rejected: first frame must be HELLO with a known source (got command '\(envelope.command ?? "")', source '\(envelope.source ?? "")').")
                    reject("[SECURITY] Connection rejected: the first message must be HELLO with a known source.",
                           text: envelope.replyFormat?.lowercased() == IPCReplyFormat.text.rawValue)
                    return
                }
                let formatName = envelope.replyFormat.flatMap { $0.isEmpty ? nil : $0.lowercased() } ?? IPCReplyFormat.json.rawValue
                guard let format = IPCReplyFormat(rawValue: formatName) else {
                    log.warn("[SECURITY] Automation connection rejected: unknown reply format '\(formatName)'.")
                    reject("[SECURITY] Connection rejected: unknown reply format.", text: false)
                    return
                }
                // Don't trust the HELLO: check which program is connected
                if let verifier = configuration.verifier, let refusal = verifier(peer, claimed) {
                    log.warn("[SECURITY] Automation connection rejected: \(refusal)")
                    reject("[SECURITY] Connection rejected: \(refusal)", text: format == .text)
                    return
                }
                source = claimed
                origin = envelope.origin
                textFrames = format == .text
                if !textFrames {
                    lock.lock()
                    jsonIdentified = true
                    lock.unlock()
                }
                // Identified: requests and watch connections may take their time
                IPCSocket.setTimeout(fd, option: SO_RCVTIMEO, seconds: 0)
                log.debug("Automation connection identified: source '\(claimed.rawValue)', client '\(envelope.client ?? "")' \(envelope.clientVersion ?? "")")
                continue
            }

            if envelope.isHello {
                log.warn("[SECURITY] Automation connection closed: repeated HELLO on a connection already identified as '\(bound.rawValue)'.")
                reject("[SECURITY] Connection rejected: HELLO is only allowed as the first message.", text: textFrames)
                return
            }
            // Whatever the client put into "source" is ignored; the connection's HELLO decides
            envelope.source = bound.rawValue

            if !textFrames, envelope.command?.uppercased() == IPCServer.watchCommand {
                lock.lock()
                watching = true
                lock.unlock()
                write(frame: IPCJSON.data(IPCReply.ok(extra: ["watching": .bool(true)]).jsonObject))
                continue
            }

            let context = IPCReplyContext(envelope: envelope, source: bound, writer: self, usesTextFrames: textFrames,
                                          origin: origin, peer: peer)
            let done = DispatchSemaphore(value: 0)
            let dispatcher = server.dispatcher
            Task.detached {
                await dispatcher.dispatch(context)
                done.signal()
            }
            done.wait()
            // Text clients wait for the exit frame; commands without a reply must still end it
            context.complete(exitCode: IPCExitCode.ok)
        }
    }

    /// The last message before the server closes a connection that broke the protocol.
    private func reject(_ message: String, text: Bool) {
        if text {
            if let frame = IPCTextFrame.text(message, to: .stderr) { write(frame: frame.payload) }
            write(frame: IPCTextFrame.exit(IPCExitCode.failure).payload)
        } else {
            write(frame: IPCJSON.data(IPCReply.error(message).jsonObject))
        }
    }
}
