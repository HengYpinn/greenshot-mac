// Greenshot for Mac (Community) - an unofficial macOS port of Greenshot
// Copyright (C) 2026 Greenshot for Mac (Community) contributors
// Based on Greenshot, Copyright (C) 2007-2026 Thomas Braun, Jens Klingen, Robin Krom
// SPDX-License-Identifier: GPL-3.0-or-later

import CryptoKit
import Darwin
import Foundation

/// Where the app listens and keeps its locks, worked out the same way by the app and by greenshot-cli (upstream
/// `NamedPipeEndpoint`: one pipe per user). Per bundle identifier, so two differently named builds don't meet; a bare
/// `swift build` gets its own names, so it runs next to an installed app.
public struct IPCEndpoint: Equatable, Sendable {
    public static let defaultBundleIdentifier = "io.github.greenshot-mac.GreenshotMac"

    public var bundleIdentifier: String
    /// The app bundle, nil for a bare build.
    public var appBundlePath: String?
    public var socketPath: String
    /// `~/Library/Application Support/<bundle identifier>`.
    public var supportFolder: URL

    public var isDevelopmentBuild: Bool { appBundlePath == nil }
    private var suffix: String { isDevelopmentBuild ? "-dev" : "" }
    /// Held by the running instance (upstream's application mutex).
    public var instanceLockURL: URL { supportFolder.appendingPathComponent("instance\(suffix).lock") }
    /// Held while a client starts the app (upstream's cold-start mutex).
    public var coldStartLockURL: URL { supportFolder.appendingPathComponent("coldstart\(suffix).lock") }

    public init(bundleIdentifier: String?, appBundlePath: String?, temporaryFolder: String, applicationSupport: URL) {
        let identifier = bundleIdentifier.flatMap { $0.isEmpty ? nil : $0 } ?? Self.defaultBundleIdentifier
        self.bundleIdentifier = identifier
        self.appBundlePath = appBundlePath
        socketPath = Self.socketPath(bundleIdentifier: identifier, development: appBundlePath == nil, temporaryFolder: temporaryFolder)
        supportFolder = applicationSupport.appendingPathComponent(identifier, isDirectory: true)
    }

    /// The endpoint of the app an executable belongs to: its bundle's identifier (from `Contents/Info.plist`), or the
    /// default one for a bare build. `executablePath` with symlinks resolved.
    public static func forExecutable(_ executablePath: String, temporaryFolder: String = userTemporaryFolder,
                                     applicationSupport: URL = defaultApplicationSupport) -> IPCEndpoint {
        let bundle = IPCPeerPolicy.appBundle(ofExecutable: executablePath)
        let identifier = bundle.flatMap { infoDictionary(ofBundle: $0)?["CFBundleIdentifier"] as? String }
        return IPCEndpoint(bundleIdentifier: identifier, appBundlePath: bundle, temporaryFolder: temporaryFolder,
                           applicationSupport: applicationSupport)
    }

    public static func infoDictionary(ofBundle bundle: String) -> [String: Any]? {
        NSDictionary(contentsOfFile: (bundle as NSString).appendingPathComponent("Contents/Info.plist")) as? [String: Any]
    }

    /// `<folder>/<bundle id>.ipc` (`-dev` for a bare build); a hashed short name when that is longer than a socket
    /// path may be.
    public static func socketPath(bundleIdentifier: String, development: Bool, temporaryFolder: String) -> String {
        let folder = temporaryFolder.hasSuffix("/") ? String(temporaryFolder.dropLast()) : temporaryFolder
        let name = bundleIdentifier + (development ? "-dev" : "") + ".ipc"
        let path = folder + "/" + name
        if path.utf8.count <= IPCSocket.maximumPathLength { return path }
        let digest = SHA256.hash(data: Data(name.utf8)).prefix(6).map { String(format: "%02x", $0) }.joined()
        return folder + "/gsmac-" + digest + ".ipc"
    }

