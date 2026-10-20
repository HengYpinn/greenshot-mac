// Greenshot for Mac (Community) - an unofficial macOS port of Greenshot
// Copyright (C) 2026 Greenshot for Mac (Community) contributors
// Based on Greenshot, Copyright (C) 2007-2026 Thomas Braun, Jens Klingen, Robin Krom
// SPDX-License-Identifier: GPL-3.0-or-later

import Foundation

/// The log file: upstream's log4net `RollingFileAppender` (`Greenshot/log4net-release.xml`): `Greenshot.log`, rolled
/// over at 1 MB into `Greenshot.log.1` ... `.3`, entries in the layout
/// `%date{ISO8601} [%thread] %-5level - [%logger] %m%n%exception`.
public enum LogFile {
    public static let fileName = "Greenshot.log"
    /// Upstream `maximumFileSize`.
    public static let maxFileSize = 1024 * 1024
    /// Upstream `maxSizeRollBackups`.
    public static let backups = 3
    /// The chunk the log viewer reads at a time (upstream `LogViewerWindow.DefaultChunkBytes`).
    public static let chunkBytes = 64 * 1024

    /// One entry before it is made safe (`LogSanitizer.fileEntry`): date, thread, level padded to five, category,
    /// message, and the error on the lines after it.
    public static func entry(date: Date, thread: String, level: LogLevel, category: String, message: String,
                             error: Error?) -> String {
        let padded = level.name.padding(toLength: 5, withPad: " ", startingAt: 0)
        var text = "\(timestamp(date)) [\(thread)] \(padded) - [\(category)] \(message)\n"
        if let error {
            text += describe(error) + "\n"
        }
        return text
    }

    /// `2026-10-16 09:00:00,000` in local time, like log4net's ISO8601 date.
    public static func timestamp(_ date: Date) -> String {
        timestampFormatter.string(from: date)
    }

    /// The type, message, domain and code of an error, with the errors under it (upstream writes the exception with
    /// its inner exceptions).
    public static func describe(_ error: Error) -> String {
        let nsError = error as NSError
        var text = "\(String(reflecting: type(of: error))): \(error.localizedDescription) (\(nsError.domain) \(nsError.code))"
        if let underlying = nsError.userInfo[NSUnderlyingErrorKey] as? Error {
            text += "\n--- Inner error: " + describe(underlying)
        }
        return text
    }

    private static let timestampFormatter: DateFormatter = {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.calendar = Calendar(identifier: .gregorian)
        formatter.dateFormat = "yyyy-MM-dd HH:mm:ss,SSS"
        return formatter
    }()

    // MARK: Reading, for the log viewer

    /// A part of the log file: its text (starting at a line, or inside a line longer than a chunk) and where it starts.
    public struct Chunk: Equatable, Sendable {
        public var text: String
        /// The byte offset of `text` in the file; 0 when the chunk reaches the start.
        public var startOffset: Int
        /// The size of the file when it was read.
        public var fileLength: Int

        public init(text: String, startOffset: Int, fileLength: Int) {
            self.text = text
            self.startOffset = startOffset
            self.fileLength = fileLength
        }

        /// There is more of the file before this chunk.
        public var hasEarlier: Bool { startOffset > 0 }
    }

    /// The end of the file, at most `bytes`, starting at a whole line (upstream `LoadTail`).
    public static func readTail(_ url: URL, bytes: Int = chunkBytes) throws -> Chunk {
        let handle = try FileHandle(forReadingFrom: url)
        defer { try? handle.close() }
        let length = Int(try handle.seekToEnd())
        let offset = max(0, length - bytes)
        return try read(handle, from: offset, to: length, fileLength: length)
    }

    /// The part before `offset`, at most `bytes`, starting at a whole line (upstream `LoadEarlierLines`); with
    /// `bytes` nil everything before it (`LoadEntireLog`).
    public static func readEarlier(_ url: URL, before offset: Int, bytes: Int? = chunkBytes) throws -> Chunk {
        let handle = try FileHandle(forReadingFrom: url)
        defer { try? handle.close() }
        let length = Int(try handle.seekToEnd())
        let end = min(max(0, offset), length)
        let start = bytes.map { max(0, end - $0) } ?? 0
        return try read(handle, from: start, to: end, fileLength: length)
    }

