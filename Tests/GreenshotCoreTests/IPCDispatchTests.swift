// Greenshot for Mac (Community) - an unofficial macOS port of Greenshot
// Copyright (C) 2026 Greenshot for Mac (Community) contributors
// SPDX-License-Identifier: GPL-3.0-or-later

import Foundation
import Testing
@testable import GreenshotCore

/// Collects the frames a reply writes.
final class CollectingWriter: IPCFrameWriter, @unchecked Sendable {
    private let lock = NSLock()
    private var collected: [Data] = []

    func write(frame payload: Data) {
        lock.lock()
        collected.append(payload)
        lock.unlock()
    }

    var frames: [Data] {
        lock.lock()
        defer { lock.unlock() }
        return collected
    }

    var textFrames: [IPCTextFrame] { frames.compactMap(IPCTextFrame.init(payload:)) }

    var exitFrames: [IPCTextFrame] {
        textFrames.filter { if case .exit = $0 { return true } else { return false } }
    }

    var stdout: String {
        textFrames.map { frame -> String in
            if case .stdout(let data) = frame { return String(decoding: data, as: UTF8.self) }
            return ""
        }.joined()
    }

    var stderr: String {
        textFrames.map { frame -> String in
            if case .stderr(let data) = frame { return String(decoding: data, as: UTF8.self) }
            return ""
        }.joined()
    }

    var jsonObjects: [JSONObject] { frames.compactMap(IPCJSON.parseObject) }
}

private struct TestFailure: Error, LocalizedError {
    var errorDescription: String? { "boom" }
}

/// Upstream `IpcRequestContextTests`.
struct IPCReplyContextTests {
    @Test func streamsAndFinalReplyBecomeTextFrames() {
        let writer = CollectingWriter()
        let context = IPCReplyContext(envelope: IPCEnvelope(command: "X"), source: .cli, writer: writer, usesTextFrames: true)
        context.stream("progress", to: .stdout)
        context.stream("warning", to: .stderr)
        context.reply(IPCReply(status: "ok", exitCode: 4, stdout: "done", stderr: "careful"))
        #expect(writer.stdout == "progress\ndone\n")
        #expect(writer.stderr == "warning\ncareful\n")
        #expect(writer.exitFrames == [.exit(4)])
    }

    @Test func errorWithoutExitCodeExitsWithOne() {
        let writer = CollectingWriter()
        let context = IPCReplyContext(envelope: IPCEnvelope(command: "X"), source: .cli, writer: writer, usesTextFrames: true)
        context.reply(IPCReply(status: "error", exitCode: 0, stderr: "no"))
        #expect(writer.exitFrames == [.exit(1)])
    }

    @Test func jsonRequestPrintsTheReplyDocument() throws {
        let writer = CollectingWriter()
        var envelope = IPCEnvelope(command: "X")
        envelope.json = true
        let context = IPCReplyContext(envelope: envelope, source: .cli, writer: writer, usesTextFrames: true)
        context.reply(.ok("text", extra: ["version": .string("1")]))
        let stdout = writer.stdout
        let document = try #require(IPCJSON.parseObject(Data(stdout.utf8)))
        #expect(document["status"] == .string("ok"))
        #expect(document["version"] == .string("1"))
        #expect(writer.exitFrames == [.exit(0)])
    }

    @Test func completeWithoutReplySendsExitFrameOnce() {
        let writer = CollectingWriter()
        let context = IPCReplyContext(envelope: IPCEnvelope(command: "X"), source: .cli, writer: writer, usesTextFrames: true)
        context.complete()
        context.complete(exitCode: 5)
        context.reply(.ok("late"))
        #expect(writer.exitFrames == [.exit(0)])
        #expect(writer.stdout.isEmpty)
    }

    @Test func derivedContextSharesTheReply() {
        let writer = CollectingWriter()
        let context = IPCReplyContext(envelope: IPCEnvelope(command: "CLI"), source: .cli, writer: writer, usesTextFrames: true)
        context.with(envelope: IPCEnvelope(command: "VERSION")).reply(.ok("1.0"))
        #expect(context.isCompleted)
        context.complete()
        #expect(writer.exitFrames.count == 1)
    }

