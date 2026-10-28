// SPDX-License-Identifier: GPL-3.0-or-later

import Darwin
import Foundation
import Testing
@testable import GreenshotCore

/// The program an external command runs answers for its own macOS privacy permissions, and otherwise starts like
/// `Foundation.Process` started it before.
struct DisclaimedProcessTests {
    struct Ended: Sendable {
        var status: Int32
        var output: Data
        var errors: Data
    }

    /// Starts the program, reads both pipes and waits on a global queue: its waits block, and a test must not block the
    /// cooperative pool.
    private func runToEnd(_ executable: String, _ arguments: [String] = [], in directory: URL? = nil) async throws -> Ended {
        try await offPool {
            let process = DisclaimedProcess()
            process.executableURL = URL(fileURLWithPath: executable)
            process.arguments = arguments
            process.currentDirectoryURL = directory
            let output = Pipe()
            let errors = Pipe()
            process.standardOutput = output
            process.standardError = errors
            try process.run()
            var outData = Data()
            let reading = DispatchGroup()
            reading.enter()
            DispatchQueue.global().async {
                outData = output.fileHandleForReading.readDataToEndOfFile()
                reading.leave()
            }
            let errData = errors.fileHandleForReading.readDataToEndOfFile()
            reading.wait()
            process.waitUntilExit()
            return Ended(status: process.terminationStatus, output: outData, errors: errData)
        }
    }

    private func offPool<T: Sendable>(_ body: @escaping @Sendable () throws -> T) async throws -> T {
        try await withCheckedThrowingContinuation { continuation in
            DispatchQueue.global().async { continuation.resume(with: Result { try body() }) }
        }
    }

    /// libquarantine's `responsibility_get_pid_responsible_for_pid`: the process macOS asks about a process's privacy
    /// permissions.
    private static let responsiblePID: (@convention(c) (pid_t) -> pid_t)? = dlsym(dlopen(nil, RTLD_NOW), "responsibility_get_pid_responsible_for_pid")
        .map { unsafeBitCast($0, to: (@convention(c) (pid_t) -> pid_t).self) }

    @Test func theSpawnAttributeIsThere() {
        #expect(DisclaimedProcess.canDisclaim)
        #expect(Self.responsiblePID != nil)
    }

    @Test func withoutTheAttributeNothingStartsAndTheErrorSaysWhy() {
        let expected = "This version of macOS can't run the program with its own privacy permissions, so Greenshot doesn't run it."
        let missing = DisclaimedProcess(setDisclaim: nil)
        missing.executableURL = URL(fileURLWithPath: "/usr/bin/true")
        let refusal = #expect(throws: DisclaimedProcessError.self) { try missing.run() }
        #expect(refusal == .cannotDisclaim)
        #expect((refusal as Error?)?.localizedDescription == expected)
        #expect(!missing.isRunning)
        #expect(missing.processIdentifier == 0)
        // The attribute there but refused.
        let failing = DisclaimedProcess(setDisclaim: { _, _ in EINVAL })
        failing.executableURL = URL(fileURLWithPath: "/usr/bin/true")
        let failure = #expect(throws: DisclaimedProcessError.self) { try failing.run() }
        #expect(failure == .cannotDisclaim)
        #expect(failing.processIdentifier == 0)
    }

    @Test func theProgramAnswersForItsOwnPermissions() async throws {
        let responsiblePID = try #require(Self.responsiblePID)
        let process = DisclaimedProcess()
        process.executableURL = URL(fileURLWithPath: "/bin/sleep")
        process.arguments = ["30"]
        try process.run()
        defer { process.terminate() }
        let pid = process.processIdentifier
        let responsible = responsiblePID(pid)
        let ours = responsiblePID(getpid())
        process.terminate()
        try await offPool { process.waitUntilExit() }
        #expect(pid > 0)
        #expect(responsible == pid)
        #expect(responsible != ours)
        #expect(process.terminationStatus == SIGTERM)
    }

    @Test func aProgramFoundInThePathAnswersForItsOwnPermissionsToo() async throws {
        let responsiblePID = try #require(Self.responsiblePID)
        let process = DisclaimedProcess()
        process.executableURL = URL(fileURLWithPath: "/usr/bin/env")
        process.arguments = ["sleep", "30"]
        try process.run()
        defer { process.terminate() }
        // The program answers for itself from its start; /usr/bin/env then becomes sleep in the same process.
        let pid = process.processIdentifier
        let responsible = responsiblePID(pid)
        process.terminate()
        try await offPool { process.waitUntilExit() }
        #expect(responsible == pid)
    }

    @Test func outputErrorsAndExitCodeComeBack() async throws {
        let ended = try await runToEnd("/bin/sh", ["-c", "printf 'out put'; printf 'err or' >&2; exit 3"])
        #expect(ended.status == 3)
        #expect(String(decoding: ended.output, as: UTF8.self) == "out put")
        #expect(String(decoding: ended.errors, as: UTF8.self) == "err or")
    }

    @Test func aChattyProgramDoesNotBlockOnFullPipes() async throws {
        let ended = try await runToEnd("/bin/sh", ["-c", "head -c 300000 /dev/zero; head -c 200000 /dev/zero >&2"])
        #expect(ended.status == 0)
        #expect(ended.output.count == 300_000)
        #expect(ended.errors.count == 200_000)
    }

    @Test func theInputIsEmpty() async throws {
        let ended = try await runToEnd("/bin/cat")
        #expect(ended.status == 0)
        #expect(ended.output.isEmpty)
    }

