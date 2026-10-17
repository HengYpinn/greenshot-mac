// Greenshot for Mac (Community) - an unofficial macOS port of Greenshot
// Copyright (C) 2026 Greenshot for Mac (Community) contributors
// Based on Greenshot, Copyright (C) 2007-2026 Thomas Braun, Jens Klingen, Robin Krom
// SPDX-License-Identifier: GPL-3.0-or-later

import Foundation

/// Every message is a 4-byte little-endian length and that many bytes (upstream `greenshot-proxy/framing.h`,
/// `NamedPipeServer.ProcessClientAsync`).
public enum IPCFrame {
    /// The smallest frame a client may send, `{}` (upstream `MIN_JSON_PAYLOAD_SIZE`).
    public static let minimumJSONLength = 2
    /// 64 MB per frame (upstream `MAX_PAYLOAD_SIZE`, ADR 003).
    public static let maximumLength = 64 * 1024 * 1024

    /// The length prefix and the payload.
    public static func encode(_ payload: Data) -> Data {
        let length = UInt32(payload.count)
        var frame = Data(capacity: payload.count + 4)
        frame.append(UInt8(truncatingIfNeeded: length))
        frame.append(UInt8(truncatingIfNeeded: length >> 8))
        frame.append(UInt8(truncatingIfNeeded: length >> 16))
        frame.append(UInt8(truncatingIfNeeded: length >> 24))
        frame.append(payload)
        return frame
    }

    /// The length in a 4-byte little-endian prefix.
    public static func length(ofPrefix prefix: Data) -> UInt32 {
        let bytes = [UInt8](prefix.prefix(4))
        guard bytes.count == 4 else { return 0 }
        var value: UInt32 = 0
        for (index, byte) in bytes.enumerated() {
            let shifted = UInt32(byte) << UInt32(8 * index)
            value |= shifted
        }
        return value
    }

    /// A JSON object as a frame.
    public static func encode(_ object: JSONObject) -> Data {
        encode(IPCJSON.data(object))
    }
}

/// The frames of a text connection (greenshot-cli): the first byte is the type (upstream `TEXT_FRAME_*`).
public enum IPCTextFrame: Equatable, Sendable {
    /// UTF-8 text for stdout.
    case stdout(Data)
    /// UTF-8 text for stderr.
    case stderr(Data)
    /// The end of the reply and the exit code.
    case exit(Int32)

    public static let stdoutType = UInt8(ascii: "O")
    public static let stderrType = UInt8(ascii: "E")
    public static let exitType = UInt8(ascii: "X")

    /// A frame's payload; nil for an empty one or an unknown type. An exit frame without its 4 bytes means 1 (failure),
    /// as the proxy reads it.
    public init?(payload: Data) {
        guard let type = payload.first else { return nil }
        let rest = payload.dropFirst()
        switch type {
        case Self.stdoutType: self = .stdout(Data(rest))
        case Self.stderrType: self = .stderr(Data(rest))
        case Self.exitType:
            guard rest.count >= 4 else {
                self = .exit(IPCExitCode.failure)
                return
            }
            self = .exit(Int32(bitPattern: IPCFrame.length(ofPrefix: Data(rest.prefix(4)))))
        default: return nil
        }
    }

    public var payload: Data {
        switch self {
        case .stdout(let text):
            return Data([Self.stdoutType]) + text
        case .stderr(let text):
            return Data([Self.stderrType]) + text
        case .exit(let code):
            let bits = UInt32(bitPattern: code)
            let bytes: [UInt8] = [Self.exitType, UInt8(truncatingIfNeeded: bits), UInt8(truncatingIfNeeded: bits >> 8),
                                  UInt8(truncatingIfNeeded: bits >> 16), UInt8(truncatingIfNeeded: bits >> 24)]
            return Data(bytes)
        }
    }

    /// A text frame for a stream, ending with a newline like upstream's `WriteTextFrameAsync`; nil for no text.
    public static func text(_ text: String?, to stream: IPCStream) -> IPCTextFrame? {
        guard var text, !text.isEmpty else { return nil }
        if !text.hasSuffix("\n") { text += "\n" }
        let data = Data(text.utf8)
        return stream == .stdout ? .stdout(data) : .stderr(data)
    }
}

/// Why reading or writing a frame stopped.
public enum IPCIOError: Error, Equatable {
    /// The other end closed the connection.
    case closed
    /// It closed in the middle of a frame.
    case truncated
    /// A length outside the allowed range.
    case invalidLength(UInt32)
    /// The socket's read or write timeout passed.
    case timedOut
    /// Another error of the system call (`errno`).
    case system(Int32)
}

/// Blocking frame I/O on a socket.
public enum IPCFrameIO {
    /// Reads exactly `count` bytes; nil when the connection ended cleanly before the first byte.
    public static func readExact(_ fd: Int32, count: Int) throws -> Data? {
        var buffer = [UInt8](repeating: 0, count: count)
        var done = 0
        while done < count {
            let result = buffer.withUnsafeMutableBytes { raw in
                Darwin.read(fd, raw.baseAddress! + done, count - done)
            }
            if result > 0 {
                done += result
            } else if result == 0 {
                if done == 0 { return nil }
                throw IPCIOError.truncated
            } else {
                let code = errno
                if code == EINTR { continue }
                if code == EAGAIN || code == EWOULDBLOCK { throw IPCIOError.timedOut }
                if code == ECONNRESET || code == EPIPE || code == EBADF || code == ENOTCONN { throw IPCIOError.closed }
                throw IPCIOError.system(code)
            }
        }
        return Data(buffer)
    }

    /// The next frame's payload; nil at a clean end of the connection. A length below `minimum` or above the maximum
    /// throws `invalidLength` without reading the payload.
    public static func readFrame(_ fd: Int32, minimum: Int = 1) throws -> Data? {
        guard let prefix = try readExact(fd, count: 4) else { return nil }
        let length = IPCFrame.length(ofPrefix: prefix)
        guard Int(length) >= minimum, Int(length) <= IPCFrame.maximumLength else { throw IPCIOError.invalidLength(length) }
        guard let payload = try readExact(fd, count: Int(length)) else { throw IPCIOError.truncated }
        return payload
    }

    /// Writes all bytes.
    public static func writeAll(_ fd: Int32, _ data: Data) throws {
        var done = 0
        while done < data.count {
            let result = data.withUnsafeBytes { raw in
                Darwin.write(fd, raw.baseAddress! + done, data.count - done)
            }
            if result >= 0 {
                done += result
            } else {
                let code = errno
                if code == EINTR { continue }
                if code == EAGAIN || code == EWOULDBLOCK { throw IPCIOError.timedOut }
                if code == EPIPE || code == ECONNRESET || code == EBADF || code == ENOTCONN { throw IPCIOError.closed }
                throw IPCIOError.system(code)
            }
        }
    }

    /// Writes one frame: length prefix and payload in one write.
    public static func writeFrame(_ fd: Int32, _ payload: Data) throws {
        try writeAll(fd, IPCFrame.encode(payload))
    }
}