    @Test func jsonConnectionGetsObjects() {
        let writer = CollectingWriter()
        let context = IPCReplyContext(envelope: IPCEnvelope(command: "X"), source: .cli, writer: writer, usesTextFrames: false)
        context.stream("chunk", to: .stdout)
        context.reply(.error("bad", exitCode: 3))
        context.complete()
        let objects = writer.jsonObjects
        #expect(objects.count == 2)
        #expect(objects.first?["stream"] == .string("stdout"))
        #expect(objects.last?["exit_code"] == .number(3))
    }

    @Test func inProcessCallersReadTheFinalReply() {
        let context = IPCReplyContext(envelope: IPCEnvelope(command: "X"), source: .appleScript)
        context.reply(.ok("fine"))
        #expect(context.finalReply == .ok("fine"))
    }
}

/// Upstream `IpcSecurityDispatcherTests`.
struct IPCDispatcherTests {
    private func makeDispatcher() -> IPCDispatcher {
        let dispatcher = IPCDispatcher()
        for command in IPCWhitelist.standard.keys where command != IPCCommand.cli && command != IPCCommand.urlScheme {
            dispatcher.table.register(command) { context in
                .ok("\(context.envelope.command ?? "") \(context.envelope.parameter("tab") ?? context.envelope.parameter("mode") ?? "")")
            }
        }
        return dispatcher
    }

    private func run(_ envelope: IPCEnvelope, source: IPCSource, dispatcher: IPCDispatcher? = nil) async -> CollectingWriter {
        let writer = CollectingWriter()
        let context = IPCReplyContext(envelope: envelope, source: source, writer: writer, usesTextFrames: true)
        await (dispatcher ?? makeDispatcher()).dispatch(context)
        context.complete()
        return writer
    }

    private func link(_ url: String) -> IPCEnvelope {
        var envelope = IPCEnvelope(command: IPCCommand.urlScheme)
        envelope.rawInput = url
        return envelope
    }

    @Test(arguments: ["greenshotmac://exit", "greenshotmac:reload_config", "greenshotmac://first_launch",
                      "greenshotmac://open_file?path=/tmp/a.png", "greenshotmac://version"])
    func linksCannotReachCommandsForbiddenToWebPages(url: String) async {
        let writer = await run(link(url), source: .urlScheme)
        #expect(writer.stderr.contains("[SECURITY] IPC command rejected"))
        #expect(writer.exitFrames == [.exit(1)])
    }

    @Test func linkRunsItsCommandWithItsParameters() async {
        let writer = await run(link("greenshotmac://settings?tab=editor"), source: .urlScheme)
        #expect(writer.stdout == "SETTINGS editor\n")
        #expect(writer.exitFrames == [.exit(0)])
    }

    @Test func commandLineFromTheCLIReachesExit() async {
        let writer = await run(IPCEnvelope.commandLine(["--exit"], cwd: nil), source: .cli)
        #expect(writer.stdout == "EXIT \n")
    }

    @Test func linkFromTheCommandLineMayExit() async {
        let writer = await run(IPCEnvelope.commandLine(["greenshotmac://exit"], cwd: nil), source: .cli)
        #expect(writer.stdout == "EXIT \n")
    }

    @Test func usageErrorExitsWithTwo() async {
        let writer = await run(IPCEnvelope.commandLine(["--bogus"], cwd: nil), source: .cli)
        #expect(writer.stderr.contains("unrecognized option '--bogus'"))
        #expect(writer.exitFrames == [.exit(2)])
    }

    @Test func commandLinesFromLinksCannotReachExit() async {
        // Upstream Dispatch_Cli_FromUrlScheme_CannotReachExit: a link source only parses one link
        let writer = await run(IPCEnvelope.commandLine(["--exit"], cwd: nil), source: .urlScheme)
        #expect(writer.stderr.contains("[SECURITY]"))
        #expect(writer.exitFrames == [.exit(1)])
    }

    @Test func unknownAndMissingCommandsAreRejected() async {
        let unknown = await run(IPCEnvelope(command: "FORMAT_DISK"), source: .cli)
        #expect(unknown.stderr.contains("not in the allowed command whitelist"))
        let missing = await run(IPCEnvelope(command: nil), source: .cli)
        #expect(missing.stderr.contains("Missing command."))
        let nowhere = await run(link("greenshotmac://cli"), source: .urlScheme)
        #expect(nowhere.stderr.contains("Missing command."))
    }

