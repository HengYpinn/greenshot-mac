// Greenshot for Mac (Community) - an unofficial macOS port of Greenshot
// Copyright (C) 2026 Greenshot for Mac (Community) contributors
// SPDX-License-Identifier: GPL-3.0-or-later

import Darwin
import Foundation
import Testing
@testable import GreenshotCore

struct IPCFramingTests {
    @Test func lengthPrefixIsLittleEndian() {
        let frame = IPCFrame.encode(Data("{}".utf8))
        let prefix = [UInt8](frame.prefix(4))
        #expect(prefix == [2, 0, 0, 0])
        #expect(frame.count == 6)
        let big = IPCFrame.encode(Data(count: 0x0102_03))
        let bigPrefix = [UInt8](big.prefix(4))
        #expect(bigPrefix == [0x03, 0x02, 0x01, 0x00])
        let length = IPCFrame.length(ofPrefix: Data(bigPrefix))
        #expect(length == 0x0102_03)
    }

    @Test func textFramesRoundTrip() {
        let out = IPCTextFrame.stdout(Data("hello\n".utf8))
        #expect(IPCTextFrame(payload: out.payload) == out)
        let err = IPCTextFrame.stderr(Data("bad\n".utf8))
        #expect(IPCTextFrame(payload: err.payload) == err)
        let exit = IPCTextFrame.exit(-2)
        let exitPayload = exit.payload
        #expect(exitPayload.count == 5)
        #expect(exitPayload.first == UInt8(ascii: "X"))
        #expect(IPCTextFrame(payload: exitPayload) == exit)
    }

    @Test func shortExitFrameMeansFailureAndUnknownTypesAreRejected() {
        #expect(IPCTextFrame(payload: Data([UInt8(ascii: "X")])) == .exit(1))
        #expect(IPCTextFrame(payload: Data("{}".utf8)) == nil)
        #expect(IPCTextFrame(payload: Data()) == nil)
    }

    @Test func textFrameGetsANewlineAndEmptyTextNone() {
        #expect(IPCTextFrame.text("Done", to: .stdout) == .stdout(Data("Done\n".utf8)))
        #expect(IPCTextFrame.text("Line\n", to: .stderr) == .stderr(Data("Line\n".utf8)))
        #expect(IPCTextFrame.text("", to: .stdout) == nil)
        #expect(IPCTextFrame.text(nil, to: .stdout) == nil)
    }

    @Test func readerRejectsLengthsOutsideTheLimits() throws {
        var fds: [Int32] = [-1, -1]
        #expect(socketpair(AF_UNIX, SOCK_STREAM, 0, &fds) == 0)
        defer { fds.forEach { close($0) } }
        IPCSocket.setTimeout(fds[1], option: SO_RCVTIMEO, seconds: 5)
        // The payload of a refused length isn't read
        try IPCFrameIO.writeAll(fds[0], Data([1, 0, 0, 0]))
        #expect(throws: IPCIOError.invalidLength(1)) { try IPCFrameIO.readFrame(fds[1], minimum: 2) }

        let tooLong = UInt32(IPCFrame.maximumLength + 1)
        let prefix: [UInt8] = [UInt8(truncatingIfNeeded: tooLong), UInt8(truncatingIfNeeded: tooLong >> 8),
                               UInt8(truncatingIfNeeded: tooLong >> 16), UInt8(truncatingIfNeeded: tooLong >> 24)]
        try IPCFrameIO.writeAll(fds[0], Data(prefix))
        #expect(throws: IPCIOError.invalidLength(tooLong)) { try IPCFrameIO.readFrame(fds[1], minimum: 2) }
    }

    @Test func readerSeesCleanEndAndTruncation() throws {
        var fds: [Int32] = [-1, -1]
        #expect(socketpair(AF_UNIX, SOCK_STREAM, 0, &fds) == 0)
        IPCSocket.setTimeout(fds[1], option: SO_RCVTIMEO, seconds: 5)
        try IPCFrameIO.writeFrame(fds[0], Data("{\"a\":1}".utf8))
        let payload = try IPCFrameIO.readFrame(fds[1], minimum: 2)
        #expect(payload == Data("{\"a\":1}".utf8))
        try IPCFrameIO.writeAll(fds[0], Data([5, 0, 0, 0, 0x7B]))
        close(fds[0])
        #expect(throws: IPCIOError.truncated) { try IPCFrameIO.readFrame(fds[1], minimum: 2) }
        let end = try IPCFrameIO.readFrame(fds[1], minimum: 2)
        #expect(end == nil)
        close(fds[1])
    }
}

/// Frames of clients that send slowly or announce more than they send (same-user denial of service).
struct IPCFrameLimitTests {
    private func pair() -> [Int32] {
        var fds: [Int32] = [-1, -1]
        _ = socketpair(AF_UNIX, SOCK_STREAM, 0, &fds)
        IPCSocket.setNoSigPipe(fds[0])
        IPCSocket.setNoSigPipe(fds[1])
        IPCSocket.setTimeout(fds[1], option: SO_RCVTIMEO, seconds: 5)
        return fds
    }

