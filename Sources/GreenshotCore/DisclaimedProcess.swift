// Greenshot for Mac (Community) - an unofficial macOS port of Greenshot
// Copyright (C) 2026 Greenshot for Mac (Community) contributors
// Based on Greenshot, Copyright (C) 2007-2026 Thomas Braun, Jens Klingen, Robin Krom
// SPDX-License-Identifier: GPL-3.0-or-later

import Darwin
import Foundation

/// A program Greenshot runs for the user (an external command, a recipe's ExternalCommand step) as its own program for
/// macOS privacy permissions: macOS asks about the program's own Screen Recording, Accessibility, files and so on, not
/// Greenshot's. A child started by `Foundation.Process` would share Greenshot's; this one is started with `posix_spawn`
/// and the spawn attribute that gives up that responsibility (`responsibility_spawnattrs_setdisclaim`, as Chromium,
/// Firefox, LLDB and iTerm2 start their helpers and shells). It stays Greenshot's child process.
///
/// Otherwise it starts the way `Process` did: a process group of its own, every signal at its default and none blocked,
/// only its standard input (empty), output and errors open, the app's environment, and the app's folder unless
/// `currentDirectoryURL` is set. The same names as `Process`; one thread waits (`waitUntilExit`), `isRunning` and
/// `terminate` work from any thread.
public final class DisclaimedProcess: @unchecked Sendable {
    public var executableURL: URL?
    public var arguments: [String] = []
    public var currentDirectoryURL: URL?
    /// Nil: to /dev/null. The write end is closed here once the program has started, so the reader sees its end.
    public var standardOutput: Pipe?
    public var standardError: Pipe?

    private enum State {
        case notStarted, running, ended
    }

    private let lock = NSLock()
    private var pid: pid_t = 0
    private var state = State.notStarted
    private var status: Int32 = 0

    public init() {}

    private typealias SetDisclaim = @convention(c) (UnsafeMutablePointer<posix_spawnattr_t?>, Int32) -> Int32

    /// libquarantine's `responsibility_spawnattrs_setdisclaim` (macOS 10.14 and later, not in the SDK's headers), looked
    /// up rather than linked so a macOS without it still starts the app.
    private static let setDisclaim: SetDisclaim? = dlsym(dlopen(nil, RTLD_NOW), "responsibility_spawnattrs_setdisclaim")
        .map { unsafeBitCast($0, to: SetDisclaim.self) }

    /// Whether this macOS can start a program as its own for privacy permissions. Without it, `run` refuses to start
    /// one: it would get Greenshot's permissions.
    public static var canDisclaim: Bool { setDisclaim != nil }

    public var processIdentifier: pid_t { lock.withLock { pid } }

    /// Like `Process.terminationStatus`: the exit code, or the number of the signal that ended the program.
    public var terminationStatus: Int32 { lock.withLock { status } }

    /// Whether the program has started and not ended; one that ended counts as ended before `waitUntilExit` returns.
    public var isRunning: Bool { lock.withLock { state == .running && !hasEnded() } }

