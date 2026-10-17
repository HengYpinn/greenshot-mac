// Greenshot for Mac (Community) - an unofficial macOS port of Greenshot
// Copyright (C) 2026 Greenshot for Mac (Community) contributors
// SPDX-License-Identifier: GPL-3.0-or-later

import Foundation
import Testing
@testable import GreenshotCore

/// Upstream `Greenshot.Tests/Core/ExceptionHelperTests.cs` and the crash detection at the next launch.
struct DiagnosticCrashTests {
    /// Shaped like a real macOS 27 crash report (bug type 309), shortened.
    static let ips = """
        {"app_name":"GreenshotMac","timestamp":"2026-10-17 12:42:18.00 +0800","app_version":"1.4.0","slice_uuid":"0b1c","build_version":"140","platform":1,"bug_type":"309","os_version":"macOS 27.0 (27A100)","incident_id":"6F2A","name":"GreenshotMac"}
        {
          "uptime" : 9000,
          "procName" : "GreenshotMac",
          "pid" : 4242,
          "procLaunch" : "2026-10-17 12:40:01.1000 +0800",
          "captureTime" : "2026-10-17 12:42:16.0843 +0800",
          "exception" : {"codes":"0x0000000000000001, 0x000000010040827c","rawCodes":[1,4299260540],"type":"EXC_BREAKPOINT","signal":"SIGTRAP"},
          "termination" : {"flags":0,"code":5,"namespace":"SIGNAL","indicator":"Trace/BPT trap: 5","byProc":"exc handler","byPid":4242},
          "asi" : {"libswiftCore.dylib":["GreenshotMac/CaptureCoordinator.swift:120: Fatal error: Unexpectedly found nil while unwrapping an Optional value"]},
          "faultingThread" : 0,
          "threads" : [{"triggered":true,"id":1,"queue":"com.apple.main-thread","frames":[
            {"imageOffset":4668293756,"symbol":"Swift._assertionFailure(_: Swift.StaticString, _: Swift.String, file: Swift.StaticString, line: Swift.UInt, flags: Swift.UInt32) -> Swift.Never","symbolLocation":172,"imageIndex":1},
            {"imageOffset":81234,"symbol":"CaptureCoordinator.finish(_:)","symbolLocation":908,"imageIndex":0},
            {"imageOffset":80000,"symbol":"closure #1 in CaptureCoordinator.captureRegion()","symbolLocation":44,"imageIndex":0},
            {"imageOffset":12345,"imageIndex":0},
            {"imageOffset":2000,"symbol":"-[NSApplication run]","symbolLocation":400,"imageIndex":2}
          ]},{"id":2,"frames":[{"imageOffset":1,"symbol":"__workq_kernreturn","imageIndex":3}]}],
          "usedImages" : [
            {"source":"P","arch":"arm64","base":4294967296,"name":"GreenshotMac","path":"/Applications/Greenshot for Mac (Community).app/Contents/MacOS/GreenshotMac","size":1,"uuid":"0b1c"},
            {"source":"P","arch":"arm64e","base":1,"name":"libswiftCore.dylib","path":"/usr/lib/swift/libswiftCore.dylib","size":1,"uuid":"aa"},
            {"source":"P","arch":"arm64e","base":2,"name":"AppKit","path":"/System/Library/Frameworks/AppKit.framework/Versions/C/AppKit","size":1,"uuid":"bb"},
            {"source":"P","arch":"arm64e","base":3,"path":"/usr/lib/system/libsystem_kernel.dylib","size":1,"uuid":"cc"}
          ]
        }
        """

    @Test func parsesACrashReport() throws {
        let report = try #require(CrashReportFile.parse(Self.ips, fileName: "GreenshotMac-2026-10-17-124218.ips"))
        #expect(report.processName == "GreenshotMac")
        #expect(report.pid == 4242)
        #expect(report.appVersion == "1.4.0")
        #expect(report.typeText == "EXC_BREAKPOINT (SIGTRAP)")
        #expect(report.messages.count == 1)
        #expect(report.messages.first?.contains("Fatal error: Unexpectedly found nil") == true)
        #expect(report.frames.count == 5)
        #expect(report.frames[1] == CrashFrame(image: "GreenshotMac", symbol: "CaptureCoordinator.finish(_:)", imageOffset: 81234))
        #expect(report.frames[3].symbol == nil)
        #expect(report.frames[4].image == "AppKit")
        let captured = try #require(report.captureTime)
        #expect(captured.timeIntervalSince1970 > 1_790_000_000)
    }