    @Test func aMissingProgramInThePathEndsWith127() async throws {
        let ended = try await runToEnd("/usr/bin/env", ["greenshot-mac-no-such-program-\(UUID().uuidString)"])
        #expect(ended.status == 127)
    }

    @Test func theFolderIsTheOneGiven() async throws {
        let folder = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString, isDirectory: true)
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: folder) }
        let ended = try await runToEnd("/bin/pwd", ["-P"], in: folder)
        let printed = String(decoding: ended.output, as: UTF8.self).trimmingCharacters(in: .newlines)
        #expect(printed == IPCEndpoint.realPath(folder.path))
    }

    @Test func noOtherFileOfTheAppIsOpenInTheProgram() async throws {
        // Opened without close-on-exec: Process never handed such files to a program either.
        let file = open("/dev/null", O_RDONLY)
        try #require(file >= 0)
        defer { close(file) }
        let ended = try await runToEnd("/bin/sh", ["-c", "if : <&\(file); then echo open; else echo closed; fi 2>/dev/null"])
        #expect(String(decoding: ended.output, as: UTF8.self) == "closed\n")
    }

    @Test func signalsTheAppIgnoresAreNotIgnoredInTheProgram() async throws {
        let previous = signal(SIGPIPE, SIG_IGN)
        defer { signal(SIGPIPE, previous) }
        // A shell can't stop ignoring a signal that was ignored when it started.
        let ended = try await runToEnd("/bin/sh", ["-c", "kill -PIPE $$; echo survived"])
        #expect(ended.status == SIGPIPE)
        #expect(ended.output.isEmpty)
    }

    @Test func terminateEndsTheProgramAndWhatItStarted() async throws {
        let process = DisclaimedProcess()
        process.executableURL = URL(fileURLWithPath: "/bin/sh")
        process.arguments = ["-c", "/bin/sleep 30 >/dev/null 2>&1 & echo $!; wait"]
        let output = Pipe()
        process.standardOutput = output
        try process.run()
        defer { process.terminate() }
        let pid = process.processIdentifier
        let line = try await offPool { output.fileHandleForReading.availableData }
        let started = try #require(pid_t(String(decoding: line, as: UTF8.self).trimmingCharacters(in: .whitespacesAndNewlines)))
        #expect(getpgid(pid) == pid)
        #expect(process.isRunning)
        process.terminate()
        try await offPool { process.waitUntilExit() }
        // No terminationStatus check: bash often ends normally once its job has ended, also under Process.
        #expect(!process.isRunning)
        // The started sleep is in the program's process group; it is gone (or a zombie) shortly after. Up to 10 seconds
        // for a busy machine.
        var gone = false
        for _ in 0..<200 where !gone {
            var info = proc_bsdinfo()
            let size = proc_pidinfo(started, PROC_PIDTBSDINFO, 0, &info, Int32(MemoryLayout<proc_bsdinfo>.size))
            gone = size <= 0 || info.pbi_status == UInt32(SZOMB)
            if !gone { try await Task.sleep(for: .milliseconds(50)) }
        }
        if !gone { kill(started, SIGKILL) }
        #expect(gone)
    }

    @Test func twoWaitersBothSeeTheExitCode() async throws {
        let process = DisclaimedProcess()
        process.executableURL = URL(fileURLWithPath: "/bin/sh")
        process.arguments = ["-c", "sleep 0.5; exit 7"]
        try process.run()
        defer { process.terminate() }
        // Both wait before the program ends; the one that doesn't collect it must not overwrite its exit code.
        let seen = try await offPool { () -> [Int32] in
            let lock = NSLock()
            var statuses: [Int32] = []
            DispatchQueue.concurrentPerform(iterations: 2) { _ in
                process.waitUntilExit()
                let status = process.terminationStatus
                lock.withLock { statuses.append(status) }
            }
            return statuses
        }
        #expect(seen == [7, 7])
        #expect(process.terminationStatus == 7)
        #expect(!process.isRunning)
    }

    @Test func anEndedProgramIsNotRunningAndTerminateDoesNothing() async throws {
        let process = DisclaimedProcess()
        process.executableURL = URL(fileURLWithPath: "/usr/bin/true")
        #expect(!process.isRunning)
        process.terminate()
        try process.run()
        try await offPool { process.waitUntilExit() }
        #expect(!process.isRunning)
        process.terminate()
        #expect(process.terminationStatus == 0)
    }

    @Test func aMissingProgramOrFolderThrowsLikeProcess() throws {
        let process = DisclaimedProcess()
        process.executableURL = URL(fileURLWithPath: "/nonexistent-\(UUID().uuidString)/program")
        let missing = #expect(throws: CocoaError.self) { try process.run() }
        #expect(missing?.code == .fileNoSuchFile)
        let notExecutable = DisclaimedProcess()
        notExecutable.executableURL = URL(fileURLWithPath: "/etc/hosts")
        let refused = #expect(throws: CocoaError.self) { try notExecutable.run() }
        #expect(refused?.code == .fileNoSuchFile)
        let noFolder = DisclaimedProcess()
        noFolder.executableURL = URL(fileURLWithPath: "/usr/bin/true")
        noFolder.currentDirectoryURL = URL(fileURLWithPath: "/nonexistent-\(UUID().uuidString)", isDirectory: true)
        let folderMissing = #expect(throws: CocoaError.self) { try noFolder.run() }
        #expect(folderMissing?.code == .fileNoSuchFile)
        #expect(!noFolder.isRunning)
    }
}