    /// Starts the program. Throws `CocoaError(.fileNoSuchFile)` naming the file, like `Process.run`, when the program
    /// isn't an executable file or the folder isn't there.
    public func run() throws {
        guard let executableURL else { throw CocoaError(.fileNoSuchFile) }
        let path = executableURL.path
        guard FileManager.default.isExecutableFile(atPath: path) else {
            throw CocoaError(.fileNoSuchFile, userInfo: [NSFilePathErrorKey: path])
        }
        var isFolder: ObjCBool = false
        if let folder = currentDirectoryURL?.path, !FileManager.default.fileExists(atPath: folder, isDirectory: &isFolder) || !isFolder.boolValue {
            throw CocoaError(.fileNoSuchFile, userInfo: [NSFilePathErrorKey: folder])
        }
        guard let setDisclaim = Self.setDisclaim else { throw POSIXError(.ENOTSUP) }

        var attributes: posix_spawnattr_t?
        try Self.check(posix_spawnattr_init(&attributes))
        defer { posix_spawnattr_destroy(&attributes) }
        let flags = POSIX_SPAWN_CLOEXEC_DEFAULT | POSIX_SPAWN_SETPGROUP | POSIX_SPAWN_SETSIGDEF | POSIX_SPAWN_SETSIGMASK
        try Self.check(posix_spawnattr_setflags(&attributes, Int16(flags)))
        try Self.check(posix_spawnattr_setpgroup(&attributes, 0))
        var everySignal = sigset_t()
        sigfillset(&everySignal)
        try Self.check(posix_spawnattr_setsigdefault(&attributes, &everySignal))
        var noSignal = sigset_t()
        sigemptyset(&noSignal)
        try Self.check(posix_spawnattr_setsigmask(&attributes, &noSignal))
        try Self.check(setDisclaim(&attributes, 1))

        var actions: posix_spawn_file_actions_t?
        try Self.check(posix_spawn_file_actions_init(&actions))
        defer { posix_spawn_file_actions_destroy(&actions) }
        try Self.check(posix_spawn_file_actions_addopen(&actions, STDIN_FILENO, "/dev/null", O_RDONLY, 0))
        for (target, pipe) in [(STDOUT_FILENO, standardOutput), (STDERR_FILENO, standardError)] {
            if let pipe {
                let source = pipe.fileHandleForWriting.fileDescriptor
                // With POSIX_SPAWN_CLOEXEC_DEFAULT only what the actions name stays open.
                try Self.check(source == target ? posix_spawn_file_actions_addinherit_np(&actions, target)
                                                : posix_spawn_file_actions_adddup2(&actions, source, target))
            } else {
                try Self.check(posix_spawn_file_actions_addopen(&actions, target, "/dev/null", O_WRONLY, 0))
            }
        }
        if let folder = currentDirectoryURL?.path {
            try Self.check(posix_spawn_file_actions_addchdir_np(&actions, folder))
        }

        let argv: [UnsafeMutablePointer<CChar>?] = ([path] + arguments).map { strdup($0) } + [nil]
        defer { argv.forEach { free($0) } }
        let result: Int32 = lock.withLock {
            var child: pid_t = 0
            let result = posix_spawn(&child, path, &actions, &attributes, argv, environ)
            if result == 0 {
                pid = child
                state = .running
            }
            return result
        }
        try? standardOutput?.fileHandleForWriting.close()
        try? standardError?.fileHandleForWriting.close()
        try Self.check(result)
    }

    /// Waits for the program to end (at once when it never started).
    public func waitUntilExit() {
        guard let pid = lock.withLock({ state == .running ? pid : nil }) else { return }
        // Waits without collecting the program first: until it is collected its process ID can't be reused, so
        // `terminate` can't hit another program.
        var info = siginfo_t()
        while waitid(P_PID, id_t(pid), &info, WEXITED | WNOWAIT) == -1 && errno == EINTR {}
        lock.withLock {
            var raw: Int32 = 0
            while waitpid(pid, &raw, 0) == -1 && errno == EINTR {}
            // <sys/wait.h>'s WIFEXITED, WEXITSTATUS and WTERMSIG, which Swift doesn't import.
            let signal = raw & 0x7f
            status = signal == 0 ? (raw >> 8) & 0xff : signal
            state = .ended
        }
    }

    /// Ends the program and what it started in its process group (SIGTERM), like `Process.terminate`. Does nothing once it
    /// has ended.
    public func terminate() {
        lock.withLock {
            guard state == .running, !hasEnded() else { return }
            if killpg(pid, SIGTERM) != 0 { kill(pid, SIGTERM) }
        }
    }

    /// Whether the running program has ended, without collecting it (with the lock held). One that is no longer this
    /// process's child counts as ended.
    private func hasEnded() -> Bool {
        var info = siginfo_t()
        guard waitid(P_PID, id_t(pid), &info, WEXITED | WNOHANG | WNOWAIT) == 0 else { return errno == ECHILD }
        return info.si_pid == pid
    }

    private static func check(_ result: Int32) throws {
        guard result != 0 else { return }
        throw POSIXError(POSIXErrorCode(rawValue: result) ?? .EINVAL)
    }
}