    /// The user's own temporary folder (`confstr(_CS_DARWIN_USER_TEMP_DIR)`, what `$TMPDIR` points to), without the
    /// environment: an app started by `open` doesn't get the terminal's.
    public static var userTemporaryFolder: String {
        var buffer = [CChar](repeating: 0, count: Int(PATH_MAX))
        let length = confstr(_CS_DARWIN_USER_TEMP_DIR, &buffer, buffer.count)
        guard length > 0, length <= buffer.count else { return NSTemporaryDirectory() }
        return String(cString: buffer)
    }

    public static var defaultApplicationSupport: URL {
        FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first
            ?? URL(fileURLWithPath: NSHomeDirectory()).appendingPathComponent("Library/Application Support")
    }

    /// The path with symlinks resolved (`realpath`), or the path itself when that fails.
    public static func realPath(_ path: String) -> String {
        guard let resolved = Darwin.realpath(path, nil) else { return path }
        defer { free(resolved) }
        return String(cString: resolved)
    }

    /// This process's executable, symlinks resolved (a greenshot-cli linked into /usr/local/bin finds its app).
    public static var currentExecutablePath: String {
        var size: UInt32 = 0
        _ = _NSGetExecutablePath(nil, &size)
        var buffer = [CChar](repeating: 0, count: Int(size) + 1)
        guard _NSGetExecutablePath(&buffer, &size) == 0 else { return realPath(CommandLine.arguments[0]) }
        return realPath(String(cString: buffer))
    }
}

/// An advisory file lock (`flock`), released when the process ends however it ends.
public final class IPCFileLock: @unchecked Sendable {
    public enum Outcome {
        case acquired(IPCFileLock)
        /// Another process holds it; the process id it wrote, if readable.
        case heldByOther(pid: pid_t?)
        case failed(String)
    }

    private var fd: Int32

    private init(fd: Int32) {
        self.fd = fd
    }

    deinit { release() }

    /// Takes the lock without waiting and writes this process's id into the file.
    public static func acquire(_ url: URL) -> Outcome {
        let fd: Int32
        switch open(url) {
        case .success(let opened): fd = opened
        case .failure(let message): return .failed(message)
        }
        guard flock(fd, LOCK_EX | LOCK_NB) == 0 else {
            let code = errno
            defer { close(fd) }
            if code == EWOULDBLOCK { return .heldByOther(pid: readPID(fd)) }
            return .failed("flock: \(String(cString: strerror(code)))")
        }
        ftruncate(fd, 0)
        let text = "\(getpid())\n"
        _ = text.withCString { pwrite(fd, $0, strlen($0), 0) }
        return .acquired(IPCFileLock(fd: fd))
    }

    /// Waits up to `timeout` for the lock (upstream's cold-start mutex: several clients starting the app at once).
    public static func wait(_ url: URL, timeout: TimeInterval) -> IPCFileLock? {
        let deadline = Date().addingTimeInterval(timeout)
        while true {
            if case .acquired(let lock) = acquire(url) { return lock }
            if Date() >= deadline { return nil }
            usleep(50_000)
        }
    }

    public func release() {
        guard fd >= 0 else { return }
        flock(fd, LOCK_UN)
        close(fd)
        fd = -1
    }

    private enum Opened {
        case success(Int32)
        case failure(String)
    }

    private static func open(_ url: URL) -> Opened {
        try? FileManager.default.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
        let fd = Darwin.open(url.path, O_RDWR | O_CREAT | O_CLOEXEC, 0o600)
        guard fd >= 0 else { return .failure("open \(url.lastPathComponent): \(String(cString: strerror(errno)))") }
        return .success(fd)
    }

    private static func readPID(_ fd: Int32) -> pid_t? {
        var buffer = [UInt8](repeating: 0, count: 32)
        let count = pread(fd, &buffer, buffer.count, 0)
        guard count > 0 else { return nil }
        let text = String(decoding: buffer.prefix(count), as: UTF8.self).trimmingCharacters(in: .whitespacesAndNewlines)
        return pid_t(text)
    }
}