    @Test func signInLinkIsIgnoredQuietly() async {
        let writer = await run(link("greenshotmac://oauth/dropbox?code=1"), source: .urlScheme)
        #expect(writer.stderr.isEmpty)
        #expect(writer.exitFrames == [.exit(0)])
    }

    @Test func accessCheckVetoes() async {
        let dispatcher = makeDispatcher()
        dispatcher.accessCheck = { command, context in
            command == IPCCommand.capture && context.source == .urlScheme ? "Capture links are off." : nil
        }
        let refused = await run(link("greenshotmac://capture/region"), source: .urlScheme, dispatcher: dispatcher)
        #expect(refused.stderr == "Capture links are off.\n")
        let allowed = await run(IPCEnvelope.commandLine(["--capture", "region"], cwd: nil), source: .cli, dispatcher: dispatcher)
        #expect(allowed.stdout == "CAPTURE region\n")
    }

    @Test func throwingHandlerStillEndsWithOneExitFrame() async {
        let dispatcher = IPCDispatcher()
        dispatcher.table.register(IPCCommand.version) { _ in throw TestFailure() }
        let writer = await run(IPCEnvelope(command: "VERSION"), source: .cli, dispatcher: dispatcher)
        #expect(writer.stderr.contains("Greenshot failed to handle the command: boom"))
        #expect(writer.exitFrames == [.exit(1)])
    }

    @Test func handlerWithoutReplyEndsWithZero() async {
        let dispatcher = IPCDispatcher()
        dispatcher.table.register(IPCCommand.version) { _ in nil }
        let writer = await run(IPCEnvelope(command: "VERSION"), source: .cli, dispatcher: dispatcher)
        #expect(writer.exitFrames == [.exit(0)])
    }

    @Test func unavailableCommandsSaySo() async {
        let dispatcher = IPCDispatcher()
        dispatcher.table.registerUnavailable([IPCCommand.runRecipe], message: IPCCommandLine.recipesUnavailable)
        let writer = await run(IPCEnvelope.commandLine(["--recipe", "ocr"], cwd: nil), source: .cli, dispatcher: dispatcher)
        #expect(writer.stderr.contains("recipes are not available yet"))
        #expect(writer.exitFrames == [.exit(1)])
    }
}

struct IPCWhitelistTests {
    private let table: IPCCommandTable = {
        let table = IPCCommandTable()
        for command in IPCWhitelist.standard.keys { table.register(command) { _ in nil } }
        return table
    }()

    @Test func commandLineMayUseEveryCommand() {
        for command in IPCWhitelist.standard.keys {
            #expect(table.isAllowed(command, for: .cli))
        }
    }

    @Test func linksOnlyShowWindowsOrCapture() {
        let allowed = Set(IPCWhitelist.standard.keys.filter { table.isAllowed($0, for: .urlScheme) })
        let expected: Set<String> = ["URL_SCHEME", "SETTINGS", "ABOUT", "SELF_SERVICE", "LOG_VIEWER", "CAPTURE", "OPEN_CLIPBOARD",
                                     "RUN_RECIPE", "RECIPE_EDITOR", "RECIPE_MANAGER"]
        #expect(allowed == expected)
    }

    @Test func finderOpensOnlyFiles() {
        let allowed = Set(IPCWhitelist.standard.keys.filter { table.isAllowed($0, for: .openWith) })
        #expect(allowed == ["OPEN_FILE"])
    }

    @Test func browserExtensionAndAIToolsHaveNothingYet() {
        for command in IPCWhitelist.standard.keys {
            #expect(!table.isAllowed(command, for: .nativeMessaging))
            #expect(!table.isAllowed(command, for: .mcp))
        }
    }

    @Test func unknownCommandIsNotAllowedAndNamesAreCaseInsensitive() {
        #expect(!table.isAllowed("FORMAT_DISK", for: .cli))
        #expect(table.isAllowed("settings", for: .urlScheme))
    }
}