    /// The whole file (for a search, upstream `ApplySearch`). Bytes that aren't UTF-8 become U+FFFD.
    public static func readAll(_ url: URL) throws -> String {
        String(decoding: try Data(contentsOf: url), as: UTF8.self)
    }

    private static func read(_ handle: FileHandle, from start: Int, to end: Int, fileLength: Int) throws -> Chunk {
        guard end > start else { return Chunk(text: "", startOffset: start, fileLength: fileLength) }
        // One byte more in front: whether the chunk starts right after a line break.
        let before = start > 0 ? 1 : 0
        try handle.seek(toOffset: UInt64(start - before))
        let read = try handle.read(upToCount: end - start + before) ?? Data()
        let data = read.dropFirst(before)
        var skip = 0
        if before == 1, read.first != 0x0A {
            // Discard the partial line before the first line break (upstream). When that leaves nothing (no line break
            // before the last byte: the chunk is inside a line longer than it), the chunk is kept from its first whole
            // character on, so the chunk before it goes on from there; upstream shows nothing and reads it again.
            if let newline = data.firstIndex(of: 0x0A), newline + 1 < data.endIndex {
                skip = newline + 1 - data.startIndex
            } else {
                skip = data.prefix(3).prefix { $0 & 0xC0 == 0x80 }.count
            }
        }
        let text = String(decoding: data.dropFirst(skip), as: UTF8.self)
        return Chunk(text: text, startOffset: start + skip, fileLength: fileLength)
    }
}

/// Appends entries to the log file and rolls it over (upstream log4net `RollingFileAppender`, `rollingStyle Size`):
/// when the file reached `maxSize`, `name.3` is deleted, `name.2` becomes `.3`, `.1` becomes `.2`, the file becomes
/// `.1`, and a new file starts. Writes go straight to the file (no buffer), so they are there when the app crashes.
/// Not thread-safe on its own: `LogHub` calls it under its lock.
final class LogFileWriter {
    let url: URL
    let maxSize: Int
    let backups: Int
    private var descriptor: Int32 = -1
    private var size = 0
    private var failed = false

    init(url: URL, maxSize: Int = LogFile.maxFileSize, backups: Int = LogFile.backups) {
        self.url = url
        self.maxSize = maxSize
        self.backups = backups
    }

    deinit {
        close()
    }

    func append(_ text: String) {
        guard !failed else { return }
        if descriptor < 0 { open() }
        guard descriptor >= 0 else { return }
        if size >= maxSize {
            roll()
            guard descriptor >= 0 else { return }
        }
        let data = Data(text.utf8)
        let written = data.withUnsafeBytes { buffer -> Int in
            guard let base = buffer.baseAddress else { return 0 }
            return Darwin.write(descriptor, base, buffer.count)
        }
        if written > 0 { size += written }
    }

    func close() {
        if descriptor >= 0 { Darwin.close(descriptor) }
        descriptor = -1
    }

    private func open() {
        do {
            try FileManager.default.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
        } catch {
            failed = true
            return
        }
        descriptor = Darwin.open(url.path, O_WRONLY | O_APPEND | O_CREAT | O_CLOEXEC, 0o644)
        if descriptor < 0 {
            failed = true
            return
        }
        size = Int(lseek(descriptor, 0, SEEK_END))
    }

    private func roll() {
        close()
        let manager = FileManager.default
        func backup(_ number: Int) -> URL { URL(fileURLWithPath: url.path + ".\(number)") }
        if backups > 0 {
            try? manager.removeItem(at: backup(backups))
            if backups > 1 {
                for number in stride(from: backups - 1, through: 1, by: -1) {
                    try? manager.moveItem(at: backup(number), to: backup(number + 1))
                }
            }
            try? manager.moveItem(at: url, to: backup(1))
        } else {
            try? manager.removeItem(at: url)
        }
        open()
    }
}
