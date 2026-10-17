// Greenshot for Mac (Community) - an unofficial macOS port of Greenshot
// Copyright (C) 2026 Greenshot for Mac (Community) contributors
// Based on Greenshot, Copyright (C) 2007-2026 Thomas Braun, Jens Klingen, Robin Krom
// SPDX-License-Identifier: GPL-3.0-or-later

import Darwin
import Foundation

/// The program on the other end of a connection, from the kernel (not from anything it sends).
public struct IPCPeer: Equatable, Sendable {
    public var uid: uid_t
    public var pid: pid_t
    /// The audit token (`LOCAL_PEERTOKEN`): identifies the process without the race of a reused process id.
    public var auditToken: Data?

    public init(uid: uid_t, pid: pid_t, auditToken: Data?) {
        self.uid = uid
        self.pid = pid
        self.auditToken = auditToken
    }
}

/// Unix domain stream sockets: the Mac's stand-in for upstream's per-user named pipe (`NamedPipeEndpoint.cs`).
/// BSD sockets rather than Network.framework, which doesn't give the peer's credentials.
public enum IPCSocket {
    /// The longest path `sockaddr_un` takes (104 bytes with the terminating zero).
    public static let maximumPathLength = 103

    struct Failure: Error, CustomStringConvertible {
        var call: String
        var code: Int32
        var description: String { "\(call): \(String(cString: strerror(code)))" }
    }

    /// Calls `body` with the address of `path`; throws when the path is too long.
    static func withAddress<T>(_ path: String, _ body: (UnsafePointer<sockaddr>, socklen_t) -> T) throws -> T {
        var address = sockaddr_un()
        address.sun_family = sa_family_t(AF_UNIX)
        let bytes = Array(path.utf8)
        guard !bytes.isEmpty, bytes.count <= maximumPathLength else { throw Failure(call: "socket path", code: ENAMETOOLONG) }
        withUnsafeMutableBytes(of: &address.sun_path) { raw in
            raw.copyBytes(from: bytes)
            raw[bytes.count] = 0
        }
        let size = socklen_t(MemoryLayout<sockaddr_un>.size)
        address.sun_len = UInt8(truncatingIfNeeded: size)
        return withUnsafePointer(to: &address) { pointer in
            pointer.withMemoryRebound(to: sockaddr.self, capacity: 1) { body($0, size) }
        }
    }

    /// A new stream socket, closed on exec and never raising SIGPIPE.
    static func makeSocket() throws -> Int32 {
        let fd = Darwin.socket(AF_UNIX, SOCK_STREAM, 0)
        guard fd >= 0 else { throw Failure(call: "socket", code: errno) }
        _ = fcntl(fd, F_SETFD, FD_CLOEXEC)
        setNoSigPipe(fd)
        return fd
    }

    /// A listening socket at `path`, readable and writable only by this user (mode 0600). An old file at the path is
    /// removed first: only the instance holding the instance lock calls this.
    public static func listen(at path: String, backlog: Int32 = 16) throws -> Int32 {
        let fd = try makeSocket()
        unlink(path)
        // No umask change (it is process wide): until the chmod the default mode lets nobody else write, and the
        // per-user temporary folder is the user's alone anyway.
        let bound = try withAddress(path) { Darwin.bind(fd, $0, $1) }
        let bindError = errno
        guard bound == 0 else {
            close(fd)
            throw Failure(call: "bind", code: bindError)
        }
        chmod(path, 0o600)
        guard Darwin.listen(fd, backlog) == 0 else {
            let code = errno
            close(fd)
            unlink(path)
            throw Failure(call: "listen", code: code)
        }
        return fd
    }

    /// A connected socket; throws when nothing listens at `path`.
    public static func connect(to path: String) throws -> Int32 {
        let fd = try makeSocket()
        let result = try withAddress(path) { Darwin.connect(fd, $0, $1) }
        guard result == 0 else {
            let code = errno
            close(fd)
            throw Failure(call: "connect", code: code)
        }
        return fd
    }

    public static func setNoSigPipe(_ fd: Int32) {
        var on: Int32 = 1
        setsockopt(fd, SOL_SOCKET, SO_NOSIGPIPE, &on, socklen_t(MemoryLayout<Int32>.size))
    }

    /// `SO_RCVTIMEO` or `SO_SNDTIMEO`; 0 waits forever.
    public static func setTimeout(_ fd: Int32, option: Int32, seconds: TimeInterval) {
        let whole = Int(max(0, seconds))
        let micro = Int32((max(0, seconds) - Double(whole)) * 1_000_000)
        var time = timeval(tv_sec: whole, tv_usec: micro)
        setsockopt(fd, SOL_SOCKET, option, &time, socklen_t(MemoryLayout<timeval>.size))
    }

    /// Asks for a larger send buffer (macOS may give less: `net.local.stream.sendspace`).
    public static func setSendBuffer(_ fd: Int32, bytes: Int32) {
        var size = bytes
        setsockopt(fd, SOL_SOCKET, SO_SNDBUF, &size, socklen_t(MemoryLayout<Int32>.size))
    }

    /// The user, process and audit token of the connected peer.
    public static func peer(of fd: Int32) -> IPCPeer? {
        var credentials = xucred()
        var length = socklen_t(MemoryLayout<xucred>.size)
        guard getsockopt(fd, 0 /* SOL_LOCAL */, LOCAL_PEERCRED, &credentials, &length) == 0,
              credentials.cr_version == XUCRED_VERSION else { return nil }
        var pid: pid_t = 0
        var pidLength = socklen_t(MemoryLayout<pid_t>.size)
        if getsockopt(fd, 0, LOCAL_PEERPID, &pid, &pidLength) != 0 { pid = 0 }
        var token = audit_token_t()
        var tokenLength = socklen_t(MemoryLayout<audit_token_t>.size)
        let tokenData: Data? = getsockopt(fd, 0, LOCAL_PEERTOKEN, &token, &tokenLength) == 0
            ? withUnsafeBytes(of: &token) { Data($0) } : nil
        return IPCPeer(uid: credentials.cr_uid, pid: pid, auditToken: tokenData)
    }

    /// The device and inode of the file at `path`, to notice that the socket file was removed or replaced.
    public static func fileIdentity(_ path: String) -> [UInt64]? {
        var info = stat()
        guard lstat(path, &info) == 0 else { return nil }
        return [UInt64(bitPattern: Int64(info.st_dev)), info.st_ino]
    }
}
