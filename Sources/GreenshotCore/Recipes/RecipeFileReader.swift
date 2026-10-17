// Greenshot for Mac (Community) - an unofficial macOS port of Greenshot
// Copyright (C) 2026 Greenshot for Mac (Community) contributors
// Based on Greenshot, Copyright (C) 2007-2026 Thomas Braun, Jens Klingen, Robin Krom
// SPDX-License-Identifier: GPL-3.0-or-later

import Foundation

/// Reads a recipe file with a size limit (security review): a file is read, parsed and validated before anyone
/// approved it, so a huge file (or a device or pipe that never ends) must not fill the memory. Upstream has no limit;
/// the largest example recipe is under 20 KB.
enum RecipeFileReader {
    /// The largest recipe file Greenshot reads.
    static let maxBytes = 1024 * 1024
    /// The most recipes one file may hold (each is validated before it is approved).
    static let maxRecipes = 50

    enum Failure: Error, Equatable {
        case unreadable
        case notAFile
        case tooLarge
    }

    /// The bytes of the regular file at `url` (symbolic links followed), at most `maxBytes`.
    static func read(_ url: URL) -> Result<Data, Failure> {
        let target = url.resolvingSymlinksInPath()
        guard let values = try? target.resourceValues(forKeys: [.isRegularFileKey, .fileSizeKey]) else { return .failure(.unreadable) }
        guard values.isRegularFile == true else { return .failure(.notAFile) }
        if let size = values.fileSize, size > maxBytes { return .failure(.tooLarge) }
        guard let handle = try? FileHandle(forReadingFrom: target) else { return .failure(.unreadable) }
        defer { try? handle.close() }
        // One byte more than allowed tells a file that grew since its size was read.
        guard let data = try? handle.read(upToCount: maxBytes + 1) ?? Data() else { return .failure(.unreadable) }
        return data.count > maxBytes ? .failure(.tooLarge) : .success(data)
    }

    /// The bytes, or nil (logged when the file is too large).
    static func data(_ url: URL) -> Data? {
        switch read(url) {
        case .success(let data):
            return data
        case .failure(let failure):
            if failure != .unreadable { log.warn(message(failure, path: url.path)) }
            return nil
        }
    }

    static func message(_ failure: Failure, path: String) -> String {
        switch failure {
        case .unreadable: return "File not found: \(path)"
        case .notAFile: return "Not a recipe file: \(path)"
        case .tooLarge: return "The recipe file is larger than \(maxBytes / 1024 / 1024) MB: \(path)"
        }
    }
}

private let log = Log("Recipes")
