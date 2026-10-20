// Greenshot for Mac (Community) - an unofficial macOS port of Greenshot
// Copyright (C) 2026 Greenshot for Mac (Community) contributors
// SPDX-License-Identifier: GPL-3.0-or-later

import Foundation
import Testing
@testable import GreenshotCore

struct LogFileTests {
    private func temporaryFolder() throws -> URL {
        let folder = FileManager.default.temporaryDirectory.appendingPathComponent("LogFileTests-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        return folder
    }

    private func read(_ url: URL) throws -> String {
        try String(contentsOf: url, encoding: .utf8)
    }

    @Test func entryLayoutIsLikeLog4net() {
        let date = DateComponents(calendar: Calendar(identifier: .gregorian), timeZone: .current,
                                  year: 2026, month: 10, day: 16, hour: 9, minute: 5, second: 7, nanosecond: 42_000_000).date
        let entry = LogFile.entry(date: date ?? Date(), thread: "main", level: .info, category: "Capture",
                                  message: "Captured", error: nil)
        #expect(entry == "2026-10-16 09:05:07,042 [main] INFO  - [Capture] Captured\n")
        let warning = LogFile.entry(date: date ?? Date(), thread: "7", level: .error, category: "Output",
                                    message: "Saving failed", error: CocoaError(.fileWriteNoPermission))
        let lines = warning.split(separator: "\n", omittingEmptySubsequences: false)
        #expect(lines.count == 3)
        #expect(lines[0] == "2026-10-16 09:05:07,042 [7] ERROR - [Output] Saving failed")
        #expect(lines[1].contains("CocoaError"))
        #expect(lines[1].contains("NSCocoaErrorDomain 513"))
    }

    @Test func errorLinesAreIndentedInTheFile() throws {
        let folder = try temporaryFolder()
        let hub = LogHub(level: .debug, unifiedLog: false)
        hub.startFile(at: folder.appendingPathComponent(LogFile.fileName))
        hub.write(.warn, category: "Upload", message: "Upload failed", error: URLError(.timedOut))
        let text = try read(folder.appendingPathComponent(LogFile.fileName))
        let lines = text.split(separator: "\n")
        #expect(lines.count == 2)
        #expect(lines[1].hasPrefix(LogSanitizer.indent))
        #expect(LogSearch.filter(text, search: "timed").entryCount == 1)
    }

    @Test func levelGateAndLevelChangeIsLogged() throws {
        let folder = try temporaryFolder()
        let url = folder.appendingPathComponent(LogFile.fileName)
        let hub = LogHub(level: .info, unifiedLog: false)
        hub.startFile(at: url)
        #expect(!hub.isEnabled(.debug))
        #expect(hub.isEnabled(.error))
        hub.changeLevel(to: .error, note: "in a test")
        #expect(hub.level == .error)
        hub.changeLevel(to: .debug, note: "again")
        #expect(hub.level == .debug)
        let text = try read(url)
        #expect(text.contains("Log level changed from INFO to ERROR in a test"))
        #expect(text.contains("Log level changed from ERROR to DEBUG again"))
    }

    @Test func rollsOverAndKeepsThreeOlderFiles() throws {
        let folder = try temporaryFolder()
        let url = folder.appendingPathComponent(LogFile.fileName)
        let writer = LogFileWriter(url: url, maxSize: 100, backups: 3)
        for number in 1...6 {
            // Each write is more than the maximum: every next write rolls the file over.
            writer.append(String(repeating: "\(number)", count: 120) + "\n")
        }
        writer.close()
        #expect(try read(url).hasPrefix("6"))
        #expect(try read(URL(fileURLWithPath: url.path + ".1")).hasPrefix("5"))
        #expect(try read(URL(fileURLWithPath: url.path + ".2")).hasPrefix("4"))
        #expect(try read(URL(fileURLWithPath: url.path + ".3")).hasPrefix("3"))
        #expect(!FileManager.default.fileExists(atPath: url.path + ".4"))
    }

    @Test func appendsToAnExistingFile() throws {
        let folder = try temporaryFolder()
        let url = folder.appendingPathComponent(LogFile.fileName)
        try Data("earlier\n".utf8).write(to: url)
        let writer = LogFileWriter(url: url)
        writer.append("later\n")
        writer.close()
        #expect(try read(url) == "earlier\nlater\n")
    }

    @Test func liveTailCollectsOnlyWhileOpen() {
        let hub = LogHub(level: .debug, unifiedLog: false)
        hub.write(.info, category: "Test", message: "before", error: nil)
        let tail = hub.beginLiveTail()
        hub.write(.error, category: "Test", message: "Log viewer test entry", error: nil)
        let taken = tail.take()
        #expect(taken.contains("Log viewer test entry"))
        #expect(taken.contains("ERROR"))
        #expect(!taken.contains("before"))
        #expect(tail.take().isEmpty)
        tail.end()
        hub.write(.error, category: "Test", message: "after the viewer closed", error: nil)
        #expect(tail.take().isEmpty)
    }

    @Test func readsTheTailFromAWholeLine() throws {
        let folder = try temporaryFolder()
        let url = folder.appendingPathComponent(LogFile.fileName)
        let lines = (1...100).map { String(format: "line %03d", $0) }
        try Data((lines.joined(separator: "\n") + "\n").utf8).write(to: url)
        let total = (lines.joined(separator: "\n") + "\n").utf8.count

        let tail = try LogFile.readTail(url, bytes: 50)
        #expect(tail.fileLength == total)
        #expect(tail.text.hasPrefix("line"))
        #expect(tail.text.hasSuffix("line 100\n"))
        #expect(tail.hasEarlier)
        #expect(tail.startOffset == total - tail.text.utf8.count)

        let earlier = try LogFile.readEarlier(url, before: tail.startOffset, bytes: 50)
        #expect(earlier.text.hasPrefix("line"))
        #expect((earlier.text + tail.text).hasSuffix("line 100\n"))
        #expect(earlier.startOffset < tail.startOffset)

        let rest = try LogFile.readEarlier(url, before: earlier.startOffset, bytes: nil)
        #expect(rest.startOffset == 0)
        #expect(!rest.hasEarlier)
        #expect(rest.text + earlier.text + tail.text == lines.joined(separator: "\n") + "\n")
    }

    @Test func aChunkStartingAtALineKeepsThatLine() throws {
        let folder = try temporaryFolder()
        let url = folder.appendingPathComponent(LogFile.fileName)
        // 100 lines of 9 bytes: the last 90 bytes are exactly the last 10 lines.
        let lines = (1...100).map { String(format: "line %03d\n", $0) }
        try Data(lines.joined().utf8).write(to: url)
        let tail = try LogFile.readTail(url, bytes: 90)
        #expect(tail.text == lines.suffix(10).joined())
        #expect(tail.startOffset == 810)
        let earlier = try LogFile.readEarlier(url, before: tail.startOffset, bytes: 90)
        #expect(earlier.text == lines[80..<90].joined())
    }

    @Test func loadingEarlierGoesOnThroughALineLongerThanTheChunk() throws {
        let folder = try temporaryFolder()
        let url = folder.appendingPathComponent(LogFile.fileName)
        let content = "first\n" + String(repeating: "x", count: 70_000) + "\nlast\n"
        try Data(content.utf8).write(to: url)
        var chunk = try LogFile.readTail(url, bytes: 20)
        #expect(chunk.text == "last\n")
        var text = chunk.text
        var reads = 0
        while chunk.hasEarlier, reads < 20 {
            let earlier = try LogFile.readEarlier(url, before: chunk.startOffset, bytes: LogFile.chunkBytes)
            #expect(earlier.startOffset < chunk.startOffset)
            text = earlier.text + text
            chunk = earlier
            reads += 1
        }
        #expect(chunk.startOffset == 0)
        #expect(text == content)
        // The tail of a file that ends with a line longer than the chunk is a part of that line, not nothing.
        let long = folder.appendingPathComponent("long.log")
        try Data((String(repeating: "y", count: 70_000) + "\n").utf8).write(to: long)
        let tail = try LogFile.readTail(long)
        #expect(tail.text.count == LogFile.chunkBytes)
        let rest = try LogFile.readEarlier(long, before: tail.startOffset)
        let whole = rest.text + tail.text
        #expect(rest.startOffset == 0)
        #expect(whole.count == 70_001)
    }

    @Test func aChunkInsideALineStartsAtACharacter() throws {
        let folder = try temporaryFolder()
        let url = folder.appendingPathComponent(LogFile.fileName)
        // 3 bytes a character: a chunk of 101 bytes starts inside one.
        let content = String(repeating: "語", count: 100) + "\n"
        try Data(content.utf8).write(to: url)
        var chunk = try LogFile.readTail(url, bytes: 101)
        var text = chunk.text
        var reads = 0
        while chunk.hasEarlier, reads < 10 {
            #expect(!chunk.text.contains("\u{FFFD}"))
            chunk = try LogFile.readEarlier(url, before: chunk.startOffset, bytes: 101)
            text = chunk.text + text
            reads += 1
        }
        #expect(!chunk.text.contains("\u{FFFD}"))
        #expect(text == content)
    }

    @Test func readsASmallFileWhole() throws {
        let folder = try temporaryFolder()
        let url = folder.appendingPathComponent(LogFile.fileName)
        try Data("only line\n".utf8).write(to: url)
        let tail = try LogFile.readTail(url)
        #expect(tail.text == "only line\n")
        #expect(tail.startOffset == 0)
        let empty = folder.appendingPathComponent("empty.log")
        try Data().write(to: empty)
        let none = try LogFile.readTail(empty)
        #expect(none.text.isEmpty)
        #expect(none.fileLength == 0)
    }

    @Test func centerKeepsItsApi() {
        // The API every package uses: building messages only when the level is written.
        let log = Log("LogFileTests")
        var built = false
        func message() -> String {
            built = true
            return "built"
        }
        if !LogCenter.isEnabled(.debug) {
            log.debug(message())
            #expect(!built)
        }
        log.error("an error entry from the tests", error: nil)
        #expect(LogCenter.subsystem.isEmpty == false)
    }
}