    @Test func withoutMessagesTheTerminationSaysHowItEnded() throws {
        let withoutASI = Self.ips.replacingOccurrences(of: #""asi" : {"libswiftCore.dylib":["GreenshotMac/CaptureCoordinator.swift:120: Fatal error: Unexpectedly found nil while unwrapping an Optional value"]},"#, with: "")
        let report = try #require(CrashReportFile.parse(withoutASI, fileName: "a.ips"))
        #expect(report.messages.isEmpty)
        #expect(report.termination == "Trace/BPT trap: 5")
        #expect(report.details.message == "GreenshotMac quit unexpectedly (Trace/BPT trap: 5): a runtime error of the app, see the stack.")
    }

    @Test func otherReportsAreIgnored() {
        #expect(CrashReportFile.parse("not json", fileName: "x.ips") == nil)
        let hang = #"{"bug_type":"288","app_name":"GreenshotMac"}"# + "\n{}"
        #expect(CrashReportFile.parse(hang, fileName: "x.hang") == nil)
    }

    @Test func normalizesToOwnFramesWithoutMessages() throws {
        let report = try #require(CrashReportFile.parse(Self.ips, fileName: "a.ips"))
        let normalized = IssueLinks.normalized(report.details)
        #expect(normalized == """
            EXC_BREAKPOINT (SIGTRAP)
            at GreenshotMac!CaptureCoordinator.finish(_:)
            at GreenshotMac!closure #1 in CaptureCoordinator.captureRegion()
            at GreenshotMac+0x3039
            """)
        #expect(!normalized.contains("Fatal error"))
    }

    @Test func withoutOwnFramesEverySymbolCounts() {
        let details = CrashDetails(kind: .caughtException, type: "NSRangeException", message: "index 3 beyond bounds",
                                   frames: [CrashFrame(image: "CoreFoundation", symbol: "__exceptionPreprocess"),
                                            CrashFrame(image: "libobjc.A.dylib", symbol: "objc_exception_throw"),
                                            CrashFrame(image: "AppKit", symbol: nil, imageOffset: 12)])
        #expect(IssueLinks.normalized(details) == "NSRangeException\nat CoreFoundation!__exceptionPreprocess\nat libobjc.A.dylib!objc_exception_throw")
    }

    @Test func hashIsTwelveHexDigitsAndStable() {
        let first = IssueLinks.hash(of: "NSRangeException\nat GreenshotMac!f()")
        #expect(first.count == 12)
        let hex = first.allSatisfy { "0123456789abcdef".contains($0) }
        #expect(hex)
        #expect(first == IssueLinks.hash(of: "  NSRangeException\nat GreenshotMac!f()\n"))
        #expect(first != IssueLinks.hash(of: "NSRangeException\nat GreenshotMac!g()"))
        #expect(IssueLinks.hash(of: "  ").isEmpty)
        // SHA-256 of "abc" starts with ba7816bf8f01.
        #expect(IssueLinks.hash(of: "abc") == "ba7816bf8f01")
    }

    @Test func messagesDontChangeTheHash() {
        let frames = [CrashFrame(image: "GreenshotMac", symbol: "Editor.save()")]
        let a = CrashDetails(kind: .caughtException, type: "NSGenericException", message: "file a.png", frames: frames)
        let b = CrashDetails(kind: .uncaughtException, type: "NSGenericException", message: "file b.png", frames: frames)
        #expect(IssueLinks.hash(of: a) == IssueLinks.hash(of: b))
    }

    @Test func searchAndNewIssueLinks() throws {
        let search = IssueLinks.searchURL(hash: "0123456789ab").absoluteString
        #expect(search == "https://github.com/HengYpinn/greenshot-mac/issues?q=is%3Aissue%20%22%5Bstack-trace-hash%3A%200123456789ab%5D%22")
        #expect(IssueLinks.searchURL(hash: "").absoluteString == "https://github.com/HengYpinn/greenshot-mac/issues")
        let issue = IssueLinks.newIssueURL(hash: "0123456789ab", type: "EXC_BAD_ACCESS (SIGSEGV)", environment: "macOS 27.0")
        let components = try #require(URLComponents(url: issue, resolvingAgainstBaseURL: false))
        let items = components.queryItems ?? []
        #expect(components.path == "/HengYpinn/greenshot-mac/issues/new")
        #expect(items.first { $0.name == "title" }?.value == "[0123456789ab] EXC_BAD_ACCESS (SIGSEGV)")
        let body = try #require(items.first { $0.name == "body" }?.value)
        #expect(body.contains("[stack-trace-hash: 0123456789ab]"))
        #expect(body.contains("macOS 27.0"))
        #expect(!issue.absoluteString.contains("+"))
    }

    @Test func parsesCallStackSymbols() {
        let frame = CrashFrame(callStackSymbol: "3   GreenshotMac                        0x0000000100a2c3f0 $s12GreenshotMac11AppDelegateC4quityyF + 120")
        #expect(frame == CrashFrame(image: "GreenshotMac", symbol: "$s12GreenshotMac11AppDelegateC4quityyF"))
        let objc = CrashFrame(callStackSymbol: "0   CoreFoundation                      0x000000018b2a2d5c __exceptionPreprocess + 176")
        #expect(objc?.symbol == "__exceptionPreprocess")
        #expect(CrashFrame(callStackSymbol: "garbage") == nil)
    }

    @Test func reportTextHasUpstreamsSections() {
        let details = CrashDetails(kind: .crashReport, type: "EXC_CRASH (SIGABRT)", message: "saving /Users/alex/Desktop/a.png",
                                   frames: [CrashFrame(image: "GreenshotMac", symbol: "f()")], reportFile: "GreenshotMac-1.ips")
        let text = details.reportText(home: "/Users/alex")
        #expect(text.hasPrefix("Exception: EXC_CRASH (SIGABRT)\nMessage: saving ~/Desktop/a.png\n"))
        #expect(text.contains("Crash report: GreenshotMac-1.ips"))
        #expect(text.hasSuffix("Stack:\n0  GreenshotMac  f()"))
    }

    // MARK: The previous run

    private let launched = Date(timeIntervalSince1970: 1_790_000_000)
    private var marker: RunMarker { RunMarker(pid: 4242, launched: launched, version: "1.4.0", processName: "GreenshotMac") }

    @Test func noMarkerIsAClean() {
        #expect(PreviousRun.evaluate(marker: nil, currentPID: 1, isRunning: { _ in false }, exceptionNote: nil, reports: []) == .clean)
    }

    @Test func aRunningCopyIsNotACrash() {
        #expect(PreviousRun.evaluate(marker: marker, currentPID: 1, isRunning: { $0 == 4242 }, exceptionNote: nil, reports: []) == .clean)
        #expect(PreviousRun.evaluate(marker: marker, currentPID: 4242, isRunning: { _ in false }, exceptionNote: nil, reports: []) == .clean)
    }

    @Test func aMarkerWithoutReportEndedAbnormally() {
        let result = PreviousRun.evaluate(marker: marker, currentPID: 1, isRunning: { _ in false }, exceptionNote: nil, reports: [])
        #expect(result == .endedAbnormally(marker))
        #expect(result.endedAbnormally)
    }

    @Test func theReportOfThatProcessIsTheCrash() throws {
        var report = try #require(CrashReportFile.parse(Self.ips, fileName: "a.ips"))
        report.captureTime = launched.addingTimeInterval(120)
        var other = report
        other.pid = 9
        let result = PreviousRun.evaluate(marker: marker, currentPID: 1, isRunning: { _ in false }, exceptionNote: nil,
                                          reports: [other, report])
        #expect(result == .crashed(marker, report.details))
        // A report of an earlier run with the same id doesn't count.
        report.captureTime = launched.addingTimeInterval(-3_600)
        let old = PreviousRun.evaluate(marker: marker, currentPID: 1, isRunning: { _ in false }, exceptionNote: nil, reports: [report])
        #expect(old == .endedAbnormally(marker))
    }

    @Test func aReportWithAProcessIDBeyondInt32IsNoMatch() throws {
        var report = try #require(CrashReportFile.parse(Self.ips, fileName: "a.ips"))
        report.captureTime = launched.addingTimeInterval(120)
        report.pid = Int(Int32.max) + 1
        let result = PreviousRun.evaluate(marker: marker, currentPID: 1, isRunning: { _ in false }, exceptionNote: nil,
                                          reports: [report])
        #expect(result == .endedAbnormally(marker))
    }

    @Test func theExceptionNoteComesFirst() {
        let note = CrashDetails(kind: .uncaughtException, type: "NSInvalidArgumentException", message: "unrecognized selector",
                                frames: [], date: launched.addingTimeInterval(30))
        let result = PreviousRun.evaluate(marker: marker, currentPID: 1, isRunning: { _ in false }, exceptionNote: note, reports: [])
        #expect(result == .crashed(marker, note))
        var older = note
        older.date = launched.addingTimeInterval(-86_400)
        let stale = PreviousRun.evaluate(marker: marker, currentPID: 1, isRunning: { _ in false }, exceptionNote: older, reports: [])
        #expect(stale == .endedAbnormally(marker))
    }

    @Test func detailsRoundTripAsJSON() throws {
        let note = CrashDetails(kind: .uncaughtException, type: "NSGenericException", message: "m",
                                frames: [CrashFrame(image: "AppKit", symbol: "x")], date: launched)
        let data = try JSONEncoder().encode(note)
        let decoded = try JSONDecoder().decode(CrashDetails.self, from: data)
        #expect(decoded == note)
    }
}