    @Test func lengthAboveTheCapIsRefusedBeforeReading() throws {
        let fds = pair()
        defer { fds.forEach { close($0) } }
        let announced = UInt32(100_000)
        let prefix: [UInt8] = [UInt8(truncatingIfNeeded: announced), UInt8(truncatingIfNeeded: announced >> 8),
                               UInt8(truncatingIfNeeded: announced >> 16), 0]
        try IPCFrameIO.writeAll(fds[0], Data(prefix))
        #expect(throws: IPCIOError.invalidLength(100_000)) {
            try IPCFrameIO.readFrame(fds[1], minimum: 2, maximum: IPCFrame.maximumHelloLength)
        }
    }

    @Test func deadlineCoversTheWholeFrameNotEachRead() throws {
        let fds = pair()
        defer { fds.forEach { close($0) } }
        // A byte every 50 ms: each read gets data in time, the frame never completes
        let writer = fds[0]
        let trickle = Thread {
            let frame = IPCFrame.encode(Data(repeating: 0x20, count: 40))
            for byte in frame {
                var value = byte
                if Darwin.write(writer, &value, 1) != 1 { return }
                usleep(50_000)
            }
        }
        trickle.start()
        let started = Date()
        #expect(throws: IPCIOError.timedOut) {
            try IPCFrameIO.readFrame(fds[1], minimum: 2, deadline: Date().addingTimeInterval(0.3))
        }
        let elapsed = Date().timeIntervalSince(started)
        #expect(elapsed < 1.5)
        shutdown(fds[1], SHUT_RDWR)
    }

    @Test func largeFrameArrivesInPieces() throws {
        let fds = pair()
        defer { fds.forEach { close($0) } }
        let payload = Data((0..<300_000).map { UInt8(truncatingIfNeeded: $0) })
        let frame = IPCFrame.encode(payload)
        let writer = fds[0]
        let sender = Thread {
            var offset = 0
            while offset < frame.count {
                let end = min(offset + 7_000, frame.count)
                try? IPCFrameIO.writeAll(writer, frame.subdata(in: offset..<end))
                offset = end
            }
        }
        sender.start()
        let received = try IPCFrameIO.readFrame(fds[1], minimum: 2)
        #expect(received == payload)
    }
}

struct IPCEnvelopeTests {
    @Test func commandLineRequestMatchesTheProxys() throws {
        // greenshot-proxy/protocol.c SendCliRequest
        let envelope = IPCEnvelope.commandLine(["--file", "a.png"], cwd: "/Users/me")
        let object = try #require(IPCJSON.parseObject(IPCJSON.data(envelope.jsonObject)))
        #expect(object["version"] == .number(1))
        #expect(object["command"] == .string("CLI"))
        #expect(object["cwd"] == .string("/Users/me"))
        #expect(object["argv"] == .array([.string("--file"), .string("a.png")]))
    }

    @Test func helloCarriesSourceFormatAndClient() {
        let hello = IPCEnvelope.hello(source: .cli, replyFormat: .text, client: "greenshot-cli", clientVersion: "1.0")
        let object = hello.jsonObject
        #expect(object["command"] == .string("HELLO"))
        #expect(object["source"] == .string("cli"))
        #expect(object["reply_format"] == .string("text"))
        #expect(object["client"] == .string("greenshot-cli"))
        #expect(object["client_version"] == .string("1.0"))
        #expect(IPCEnvelope(json: object).isHello)
    }

    @Test func readsKnownMembersLenientlyAndKeepsTheRest() {
        let text = #"{"command":"OPEN_FILE","files":["a.png",3],"json":"yes","parameters":{"Tab":"editor"},"payload":{"x":1}}"#
        let object = IPCJSON.parseObject(Data(text.utf8)) ?? [:]
        let envelope = IPCEnvelope(json: object)
        #expect(envelope.command == "OPEN_FILE")
        #expect(envelope.files == ["a.png"])
        #expect(envelope.json == false)
        #expect(envelope.parameter("tab") == "editor")
        #expect(envelope.extra["payload"] == .object(["x": .number(1)]))
        #expect(envelope.version == 1)
    }

    @Test func parametersAreCaseInsensitiveAndTheLastOneWins() {
        var envelope = IPCEnvelope(command: "SETTINGS")
        envelope.setParameter("Tab", "general")
        envelope.setParameter("TAB", "editor")
        #expect(envelope.parameter("tab") == "editor")
        #expect(envelope.parameters.count == 1)
    }

    @Test func notJSONOrNotAnObjectIsRejected() {
        #expect(IPCJSON.parseObject(Data("[1,2]".utf8)) == nil)
        #expect(IPCJSON.parseObject(Data("{".utf8)) == nil)
    }

    @Test func replyJSONHasExitCodeAsInteger() {
        let reply = IPCReply.ok("Greenshot for Mac version 1.0", extra: ["version": .string("1.0")])
        let text = IPCJSON.text(reply.jsonObject)
        #expect(text.contains("\"exit_code\":0"))
        #expect(text.contains("\"version\":\"1.0\""))
        #expect(!text.contains("stderr"))
        let back = IPCReply(json: reply.jsonObject)
        #expect(back == reply)
    }

    @Test func booleansStayBooleans() {
        let object = IPCJSON.parseObject(Data(#"{"a":true,"b":1}"#.utf8)) ?? [:]
        #expect(object["a"] == .bool(true))
        #expect(object["b"] == .number(1))
    }

    @Test func captureModesAndAliases() {
        #expect(AutomationCaptureMode(name: "region") == .region)
        #expect(AutomationCaptureMode(name: "Full-Screen") == .fullScreen)
        #expect(AutomationCaptureMode(name: "fullscreen") == .fullScreen)
        #expect(AutomationCaptureMode(name: "last_region") == .lastRegion)
        #expect(AutomationCaptureMode(name: "last") == .lastRegion)
        #expect(AutomationCaptureMode(name: "WINDOW") == .window)
        #expect(AutomationCaptureMode(name: "ocr") == .text)
        #expect(AutomationCaptureMode(name: "movie") == nil)
        #expect(AutomationCaptureMode(name: nil) == nil)
    }
}
