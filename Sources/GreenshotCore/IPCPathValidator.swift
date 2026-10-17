// Greenshot for Mac (Community) - an unofficial macOS port of Greenshot
// Copyright (C) 2026 Greenshot for Mac (Community) contributors
// Based on Greenshot, Copyright (C) 2007-2026 Thomas Braun, Jens Klingen, Robin Krom
// SPDX-License-Identifier: GPL-3.0-or-later

import Darwin
import Foundation
import ImageIO
import UniformTypeIdentifiers

/// Checks a file path that came over the automation channels (upstream `IpcSecurityDispatcher.TrySanitizeAndResolvePath`,
/// docs §3.2). Windows' alternate data streams, drive letters, device names and UNC paths don't exist on the Mac; what
/// they guard against does: a path must be plain text, resolve to a regular file (not a folder, FIFO or `/dev` node) and
/// have the extension of an image the editor reads.
public enum IPCPathValidator {
    public struct Failure: Error, Equatable, Sendable {
        public var message: String
    }

    /// The extensions of the types ImageIO reads, plus the app's own `.greenshot` (upstream: the extensions of the
    /// registered file format handlers, `GetAllowedImageExtensions`).
    public static func imageExtensions(typeIdentifiers: [String]) -> Set<String> {
        var extensions: Set<String> = [GreenshotFile.fileExtension.lowercased()]
        for identifier in typeIdentifiers {
            for tag in UTType(identifier)?.tags[.filenameExtension] ?? [] { extensions.insert(tag.lowercased()) }
        }
        return extensions
    }

    /// What the editor opens: every type ImageIO reads (`ImageFileLoader`), plus `.greenshot`.
    public static var editorImageExtensions: Set<String> {
        imageExtensions(typeIdentifiers: (CGImageSourceCopyTypeIdentifiers() as? [String]) ?? [])
    }

    /// A `.greenshot` file, or a file ImageIO reads whatever its name says (Finder may hand over an image without its
    /// extension).
    public static func isReadableImage(_ url: URL) -> Bool {
        if GreenshotFile.isGreenshotFile(url) { return true }
        guard let source = CGImageSourceCreateWithURL(url as CFURL, nil) else { return false }
        return CGImageSourceGetType(source) != nil && CGImageSourceGetCount(source) > 0
    }

    /// The absolute, standardized path of `raw`; relative paths are taken from `cwd`. With `acceptsContent`, an existing
    /// regular file whose extension isn't allowed still passes when it accepts the file (the user's own files from
    /// Finder: an image the editor reads, whatever its name).
    public static func resolve(_ raw: String, cwd: String?, allowedExtensions: Set<String>,
                               acceptsContent: ((URL) -> Bool)? = nil) -> Result<URL, Failure> {
        if raw.trimmingCharacters(in: .whitespaces).isEmpty { return .failure(Failure(message: "Path is empty or whitespace.")) }
        for scalar in raw.unicodeScalars {
            if scalar.value < 0x20 || scalar.value == 0x7F {
                return .failure(Failure(message: "Path contains illegal control characters."))
            }
            if isInvisibleFormatting(scalar.value) {
                return .failure(Failure(message: "Path contains forbidden Unicode formatting or bidirectional override characters."))
            }
        }

        let absolute: String
        if raw.hasPrefix("/") {
            absolute = raw
        } else {
            guard let cwd, cwd.hasPrefix("/") else {
                return .failure(Failure(message: "Relative path without the caller's working directory."))
            }
            absolute = (cwd as NSString).appendingPathComponent(raw)
        }
        let url = URL(fileURLWithPath: absolute).standardizedFileURL

        let ext = url.pathExtension.lowercased()
        let extensionAllowed = !ext.isEmpty && allowedExtensions.contains(ext)
        let extensionRefusal = Failure(message: "File extension '\(url.pathExtension.isEmpty ? "" : "." + url.pathExtension)' is not permitted.")
        if !extensionAllowed, acceptsContent == nil { return .failure(extensionRefusal) }

        var info = stat()
        guard stat(url.path, &info) == 0 else {
            return .failure(Failure(message: "File does not exist: '\(url.path)'"))
        }
        guard info.st_mode & S_IFMT == S_IFREG else {
            return .failure(Failure(message: "Not a regular file: '\(url.path)'"))
        }
        if !extensionAllowed, let acceptsContent, !acceptsContent(url) { return .failure(extensionRefusal) }
        return .success(url)
    }

    /// The files of one OPEN_FILE request. Strict (greenshot-cli, AppleScript, Shortcuts; upstream
    /// `HandleOpenFileAsync`): the first refused path refuses the request. Lenient (Finder, the Dock, the Services menu:
    /// files the user picked): every file that passes opens, files the editor reads pass whatever their extension, and
    /// only the refused ones are reported.
    public struct Batch: Equatable, Sendable {
        public var accepted: [URL] = []
        /// The refused paths as given, with the reason.
        public var refused: [Refusal] = []

        public struct Refusal: Equatable, Sendable {
            public var path: String
            public var message: String
        }

        public init() {}
    }

    public static func resolve(_ paths: [String], cwd: String?, allowedExtensions: Set<String>, lenient: Bool,
                               acceptsContent: @escaping (URL) -> Bool = isReadableImage) -> Batch {
        var batch = Batch()
        for path in paths {
            switch resolve(path, cwd: cwd, allowedExtensions: allowedExtensions, acceptsContent: lenient ? acceptsContent : nil) {
            case .success(let url):
                batch.accepted.append(url)
            case .failure(let failure):
                batch.refused.append(Batch.Refusal(path: path, message: failure.message))
                if !lenient {
                    batch.accepted.removeAll()
                    return batch
                }
            }
        }
        return batch
    }

    /// U+200B..U+200F (zero-width characters and marks), U+202A..U+202E (bidi embeddings and overrides), U+2066..U+2069
    /// (bidi isolates), U+FEFF (byte order mark).
    static func isInvisibleFormatting(_ value: UInt32) -> Bool {
        if value >= 0x200B, value <= 0x200F { return true }
        if value >= 0x202A, value <= 0x202E { return true }
        if value >= 0x2066, value <= 0x2069 { return true }
        return value == 0xFEFF
    }
}
